# Busca Universal — backend local multiconteúdo (etapas 4C/2/4)

## Atualização local: Empregos (Etapa 6A)

A coleção `jobs` usa a identidade `jobs__{id}` no mesmo índice e cursor de
Comércios, Turismo, Notícias e Eventos. O gatilho `syncJobsSearchIndex` é
registrado somente no Emulator `demo-*`, relê o estado atual numa transação e
remove projeções inelegíveis. Pesquisa por título, descrição e, quando
presentes, empresa, localização, categoria e modalidade/tipo (`employmentType`
ou `type`). `contact`, prazo de candidatura e campos administrativos não são
indexados nem retornados. A política exige `published == true`; `active` e
`expiresAt` são opcionais, mas se presentes precisam ser válidos e elegíveis.
O prazo de candidatura não substitui `expiresAt`.

O filtro local `jobs` e `all` pesquisam o índice único e usam o mesmo cursor
determinístico. O resultado preserva coleção e ID originais. `jobDetail` abre
uma tela local segura; a callable de detalhe é descrita abaixo. Ações externas
de contato/candidatura não são abertas.

`integration/jobs_search_emulator.js` usa IDs aleatórios, testa gatilho,
visibilidade, prefixos, filtros, paginação e projeção, e remove apenas os seus
próprios documentos. Não limpa o Emulator persistente nem toca no export.

## Atualização local: Detalhe de Empregos (Etapa 6B)

`getSearchJob` é registrado somente sob o gate do Emulator demo com Firestore
loopback. Exige Auth e App Check, valida o ID, usa quota própria de detalhe e
relê `jobs/{id}` antes de retornar. Publicação é obrigatória; `active` e
`expiresAt` seguem a política opcional comum. `applicationDeadline` não é usado
como expiração. A resposta allowlist contém título, descrição, categoria,
localização, empresa e modalidade/tipo somente quando presentes. `contact`,
telefone, WhatsApp, links de candidatura e campos administrativos são omitidos.
O Admin rotula o campo como “Contato ou responsável”, sem política que autorize
sua publicação como canal de candidatura; por isso não é exposto. O schema não
define um campo confiável de data de publicação, então a tela não inventa uma.

O destino `jobDetail` abre `JobDetailPage`, que obtém os dados novamente pela
callable e preserva a pesquisa sob a rota na pilha. Erros têm retry e vagas
retiradas retornam estado indisponível. A tela não abre canais externos.

## Atualização local: Eventos (Etapa 5A)

A coleção `events` participa do mesmo índice sob a identidade `events__{id}`.
O gatilho local lê o estado atual e projeta somente o título, resumo,
categoria, data, localização e imagem autorizada; a pesquisa aceita o filtro
`events` e inclui esses registros em `all`. Título, categoria, descrição,
localização e a data textual são normalizados em termos/prefixos limitados.
`eventDate`/`date`/`startsAt` descrevem quando ocorre o evento e não são usados
como expiração. A elegibilidade exige `published == true`, `active == true`
quando o campo existe e `expiresAt` futuro quando presente. Antes de retornar,
cada candidato ainda é revalidado na coleção de origem. Os cards de Eventos
abrem um resolver local autenticado que relê `events/{id}`, revalida visibilidade
e retorna somente campos públicos permitidos. A data de realização não expira o evento.

`functions/integration/events_search_emulator.js` testa o trigger, projeção,
visibilidade, prefixos, filtro Eventos/Todos, paginação, identidade composta e
alterações usando IDs exclusivos. O teste é aditivo e remove somente seus
próprios fixtures; não apaga o banco persistente nem altera exports. Também
valida autorização, projeção pública e estados indisponíveis do detalhe.

## Atualização local: Notícias (Etapa 4)

O mesmo índice também aceita `establishments`, `routes` e `news`, sempre sob a
guarda `demo-*` + Functions Emulator + Firestore loopback. Notícias usa
`news__{id}`, tipo/grupo `news`, e pode ser pesquisada pelo filtro Notícias ou
em Todos. Título, categoria, resumo, localização e informação adicional entram
na normalização/prefixos; os textos são limitados antes da extração e a projeção
continua em allowlist. `syncNewsSearchIndex` consulta o documento atual dentro da
transação. Cada candidato passa novamente pela política de publicação, `active`
opcional e expiração.

Notícias e Eventos são resolvidos por callables autenticadas no Emulator, que
revalidam publicação e retornam somente campos públicos permitidos. `getSearchEvent`
usa quota separada. Nenhum handler de busca foi habilitado fora do Emulator, nem houve deploy.

