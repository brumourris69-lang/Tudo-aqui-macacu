# Busca de estabelecimentos — backend Node local (4C)

## Estado e limites de ativação

Não foi feito deploy, backfill, criação de coleções reais, mudança de plano ou
conexão da interface. Upload e notificações mantêm suas implementações existentes.
Search só é exportada pelo entrypoint quando FUNCTIONS_EMULATOR=true,
GCLOUD_PROJECT começa com demo- e FIRESTORE_EMULATOR_HOST é loopback com porta.
Sem os três critérios não existem novos exports de produção. Handlers repetem
a verificação antes de usar armazenamento. Não remover esse gate nesta etapa.

Foram inspecionados firebase.json e Rules. Não houve alteração neles: o índice
business_search_index e os contadores business_search_rate_limits não pertencem
à lista pública atual. Confirmar/validar deny real antes de qualquer ativação.
Admin SDK ignora Rules, portanto handlers fazem as próprias verificações.

## Implementação

- business_search.js: porta Node do contrato Dart, projeção pública, categorias,
  normalização, prefixos, sincronização e pesquisa com armazenamento injetável.
- business_search_firestore.js: transações Firestore, consulta paginada do índice,
  leitura pontual batched das origens e limitador persistente por usuário.
- business_search_functions.js: onDocumentWritten + callable registrados somente
  no ambiente demo local; enforceAppCheck, limites de instâncias/concurrency e
  erros seguros. Não precisa de credencial de serviço dentro do Flutter.
- Fixtures JSON compartilhadas e teste Flutter verificam paridade com a base
  Dart. A otimização de lotes Node respeita o teto de 40 do contrato anterior.

## Sincronização e expiração

syncBusinessSearchIndex lê documento ATUAL e projeção atual na mesma transação.
Nunca usa event.data como fonte. Leitura antes das escritas e retry do SDK evitam
sobrescrever com estado antigo em conflitos. ID estável establishments__{id};
ID original continua na projeção. IDs cujo prefixo excederia 1500 bytes ficam
rejeitados explicitamente, sem inventar identidade alternativa.

Projeção é substituída integralmente, removendo termos/campos antigos. Comparação
ignora só indexedAt: eventos repetidos, alterações de contato/campos privados e
conteúdo público idêntico não escrevem novamente. Despublicação, active=false,
exclusão, campos inválidos ou expiresAt vencido removem o índice se existir.
Cada sincronização faz duas leituras (fonte + índice) e zero ou uma escrita/
exclusão, salvo retries de transação. indexedAt é serverTimestamp.

Expiração é revalidada com relógio do servidor a cada busca; não exige uma edição.
Limpeza agendada/reconciliação paginada ainda é pendência. Não há backfill/varredura
implementado ou executado. Eventos atrasados podem reduzir cobertura enquanto
não reconciliados; a revalidação impede devolver dados antigos/ineligíveis.

## Consulta e custos

Entrada: query (até 80 caracteres, 1–4 palavras de 2–24), filter
all/commerce/services, limit inteiro 1–20, cursor opcional queryKey/lastIndexId.
Nenhuma coleção, campo, ordenação ou limite é escolhido arbitrariamente pelo
cliente. Cursor é validado/vinculado à consulta; não é autorização.

Índice: projeção SearchResult + terms (até 64), prefixes (2–24), group,
schemaVersion=1, indexedAt. Palavras vêm de título/categoria/subcategoria/resumo
de 180 caracteres, sem texto privado e sem keywords não existentes. Imagens
ficam vazias por padrão até existir uma política explícita de autorização.

Consulta: prefixes array-contains âncora mais longa, group opcional, ordenação
por document ID, startAfter cursor. Faz select só de ID, origem, terms e versão.
Projeção reduz transferência, NÃO reduz o preço de leitura do documento.
Filtro composto poderá exigir índice composto (prefixes/group/document ID);
nenhum índice foi criado/configurado. Validar no Emulator e ambiente autorizado.

