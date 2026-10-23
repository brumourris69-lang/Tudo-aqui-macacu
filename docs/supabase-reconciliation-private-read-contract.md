# Contrato proposto — leitura privada para reconciliação do catálogo V2

Data: 21/10/2026
Estado: implementado e validado localmente; não aplicado a qualquer serviço hospedado.

## Constatação original — resolvida localmente

Não existe hoje um caminho autorizado para o scanner ler o estado completo do destino:

- `search_public_establishments_v2`, `list_public_establishments_v2` e
  `get_public_establishment_v2` retornam apenas conteúdo público elegível. Não
  mostram itens não publicados, inativos, expirados ou logicamente excluídos;
  também omitem `catalog_version` e `outbox_operation_id`.
- A migration do escritor revoga `SELECT` direto de `service_role` nas tabelas
  internas. Consulta direta não é uma alternativa válida.
- `supabase_catalog_rpc_rest.mjs` aceita somente os dois nomes fixos de RPC
  escritor e somente um argumento correspondente a cada escritor.
- As RPCs públicas não expõem a tabela de tombstones. Usá-las para reconciliação
  poderia interpretar uma ausência como estado inexistente e não detectaria uma
  tentativa de ressuscitar um ID tombstonado.

Essa lacuna motivou o contrato abaixo. O leitor privado está implementado na
migration incremental e no adaptador PostgREST server-side. Não se relaxaram
grants, não se reutilizaram RPCs públicas e não se concedeu `SELECT` direto.

## Contrato incremental implementado

Adicionar uma migration independente, sem alterar V1, V2 ou o escritor:

1. Criar armazenamento interno de snapshots com `snapshot_id`, horário de
   captura, expiração e linhas materializadas por `(snapshot_id, id, row_kind)`.
   `row_kind` distingue `catalog` de `tombstone`, permitindo que ambos existam
   para o mesmo ID sem ambiguidade.
2. Uma RPC `begin_catalog_reconciliation_snapshot_v2(p_snapshot_id uuid)` deve
   materializar, numa única transação, as linhas necessárias das duas tabelas.
   Deve projetar colunas explicitamente e excluir `search_document` e qualquer
   campo fora da allowlist. Repetir o mesmo `snapshot_id` deve ser idempotente e
   nunca substituir um snapshot existente.
3. Uma RPC
   `read_catalog_reconciliation_page_v2(p_snapshot_id uuid, p_after_id text,
   p_page_size integer)` deve devolver IDs distintos ordenados, linha de catálogo
   e tombstone correspondentes, cursor seguinte, indicador de conclusão e o
   mesmo `snapshot_id`. Limitar `page_size` a 200 e validar IDs/cursors.
   Snapshot expirado deve usar SQLSTATE `55000`, mapeado pelo adaptador para
   `snapshot_expired` sem mensagem bruta.
4. Uma RPC privada de descarte apaga somente o snapshot solicitado e é
   idempotente. Cada novo snapshot remove no máximo um snapshot expirado; não há
   Cron nem limpeza global.
5. Todas as funções serão `SECURITY DEFINER`, propriedade de `postgres`, com
   `search_path = ''`, nomes qualificados, argumentos limitados e sem SQL
   dinâmico. Revogar `EXECUTE` de `PUBLIC`, `anon` e `authenticated`; conceder
   apenas a `service_role`. Revogar todo acesso direto às tabelas de snapshot,
   inclusive de `service_role`.
6. As RPCs não são expostas ao Flutter nem adicionadas à superfície pública. O
   novo cliente PostgREST server-side tem allowlist própria de três nomes e
   argumentos exatos; valida os formatos de resposta, impõe limites de bytes e
   timeout HTTP e sanitiza falhas. O teste local confirmou que uma chamada sem
   JWT recebe 401/SQLSTATE 42501.

## Consistência e limites

O snapshot PostgreSQL fixa o lado do destino durante a paginação. Firestore e
PostgreSQL não compartilham transação distribuída; o `snapshotId` representa o
par de identificadores/tempos de captura, não um instante global atômico. O
relatório permanece observacional. Antes de qualquer futuro backfill, o worker
deverá reler o documento canônico, conferir `catalogVersion` e
`outboxOperationId`, e então usar o escritor V2 idempotente. Nunca aplicar
diretamente um payload antigo do relatório. Tombstones sempre bloqueiam
republicação comum.

