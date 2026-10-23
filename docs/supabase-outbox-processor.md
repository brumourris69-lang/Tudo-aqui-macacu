# Processador local da outbox

O processador em `supabase/functions/_shared/catalog_outbox_processor.mjs` compõe o adapter transacional Firestore, o protocolo V1/V2 e o wrapper das RPCs privadas do catálogo V2. `processPage()` consulta uma página limitada, reivindica cada evento por transação, relê o documento canônico, grava projeção ou tombstone e confirma `synced` somente após a resposta `applied` ou replay `replayed` do escritor. A execução é sequencial por página e devolve somente estado e metadados sanitizados; não registra payloads nem erros brutos.

## Limites e falhas

- O writer chama exclusivamente `apply_establishment_projection_v2(p_projection)` e `apply_establishment_tombstone_v2(p_tombstone)`. A projeção tem allowlist idêntica à migration SQL. `applied` vira confirmação positiva, `replayed` vira duplicata idempotente, SQLSTATE `23514` vira conflito terminal sanitizado e `22023` vira falha permanente. Resultados desconhecidos nunca confirmam a outbox.
- Falha de transporte do Supabase agenda retry. Se o Supabase confirmar e a transação de confirmação Firestore falhar, o evento mantém lease/estado sem confirmação; após expiração, o replay da mesma versão/operação é seguro pelo escritor SQL. Lease perdido impede a confirmação do worker antigo.
- O caminho de tombstone é distinto da despublicação: exclusão lógica usa a RPC de tombstone e bloqueia republicação; despublicação envia projeção normal com `published=false` e `deleted_at=null`.
- O módulo não inicia agenda, não processa eventos em background e não configura autenticação de máquina. O adapter Firestore recebe um store já autenticado; `workerId` é somente identidade de lease.

## IAM e identidade futura