Primeiro lote tem tamanho igual aos resultados ainda necessários, no máximo 20.
Termos adicionais são conferidos no índice antes de ler origem. Isso pode omitir
uma edição ainda não sincronizada; é consistência eventual, não vazamento.
Origens candidatas são lidas com getAll: menos RPCs, mesmo número de leituras
cobradas. Origem atual sempre revalida publicação/active/expiração/categoria/termos
e gera resultado novo. Não reutiliza uma resposta pública antiga em cache.
Repõe apenas vagas restantes, até 40 candidatos por chamada. Não faz lookahead
extra; cursor pode levar a uma página final vazia. IDs não se repetem em navegação
sem mudanças concorrentes do conjunto; paginação não é snapshot imutável.

Estimativa por chamada aceita (sem retries):

| Cenário | Docs de índice | Docs de origem | Escritas de sincronização |
| --- | ---: | ---: | ---: |
| Busca de 5 resultados, todos válidos | 5 | 5 | 0 |
| Página com 20 resultados, todos válidos | 20 | 20 | 0 |
| 40 candidatos rejeitados por termos adicionais | 40 | 0 | 0 |
| Pior caso: 40 candidatos passam termos, mas fonte está ineligível | 40 | 40 | 0 |
| Sem candidato | 0 (consulta vazia tem cobrança mínima) | 0 | 0 |

Limitação contra abuso acrescenta **1 leitura + 1 escrita de contador por chamada
aceita**, separadas das operações acima. Rejeição por frequência faz 1 leitura,
sem escrita/consulta de índice. Query/auth/app inválidos não chegam ao contador.
Queries vazias cobram pelo menos uma leitura; entradas de índice, armazenamento,
execução e retries podem ter cobrança adicional. Não prometer custo só com
contagem de documentos. Até 40 pequenas consultas podem ocorrer com limit=1 e
fontes rejeitadas; limite total de candidatos e timeout continuam obrigatórios.

## Segurança e visitantes

Callable valida tokens via SDK e exige auth.uid e App Check; booleans do cliente
não têm valor. Visitante atual sem token é rejeitado, assim como provider anonymous.
Não foi criado login anônimo nem alterada a UI. Autorizar pesquisa pública futura
exige decisão explícita sobre identidade e proteção contra abuso.

Limiter transacional por hash do UID: máximo 30 chamadas/minuto e intervalo mínimo
350ms. Estado privado contém só janela, contagem, horário e expiração do contador.
Não grava texto pesquisado ou tokens. TTL não foi ativado: limpeza desses contadores
é pendência. Limite por conta não evita muitas contas; proteção global/adicional,
monitoramento e orçamento precisam ser definidos antes da produção. App Check
também não substitui rate limit. minInstances não é definido (não mantém instância
sempre ativa). Handler usa maxInstances=2, concurrency=4, timeout=15s.

Falhas de SDK são convertidas em mensagem genérica, sem logs de documentos,
tokens, credenciais ou resposta interna. Revalidação vale para o instante da
leitura; mudança posterior não pode revogar retroativamente resposta já entregue.
Revalidar também na abertura de BusinessProfile quando houver integração.

## Testes e pendências

Testes Node usam mapas/SDK mocks e fixtures; testes Flutter usam as mesmas fixtures.
O runtime Firestore Emulator não estava disponível no cache local inspecionado;
CLI Firebase existente e Java não bastam para executar a suíte completa. Portanto
não foram validados App Check/Auth reais, execução real de triggers, conflitos
reais, Rules, necessidade de índices compostos ou consultas no Emulator.
Nenhuma conexão com produção foi usada nos testes.

Antes de ativar: instalar/configurar Emulator com projeto demo e SDKs, testar
functions/Auth/Firestore e Rules, confirmar política de visitantes e imagens,
configurar App Check no app, controles de abuso global, limpeza de contadores e
índice expirado, índices compostos, orçamento/Blaze e backfill paginado autorizado.
Somente depois liberar gate de produção mediante autorização, implantar e
integrar UniversalSearchRepository à interface. Não executar esses passos agora.

Fontes:
- https://firebase.google.com/docs/functions/firestore-events
- https://firebase.google.com/docs/app-check/cloud-functions
- https://firebase.google.com/docs/emulator-suite/connect_firestore
- https://firebase.google.com/docs/firestore/pricing