A materialização consome I/O, CPU, espaço temporário e uma transação proporcional
ao catálogo. O contrato limita cada fonte a 10.001 candidatos antes da união,
falha se houver mais de 10.000 IDs ou 64 MiB materializados, limita snapshots
ativos a quatro, páginas a 200 linhas e a validade a uma hora. Todas as RPCs têm
`statement_timeout` de 30 segundos. Um índice parcial por ID de estabelecimento
e o índice de cursor `COLLATE "C"` sustentam a leitura. O descarte não remove
dados do catálogo.

## Validação local concluída para leitura e checkpoint

- pgTAP: `EXECUTE` apenas para `service_role`; nenhuma leitura direta de tabela;
  grants negados a `anon`/`authenticated`; dono, `SECURITY DEFINER` e
  `search_path` seguros.
- pgTAP: snapshot inclui registros publicados, não publicados, inativos,
  expirados, com exclusão lógica e tombstones, preservando ID, versão e operação;
  exclui `search_document`.
- pgTAP: paginação determinística com IDs legados, limite, cursor inválido,
  snapshot desconhecido/expirado e tombstone junto à linha do mesmo ID.
- Node: transporte aceita apenas os nomes/argumentos fixos, sanitiza status e
  respostas inválidas, limita bytes e nunca registra chave/corpo bruto.
- Integração local: o leitor pareia `readTime` do Firestore Emulator e snapshot
  materializado PostgreSQL. O scanner read-only e o checkpoint em arquivo foram
  executados com o Firestore Emulator e as RPCs privadas reais via PostgREST local;
  nenhum writer do catálogo foi chamado.
- Repetição do mesmo snapshot é estável; descarte concorrente é idempotente e
  chamadas posteriores falham com código sanitizado.

Validação local executada em PostgreSQL 15.19, imagem
`public.ecr.aws/supabase/postgres:15.19.0.004`, sem pull, usando banco descartável
em `--network none`, sem portas publicadas, rootfs read-only, usuário `postgres`
não-root e mounts read-only. As cinco suítes TAP passaram com 267/267 asserções:
V1 28, hardening 48, V2 93, escritor privado 49 e leitura privada 49.

PostgREST 14.18, já em cache, foi conectado somente ao namespace de rede `none`
do banco, sem porta publicada. Com JWT sintético `service_role`, chamadas HTTP
reais ao escritor, `begin`, `read_page` e `dispose` retornaram sucesso; a página
continha apenas a projeção permitida e metadados de versão/operação. Sem JWT, a
RPC privada foi negada. Esse primeiro ciclo validou PostgreSQL/PostgREST local;
um ciclo posterior também executou o adaptador Node end-to-end no ambiente local.

O leitor Firestore, leitor pareado, checkpoint e scanner têm testes unitários;
dois testes condicionais foram executados de forma explícita contra o Firestore
Emulator e PostgreSQL/PostgREST locais. O teste composto varreu IDs Unicode
legados, persistiu checkpoint recuperável e confirmou que contatos privados não
aparecem no relatório. A suíte compartilhada final passou 199/203, com quatro
integrações condicionais ignoradas quando executada sem seus serviços; `npm test
--prefix functions` passou 185/185. O subconjunto direcionado passou 50/50.
Deno 2.9.7 verificou os módulos de reconciliação com `--cached-only`; `node
--check`, `deno fmt --check` e `git diff --check` passaram. Nenhum teste acessou
Firebase ou Supabase hospedado.

## Limites e próximos gates

A migration, o leitor PostgREST, o leitor Firestore, o coordenador read-only e o
checkpoint local foram exercitados nos serviços descartáveis. Ainda falta uma
releitura transacional da origem imediatamente antes de qualquer writer e a
validação de uma estratégia de backfill local; não há escrita de reconciliação.
Os snapshots de Firestore e PostgreSQL não formam um instante distribuído
atômico. Nenhum dado hospedado, deploy ou backfill foi acessado/executado.

O mecanismo local de reconciliação é observacional e read-only. Ainda não há
backfill, aplicação de findings, validação de reexecução operacional nem
reconciliação de dados reais. Os checkpoints em arquivo servem à execução local
single-host e não são um armazenamento distribuído de produção.

Antes de qualquer uso hospedado, ainda são necessários: revisão do custo de
materialização em volume representativo, estratégia de índice/execução da
migration sem bloquear escritas, IAM mínimo, validação dos índices reais, gestão
segura de service key, teste de homologação autorizado e plano de pausa/rollback.