## Estado e limites de ativação

Busca de estabelecimentos, Turismo, Notícias e Eventos funciona somente em `searchLocal` com o
Firebase Emulator `demo-universal-search`. Nenhum deploy, backfill, criação de
coleções reais ou mudança de plano. Uploads e notificações mantêm suas funções.
Handlers de busca só são exportados quando `FUNCTIONS_EMULATOR=true`, o projeto
começa com `demo-` e Firestore usa loopback; os handlers repetem a verificação.
O entrypoint de produção continua sem esses exports.

Foram inspecionados firebase.json e Rules. Não houve alteração neles: o índice
business_search_index e os contadores business_search_rate_limits não pertencem
à lista pública atual. Confirmar/validar deny real antes de qualquer ativação.
Admin SDK ignora Rules, portanto handlers fazem as próprias verificações.

## Implementação

- business_search.js: projeções públicas para `establishments`, `routes`, `news` e `events`,
  categorias, normalização, prefixos, cursores compostos e pesquisa indexada.
- business_search_firestore.js: transações Firestore, consulta paginada do índice,
  leitura pontual em lote nas coleções de origem e limitadores por usuário.
- business_search_functions.js: gatilhos de `establishments`, `routes`, `news` e `events`, pesquisa
  e resolução de detalhe registrados somente no demo local; App Check, limites e
  erros seguros. Nenhuma credencial administrativa fica no Flutter.
- Fixtures JSON compartilhadas e teste Flutter verificam paridade com a base
  Dart. A otimização de lotes Node respeita o teto de 40 do contrato anterior.

## Sincronização e expiração

Os gatilhos de cada coleção indexada leem a origem ATUAL e a projeção correspondente
na mesma transação. Nunca usam `event.data` como fonte. Leitura antes das escritas e retry
do SDK evitam sobrescrever com estado antigo em conflitos. IDs determinísticos
`{collection}__{id}` preservam o ID original na projeção.
IDs cujo prefixo excederia 1500 bytes são rejeitados.

Projeção é substituída integralmente, removendo termos/campos antigos. Comparação
ignora só indexedAt: eventos repetidos, alterações de contato/campos privados e
conteúdo público idêntico não escrevem novamente. Despublicação, active=false,
exclusão, campos inválidos ou expiresAt vencido removem o índice se existir.
Cada sincronização faz duas leituras (fonte + índice) e zero ou uma escrita/
exclusão, salvo retries de transação. indexedAt é serverTimestamp.

Expiração é revalidada com relógio do servidor a cada busca e ao resolver
detalhes de Turismo, Notícias e Eventos; não exige uma edição.
Limpeza agendada/reconciliação paginada ainda é pendência. Não há backfill/varredura
implementado ou executado. Eventos atrasados podem reduzir cobertura enquanto
não reconciliados; a revalidação impede devolver dados antigos/ineligíveis.

## Consulta e custos

Entrada: query (até 80 caracteres, 1–4 palavras de 2–24), filter
all/commerce/services/tourism/news/events, limit inteiro 1–20, cursor opcional queryKey/lastIndexId.
Nenhuma coleção, campo, ordenação ou limite é escolhido arbitrariamente pelo
cliente. Cursor é validado/vinculado à consulta; não é autorização.

Índice: projeção SearchResult + terms (até 64), prefixes (2–24), group, tipo,
schemaVersion=2, indexedAt. Palavras vêm de título/categoria/subcategoria,
resumo e, em rotas e eventos, localização. Registros de estabelecimentos com schemaVersion=1
continuam legíveis; uma sincronização os atualiza para versão 2. Dados privados
não são copiados. Imagens do índice ficam vazias sem autorização explícita.

Consulta: prefixes array-contains âncora mais longa, group para comércios/serviços
e Eventos ou type para Turismo/Notícias, sem filtro adicional em Todos, ordenação
por document ID, startAfter cursor. Faz select só dos campos de validação do
índice. O arquivo `firestore.search-local.indexes.json` contém os compostos
`prefixes/group` e `prefixes/type`, usado somente pela configuração de Emulator.
`firestore.indexes.json` de distribuição não foi alterado nem implantado. O
Emulator não impõe os compostos, portanto a execução local não comprova o estado
de índices em produção. Projeção reduz transferência, não o preço das leituras.

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
A abertura de um detalhe de Turismo, Notícias ou Eventos acrescenta uma leitura
pontual na coleção de origem e um contador independente, sem consulta à coleção inteira.

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