Em produção, o consumidor deve usar uma identidade de serviço dedicada, não uma chave no Flutter. Com o checkpoint global adicionado, as permissões mínimas candidatas são `datastore.databases.get` (begin/rollback de transação), `datastore.entities.get` e `datastore.entities.list` (`runQuery` por ID e páginas), `datastore.entities.update` (leases/transições/eventos e checkpoint) e `datastore.entities.create` (somente criação inicial de `catalog_outbox_scan_state/consumer-v1`). Não é necessário `datastore.entities.delete`. O allowlist do adaptador limita esse checkpoint a um único ID, mas isso é uma restrição de código, não uma fronteira de IAM: uma credencial comprometida pode chamar a API Google diretamente, e IAM não oferece uma regra por coleção equivalente a Firestore Rules. Validar escopo efetivo/recurso e IAM Policy Troubleshooter antes de escolher o projeto de homologação; se a função sobre documentos de outras coleções for ampla demais, usar projeto/banco isolado ou um broker de identidade mais restrito. A tabela oficial de permissões por método está na [documentação IAM do Firestore](https://firebase.google.com/docs/firestore/security/iam).

O writer Supabase exige `EXECUTE` nas duas funções privadas V2. A migration base concedia isso a `service_role`, cuja chave continua ampla para outras APIs/RPCs e bypassa RLS. A migration candidata `20261024000100_restrict_catalog_writer_v2.sql` prepara três papéis: `catalog_writer_v2` (`NOLOGIN`, grupo executor), `catalog_writer_v2_login` (`LOGIN`, sem senha inicialmente) e `catalog_writer_v2_owner` (dono das funções, `NOLOGIN`, sem `BYPASSRLS`). O LOGIN herda somente o grupo executor, que recebe `EXECUTE` nas duas RPCs e nenhum grant nas tabelas. O `service_role` mantém temporariamente o EXECUTE para o consumidor PostgREST atual. O dono das funções recebe grants de tabela limitados, políticas RLS específicas e permissão de `UPDATE` em tombstones apenas porque o escritor usa `SELECT ... FOR UPDATE`; o trigger de imutabilidade continua rejeitando alterações. Os escritores continuam com allowlists, `search_path` vazio e timeouts limitados.

A migration é candidata local e **não foi executada**. O contrato SQL `supabase/tests/database/catalog_writer_role_v2.sql` contém 52 asserções planejadas para validar atributos, membership, INHERIT/SET ROLE, CONNECT ao banco, execução das RPCs, negações de DML direto em tabelas do catálogo e outras tabelas de aplicação, RLS, replay e tombstone. Também valida a compatibilidade temporária de `service_role`. `catalog_private_writer_v2.sql` e o harness de concorrência usam a role executor. Esses testes não são prova de permissões até rodarem em PostgreSQL real; `SET ROLE` no teste também não equivale a uma conexão autenticada por senha.

A role `catalog_writer_v2_login` é criada com `LOGIN INHERIT`, sem `SUPERUSER`, `CREATEDB`, `CREATEROLE`, `REPLICATION`, `BYPASSRLS`, sem membership do owner/service_role e com `PASSWORD NULL`. Portanto, autenticação por senha deve falhar até que um segredo seja provisionado fora das migrations e do repositório. O procedimento futuro deve usar secret manager/variável protegida e testar uma conexão real como o LOGIN, incluindo username `[ROLE].[PROJECT-REF]` no Shared Pooler. A documentação Supabase confirma suporte a custom LOGIN roles em conexões diretas e poolers; a documentação PostgreSQL 15 confirma que o membro `INHERIT` herda os privilégios do grupo `NOLOGIN`, pode usar o EXECUTE herdado sem `SET ROLE`, e também pode `SET ROLE` para o executor. Este contrato permanece sem teste de conexão real.

Foi preparado `catalog_postgres_writer_v2.mjs`, que implementa o mesmo contrato `rpc(name,args)` do processador e permite somente as duas chamadas SQL constantes com parâmetro JSONB vinculado. O adaptador é independente de driver e delega ao `query` injetado a aplicação efetiva do timeout e TLS. Ainda não existe driver Deno integrado ao entrypoint. O arquivo manual `supabase/operations/cutover_catalog_writer_v2.sql` contém precondições transacionais para revogar `service_role`; está fora da pasta migrations para evitar corte automático caso várias migrations sejam aplicadas juntas. O consumidor atual permanece em PostgREST/service_role. Não executar esse script até a nova conexão LOGIN passar em PostgreSQL local, o consumidor trocar de transporte e a implantação do novo consumidor ser autorizada.

Para a conexão Edge futura, a documentação oficial do Supabase recomenda o transaction pooler para workloads serverless e informa que esse modo não suporta prepared statements; a amostra oficial do cliente `postgres` configura `prepare: false`. A composição concreta ainda precisa fixar uma versão do driver já aprovada, TLS obrigatório, limite de conexões, cancelamento/timeouts do driver e formato de `SUPABASE_CATALOG_DATABASE_URL`, mantendo service_role ausente e proibindo fallback. Referências: [Edge Function → PostgreSQL](https://supabase.com/docs/guides/functions/connect-to-postgres), [conexão e poolers](https://supabase.com/docs/guides/database/connecting-to-postgres), [custom roles no Supabase Pooler](https://supabase.com/docs/guides/database/connecting-to-postgres#connecting-to-supabase-with-the-shared-pooler) e [membership de roles PostgreSQL 15](https://www.postgresql.org/docs/15/role-membership.html). Não houve credenciais, consultas remotas nem provisionamento de roles nesta etapa.

## Varredura limitada e checkpoint global — etapa 07.5.6B

O adapter examina até 4 páginas de 25 documentos por execução (máximo 100 docs), mantendo `readTime` e ordenação determinística por `__name__`. Backoff, leases ativos, registros malformados sem timestamp elegível e estados não ativos são filtrados depois da consulta, mas não bloqueiam páginas posteriores. A configuração atual processa no máximo 1 evento por chamada Edge; métricas distinguem páginas/documentos examinados, elegíveis e reivindicados.

`catalog_outbox_scan_state/consumer-v1` persiste o cursor do snapshot e usa lease transacional global. Uma chamada seguinte retoma o snapshot; ao final, o cursor é limpo. Se o snapshot exceder 45 minutos, a consulta abre um `readTime` novo depois do último ID confirmado, preservando avanço sem voltar ao início a cada execução. Inserções com IDs anteriores ao cursor são vistas no próximo ciclo completo. Falha libera o lease preservando o cursor; falha ao confirmar checkpoint retorna erro sanitizado e não confirma trabalho parcial. O documento é limitado pelo adaptador REST ao ID fixo; não há match para essa coleção nas Rules candidatas, então clientes não ganham acesso. A confirmação das Rules/IAM hospedados não ocorreu.

O orçamento de scanner é até 100 documentos em 4 consultas `runQuery`, batch de no máximo 1 evento e chamadas REST individuais limitadas a 3 s (Firestore) e 5 s (Supabase). No pior caminho esperado de um evento, há até quatro consultas de scan, transações Firestore de acquire/advance e no máximo uma sequência claim/read/canonical/write/ack ou retry; a estimativa conservadora por limites de chamada é abaixo de 100 s, contra o timeout pg_net de 140 s e o teto Edge Free documentado de 150 s. O lease do evento é 120 s e o lease da varredura 180 s; se a plataforma interromper a execução, o lease global bloqueia nova execução somente até 180 s. Esses limites ainda precisam ser medidos no Edge Runtime gerenciado. Sob backlog finito e invocações que continuem, o cursor atravessa cada página ativa do snapshot; ao expirar `readTime`, a busca abre snapshot novo depois do último ID, em vez de reiniciar no início. IDs inseridos atrás do cursor ficam para o próximo ciclo completo, não são perdidos. Um fluxo infinito de gravações não tem garantia de latência finita.

## Índice da consulta

`queryOutboxPage` usa somente `state IN ('pending','processing')` e ordenação ascendente por `__name__`, com limite e cursor no nome do documento. Não há filtro composto; com indexação automática padrão, o índice ascendente de campo único `state` inclui a ordenação final por `__name__`, portanto não se prevê índice composto. A configuração atual não isenta `catalog_outbox.state`. Se forem adicionados filtros por `nextAttemptAt`/`leaseExpiresAt` ou uma ordenação diferente, o plano de índices deve ser reavaliado. Índices e comportamento precisam ser conferidos no projeto real antes de liberar; Emulator não comprova que os índices hospedados estejam prontos. Consulte a [visão de índices do Firestore Standard](https://docs.cloud.google.com/firestore/native/docs/standard-index-overview).

Leituras transacionais por ID usam `documents:runQuery` com igualdade em `__name__` e o token da transação no corpo JSON. A forma REST `GET ...?transaction=` é válida na API, mas o Emulator local v1.22.0 lançou `Unmapped JavaType: BYTE_STRING` e deixou o pedido sem resposta. O caminho `runQuery` passou no Emulator e mantém a leitura na transação; a API documenta `transaction` no corpo de `runQuery` ([referência oficial](https://docs.cloud.google.com/firestore/docs/reference/rest/v1/projects.databases.documents/runQuery)).

## Validação local

- Testes Node com store Firestore em memória e RPC Supabase simulada comprovam composição, versão V1/V2, concorrência simulada, retry, replay, tombstone e perda de lease. Eles não provam transações Firestore reais nem disponibilidade do Supabase.
- `firebase_firestore_outbox_emulator.integration.test.mjs` usa o Firestore Emulator somente quando `FIRESTORE_EMULATOR_HOST` contém um endereço numérico de loopback. No Emulator v1.22.0, a suíte passou com duas transações REST independentes disputando o mesmo evento: uma confirmou, a outra recebeu `ABORTED`, e a leitura posterior mostrou um único claim/lease. Também exercitou renovação, expiração/takeover, negação de confirmação pelo lease antigo, ciclo V1, rejeição de V2 inválido, paginação no mesmo `readTime`, cursor expirado, processador, retries, tombstone e replay após falha de confirmação. O teste injeta IDs e conteúdo sintéticos no banco efêmero; o destino Supabase continua simulado. Não importar nem exportar dados.
- A execução local desta etapa concluiu esse teste integrado (1/1) no projeto demo, e a suíte Node compartilhada terminou em 141 aprovados, 0 falhas e 1 teste de Emulator intencionalmente ignorado na execução sem host. A suíte Functions terminou em 185/185. O Emulator foi iniciado somente em loopback, sem Rules, importação ou exportação; logo isso não valida Rules nem IAM.
- Para a execução manual, vincular exclusivamente o JAR local do Firestore Emulator ao host `127.0.0.1`, projeto `demo-universal-search`, sem `--import-data`, `--seed_from_export` ou `--export-on-exit`; configurar `FIRESTORE_EMULATOR_HOST=127.0.0.1:<porta>` apenas no processo Node. Encerrar somente o PID iniciado pelo teste.
- Nenhuma validação hospedada ocorreu. Antes de liberar sincronização, ainda são necessários: validação IAM e secret manager, teste de índices no projeto, confirmar a identidade Supabase com o privilégio mínimo, testar erros SQL reais no Supabase local isolado e definir limites operacionais/reconciliação.

## Identidade e permissões — preparação 07.5.6C (22/10/2026)

### Firebase

O Edge Function atual assina assertion de service account e troca por OAuth access token de curta duração. A chave privada JSON continua sendo uma credencial de longa duração, embora o token OAuth usado nas chamadas Firestore expire. O adaptador aceita um `getAccessToken` injetável, mas o entrypoint de produção local continua configurado para a chave JSON; não há credencial externa de identidade emitida pelo runtime Edge. Workload Identity Federation só funciona quando há um IdP externo confiável emitindo credencial OIDC/SAML/X.509 aceita pelo pool Google. Não foi encontrado no runtime/configuração local um token de workload Supabase que satisfaça essa condição; não afirmar WIF para este desenho.

O caminho menos arriscado sem trocar a plataforma é manter uma conta de serviço dedicada, chave apenas em Secret Manager de Edge, IAM customizado mínimo, chave rotacionada e ambientes/projetos separados. Isso deixa risco residual de chave estática. Alternativa mais forte é mover o consumidor para Cloud Run Job/Cloud Scheduler com service account anexada e ADC, ou fornecer um IdP/broker de workload efetivamente atestado; isso muda a hospedagem e pode exigir billing. A escolha não foi ativada.

O entrypoint agora exige `FIREBASE_PROJECT_ID`, valida a sintaxe, valida JSON sintético/real sem imprimir conteúdo e exige `project_id` e `client_email` compatíveis. Configuração ausente, inválida ou cruzada mantém o consumer desabilitado. Isso previne seleção acidental do projeto histórico por default; não substitui IAM nem protege uma chave válida roubada. `FIREBASE_SERVICE_ACCOUNT_JSON` continua lido apenas dentro da função server-side e os erros do signer são sanitizados.

### Matriz IAM candidata por método REST

| Operação do consumer | Método REST usado | Permissão IAM necessária | Justificativa / prova futura |
|---|---|---|---|
| Abrir transação read-write e rollback best-effort | `documents:beginTransaction`, `documents:rollback` | `datastore.databases.get` | Google documenta essa permissão para begin/rollback de transação. Testar início, callback abortado e rollback sem commit. |
| Consultar página ordenada da outbox | `documents:runQuery` com collection query | `datastore.entities.get`, `datastore.entities.list` | `runQuery` exige ambas; testar query permitida e falta individual de cada permissão. |
| Ler evento/checkpoint dentro da transação | `documents:runQuery` com igualdade em `__name__` | `datastore.entities.get`, `datastore.entities.list` | Mesmo método REST; o predicado por ID não reduz o permission set do método. |
| Criar o checkpoint `consumer-v1` na primeira execução | `documents:commit` com `currentDocument.exists=false` | `datastore.entities.create` | Apenas o primeiro commit que materializa o checkpoint; teste de criação e negação sem permissão. |
| Renovar/limpar checkpoint e alterar estado do evento | `documents:commit` com `updateTime`/exists precondition | `datastore.entities.update` | Claims, leases, retries, confirmação, superseded/dead-letter e avanço do cursor são atualizações. |
| Remover documento de evento/checkpoint | Nenhum caminho no adaptador | Nenhuma; `datastore.entities.delete` não necessária | Confirmado por inspeção dos métodos `create`/`update`; teste futuro deve negar DELETE sob a identidade. |

IAM de entidade não oferece a fronteira por coleção esperada: o allowlist do cliente REST é defesa de código, mas uma credencial IAM com `entities.get/list/update/create` pode chamar Firestore diretamente dentro do escopo que recebeu. Não conceder `roles/datastore.user` como mínimo: esse role agrega `datastore.entities.*` e permissões adicionais. Criar role customizado somente depois de testar no projeto de homologação, preferindo escopo de banco se o produto aceitar; se o consumidor não puder ter acesso amplo aos demais documentos do banco, separar banco/projeto ou usar broker com autorização própria. A matriz foi derivada da [tabela oficial de permissões por método Firestore](https://docs.cloud.google.com/firestore/native/docs/security/iam); Emulator não prova IAM.

### Invocador e agendamento

O invocador é separado da identidade Firestore e da identidade SQL. O endpoint usa HMAC SHA-256 dedicado, timestamp de 90 s e envelope fixo; `verify_jwt=false` é necessário ao modelo atual, mas não é autenticação. A chave publishable identifica o projeto/API, não autoriza executar o consumer. Guardar segredo HMAC no Vault do Postgres e no secret da função, rotacionar coordenadamente com job pausado e testar apenas em homologação. Uma reprodução dentro da janela ainda pode causar uma varredura adicional limitada; checkpoint lease global e idempotência protegem o dado, não eliminam uso de quota.

### Supabase/PostgreSQL

`service_role` e a nova `sb_secret_...` são chaves server-only privilegiadas e bypassam RLS; a key nova facilita identificação/rotação e bloqueia certos usos em browser, mas não cria privilégio restrito. A RPC REST atual limita o código a duas funções, porém o token continua tendo amplo acesso em outras rotas. Não substituir por publishable key nem assinar JWT com segredo de projeto achando que isso reduz privilégio.

Alternativa candidata de privilégio mínimo: Deno Postgres client via Shared Pooler em transaction mode, com uma role login dedicada, sem `BYPASSRLS`, sem grants de tabela e com acesso a um schema não exposto contendo dois wrappers `SECURITY DEFINER` de `search_path=''`, que chamam os escritores atuais e aceitam somente JSON de projeção/tombstone. Wrapper EXECUTE somente à role dedicada; login/senha só em secret server-side, rotacionável. Supabase documenta o acesso Postgres a partir de Edge Functions e recomenda transaction pooler para workloads serverless; não usar `SUPABASE_DB_URL` sem comprovar que não é superuser. Esta alternativa exige driver e migration/grants, auditoria de `PUBLIC` executables e teste de todas as RPCs públicas para não afetar compatibilidade. Não foi implementada: não havia PostgreSQL/psql local nem CLI Supabase disponível, e Docker não foi iniciado. A documentação oficial consultada: [Edge → Postgres](https://supabase.com/docs/guides/functions/connect-to-postgres), [connection pooling](https://supabase.com/docs/guides/database/connecting-to-postgres) e [API keys e papéis](https://supabase.com/docs/guides/getting-started/api-keys).

### Homologação bloqueada

Antes de um teste hospedado ainda são necessários: escolher Supabase Edge com risco formal da chave estática Firebase ou mover consumidor para ambiente com identidade gerenciada; provisionar SA dedicada/IAM e provar negativos; validar índices; escolher `service_role`/secret com risco aceito ou construir/testar role SQL restrita; validar rotação HMAC; confirmar Edge runtime e job comentado. Nenhum projeto, identidade, chave, role, extensão, índice, Cron ou segredo foi criado nesta etapa.

## Planejador de reconciliação read-only

`catalog_reconciliation.mjs` compara uma página já carregada de documentos canônicos,
projeções V2 e tombstones. Ele não consulta Firestore/PostgreSQL nem aplica ações. O
relatório diferencia projeção ausente/antiga, tombstone ausente/antigo, versões em
conflito, destino mais novo, registro canônico ausente e origem inválida. Detecta IDs de
operação canônicos duplicados e divergência entre tombstone e metadados da projeção.
Payloads recomendados são produzidos pela allowlist já usada pelo processador; dados
privados não aparecem no relatório.

Um tombstone de destino sempre bloqueia publicação automática, mesmo que o documento
canônico pareça mais novo. Registro Supabase sem origem Firestore não é excluído; vai
para revisão manual. Versões iguais com operação ou conteúdo divergente também exigem
revisão. Despublicação continua sendo uma projeção normal com `published=false`, não
um tombstone. Um campo `deleted_at` na própria projeção também bloqueia tentativa de
republicação quando a página de tombstones estiver incompleta.

O planejador é somente uma comparação de snapshots fornecidos pelo chamador. O scanner
abaixo acrescenta paginação e contrato de checkpoint injetável, mas ainda não possui
adapters reais, armazenamento durável, escrita de backfill ou revalidação transacional
imediatamente antes da aplicação. Antes de qualquer backfill, o executor deverá reler a
versão canônica, usar o escritor idempotente V2, registrar cursor/readTime em checkpoint
durável e pausar em conflito/tombstone. Os testes atuais usam fixtures sintéticas e não
comprovam consistência temporal de leituras entre Firestore e Supabase.

### Scanner paginado read-only

`catalog_reconciliation_scan.mjs` percorre páginas já unidas pelo adapter de leitura e
chama o planejador acima. O reader deve retornar os documentos canônicos, projeções e
tombstones da mesma página lógica, ordenados pela união dos IDs, e ecoar exatamente o
`snapshotId` solicitado. O cursor é o último ID da página; IDs repetidos entre páginas,
ordem incorreta, páginas acima do limite e snapshot divergente falham antes de salvar
recomendações.

O `checkpointStore` precisa implementar `load(snapshotId)` e `commitPage(...)` com
compare-and-swap em `expectedSequence`. `commitPage` deve persistir findings e novo
checkpoint atomicamente; caso contrário, uma queda entre as duas escritas pode perder ou
duplicar resultados. O módulo não oferece armazenamento concreto e não usa a outbox de
produção para checkpoints. Limites atuais: até 200 IDs por página e 1.000 páginas por
execução; `maxPages` menor permite pausa retomável. Erro de leitura, snapshot expirado,
checkpoint inválido ou conflito de concorrência é sanitizado e nunca reinicia a varredura
automaticamente.

Isso continua sendo um scanner de diagnóstico, não um backfill: nenhum writer de
Firestore/PostgreSQL é injetado e nenhuma ação recomendada é aplicada. O adapter real
precisa comprovar que o token representa snapshots estáveis de ambas as fontes. Como
Firestore e PostgreSQL não fornecem um snapshot distribuído comum, findings só podem ser
tratados como candidatos; antes de uma futura escrita, a versão canônica e o tombstone
devem ser relidos e o escritor V2 deve revalidar a monotonicidade. O planner detecta IDs
de operação duplicados dentro de cada página; uma implementação persistente deve também
provar unicidade global antes de promover o relatório a backfill.
