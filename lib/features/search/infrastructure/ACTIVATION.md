# Infraestrutura preparada, não ativada — etapa 4A

## Arquitetura

UniversalSearchPage continua sem conexão. UniversalSearchRepository é o contrato
da futura chamada intermediária. BusinessSearchServer representa lógica de
servidor com armazenamento injetável; NÃO é servidor confiável quando executado
no celular. Seus ports ainda não têm implementação Firebase. Não há trigger,
callable exportada, inicialização Firebase, índice real ou backfill.

BusinessRepository continua sendo a origem das funcionalidades atuais e não foi
alterado. Não usar watchPublishedBusinesses para implementar busca por varredura.
Os resultados reaproveitam SearchResult, BusinessSearchAdapter (e Business),
BusinessSearchPolicy e search_normalization. BusinessProfile permanece o destino
existente; resolver o documento por ID e preservar favoritos na integração futura.

## Índice privado proposto

business_search_index / establishments__{ID original}

Campos: os nove campos públicos de SearchResult, terms, prefixes, group,
schemaVersion=1, indexedAt (Timestamp do servidor na persistência futura).
Sem documento original, contatos, dados administrativos, permissões ou tokens.
Imagem somente quando uma política explícita authorizeImage autorizar o URL;
nenhum domínio/URL está automaticamente autorizado. Até essa política existir,
fornecer (_) => false e omitir a imagem.

Termos vêm de título, categoria, subcategoria e resumo público (180 caracteres).
Máximo 64 palavras, cada uma limitada a 24 caracteres. Prefixos de 2 a 24
caracteres, no máximo 1472. Não gera todos os trechos/n-grams. Não cobre o restante
da descrição, palavras-chave ainda não existentes, fuzzy, frases ou relevância.
A consulta aceita 1–4 palavras de 2–24 caracteres, até 80 caracteres totais.
Todas precisam corresponder a prefixos de palavras atuais. A ordenação é por ID,
não por relevância. Corte de termos pode reduzir cobertura; documentar na UI futura.

## Consulta e paginação futuras

Servidor consulta apenas índice com prefixes array-contains palavra-âncora,
group == commerce/services quando escolhido, orderBy(FieldPath.documentId),
startAfter último ID, limit(40). Uma única condição array-contains: AND de palavras
é verificado no servidor contra fonte atual, não como consulta Firestore inválida.
Até 20 resultados e 40 candidatos por chamada. Cursor deve ficar associado ao
filtro/consulta normalizados; validar ID/tamanho no transport adapter. Não concede
acesso nem permite escolher coleção. Página vazia pode ter continuação.

Proposta de índice composto: prefixes CONTAINS + group ASC + __name__ ASC para
consulta filtrada. Confirmar no Emulator/Firestore antes do deploy; a consulta
sem group pode aproveitar índice de array existente. Não há definição adicionada
a firebase.json nem criação de índice nesta etapa. Não indexar title/summary/image
desnecessariamente; revisar isenções dos campos e limites antes da ativação.

## Sincronização

Futuro onDocumentWritten(establishments/{id}) passa somente ID ao sincronizador.
Transação deve ler a fonte atual e substituir integralmente ou excluir a projeção.
Não aplicar snapshot atrasado do evento. A transação Firestore deve reexecutar
em conflitos; todos os reads precedem writes. ID estável evita duplicação;
replace completo remove prefixos antigos. Repetições convergem ao estado atual.
Clock deve vir do servidor, não do dispositivo ou do horário do evento antigo.
indexedAt é diagnóstico, não prova de elegibilidade/versão de publicação.

Expiração não gera evento de escrita: leitura valida sempre expiresAt; futura
limpeza agendada/reconciliação paginada chamará synchronize para remover restos.
Reconciliação e backfill são requisitos operacionais futuros, não executados aqui.
Consistência eventual pode omitir novos resultados enquanto o índice atrasa.

## Segurança

Regras locais só incluem coleções públicas conhecidas, não esse índice. Não
adicionar índice ao allowlist público. Preparar/validar deny de leitura/escrita
cliente e testar também regras realmente implantadas antes de ativar.
Admin SDK ignora Rules: callable precisa da própria validação explícita.
Mesmo índice privado contém só projeção pública. Uma fonte despublicada pode
deixar resíduos privados até reconciliação; nunca devolver projeção antiga.

Cada candidato lê establishments/{id} atual, reavalia published/active/expiresAt,
categoria e palavras e gera novamente projeção com allowlist. Documento excluído
ou incerto é omitido. Não há fallback demonstrativo ou campos privados na resposta.
A verificação representa o estado no instante da leitura: alterações subsequentes
e cache previamente entregue não podem ser revogados retroativamente. Revalidar
também antes de abrir BusinessProfile.

Política preparada exige Firebase Auth + App Check. Na callable futura, derivar
esses sinais de request.auth/request.app, NUNCA de booleans enviados pelo cliente.
App Check não é limitador de frequência. Antes de ativar: rate limit por identidade,
limites de instâncias/concurrency/timeout, proteção contra abuso, cursor validado
ou assinado e orçamento/alertas. Não ativar o endpoint sem esses controles.
Não exigir login de visitantes silenciosamente: confirmar experiência pública;
Auth anônima é uma opção a aprovar. App Check não foi instalado/configurado aqui.
Não armazenar respostas públicas indefinidamente; cache curto e revalidação.

## Custos/dependências e gate de ativação

Exige Cloud Functions de produção, portanto Blaze. Plano atual/faturamento não
foi consultado nem alterado. Functions/admin e cloud_functions já constam no
projeto, mas não há integração de busca. Não exige Algolia/Typesense/Meilisearch.
Cada chamada: até 40 documentos de índice + até 40 leituras pontuais de origem,
além da cobrança aplicável de índice/execução; chamadas vazias também podem cobrar.
Escritas/remoções por alteração, armazenamento de prefixos, reconciliação e backfill
adicionam custos. Sem volume/uso, não há estimativa mensal confiável.

O backend existente é Node 20. Este núcleo Dart especifica/testa o contrato e
não é implantável em functions/index.js. Antes da ativação, implementar adapters
Node de transação/query/callable e portar a política com testes de paridade contra
estes casos. Não introduzir normalizadores com semânticas divergentes. Validar
índices/regras no Emulator, aprovar faturamento e imagem, backfill paginado,
deploy autorizado, e só depois conectar UniversalSearchPage por repositório.

Fontes oficiais verificadas:
- https://firebase.google.com/docs/functions/get-started (Blaze)
- https://firebase.google.com/docs/functions/firestore-events (ordem/repetição)
- https://firebase.google.com/docs/firestore/query-data/queries (array-contains)
- https://firebase.google.com/docs/firestore/security/rules-query (Rules)
