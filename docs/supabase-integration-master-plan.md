# Plano mestre — Firestore canônico → Supabase V2

Atualizado em 22/10/2026. Este registro acompanha a execução local e separa
claramente evidências locais de homologação hospedada.

## Baseline e regras de preservação

- Branch observada: `codex/supabase-search-pilot`.
- HEAD observado no início desta execução: `f767b17ba781d4931c9b241ebcc04ea06174b52e`.
- Baseline confirmada em 21/10/2026 para a etapa 07.5.7D: 242 caminhos em
  `git status --short --untracked-files=all` (133 linhas no formato compacto),
  zero staged. Branch `codex/supabase-search-pilot`; HEAD
  `f767b17ba781d4931c9b241ebcc04ea06174b52e`.
- Quatro exclusões antigas de TOML continuam preservadas como estavam. A contagem
  histórica de 145 caminhos não foi tratada como invariante; nenhum reset ou restore
  foi executado.
- Firebase/Supabase hospedados, credenciais reais, deploy, commit e push não foram usados.

## Etapas

| Etapa | Estado | Evidência / pendência |
|---|---|---|
| 07.5.1–07.5.4 — Rules, protocolo, adaptador e processador | APROVADA LOCALMENTE (histórico informado) | Rules candidatas e Firestore Emulator foram validados em etapas anteriores; as Rules principais não foram publicadas. |
| 07.5.5 — Persistência PostgreSQL local | APROVADA LOCALMENTE | Quatro migrations aplicadas no PostgreSQL 15.19 descartável. pgTAP histórico: 28/28 + 48/48 + 93/93 + 49/49 = 218/218; concorrência entre sessões: 11/11. Nesta continuação, Firestore Emulator → processador → RPC real via PostgREST HTTP 14.18 → PostgreSQL → confirmação Firestore passou 1/1. O teste atual publicou somente PostgREST em loopback; DB sem porta host, dados em tmpfs e migrations RO. O runtime Edge habilitado e serviços hospedados continuam pendentes. |
| 07.5.6 — Consumidor agendável | INTEGRAÇÃO LOCAL REAL VALIDADA; HOMOLOGAÇÃO HOSPEDADA PENDENTE | Deno 2.9.7, PostgreSQL 15.19 e Firestore Emulator foram integrados localmente em 07.5.6G; 07.5.6H corrigiu lint e validou TLS local com certificado sintético. A regressão atual: shared Node 247 aprovados/6 condicionais ignorados, Functions 196/196, consumidor Deno 3/3, lint/check/formatação Deno aprovados e testes focalizados do driver/configuração/agenda 13/13. O consumer continua desligado por padrão; sem credenciais reais, IAM, pooler, Edge Runtime gerenciado ou Cron hospedado validados. Consultar as seções 07.5.6G/H. |
| 07.5.6C — Segurança/identidade do consumidor | PREPARADA LOCALMENTE — IDENTIDADE, IAM, CREDENCIAL SQL E EDGE HOSPEDADOS PENDENTES | O entrypoint agora exige `FIREBASE_PROJECT_ID` explícito e confere a correspondência do projeto no JSON de conta de serviço; ausência/mismatch mantém o handler desligado. Configuração, checkpoint e handler tiveram testes locais. IAM mínimo foi mapeado por método REST. WIF não está disponível automaticamente no Edge runtime atual; `service_role`/secret key continuam privilegiadas. Não foram criados papéis, IAM ou credenciais, e não houve teste SQL nesta etapa: `psql`/Supabase CLI não disponíveis e Docker não foi iniciado. Ver seção 07.5.6C ao final. |
| 07.5.6D — PostgreSQL restrito + writer | VALIDADA LOCALMENTE EM POSTGRESQL 15.19 | Migration preparada e executada somente no PostgreSQL descartável. As roles foram comprovadas por pgTAP e conexão real do LOGIN por TCP loopback com senha aleatória efêmera. `service_role` continua compatível; o corte manual não foi executado. O entrypoint continua PostgREST e ainda não usa o driver LOGIN. |
| 07.5.6F — validação das permissões PostgreSQL | VALIDADA LOCALMENTE — HOSPEDADO PENDENTE | PostgreSQL 15.19 isolado, 6 migrations em ordem, 319/319 pgTAP e 11/11 checks de concorrência real. Login TCP provou só CONNECT + as duas RPCs V2; SELECT/INSERT/UPDATE/DELETE diretos nas duas tabelas, RPC de snapshot e SET ROLE owner foram negados (42501). Sem acesso hospedado, sem credenciais persistidas; consumidor/driver, pooler e IAM continuam pendentes. |
| 07.5.7 — Migração dos produtores administrativos | IMPLEMENTAÇÃO LOCAL PREPARADA — ATIVAÇÃO BLOQUEADA | Nesta etapa, as candidatas V1/V2 passaram 36/36 cenários integrados, incluindo exclusão física negada; o handler autenticado passou 4/4. Ainda falta provar os fluxos Flutter reais do ContentEditor/importador contra os Emulators. O caminho híbrido continua opt-in e a rota padrão ainda escreve diretamente em fluxos legados. Ativação depende de compatibilidade de clientes, Rules principais, endpoint autenticado e produtores migrados. |
| 07.5.8 — IAM, índices e homologação | PENDENTE | Emulator não comprova IAM nem índices hospedados. Avaliar conta de serviço dedicada com escopo mínimo compatível com Firestore, índices compostos reais e chave Supabase estritamente server-side. Nenhuma chamada hospedada executada. |
| 07.5.9 — Reconciliação/backfill | APROVADA LOCALMENTE (varredura read-only) | Leitor pareia o readTime do Firestore Emulator e o snapshot PostgreSQL privado; scanner e checkpoint local durável/CAS foram exercitados juntos com PostgREST e Firestore Emulator. Nenhum writer do catálogo foi chamado e nenhum backfill foi executado. Permanecem homologação de IAM/índices, execução hospedada autorizada e desenho/validação separados para qualquer aplicação de recomendações. |
| 07.5.10 — Implantação gradual | PREPARADA LOCALMENTE / IMPLANTAÇÃO BLOQUEADA | Checklist de pausa, canário, monitoramento e rollback documentado abaixo. Execução hospedada continua bloqueada pelas pendências de IAM/índices e integração operacional das etapas 07.5.6–07.5.8; nenhum recurso foi publicado. |

### Auditoria de produtores — 07.5.7

- Estado atual após a continuação registrada abaixo: `ContentEditor` e
  `InitialContentImporter.importExamples()` oferecem uma rota explícita de desenvolvimento
  para `manage-establishments`, condicionada a `HYBRID_ADMIN_ENABLED=true` em build debug.
  Nessa rota, remoção é exclusão lógica versionada e o importador preserva IDs `modelo-*`.
- A rota padrão ainda grava diretamente no Firestore: o editor pode usar
  `DocumentReference.delete()` e o importador faz batch. Esses caminhos não emitem outbox;
  por isso a rota híbrida não foi habilitada por padrão e a migração operacional permanece
  incompleta até validar endpoint/runtime, Rules/clientes e todos os produtores relevantes.
- Os gatilhos `business_search_functions.js` / `business_search.js` atualizam o índice
  de busca legado; eles não são consumidores Supabase e não devem ser removidos antes
  da migração dos leitores.
- A função administrativa foi ampliada localmente com `delete` lógico, timestamp
  server-side e outbox atômica. As Rules principais continuam intactas; publicar a
  candidata ou habilitar a rota híbrida sem migrar os fluxos padrão pode bloquear
  gravações existentes.

## Implementação local de 07.5.6 nesta execução

- `supabase/functions/_shared/catalog_outbox_consumer.mjs`: endpoint POST sem payload
  configurável pelo cliente, desligado por padrão, limite de página de até 25, trava
  de concorrência por isolate e resumo de resultados sanitizado.
- Autenticação de máquina: HMAC-SHA-256 de segredo de pelo menos 32 bytes sobre
  versão, método, caminho e timestamp; janela de validade de 90 segundos. Nenhum
  segredo é embutido, logado ou devolvido. O processamento continua protegido pelos
  leases transacionais Firestore entre isolates/processos.
- `supabase/functions/_shared/supabase_catalog_rpc_rest.mjs`: transporte PostgREST
  com allowlist apenas para `apply_establishment_projection_v2` e
  `apply_establishment_tombstone_v2`, URL HTTPS (HTTP permitido só em loopback),
  corpo/timeout limitados e erro upstream sanitizado.
- `supabase/functions/consume-catalog-outbox/index.ts`: composição server-side,
  desligada salvo opt-in `CATALOG_CONSUMER_ENABLED=true` e presença de todos os
  segredos. O HMAC é requisito adicional porque `verify_jwt=false` é necessário
  para esta autenticação não baseada em JWT Supabase.
- `supabase/config.toml`: configuração local da nova função com `verify_jwt=false`;
  o handler valida HMAC antes de acessar Firestore/PostgreSQL. Isso não foi publicado.
- `supabase/functions/_shared/admin_establishments.mjs`: adicionada operação
  administrativa `delete` lógica; grava `deletedAt` pelo timestamp do servidor,
  despublica, incrementa a versão e cria outbox na mesma transação. O bloqueio
  existente impede update/republish posteriores. Não realiza exclusão física.
- Testes Node do handler e do transporte não acessam rede nem usam credenciais reais.
  A integração real de lógica local usou somente o Firestore Emulator em loopback e
  o PostgreSQL descartável com `--network none`.

## Agendamento e segurança ainda pendentes

A documentação oficial atual do Supabase descreve agendamento com `pg_cron` e
invocação HTTP com `pg_net`, guardando URL/chaves no Vault. Isso oferece um caminho
simples, mas não prova que extensões, frequência, limites ou custos estão incluídos
no plano do projeto. Confirmar no plano e no painel antes de qualquer ativação.
Referências: [agendar Edge Functions](https://supabase.com/docs/guides/functions/schedule-functions),
[autenticação de funções](https://supabase.com/docs/guides/functions/auth),
[pg_cron](https://supabase.com/docs/guides/cron) e
[pg_net](https://supabase.com/docs/guides/database/extensions/pg_net).

O segredo HMAC deverá ser criado/rotacionado fora do Git e disponibilizado ao
agendador via Vault; o segredo da função deverá ser configurado separadamente no
ambiente de execução. `SUPABASE_SERVICE_ROLE_KEY` no Edge Function é um risco
residual de privilégio amplo: o escritor SQL aceita apenas duas RPCs por allowlist,
mas a chave `service_role` pode ter privilégios adicionais. Resolver uma identidade
PostgREST realmente restrita a EXECUTE antes da homologação.

O entrypoint também espera `FIREBASE_SERVICE_ACCOUNT_JSON`, uma chave estática de
servidor que não foi fornecida nem testada. Antes da implantação, avaliar identidade
Google sem chave exportável ou, se indisponível no runtime escolhido, definir cofre,
rotação, controle operacional e aceitação formal do risco residual.

### Preparação local do consumidor e agenda — 07.5.6 (22/10/2026)

- Estado: **IMPLEMENTAÇÃO LOCAL PREPARADA; HOMOLOGAÇÃO EDGE, IAM E AGENDAMENTO HOSPEDADOS PENDENTES**.
- `consume-catalog-outbox` aceita somente POST autenticado por HMAC SHA-256 com
  janela de 90 s e corpo ausente ou exatamente `{}`. O envelope `{}` é o padrão
  JSON enviado pelo `pg_net`; parâmetros de lote/cursor continuam proibidos. `verify_jwt=false`
  permanece necessário para esse endpoint HMAC, mas o handler continua fail-closed
  quando flag ou qualquer configuração estão ausentes.
- Cada chamada Edge executa no máximo 1 evento, após varrer até 4 páginas de 25
  documentos (100 examinados). REST Firestore tem timeout configurado de 3 s por
  requisição e PostgREST de 5 s. O exemplo inerte de agenda
  usa timeout HTTP `pg_net` de 140 s, abaixo do teto documentado de 150 s por execução
  Edge no plano Free. Essas cotas e a disponibilidade de `pg_cron`, `pg_net` e Vault
  precisam ser confirmadas no projeto/plano antes de ativar.
- Métricas emitidas são agregadas e sanitizadas: execução, duração, contagens por
  estado, backlog indicado por `hasMore`, rejeição de sobreposição e falha HMAC
  amostrada por isolate a cada 10 s. Não carregam IDs, cursores, payload, segredo ou
  erro bruto. A amostragem é local ao isolate, portanto não é limite global de logs.
- O artefato `supabase/schedules/consume_catalog_outbox.sql.example` tem todas as
  linhas executáveis comentadas; pode ser aberto/revisado, mas não é migration e não
  foi aplicado. `pg_net` é assíncrono: agendar/encaminhar não prova sucesso da função;
  operação futura terá de correlacionar o ID com `net._http_response` e validar status.
- Validação local atualizada (22/10/2026): Node shared **225 aprovados, 0 falhas,
  6 integrações condicionais ignoradas**; Functions `npm test` **196/196**;
  `npm run check` aprovado. Deno 2.9.7: check e lint passaram; formatação passou
  para os dois arquivos TypeScript Deno; testes do handler **2/2**. O `deno fmt`
  não foi aplicado aos módulos `.mjs` existentes, cujo estilo de aspas/quebras é
  controlado pelo padrão Node do projeto. Firestore Emulator isolado: **2/2 testes
  de integração passaram em execuções separadas**. O teste do adaptador provou
  transações concorrentes independentes, claim único, takeover de lease, retry,
  confirmação e cursor expirado rebaseado. O teste do scanner/checkpoint usou 27
  eventos sintéticos: 12 em backoff, 13 com lease ativo, um V2 elegível e um V1
  elegível; a primeira execução avançou após 26 documentos e persistiu o cursor; a
  seguinte processou V1 e limpou o checkpoint.
  A configuração temporária do Emulator usou Rules permissivas fora do repositório
  apenas para testar o adaptador de servidor; não é validação das Rules de cliente.
  A integração usou RPC de destino simulada, não repetiu PostgreSQL nem testou o
  Supabase Edge Runtime gerenciado.
- Custos ilustrativos do exemplo (uma invocação a cada 10 min): 144 chamadas/dia,
  4.320 em 30 dias e no máximo 144 eventos processados/dia quando cada chamada
  encontra um elegível. O scanner examina até 14.400 documentos/dia; somando até
  quatro leituras transacionais por evento e duas leituras do checkpoint por run,
  o teto aproximado deste caminho é 15.264 leituras e 576 gravações Firestore/dia,
  antes de retries, varreduras extras e tráfego de outros recursos. São limites
  teóricos de operação, não consumo medido nem previsão de fatura; recalcule após
  medir backlog, frequência e cotas já usadas.
- Bloqueios de segurança não resolvidos: o entrypoint requer `FIREBASE_SERVICE_ACCOUNT_JSON`
  (chave privada estática) e `SUPABASE_SERVICE_ROLE_KEY` (credencial de privilégio
  amplo). Não foi demonstrada Workload Identity Federation no runtime Edge nem uma
  chave PostgREST com privilégio restrito somente às RPCs privadas. O HMAC é segredo
  compartilhado, não identidade de workload; há janela de replay de 90 s, mitigada
  pelo corpo fixo, lote limitado e leases/idempotência, mas replay pode consumir uma
  invocação adicional. Não criar ou provisionar chaves até decidir uma identidade e
  um mecanismo de rotação seguros.
- Separação de identidade confirmada para planejamento: (A) o invocador é autenticado
  pelo HMAC dedicado no handler, não pela publishable `apikey`; `verify_jwt=false`
  sozinho não autoriza nada. A assinatura aceita só POST, caminho fixo, envelope vazio
  e timestamp de 90 s. Não há nonce persistido; replay dentro da janela pode iniciar
  outra varredura limitada, controlada pelo lease global e pela idempotência. Rotação
  futura precisa pausar o Cron, trocar o mesmo segredo no Vault e no secret da função,
  testar uma chamada sintética e então reativar; divergência falha fechada. (B) Firestore
  usa hoje service-account JSON estático; a Edge Function não recebe automaticamente
  uma identidade Google/ADC, e federação não foi demonstrada. (C) PostgREST usa hoje
  `service_role`, que tem `BYPASSRLS`; não equivale a uma role restrita, mesmo com as
  RPCs allowlisted. A alternativa localmente não validada é um usuário PostgreSQL dedicado
  de conexão direta/pooler, sem grants de tabela, somente `USAGE` do schema e `EXECUTE`
  nas duas RPCs `SECURITY DEFINER` existentes, com `NOINHERIT`/sem `BYPASSRLS`; isso
  requer conexão/driver e migration/grants revisados antes de qualquer implantação.
- Matriz IAM candidata do consumidor (não concedida): `datastore.databases.get` para
  begin/rollback de transação; `datastore.entities.get` e `datastore.entities.list`
  para `runQuery` por ID e varredura; `datastore.entities.update` para leases,
  confirmações e checkpoint; `datastore.entities.create` para a criação inicial do
  checkpoint. Nenhum método atual exige `datastore.entities.delete`. Essa lista segue
  a tabela oficial de permissões por método; Emulator não a comprova. IAM é mais amplo
  que o allowlist: permissões de entidade não são limitadas a coleções, portanto a
  identidade poderia ler/listar e atualizar outros documentos no escopo autorizado,
  e criar outros documentos. Revisar escopo de banco/projeto e um broker mais estreito
  antes de homologar. Nenhum IAM real foi criado.
- Equidade/backlog: a consulta de estados ativos agora varre páginas determinísticas
  após filtrar backoff e leases; o checkpoint serializa execuções e persiste avanço.
  O cursor usa snapshot estável e, após 45 min, reabre `readTime` novo depois do último
  ID; eventos inseridos antes do cursor entram no próximo ciclo. Testes unitários e a
  prova Emulator demonstraram avanço no backlog coberto. Uma taxa de inserção superior
  à capacidade de processamento pode aumentar indefinidamente a latência, e IDs novos
  atrás do cursor aguardam o ciclo seguinte.
- Próximo gate: validar o handler no Supabase Edge Runtime compatível, definir identidades
  separadas e privilégio mínimo, confirmar IAM/índices em homologação e autorizar
  explicitamente qualquer credencial ou agenda. Deno local e Emulator não substituem
  essas provas; a etapa permanece **não homologada**.

Índices: a consulta atual filtra `state IN (pending, processing)` e ordena por
`__name__`; o Emulator não valida a disponibilidade nem a prontidão de índices do
serviço hospedado. Confirmar o plano da consulta e quaisquer índices indicados antes
de homologar.

## Próximos passos locais

1. Disponibilizar o Deno/Supabase Edge Runtime já autorizado ou solicitar autorização
   específica para ferramenta faltante; validar imports/handler sem secrets reais.
2. Disponibilizar PostgREST local compatível e executar o teste de RPC via HTTP,
   preservando as provas SQL atuais.
3. Revisar autenticação machine-to-machine, rotação HMAC e chave Postgres de menor
   privilégio; não ativar cron.
4. Validar `delete` lógico versionado nas Rules candidatas/Emulator.
5. Adaptar `ContentEditor` e `InitialContentImporter` a um cliente server-side,
   preservando IDs, versões e respostas; cobrir com testes locais.
6. Só depois migrar escritores e coordenar as Rules candidatas, preservando clientes
   antigos suportados.
7. Preparar IAM/índices em projeto de homologação somente após autorização expressa.
8. Não avançar a produção sem evidência hospedada e aprovação final.

## Fechamento desta execução (21/10/2026)

- `functions`: `npm test` passou 185/185; `npm run check` já havia passado.
- Testes compartilhados Supabase/Functions: `node --test supabase/functions/_shared/*.test.mjs`
  passou com 145 aprovados, 0 falhas e 2 testes de integração ignorados por não
  receberem as variáveis de execução. Os testes condicionais não substituem a prova
  integrada abaixo.
- Integração executada explicitamente: `catalog_outbox_postgres.integration.test.mjs`
  passou 1/1 com Firestore Emulator em `127.0.0.1:18087` e o PostgreSQL descartável
  `macacu-0755-pg-20261020`. O fluxo incluiu endpoint HMAC local, transações Firestore,
  escritor SQL e leitura do estado persistido. O destino foi chamado pelo bridge local
  `docker exec ... psql`, não por PostgREST HTTP.
- `git diff --check` passou; os avisos foram somente conversões de fim de linha CRLF/LF.
- O runtime Deno/Supabase Edge, PostgREST HTTP local, IAM hospedado e índices hospedados
  seguem sem validação. Não foi feita chamada remota nem ativado Cron.
- Recursos temporários usados: um container PostgreSQL sem rede/portas e um Firestore
  Emulator em loopback, projeto demo fictício, sem snapshots. Ambos foram encerrados ao
  final desta execução; imagem, volumes e demais serviços preexistentes permanecem.
  O container foi removido; o Emulator não mantém listener em 18087 e o Docker Engine foi
  desligado, como no início. Os volumes preexistentes `supabase_db_tmacacu-stage031-f3365ccf`
  e `supabase_db_tudo-aqui-macacu-search-pilot` continuam presentes. Git terminou com
  118 entradas visíveis, zero staged; os quatro TOMLs seguem como exclusões preexistentes.

### Estado final das etapas

- **07.5.5 — APROVADA LOCALMENTE (SQL + PostgREST HTTP)**: este fechamento registrou
  primeiro a persistência PostgreSQL pelo bridge `psql`; a integração HTTP ainda estava
  pendente naquele momento. A complementação posterior abaixo executou e aprovou o fluxo
  Firestore Emulator → processador → PostgREST → PostgreSQL → confirmação Firestore.
- **07.5.6 — APROVADA LOCALMENTE (protótipo fail-closed, sem agenda)**: handler HMAC,
  adaptador REST allowlisted, processador e composição Edge Function foram preparados.
  O entrypoint real foi carregado no Edge Runtime sem secrets e rejeitou requisições; os
  testes Deno do handler passaram. Isso não equivale a uma execução autenticada do
  consumidor com Firestore e PostgREST locais ou hospedados. Nenhum Cron foi criado ou
  ativado.
- **07.5.7 — EM EXECUÇÃO (auditoria + compatibilidade parcial)**: o contrato de criação
  do backend agora aceita opcionalmente um ID seguro fornecido pelo servidor cliente e
  mantém esse ID na outbox; isso permite preservar IDs `modelo-*` do importador. A
  mudança passou em teste Node, mas ainda não foi exercitada no Emulator após a mudança.
  ContentEditor e importador continuam gravando diretamente e a migração dos produtores
  permanece bloqueada até validar o runtime Edge e a integração cliente.

### Achados concretos de compatibilidade dos produtores

- A criação do backend gerava sempre UUID. Isso impedia o importador de preservar
  `modelo-*`; a API local agora aceita `entityId` opcional na criação, sujeita à mesma
  validação de ID já usada para updates. Sem `entityId`, o UUID server-side continua
  funcionando. A identidade fica vinculada ao `requestId` idempotente.
- O `InitialContentImporter` ainda faz leitura ampla da coleção para descobrir IDs
  existentes e envia `createdAt`, `updatedAt` e `source`; o endpoint rejeita esses campos
  de servidor/legado, como deve. A migração futura precisa usar request IDs estáveis,
  enviar apenas campos permitidos e tratar conflito como “já existente”, sem depender
  de leitura ampla do cliente.
- O `ContentEditor` envia `updatedAt` como sentinel Firestore e `expiresAt` como
  `Timestamp`/`FieldValue.delete`; o endpoint espera timestamp ISO ou `null`, pois
  controla `updatedAt` no servidor. O adapter Flutter terá de normalizar/remover esses
  valores e selecionar o contrato por operação.
- O botão de exclusão do editor ainda usa `DocumentReference.delete()` (exclusão
  física). Deve chamar `operation=delete` para tombstone versionado. Republicação após
  despublicação exige a operação explícita `republish`; o endpoint não aceita mudar
  `published=false` para `true` por update genérico.
- Não alterei Flutter ou Rules principais/candidatas: não há Deno/Edge Runtime nem
  endpoint local disponível para validar a chamada cliente/servidor ponta a ponta.
  Habilitar a candidata de Rules antes de migrar todos os produtores bloquearia o editor
  e o importador existentes.

## Continuação local — 07.5.7 (21/10/2026)

Estado antes de editar nesta continuação: mesma branch/HEAD, 120 entradas em
`git status --short`, zero staged; as quatro exclusões de TOML e todos os trabalhos
locais foram mantidos. Não foram iniciados serviços nem acessados endpoints hospedados.

Implementações e correções verificadas:

- `ContentEditor` encaminha, apenas quando `HYBRID_ADMIN_ENABLED=true` em build debug,
  criar/editar/despublicar/republicar e exclusão lógica pelo endpoint; caso contrário mantém o caminho
  preexistente. Versão é precondição, a payload passa por allowlist, categorias não
  empresariais não entram no catálogo, e falhas não fazem fallback para Firestore. A
  reserva de request ID permanece na tela após respostas ambíguas; somente resposta
  definitivamente inválida da tentativa atual pode descartá-la.
- `InitialContentImporter` no mesmo opt-in preserva `modelo-*`, não converte tipos de
  conteúdo não empresariais e cria cada fonte/outbox pela API. O caminho padrão continua
  inalterado enquanto a integração de servidor não for homologada.
- Backend aceita patch de campos allowlistados durante `republish`, sem permitir
  republicar tombstone. `unpublish` segue reversível e não grava `deletedAt`; `delete`
  lógico segue permanente/versionado.
- O ID REST Firestore foi alinhado às regras do documento: ID canônico até 1500 bytes
  UTF-8, sem `/`, `.` ou `..`, nomes reservados bloqueados; os IDs da outbox conservam
  a validação ASCII restrita. `Document.name`/`referenceValue` usam o nome de recurso
  canônico sem URI-encoding no corpo JSON. Fonte: [referência oficial Firestore
  Document](https://cloud.google.com/firestore/docs/reference/rest/v1/Document) e
  [Value.referenceValue](https://cloud.google.com/firestore/docs/reference/rest/v1/Value).
- O gateway `SecureBackend` local agora possui uma allowlist menor que a do transporte
  interno de busca, para rejeitar operações de detalhe não autorizadas antes de consultar
  o canal nativo. Os testes de recuperação de sessão local foram corretamente movidos
  para a matriz `search-local` e incluídos no job correspondente do CI.

Verificação desta continuação:

- Cliente híbrido Flutter: 26/26 na Etapa 06.1; análise Flutter completa: sem issues.
- Matriz Flutter normal do CI (`--exclude-tags search-local`): 610 aprovados, 24 pulados.
- Matriz local com defines demo/loopback: 52/52; App Check alternativo: 9/9.
- `functions`: 185/185; `npm run check` aprovado.
- Suíte compartilhada: 151 total, 149 aprovados, zero falhas e 2 integrações condicionais
  ignoradas sem variáveis de serviço. Nenhuma dessas duas contagens é prova hospedada.
- `git diff --check` aprovado. `dart format --output=none lib test` identificou 21
  arquivos pré-existentes fora do formato; não rodei formatação em massa para evitar
  reescrever alterações locais. Os arquivos novos do cliente e seus testes estão formatados.

Limite de 07.5.7: esta é uma rota opt-in de desenvolvimento, não uma migração operacional.
O endpoint ainda requer Supabase Edge Runtime, credencial/IAM Firestore confiáveis,
PostgREST de menor privilégio, secret management, Rules/clientes coordenados e validação
local da chamada HTTP ponta a ponta. A reserva do request ID do editor é mantida enquanto
a tela permanece aberta; se o app for encerrado após uma resposta ambígua, a chave não é
persistida entre processos. Isso deve ser resolvido antes de habilitar gravações remotas
como fluxo padrão. Nada foi ativado no build normal.

### Fechamento do inventário desta execução

Verificação final em 21/10/2026: branch `codex/supabase-search-pilot`, HEAD
`f767b17ba781d4931c9b241ebcc04ea06174b52e`, 121 entradas em `git status --short`, zero
staged. O início desta continuação havia 120 entradas; a diferença é trabalho local desta
execução e não foi removida nem restaurada. `git diff --check` passou. O comando de
formatação em modo `--output=none` não reescreveu arquivos; identificou apenas o arquivo
grande preexistente `lib/redesigned_app.dart` como fora do formatter, evitando formatação
em massa.

Bloqueio de runtime confirmado por inspeção somente leitura: `deno` e `supabase` não estão
no PATH disponível. Docker existe, mas nenhum serviço/container foi iniciado; não houve
instalações nem conexões hospedadas.

## Complemento de validação — PostgREST HTTP real (21/10/2026)

- A etapa 07.5.5 agora também passou pelo caminho HTTP real, sem substituir a prova SQL
  anterior: Firestore Emulator em `127.0.0.1:18087` → processador/handler HMAC → cliente
  PostgREST → RPC privada V2 → PostgreSQL 15.19 → confirmação Firestore. O teste
  `catalog_outbox_postgres.integration.test.mjs` passou 1/1, sem skip.
- As quatro migrations V1, hardening, V2 e escritor privado foram aplicadas em ordem.
  O PostgreSQL usou container descartável, dados em tmpfs (1 GiB), sem porta publicada
  e migration montada somente para leitura. PostgREST 14.18 ficou publicado somente em
  `127.0.0.1:25432`; JWT e senha eram sintéticos, efêmeros e não foram registrados.
  O bridge Docker permitiu egress teórico; nenhuma conexão a serviço hospedado foi feita.
- O fluxo passou por publicação, replay, atualização, evento antigo, despublicação,
  republicação, exclusão lógica/tombstone, retry após falha de transporte, replay após
  falha de confirmação Firestore, concorrência de dois workers e operações administrativas
  fictícias. A consulta final encontrou 9 projeções `e2e-*`, 3 tombstones `e2e-*`; no
  Emulator, 18 eventos estavam `synced` e 2 `superseded` após o teste. Esses dados eram
  sintéticos e foram removidos ao encerrar os containers/Emulator.
- A validação revelou e corrigiu duas incompatibilidades locais: (a) PostgREST standalone
  serve `/rpc/...`, enquanto Supabase atrás do gateway usa `/rest/v1/rpc/...`; o cliente
  REST agora mantém `/rest/v1` como padrão e aceita somente prefixo vazio ou esse prefixo
  fixo; (b) o escritor agora preserva os códigos sanitizados `catalog_conflict` e
  `permanent_failure` do adapter HTTP, convertendo conflito em resultado terminal em vez
  de retry transitório. Testes de regressão cobrem os dois comportamentos.
- Testes unitários do adapter REST/escritor: 12/12; teste integrado HTTP: 1/1; suite
  compartilhada: 151 aprovados, 0 falhas, 2 integrações condicionais puladas (153 total);
  suite `functions`: 185/185 e `npm run check` passaram. O teste condicional permaneceu
  pulado na execução sem variáveis; a integração HTTP foi executada explicitamente.
- Cliente administrativo Flutter: 14/14 testes e `flutter analyze --no-pub` sem issues;
  os novos casos verificam as requisições explícitas de despublicação e exclusão lógica.
  Isso valida o contrato do cliente com transporte mockado, não a chamada real do app a
  um Edge Runtime ativo.
- A rede bridge foi necessária para o processo Node no host alcançar PostgREST; somente
  a porta HTTP local foi publicada. O PostgreSQL permaneceu sem bind no host. O ambiente
  valida transporte local e persistência real em PostgreSQL, mas não valida runtime Edge,
  credenciais/IAM hospedados, índices hospedados, agendamento, nem segurança de egress
  do container bridge. Não habilita Cron ou produção.
- Limpeza: removidos somente os containers PostgreSQL/PostgREST e a rede desta validação;
  o Java do Firestore Emulator foi encerrado após o endpoint de shutdown responder 404 e
  confirmação de que o PID 3516 era o processo Java 21 que possuía a porta 18087. As portas
  18087/25432 ficaram livres. Docker Desktop voltou ao estado parado. Os dois volumes
  anteriores foram preservados. As imagens oficiais em cache foram mantidas; os CLIs e a
  cópia de configuração/função permanecem em diretórios temporários exclusivos desta
  execução, sem PATH/global changes.
- Estado após a validação: etapa 07.5.5 aprovada localmente incluindo HTTP/PostgREST;
  07.5.6 continua protótipo local, sem runtime habilitado, credenciais de máquina ou Cron;
  07.5.7 continua opt-in/debug até testar cliente contra runtime e Rules coordenadas;
  07.5.8–07.5.10 seguem pendentes de IAM/índices reais, reconciliação e implantação
  controlada. Não houve conexão hospedada ou mudança de Rules principais.
- Git final: branch `codex/supabase-search-pilot`, HEAD
  `f767b17ba781d4931c9b241ebcc04ea06174b52e`, 121 linhas em `git status --short`, zero
  staged e quatro exclusões TOML preservadas. Nenhum commit/push foi feito.

## Automação local do plano (21/10/2026)

- Criado `tools/hybrid-validation-runner.mjs` para executar as regressões locais em uma
  ordem única, com timeout, cancelamento da árvore de processos, interrupção no primeiro
  erro, resumo JSON por etapa e contagem de testes/skips quando o formato TAP é emitido.
- O padrão cobre Functions (testes e sintaxe), scripts Node, módulos compartilhados,
  regressões Python, análise Flutter, matriz Flutter normal, `searchLocal`, App Check e
  `git diff --check`. Não inicia serviços nem instala dependências.
- A integração Firestore Emulator/PostgreSQL só é adicionada com
  `--include-local-integration`, e o preflight exige `127.0.0.1:18087`, container com
  prefixo descartável e, se houver PostgREST, URL apenas em `127.0.0.1:25432` com
  container PostgREST marcado. O runner não cria nem encerra serviços.
- Credenciais e seletores de Firebase/Supabase são removidos do ambiente padrão dos
  subprocessos; falhas são exibidas com sanitização e o runner não tenta novamente.
- Testes do runner: 8/8. Execução completa final com Deno 2.9.7: 14/14 etapas
  aprovadas — os 11 gates padrão mais `deno check --cached-only`, os testes Deno do
  handler (2/2) e `deno fmt --check` no teste novo. Nenhum Emulator ou container foi
  iniciado nesta execução do runner.
- O relatório ainda não inicia a integração automaticamente: o preparo/inspeção de
  containers permanece uma operação separada para evitar tomar posse ou limpar recursos
  preexistentes. O modo local também não é homologação hospedada.
- A automação não resolve as pendências das etapas 07.5.6–07.5.10: runtime Deno/Edge,
  credenciais/IAM de menor privilégio, sincronização automática, migração de todos os
  produtores, índices hospedados, reconciliação e implantação gradual. Essas tarefas
  precisam avançar sequencialmente; o runner reduz a repetição dos testes, não substitui
  implementação nem inventa permissões/segredos.

### Reconciliação local composta — atualização (21/10/2026)

- Implementados o leitor paginado Firestore REST com `readTime` fixo, cursor por ID
  legado/Unicode, allowlist canônica e remoção de contatos sem aprovação; o leitor
  composto une essa origem ao snapshot privado PostgreSQL sem escrever no catálogo.
- Implementado checkpoint local em arquivo, com CAS entre instâncias, gravação
  atômica e campos/report allowlisted. Diretórios redirecionados por junction são
  recusados e o timeout do lock usa relógio monotônico do processo, não o relógio
  injetado do relatório.
- Testes finais: Node compartilhado 199 aprovados, 0 falhas, 4 integrações
  condicionais ignoradas na execução sem serviços; Functions 185/185; subconjunto
  direcionado 48/48. Duas integrações foram também executadas explicitamente no
  Firestore Emulator e no PostgreSQL/PostgREST local: paginação/readTime e varredura
  composta read-only passaram. Deno 2.9.7 check/fmt, `node --check` e
  `git diff --check` passaram.
- Isso não é sincronização nem backfill: nenhum writer foi chamado, nenhum dado
  hospedado foi acessado, e o par Firestore/PostgreSQL não constitui snapshot global
  atomicamente consistente. A próxima fronteira real continua sendo revisão de
  produtores, IAM/índices hospedados e autorização específica antes de qualquer
  homologação remota ou implantação.

### Checklist local de liberação/rollback — 07.5.10

Este checklist prepara a operação; não concede autorização para executar em
serviços hospedados.

**Pré-condições GO:** 07.5.6 deve ter uma execução autenticada reproduzível no
runtime escolhido; 07.5.7 deve cobrir todos os escritores críticos e compatibilidade
de clientes/Rules; 07.5.8 deve comprovar IAM mínimo, chave somente servidor e índices
reais; 07.5.9 deve validar estratégia de backfill e revalidação transacional da
origem. A suíte local completa e um evento canário sintético devem passar antes da
homologação.

**Ativação gradual proposta:** começar com consumidor desativado; aplicar mudanças
de schema/Rules somente após checagem de compatibilidade; habilitar um lote pequeno
em ambiente de homologação; confirmar versão/operação em Firestore e projeção no
PostgreSQL; observar backlog, idade do evento, retries e dead-letter; aumentar lote
apenas após janela de estabilidade. Produção exigirá aprovação específica antes de
cada mudança externa.

**Pausa e rollback:** desligar o agendador/flag do consumidor sem alterar o Firestore
canônico; deixar leases expirarem ou concluir apenas operações cujo lease ainda é
válido; não apagar projeções nem tombstones como rollback. Corrigir divergências com
novos eventos versionados ou reconciliação forward-only. Retomar somente após
verificar fila, estado persistido e limites de retries. Registrar contagens antes e
depois, sem payloads pessoais.

**Critérios NO-GO:** qualquer escritor crítico sem outbox, incompatibilidade de
cliente/Rules, autenticação ampla, índice ausente, writer privado acessível ao
cliente, evento antigo sobrescrevendo versão, tombstone ressuscitado, divergência
sem reparo forward-only, ou ausência de métricas/pausa testada.
- A checagem Deno 2.9.7 e os testes Deno do handler, executados com o ZIP temporário já existente e hash
  `A0C3101B4158D1DFB7D6A78A7BF0F3DE80C96BB423C152BEEC8BEB22786F2238`, encontrou e
  ajudou a corrigir erros reais de tipagem no entrypoint Edge: `processor` e `request`
  eram implícitos e a composição não satisfazia o parâmetro `retryPolicy` inferido. O
  processador agora usa o `DEFAULT_RETRY_POLICY` compartilhado exportado pelo protocolo;
  o entrypoint declara os tipos do processor e da requisição. `deno check --cached-only`
  passou. Dois testes Deno do handler passaram (2/2); `deno fmt --check` passou no novo
  teste. O entrypoint antigo usa aspas/formatação diferentes do formatter Deno; não fiz
  reformat em massa. O runner aceita `--deno-bin` para repetir check, testes e formato
  sem download/rede.
- Para repetir a sequência local completa, use `node tools/hybrid-validation-runner.mjs`
  e acrescente `--deno-bin <caminho-absoluto-do-deno>` quando a cópia portátil estiver
  disponível. A validação integrada Firestore/PostgreSQL permanece uma opção separada
  e exige serviços descartáveis iniciados e inspecionados antes; o runner falha fechado
  se o preflight não comprovar o destino local.

### Edge Runtime local — probe do user worker (21/10/2026)

- A imagem oficial `public.ecr.aws/supabase/edge-runtime:v1.77.4` foi validada no
  user worker, com digest `sha256:ad45164b7548bf5820ed7be714789c17ac2865edce79a09cfb4c3756c3d365a8`.
- Container temporário inspecionado antes do start: `NetworkMode=none`, sem
  `PortBindings`/portas publicadas, rootfs read-only, UID 10001, capabilities removidas,
  `no-new-privileges`, limites de 768 MiB/1 CPU/64 PIDs e uma única montagem read-only
  da cópia temporária da função e módulos compartilhados. Nenhuma variável de segredo
  foi passada.
- O worker carregou o `index.ts` real e os módulos compartilhados. Seis chamadas locais
  verificadas: GET 405; POST sem secrets 503 `consumer_unavailable`; HMAC ausente/inválida
  401; corpo inválido 400; HMAC sintética válida 200 contra processador falso, com resumo
  sanitizado. Isso comprova o handler no user worker e fail-closed; não comprova credenciais
  reais, leitura do Firestore, escrita PostgreSQL, sincronização completa ou agendamento.
- Criados `tools/edge-runtime-consumer-probe.mjs` e seus testes; o runner agora executa
  os próprios testes de segurança offline e permite o probe apenas com a opção
  `--edge-runtime-probe`. O probe recusa imagem/digest divergente, não faz pull nem
  inicia Docker Desktop e remove apenas o container e diretório temporários que cria.
- Execução real do probe: 6/6 verificações HTTP aprovadas. Testes do harness offline:
  14/14. Deno disponível localmente: 2.9.7. O container foi removido; Docker Desktop foi
  desligado novamente; as duas volumes preexistentes permaneceram. A imagem permanece
  no cache. Nenhum serviço hospedado foi acessado.
- Atualização local desta execução: o runner inclui `orchestrator-harness-tests` por
  padrão; probe de Edge segue opt-in. IAM/credenciais, execução autenticada, integração
  com serviços, Cron, migração operacional de escritores, reconciliação hospedada e
  implantação permanecem bloqueios separados.

### Continuação local — reconciliação segura (21/10/2026)

- Criado `catalog_reconciliation.mjs`, comparador puro/read-only de uma página já
  fornecida. Gera somente recomendações de projeção/tombstone allowlisted; não lê nem
  grava em serviços.
- Cenários: estado sincronizado, projeção ausente/atrasada, conteúdo conflitante na
  mesma versão, destino mais novo, origem ausente/inválida, tombstone ausente/atrasado,
  tombstone coincidente, divergência entre tombstone e linha, tombstone embutido na linha,
  IDs de operação duplicados e snapshots malformados. São 12 testes sintéticos.
- Regras fail-closed: não sugere exclusão para linhas sem origem; divergências e versões
  superiores vão para revisão manual; tombstone no catálogo ou na tabela de tombstones
  bloqueia republicação; a coluna interna `search_document` não é confundida com o
  contrato da projeção allowlisted.
- `npm test --prefix functions`: 185/185. Runner com Deno 2.9.7 e probe Edge opt-in:
  16/16 stages aprovados;
  Functions 185/185, harness 14/14, compartilhados 164 aprovados + 2 testes de Emulator
  condicionais ignorados, Flutter `searchLocal` 52/52, App Check 9/9, análise limpa e
  `git diff --check` aprovado. Os 2 skips não contam como execução integrada.
- O scanner agora define paginação e checkpoint por interfaces, mas ainda não possui
  adapters reais, armazenamento durável, revalidação transacional antes do backfill ou
  gravações. Nenhum dado real foi consultado ou alterado.

### Continuação local — scanner read-only de reconciliação (21/10/2026)

- Criado `catalog_reconciliation_scan.mjs` para percorrer páginas fornecidas por um
  reader injetável, chamar o planejador existente e pausar/retomar usando cursor e
  `snapshotId` fixo. `maxPages` limita cada execução; página inválida, fora de ordem,
  repetida, acima do limite ou de snapshot divergente falha antes do commit.
- Checkpoint usa sequência CAS. O contrato `commitPage` exige persistir findings e
  checkpoint na mesma operação; erro de leitura, snapshot expirado, falha de persistência
  ou disputa não é repetido automaticamente e não avança o cursor.
- Nove testes da suíte cobrem retomada sem duplicar findings, leitura falha, snapshot
  divergente, ordem/cursor inválidos, ID reservado, commit atômico falho, concorrência
  no CAS, limite de páginas e leitura de checkpoint sanitizada.
- Limite deliberado: nenhum adapter Firestore/PostgreSQL ou armazenamento durável foi
  criado. O scanner recebe páginas lógicas já unidas e depende do adapter futuro para
  comprovar snapshot estável entre as duas fontes. Findings são somente candidatos; não
  existe writer, backfill nem revalidação pré-escrita. A unicidade de `outboxOperationId`
  entre páginas ainda precisa ser comprovada pelo adapter antes de promover findings.
- A alteração não muda produtores, Rules, RPCs ou comportamento Flutter e não consulta
  serviços. Execução limitada aos testes locais e validação estática abaixo.

Verificação desta continuação:

- `node --test supabase/functions/_shared/*.test.mjs`: 175 testes, 173 aprovados,
  0 falhas e 2 testes condicionais de Emulator/PostgreSQL ignorados por falta dos
  serviços. Os 9 testes do scanner estão incluídos.
- `npm test --prefix functions`: 185/185.
- Runner completo sem probe Docker: 15/15 etapas; Flutter analyze limpo, matriz
  Flutter normal aprovada, `searchLocal` 52/52, App Check 9/9, Deno handler 2/2,
  Android/Python/scripts/harness aprovados e `git diff --check` aprovado.
- Deno 2.9.7: `deno check --cached-only` do scanner e `deno fmt --check` do scanner e
  testes passaram após aplicar o formato oficial. `node --check` dos dois arquivos passou.
- Nenhum Emulator, container ou serviço hospedado foi iniciado/acessado nesta etapa.

Inventário depois desta continuação: mesma branch e HEAD acima; `git status --short`
mostra 126 linhas e `git status --short --untracked-files=all` expande para 171 caminhos,
zero staged; as quatro exclusões TOML seguem presentes. Docker Desktop está desligado,
sem container ou listener criado; os dois volumes preexistentes e a imagem Edge Runtime
em cache foram preservados. O processo Codex PID 11496 permaneceu presente e intocado.

### Continuação local — contrato de leitura para reconciliação (21/10/2026)

- Auditoria das migrations e do adaptador REST confirmou que não há leitor privado
  do destino. As RPCs públicas filtram estados não visíveis e omitem versão/operação;
  o escritor REST aceita apenas as duas RPCs de escrita; e `service_role` não possui
  `SELECT` direto nas tabelas internas.
- O contrato incremental recomendado para materializar um snapshot privado PostgreSQL,
  paginar catálogo+tombstones por ID e descartá-lo está em
  `docs/supabase-reconciliation-private-read-contract.md`. Ele mantém as RPCs públicas
  intactas e propõe `EXECUTE` apenas para `service_role`, sem grant de tabela.
- Ainda não foram criados migration, RPC, adaptador ou backfill. O snapshot PostgreSQL
  não pode ser atomicamente alinhado ao Firestore; a reconciliação permanece observacional
  e qualquer futura aplicação deverá reler a origem e validar versão/operação imediatamente
  antes de chamar o escritor idempotente.
- A materialização inteira requer limite de tamanho/duração definido com dados locais de
  teste antes de implementar. Nenhum serviço ou dado hospedado foi acessado nesta análise.
- Verificação desta continuação: planejador + scanner `node --test` 21/21; `npm test
  --prefix functions` 185/185. Docker CLI está instalado, mas o Engine está desligado e
  `psql` não está disponível no PATH. Nenhum serviço foi iniciado; pgTAP do contrato
  privado ainda não existe e deverá ser executado em PostgreSQL descartável antes de
  considerar o leitor validado.

### Continuação local — snapshot privado PostgreSQL para reconciliação (21/10/2026)

- Criada `20261023000100_private_catalog_reconciliation_snapshot_v2.sql`, sem alterar
  as migrations V1/V2 ou o escritor. As RPCs privadas materializam apenas campos
  permitidos, incluindo estados ocultos e tombstones, com até 10.000 IDs/64 MiB,
  quatro snapshots ativos, TTL de uma hora, páginas de até 200, timeout SQL de 30 s,
  índice parcial de IDs de estabelecimentos e índice de cursor `COLLATE "C"`.
- Criado `supabase_catalog_reconciliation_rest.mjs`, separado do writer, com allowlist
  fechada de três RPCs, argumentos/resultados validados, limite de resposta, timeout,
  URL segura e erros sanitizados. O scanner passou a comparar IDs por pontos de código
  Unicode para coincidir com a ordenação SQL determinística.
- Validação final em PostgreSQL 15.19 local: cinco migrations em ordem e suites pgTAP
  V1 28/28, hardening 48/48, catálogo V2 93/93, escritor 49/49 e snapshot/leitor
  49/49 — total 267/267. O primeiro ensaio do leitor antes dos limites adicionais
  passou 266/266, mas não é contado como validação final.
- PostgREST 14.18 em cache compartilhou somente o namespace de rede `none` do PostgreSQL,
  sem portas publicadas. Um JWT sintético de `service_role` validou escrita HTTP fictícia,
  begin/read/dispose e a allowlist; chamada sem JWT foi negada 401/42501. Isso não valida
  o adapter Node end-to-end nem serviço hospedado. O adapter REST e o contrato estático
  têm testes unitários separados.
- `npm test --prefix functions` passou 185/185; os testes direcionados do scanner,
  leitor REST e contrato passaram após correções locais; `node --check`, Deno check/fmt
  e `git diff --check` foram executados. A suite compartilhada foi executada, com dois
  testes de integração condicionais ignorados; total exato será registrado no fechamento.
- Limitação: ainda não há snapshot/read adapter Firestore ligado ao snapshot PostgreSQL,
  checkpoint durável nem aplicação automática de findings. Os snapshots são locais a
  cada serviço e não representam transação distribuída. Sem backfill, serviço hospedado,
  IAM, alteração de Rules, deploy, commit ou push.
- Contêineres criados somente nesta validação foram encerrados/removidos; volumes
  preexistentes e imagens foram preservados. O Docker Desktop foi iniciado apenas para
  os testes e deve voltar ao estado inicial desligado ao fechar a validação.

### Continuação local — validação do contrato de ID do cliente híbrido (21/10/2026)

- O cliente Flutter agora rejeita uma resposta cujo `entityId` difere do ID explicitamente enviado. Isso protege IDs legados preservados pelo importador e evita contabilizar como criada uma entidade diferente; criações sem ID continuam aceitando o ID atribuído pelo servidor.
- Regressão TDD: o teste de resposta com ID divergente falhou antes da mudança e passou depois (`invalidResponse`).
- `flutter analyze --no-pub`: sem problemas. `flutter test --no-pub test/hybrid_admin_establishments_repository_test.dart test/content_editor_persistence_test.dart`: 48/48 aprovados. Nenhum serviço foi iniciado e nenhuma chamada remota ocorreu.
- A rota administrativa continua debug opt-in e o importador/editor ainda têm caminho direto por padrão. Não habilitar Rules candidatas nem considerar 07.5.7 concluída até validar runtime/cliente e inventariar os escritores críticos remanescentes.

### Conferência adicional da continuação 07.5.5–07.5.7 (21/10/2026)

- Estado observado nesta sessão: branch `codex/supabase-search-pilot`, HEAD
  `f767b17ba781d4931c9b241ebcc04ea06174b52e`, 129 entradas em `git status --short`,
  zero staged. A diferença de contagem é apenas observacional; nenhum arquivo preexistente
  foi restaurado, removido ou descartado.
- A integração HTTP ponta a ponta da seção “Complemento de validação — PostgREST HTTP
  real” permanece a evidência aprovada de 07.5.5. Não foi repetida aqui. Nesta sessão,
  uma nova tentativa de iniciar o Firestore Emulator parou antes de iniciar ou executar
  testes: o Firebase CLI 15.32.1 encontrado no cache exige Java 21, enquanto o processo
  usou o Java global 17. Não houve download/instalação de JDK, acesso hospedado ou teste
  de integração nesta tentativa; ela não invalida nem substitui a prova 1/1 anterior.
- Validação local fresca do consumidor: Deno 2.9.7 `deno check --cached-only` aprovado;
  `deno test --cached-only` 2/2; `deno fmt --check` dos dois arquivos do entrypoint/teste
  aprovado após formatação apenas do entrypoint TypeScript existente.
- Regressões frescas: `functions/npm test` 185/185; `functions/npm run check` aprovado;
  suíte compartilhada `node --test supabase/functions/_shared/*.test.mjs` 199 aprovados,
  0 falhas e 4 integrações condicionais ignoradas sem serviços/variáveis. Nesta sessão,
  `flutter analyze --no-pub` não apontou problemas e os testes direcionados do cliente
  híbrido/editor passaram 48/48. `git diff --check` aprovado.
- 07.5.6 continua sem execução autenticada do consumidor integrado ao runtime e sem
  agendamento. 07.5.7 continua sendo uma rota administrativa de desenvolvimento opt-in;
  editor e importador mantêm escrita Firestore direta como padrão. Não habilitar o opt-in,
  mudar Rules principais nem declarar a migração administrativa completa.
- Docker Desktop foi devolvido ao estado desligado e apenas containers/rede temporários
  criados para esta sessão foram removidos; imagens e volumes preexistentes foram
  preservados. Nenhuma chamada Firebase/Supabase hospedada, deploy, commit ou push ocorreu.

### Validação local de produtor administrativo — Firestore Emulator (21/10/2026)

- JDK Temurin portátil existente, extraído para pasta temporária: 21.0.12.1 LTS;
  SHA-256 do ZIP conferido com o artefato já aprovado no inventário:
  `F9D6E191AB098C0D416E7D588A24420A8621CD2F4720DAB2459B8B7B2D2D8B4E`.
  `JAVA_HOME`/`PATH` foram definidos apenas no processo do teste; em processo separado,
  o Java global continuou em 17.0.20.1.
- Firebase CLI 15.32.1 e Firestore Emulator v1.22.0 já estavam disponíveis. Foi
  iniciado somente o Firestore Emulator do projeto `demo-universal-search`, em
  `127.0.0.1:8087`, com `firebase.search-emulator.json`, sem import/export. O Auth
  Emulator não estava no cache e não foi baixado. Nenhuma chamada hospedada ocorreu.
- Novo teste condicional:
  `supabase/functions/_shared/admin_establishments_firestore_emulator.integration.test.mjs`.
  Ele executa o handler administrativo real e as suas transações contra o Emulator
  via Firebase Admin SDK, usando UID/token/verificador sintéticos e um adaptador de
  teste. Cenários: criação pareada schemaVersion 2; replay; atualização; duas
  atualizações concorrentes na mesma versão (uma confirma e outra recebe conflito);
  despublicação reversível; republicação; tombstone lógico; tentativa de republicar
  tombstone; tentativa de republicar tombstone; rejeição de usuário comum sem
  autorização; rejeição de campo administrativo; falha injetada ao incluir outbox com
  rollback do documento canônico; revogação Admin. Resultado: 1/1 teste integrado
  aprovado; documentos fictícios removidos antes do encerramento.
- O primeiro ensaio falhou apenas por expectativa incorreta no teste: replay retorna
  HTTP 200, conforme o contrato `replayResult`, não 201. A expectativa do teste foi
  corrigida sem alteração de produção e a execução seguinte passou 1/1.
- Limite deliberado: o teste usa adaptador com privilégios de servidor, logo Firestore
  Rules não são aplicadas nessa rota. A identidade é sintética; não se comprovou a
  verificação de Firebase ID token neste Emulator. O harness de cliente das Rules V1/V2
  requer Auth Emulator, ausente no cache; não foi baixado por restrição de instalação.
  As aprovações históricas das Rules continuam como evidência histórica separada.
- Com `HYBRID_ADMIN_ENABLED` ausente/false (padrão), `ContentEditor` usa gravação
  direta Firestore e exclusão física; `InitialContentImporter` lê a coleção e cria
  `modelo-*` por batch, sem outbox. Com opt-in, ambos chamam o repositório administrativo;
  importação é sequencial por registro, então cada par é atômico, mas o lote inteiro não
  é uma transação. A rota é limitada a debug e não há endpoint hospedado validado. Vagas
  usam repositório próprio; rotas, utilities, home pages e reviews são outros domínios,
  não escritores do catálogo de estabelecimentos V2 segundo o contrato atual.
- Não houve migração do caminho padrão, alteração Flutter, Rules principais/candidatas,
  SQL, função de produção ou endpoint. Não há versão mínima aprovada para forçar clientes
  antigos a migrar; publicar Rules que rejeitem gravação direta antes da compatibilidade
  pode quebrá-los. Estado correto: **backend produtor validado localmente; migração do
  editor/importador e ativação permanecem pendentes**.
- Regressões frescas: suíte compartilhada Node 199 aprovada, 0 falhas, 5 testes de
  integração condicionais ignorados sem serviços; `functions npm test` 185/185;
  `functions npm run check` passou; `flutter analyze --no-pub` sem problemas;
  editor/repositório híbrido 48/48; autorização/debug gate 13 aprovados e 1 ignorado.
  `git diff --check` aprovado no fechamento. Deno não foi alterado nesta etapa.
- `firebase emulators:exec` encerrou Firestore, hub e logging; não há listeners nas
  portas 8087, 4407, 4507 ou 9150. O log local `firestore-debug.log` foi preservado,
  sem tentativa de apagar artefato que não foi inventariado antes do teste. Docker
  permaneceu desligado.

### Finalização local dos produtores — 07.5.7B (21/10/2026)

- O importador agora concentra sua execução híbrida em
  `InitialContentImporterService`. Cada item novo usa uma única chamada autenticada
  ao endpoint administrativo; esse handler grava documento e outbox na mesma
  transação. O lote é sequencial e não é atômico como um todo. Em repetição, os
  marcadores `catalogVersion` + `outboxOperationId` reconhecem itens confirmados;
  se a resposta se perdeu depois do commit, o retry não duplica a operação. Tombstones
  são ignorados e IDs legados/inconsistentes resultam em conflito, sem sobrescrita.
  IDs `modelo-*` são preservados. Não há checkpoint de lote adicional nem nova fila.
- O importador mantém a rota antiga como padrão quando `HYBRID_ADMIN_ENABLED` está
  desligado; no modo híbrido, outras categorias são ignoradas e a allowlist remove
  campos desconhecidos/privados. Uma leitura falha interrompe o fluxo sem fallback
  para escrita direta. A autorização local da UI é apenas guarda de UX; a decisão de
  segurança permanece no endpoint, que verifica token Firebase e autorização Admin.
- O ContentEditor continua opt-in. Estabelecimentos que já têm metadados de ciclo de
  vida híbrido são bloqueados contra gravação direta e exclusão física quando a flag
  estiver desligada. No caminho híbrido, criação/edição/publicação/despublicação e
  exclusão lógica usam o repositório administrativo; o tombstone não pode ser removido
  por exclusão física silenciosa. Documentos legados sem marcadores e outras coleções
  continuam no fluxo existente. Upload Cloudinary é anterior à transação; uma falha
  posterior pode deixar um arquivo remoto órfão e não foi alterada nesta etapa.
- Firestore Emulator local com projeto `demo-universal-search`, somente Firestore em
  `127.0.0.1:8087`, JDK Temurin portátil 21.0.12.1 e Firebase CLI 15.32.1: o teste
  integrado do handler servidor passou 1/1. Validou pareamento atômico V2, replay,
  atualização concorrente, despublicação/republicação, tombstone, negações e rollback.
  A identidade/verificação é sintética e o Admin SDK ignora Rules; portanto não prova
  autenticação real nem autorização de cliente. Auth Emulator não estava no cache e
  não foi baixado. As Rules candidatas não foram revalidadas nesta execução.
- Testes Flutter do importador: 19/19; importador + repositório: 34/34; persistência
  do editor (incluindo bloqueios widget de salvar e exclusão física): 35/35. Suíte
  Flutter sem o tag `search-local`: 633 aprovados, 24 ignorados,
  0 falhas. Tag local, com os três `dart-define` de projeto/host/ativação corretos:
  15/15. Uma execução sem esses defines teve 10 falhas em `local_native_gate_test`;
  a execução configurada do tag passou, sem alterar esses testes. `flutter analyze
  --no-pub` não apontou problemas.
- Regressões: `functions npm test` 185/185; `functions npm run check` aprovado;
  testes compartilhados Node 199 aprovados, 0 falhas e 5 integrações condicionais
  ignoradas. O teste de Emulator foi executado separadamente (1/1). Deno não foi
  alterado. `git diff --check` passou.
- Situação: **IMPLEMENTAÇÃO LOCAL PREPARADA — ATIVAÇÃO BLOQUEADA**. Não foram
  habilitados `HYBRID_ADMIN_ENABLED`, publicação de Rules, endpoint hospedado,
  consumidor ou Cron. Falta Auth Emulator para os cenários de token/cliente, revalidar
  Rules V1/V2, validar o endpoint no runtime e estabelecer política compatível com
  clientes antigos/versão mínima. Não houve acesso hospedado.

### Validação de autenticação e Rules — 07.5.7C (21/10/2026)

- Baseline antes da execução: branch `codex/supabase-search-pilot`, HEAD
  `f767b17ba781d4931c9b241ebcc04ea06174b52e`, 240 caminhos em
  `git status --short --untracked-files=all`, zero staged. Estado no fechamento:
  242 caminhos, 133 linhas em `git status --short`, zero staged. Os dois caminhos
  adicionais são os novos harnesses em `functions/integration/`; os demais trabalhos
  locais foram preservados.
- **Nenhum download foi necessário.** Firebase CLI 15.32.1 implementa Auth Emulator
  dentro do runtime Node da própria CLI; ele não consta na lista de emuladores que
  exigem binário/JAR separado. O Auth-only smoke emitiu usuário e ID token fictícios
  pelo SDK cliente, verificou o token com Firebase Admin SDK no Emulator e passou.
  Firestore Emulator v1.22.0 já estava em cache. Foi usado Temurin portátil 21.0.12.1,
  SDK Firebase JS 11.10.0, com `JAVA_HOME`/`PATH` limitados aos processos da validação,
  configuração `firebase.search-emulator.alt-f8a39297e1924ff79950828aef315f74.json`,
  projeto `demo-universal-search` e Auth/Firestore em `127.0.0.1:19097`/`127.0.0.1:18087`.
  `FIREBASE_AUTH_EMULATOR_HOST` foi definido somente no processo filho executado pela CLI.
- O novo harness `functions/integration/catalog_outbox_auth_rules_emulator.mjs` usa
  Firebase Auth e Firestore SDK cliente para as Rules, carrega separadamente V1 e V2,
  usa Admin SDK somente para preparar/verificar fixtures e exercita o handler de negócio
  real em HTTP local. Resultado integrado: **18 grupos aprovados e 16 reprovados** em
  34 (17 por candidata). Em V1 e V2 passaram token Auth validado pelo Admin SDK,
  leitura mínima/autorização e negações de leitura, criação atômica pareada, negação de
  gravação por usuário comum, privacidade da outbox, negação de evento órfão, atualização,
  despublicação reversível, republicação versionada sem tombstone e bloqueio de novo
  login para conta desativada.
- As 16 falhas (8 por candidata) foram `rules-expression-budget-exceeded`, teto de
  1.000 expressões: replay, documento canônico sem outbox, par divergente, salto de
  versão, estado `synced` forjado, campo privado, republicação de tombstone e autorização
  Admin revogada. Logo, essas negações **não foram comprovadas**: não se pode tomar o
  erro de orçamento como evidência semântica de negação. As Rules candidatas precisam
  de otimização antes de serem consideradas validadas. Rules principais não foram
  modificadas.
- O handler real foi testado localmente em composição explicitamente isolada: Admin SDK
  verificando token do Auth Emulator, `authorizeAdmin` real, transações no Firestore
  Emulator e servidor HTTP em loopback. **4/4 verificações aprovadas**: token emulado
  autorizado para a fixture Admin; ausente/malformado/expirado/projeto incorreto/usuário
  comum negados sem escrita; replay idempotente e revogação central negando gravação;
  conta desativada bloqueada e verificador de produção RS256 rejeitando token unsigned.
  O entrypoint Deno de produção e `verifyFirebaseIdToken` não foram enfraquecidos ou
  alterados; essa composição local não valida assinatura RS256 real nem é um bypass
  selecionável em hospedagem.
- ContentEditor e InitialContentImporter **não foram exercitados end-to-end** com sessão
  Flutter autenticada contra esse endpoint. As regressões unitárias/widget usam seus
  harnesses existentes e não substituem essa prova. A execução foi interrompida nesse
  limite porque as candidatas falharam em negações críticas por orçamento de Rules.
  Testes Flutter focados (importador, repositório híbrido, persistência e galeria do
  editor): 75/75; `flutter analyze --no-pub`: sem problemas. Functions `npm test`:
  186/186; `npm run check`: aprovado; testes Node direcionados do endpoint/verificador/
  autorização/Rules: 45/45; teste estático do harness: 17/17; `node --check` e
  `git diff --check`: aprovados.
- Os Emulators foram encerrados pelo `emulators:exec`; não restaram listeners nas portas
  18087, 19097, 14407, 14507 ou 19150. Nenhum serviço hospedado, conta/segredo real,
  instalação, Docker, publicação de Rules, ativação de flag, deploy, commit ou push foi
  usado. As únicas adições desta etapa são os harnesses
  `functions/integration/auth_emulator_sdk_smoke.js` e
  `functions/integration/catalog_outbox_auth_rules_emulator.mjs`; não houve mudança em
  Rules, verificador de produção, Flutter ou dados.
- Estado: **BLOQUEADA PARA VALIDAÇÃO COMPLETA E ATIVAÇÃO**. Próximos passos mínimos:
  otimizar somente as Rules candidatas para caber no orçamento sem reduzir garantias;
  repetir os cenários negativos V1/V2; então exercitar ContentEditor e importador com
  Flutter autenticado no Emulator e endpoint local. Não ativar `HYBRID_ADMIN_ENABLED`,
  publicar Rules nem iniciar o consumidor hospedado antes desses critérios.

### Otimização segura das Rules V1/V2 — 07.5.7D (21/10/2026)

- A causa observada pelo Emulator foi a avaliação duplicada dos validadores completos
  de criação e atualização nos mesmos pedidos de escrita pareada. A cobertura também
  destacou os validadores de texto chamados repetidamente. A primeira rodada, que
  removeu verificações duplicadas do evento, e a segunda, que reduziu leituras de campos,
  ainda reproduziram o teto de 1.000 expressões; a terceira, com despacho único por
  `allow write`, eliminou a duplicação e fez as negações passarem semanticamente.
- Nas duas candidatas, `str()` agora lê o campo opcional uma vez com valor padrão vazio,
  preservando a rejeição de `null`, tipo incorreto e strings acima do limite. O novo
  Para campos alterados, o diff decide se a validação é necessária; o mesmo helper
  preserva a aceitação de remoção de opcionais e rejeita `null` explícito. A regra de
  estabelecimento usa um único `allow write`: `resource == null` escolhe criação;
  caso contrário usa a validação de atualização. `request.resource != null` mantém
  exclusão física negada. Foram preservados autorização Admin versionada, allowlists,
  atomicidade com `getAfter()`, versões, outbox privada, despublicação reversível e
  tombstones. As regras genéricas de conteúdo público agora listam explicitamente as
  mesmas 19 coleções de raiz, sem sobreposição com estabelecimentos/outbox.
- Validação final no Auth/Firestore Emulator: **36/36 grupos Rules aprovados**, 18 para
  V1 e 18 para V2, mais **4/4 verificações do handler autenticado**. Os dois cenários
  adicionais confirmam que exclusão física não remove o documento canônico. Os oito
  ataques anteriores (replay, fonte sem outbox, par divergente, salto de versão, evento
  `synced`, campo privado, ressurreição de tombstone e Admin revogado) foram negados sem
  `rules-expression-budget-exceeded`. Os testes usam Firebase SDK cliente para Rules;
  Admin SDK ficou restrito a fixtures e leitura de estado final.
- O endpoint de cobertura registrou 16 amostras de grupos críticos; a maior soma
  agregada de subexpressões foi 1.058. Essa soma não representa o orçamento exato
  restante de uma requisição; o Emulator não expõe uma margem direta por requisição.
  A evidência operacional é que os 36 grupos foram concluídos e nenhum chegou ao erro
  do limite. A margem numérica exata permanece desconhecida.
- Ferramentas observadas: Temurin portátil 21.0.12.1. O Firebase CLI 15.32.1 solicitado
  não foi encontrado instalado/em cache; somente firebase-tools 15.34.0 estava disponível
  em pasta temporária existente e foi usado, sem download ou instalação nesta etapa.
  Auth Emulator veio com a CLI e Firestore Emulator v1.22.0 já estava em cache. Projeto
  `demo-universal-search`, loopback `127.0.0.1:19097`/`127.0.0.1:18087`; Java 17 global
  permaneceu intacto. Assim, a validação local passou, mas a execução exata com CLI
  15.32.1 não foi demonstrada.
- Regressões: teste estático das Rules **20/20**; Functions `npm test` **189/189** e
  `npm run check` aprovado; testes compartilhados Supabase/Functions **199 aprovados,
  0 falhas, 5 ignorados** por dependerem de Emulator/PostgreSQL não configurados nessa
  suíte; `node --check` aprovado; `flutter analyze --no-pub` sem problemas; testes
  Flutter direcionados de importador, repositório híbrido, persistência e galeria do
  editor **75/75**; `git diff --check` aprovado.
- Os testes Flutter direcionados continuam sendo unitários/widget e não são prova de
  sessão Flutter real contra Rules. Não há `integration_test` existente para esses
  fluxos; `flutter emulators` não encontrou fontes AVD e o único device listado era
  `ASUS AI2501 B`, que não foi presumido ser Emulator nem utilizado. Portanto
  ContentEditor/InitialContentImporter end-to-end permanecem pendentes.
  HYBRID_ADMIN_ENABLED segue falso, Rules principais e verificador RS256 seguem
  intocados, sem chamadas hospedadas ou publicação.
- No fechamento: branch `codex/supabase-search-pilot`, HEAD
  `f767b17ba781d4931c9b241ebcc04ea06174b52e`, 242 caminhos expandidos (133 linhas
  compactas), zero staged. `emulators:exec` encerrou os serviços e não há listeners nas
  portas de teste. Estado: **Rules candidatas V1/V2 aprovadas localmente com ressalva da
  versão da CLI; Etapa 07.5.7 segue implementação local preparada, ativação bloqueada**.
  Próxima ação: validar os fluxos Flutter reais no Emulator dedicado e resolver a
  compatibilidade da versão da CLI; depois revisar a política de clientes antigos antes
  de qualquer ativação.

### Testes integrados Flutter + Auth — 07.5.7E (21/10/2026)

- Estado: **TESTES DE COMPONENTE APROVADOS — INTEGRAÇÃO PENDENTE**. Esta rodada não
  executou login no app, `ContentEditor`/`InitialContentImporter` contra serviços reais
  de Emulator, nem alterou Flutter, Rules ou configuração da flag.
- Baseline conferida antes dos testes: branch `codex/supabase-search-pilot`, HEAD
  `f767b17ba781d4931c9b241ebcc04ea06174b52e`, 242 entradas em
  `git status --short --untracked-files=all`, zero staged. Estado preservado.
- Ambiente: Flutter 3.47.3 / Dart 3.13.3. O projeto tem somente diretório de plataforma
  Android; `integration_test/`, `windows/`, `web/`, `ios/`, `macos/` e `linux/` não
  existem, e `integration_test` não está nas dependências resolvidas. `flutter emulators`
  não encontrou AVDs. Windows e Chrome aparecem como dispositivos Flutter, mas sem os
  runners correspondentes no projeto. Um dispositivo Android aparece como `ASUS AI2501 B`;
  não foi usado porque não foi identificado/autorizado como emulador descartável.
- A configuração local já existente `firebase.search-emulator.json` fixa Auth, Firestore
  e Functions em `127.0.0.1:9097`, `:8087` e `:5007`; todas essas portas estavam livres.
  Os endpoints alternativos `19097/18087/15007` também estavam livres, mas o bootstrap
  Flutter usa por padrão `9097/8087/5007`. O JDK 21 portátil e firebase-tools 15.34.0
  já estão disponíveis em diretórios temporários; não foram necessários nesta rodada.
  Nenhum Emulator foi iniciado, nenhum endpoint foi chamado e não houve acesso hospedado.
- Revisão dos fluxos efetivos: `HYBRID_ADMIN_ENABLED` é `bool.fromEnvironment`, padrão
  `false`; `HybridAdminRuntime` rejeita build não-debug e configuração fora dos endpoints
  aprovados. Com a flag desligada, o importador usa o batch Firestore legado e o editor
  grava pelo caminho antigo. Com a flag ligada em debug, os estabelecimentos passam pelo
  repositório autenticado; criação/edição/publicação/despublicação/republicação usam o
  endpoint, enquanto exclusão lógica exige confirmação. O guard do editor barra escrita
  legada e exclusão física em documentos com marcadores de outbox/tombstone. O caminho
  legado ainda pode excluir fisicamente documentos sem esses marcadores. Outras coleções,
  inclusive vagas e conteúdo fora do domínio de estabelecimentos, permanecem fora deste
  contrato.
- Bloqueios de integração: o entrypoint Supabase Edge
  `supabase/functions/manage-establishments/index.ts` usa `tudo-aqui-macacu` e exige
  segredo de conta de serviço; não é destino de teste demo. A composição Node já existente
  valida o handler real com token Auth Emulator/Admin SDK, autorização central e Firestore
  Emulator, mas expõe rota temporária `/manage-establishments`; o repositório Flutter
  aceita `/functions/v1/manage-establishments`. Ainda falta disponibilizar uma ponte
  somente de teste, com guardas explícitos demo/loopback e rota compatível, sem alterar o
  verificador RS256 de produção. O outro bloqueio é não haver dispositivo de integração
  autorizado nem harness `integration_test` configurado. Não foi criado harness não
  executável nem adicionada dependência sem validação.
- Testes executados nesta rodada:
  - `flutter analyze --no-pub`: sem problemas.
  - Suíte comum `flutter test --no-pub --exclude-tags=search-local`: **633 aprovados,
    24 ignorados, 0 falhas**.
  - Casos marcados `search-local`, com `LOCAL_SEARCH_EMULATORS=true`, projeto
    `demo-universal-search` e host `127.0.0.1`: `local_native_gate_test.dart` **8/8**;
    `local_session_recovery_test.dart` **7/7**.
  - Testes direcionados de importador, repositório híbrido, editor, galeria e autorização:
    **83 aprovados, 1 ignorado, 0 falhas**. São unitários/widget e não comprovam rede,
    Auth ou persistência no Emulator.
  - A execução simples sem defines (`flutter test --no-pub`) falhou em 10 casos dos
    arquivos `search-local`: os testes esperam os defines de demo/loopback e não podem
    passar no modo padrão. A matriz segmentada com os defines acima passou.
  - `functions`: `npm test` **189/189**, `npm run check` aprovado.
  - Node compartilhado: **83/83** testes de handler administrativo, protocolo,
    processador e consumidor.
- Para reproduzir os testes de componente, use os comandos acima. Para validar a etapa
  ponta a ponta, primeiro disponibilize um AVD Android descartável ou confirme que o
  dispositivo listado é um Emulator/MEmu descartável e pode ser usado. Depois configure
  `integration_test` a partir do Flutter SDK (sem baixar pacote externo, mas registrando
  a dependência de SDK necessária), e prepare/reutilize um endpoint local de teste na rota
  esperada. Inicie Auth/Firestore somente em loopback com o projeto demo, sem importação
  de snapshots; use credenciais e dados fictícios. Só então execute os fluxos autenticados
  do editor e importador e verifique documentos/outbox no Emulator. Até essa prova,
  07.5.7 permanece **IMPLEMENTAÇÃO LOCAL PREPARADA — ATIVAÇÃO BLOQUEADA**; a flag global
  continua falsa, Rules principais não publicadas e consumidor hospedado desativado.

### 07.5.7F — Preparação de integração Flutter autenticada (21/10/2026)

- Estado: **INFRAESTRUTURA LOCAL PREPARADA; EXECUÇÃO FLUTTER E2E PENDENTE**.
- Baseline observada antes desta continuação: branch `codex/supabase-search-pilot`,
  HEAD `f767b17ba781d4931c9b241ebcc04ea06174b52e`, 245 caminhos em status detalhado,
  zero staged. Preservada; a contagem final inclui arquivos locais desta etapa.
- Preparados: bridge HTTP de teste em `127.0.0.1:5077`, rota compatível com Flutter,
  guardas do projeto demo e Emulators, teste Node offline com o handler real, cenário
  Node para Auth Emulator, configuração E2E com Rules V2 candidata sem import/export e
  alvo Android `integration_test` com defines fictícios explícitos.
- Segurança preservada: o verificador RS256 de produção não foi alterado; a bridge usa
  Firebase Admin apontado aos Emulators e falha fechada sem projeto demo, Auth
  `127.0.0.1:9097`, Firestore `127.0.0.1:8087` e confirmação local. A flag global
  permanece falsa; as Rules principais não foram substituídas; nenhuma chamada hospedada
  foi feita.
- Verificações: Functions Node **196/196**; `npm run check` valida bridge e cenário Auth;
  Flutter direcionado **74/74** e análise estática sem problemas. O alvo
  `integration_test` foi analisado, mas a tentativa de `flutter test` acionou
  `assembleDebug` Android e foi interrompida; não conta como execução E2E.
- Bloqueio objetivo: o SDK existe, mas `emulator.exe`, `system-images` e AVD não existem.
  O único dispositivo ADB é o ASUS AI2501 B, fora do escopo. Firebase CLI portátil
  15.32.1 e Firestore Emulator estão disponíveis; o artefato Auth Emulator não está no
  cache. Não houve download nem início de Emulator nesta etapa.
- Para completar, é necessário disponibilizar um Android Emulator/AVD descartável e o
  Auth Emulator oficial. Depois, usar somente `firebase.search-local-admin-e2e.json` em
  loopback sem snapshots, iniciar a bridge e executar o alvo Android com usuário fictício
  `.invalid`. A ativação operacional continua bloqueada.

### 07.5.7G — Auth/Rules e preparação Android (21/10/2026)

- Estado: **BACKEND LOCAL VALIDADO; FLUTTER E2E BLOQUEADO POR ESPAÇO EM DISCO**.
- Baseline observada: branch `codex/supabase-search-pilot`, HEAD
  `f767b17ba781d4931c9b241ebcc04ea06174b52e`, 251 caminhos detalhados, zero staged.
  Alterações preexistentes preservadas.
- Ferramentas: Firebase CLI portátil **15.32.1** iniciou Auth e Firestore Emulator sem
  baixar artefato adicional; Auth Emulator é iniciado pela CLI. Usado Temurin portátil
  **21.0.12.1+1** apenas nos processos de teste; `java` global permaneceu Microsoft
  OpenJDK **17.0.20.1**. Android SDK recebeu somente Emulator **37.2.12.0** e imagem
  oficial `system-images;android-36;google_apis;x86_64` revisão **7**.
- AVD novo `tudo_aqui_macacu_e2e` criado e listado. O boot falhou antes da inicialização
  do Android: Emulator exige **7.372,80 MB** livres para userdata e a unidade C tinha
  cerca de **6,3 GiB** livres; não removemos arquivos para liberar espaço. Nenhum APK,
  app, conta Google ou dado foi instalado/criado no dispositivo. O único dispositivo ADB
  permaneceu o ASUS, que não recebeu comandos de alteração.
- Auth/bridge local: o cenário Node passou com token do Auth Emulator, endpoint de teste,
  criação atômica de estabelecimento/outbox V2, usuário comum negado, token inválido
  negado, token Admin revogado rejeitado e novo token do Admin desativado negado. Um
  preflight sem `FUNCTIONS_EMULATOR=true` foi corretamente rejeitado pelo guard local;
  a execução seguinte, com a variável restrita ao processo, passou.
- Rules candidatas via SDK cliente autenticado: **36/36 grupos** V1/V2 e endpoint
  **4/4 verificações** passaram. Cobertos pareamento atômico, leitura mínima de
  autorização, negações, replay, versões, tombstones, publicação/despublicação, token
  revogado/desativado, endpoint real e rejeição de token não assinado pelo verificador
  RS256. Admin SDK foi usado apenas para fixtures/consultas privilegiadas; as provas de
  Rules foram feitas com Firebase client SDK. Rules principais não mudaram.
- Ajuste local: o harness de Rules agora lê os endereços Auth/Firestore do ambiente e
  valida loopback e porta explícita, mantendo 18087/19097 como fallback. Isso alinhou o
  teste às portas `127.0.0.1:9097`/`127.0.0.1:8087` da configuração E2E.
- Regressão: Functions **196/196**, `npm run check` aprovado, Flutter direcionado
  **89 aprovados / 1 ignorado**, `flutter analyze --no-pub` sem problemas e
  `git diff --check` aprovado. Auth/Firestore Emulators foram encerrados e suas portas
  liberadas. AVD e pacotes Android autorizados permanecem disponíveis.
- Pendência: os fluxos reais no app Android para ContentEditor e InitialContentImporter
  ainda não foram executados. Para continuar, liberar espaço suficiente na unidade C
  para criar userdata do AVD e manter folga operacional (recomendado pelo menos 10 GiB),
  então iniciar somente esse AVD e repetir a integração Flutter autenticada. A etapa
  segue **IMPLEMENTAÇÃO LOCAL PREPARADA — ATIVAÇÃO BLOQUEADA**; flag global falsa,
  Rules principais não publicadas e consumidor hospedado desativado.

### 07.5.7H — Diagnóstico de armazenamento do AVD (21/10/2026)

- Estado: **BLOQUEADO; NENHUM NOVO BOOT OU E2E EXECUTADO**.
- Inventário não destrutivo: única unidade de dados local é `C:`, com **6,22 GiB** livres;
  a partição de sistema sem letra tem cerca de 86 MB e não comporta dados. Não há unidade
  local alternativa. Android SDK e AVD ficam em C; `ANDROID_AVD_HOME` não está definido
  no escopo de processo, usuário ou máquina.
- O AVD `tudo_aqui_macacu_e2e` permanece intacto e sem `userdata-qemu.img` criado; só
  contém configuração e diretórios vazios de dados/snapshots. A imagem de sistema API 36
  e o APK `app-searchlocal-debug.apk` (246.089.590 bytes) já existem. O workspace mantém
  `build` com 6,70 GiB, `.gradle/caches` com 4,25 GiB, `.dart_tool` com 0,96 GiB e
  `functions/node_modules` com 0,18 GiB. Nenhum desses diretórios foi limpo ou movido.
- O boot anterior reportou necessidade de **7.372,80 MB** para userdata; C tem cerca de
  6,22 GiB (aprox. 6.369 MiB), insuficiente por cerca de 1 GiB antes de reservar espaço
  para Flutter/Gradle. Recomenda-se pelo menos **10 GiB livres** para executar o fluxo
  completo com folga.
- `emulator -help-disk-images` confirma suporte a `-data`/`-datadir` para escolher onde
  gravar imagens mutáveis, mas não cria espaço adicional sem outra unidade. A
  documentação Android Studio apresenta um ajuste de “Internal Storage” no Device
  Manager; Android Studio não está instalado. Os overrides de `disk.dataPartition.size`
  tentados na etapa anterior foram normalizados de volta para 6 GiB, portanto não há
  override menor efetivo comprovado neste CLI/AVD. `-partition-size` trata a partição de
  sistema, não resolve userdata. Não repetimos o boot nem alteramos o AVD.
- Resultado: sem apagar/mover dados nem instalar uma ferramenta de gerenciamento,
  nenhuma alternativa segura foi encontrada nesta sessão. O passo mínimo é liberar
  espaço em C fora do projeto/SDK ou disponibilizar uma unidade de dados local com pelo
  menos 10 GiB livres; então retomar o boot do AVD existente. O estado permanece
  **IMPLEMENTAÇÃO LOCAL PREPARADA — ATIVAÇÃO BLOQUEADA**.

### 07.5.7H — Reexecução após disponibilidade de armazenamento (22/10/2026)

> O resultado abaixo registra o checkpoint inicial e foi atualizado pela seção
> “Fechamento da execução” no final deste documento.

- Estado: **PARCIAL; AVD VALIDADO, FLUTTER E2E INCOMPLETO**. O bloqueio de espaço deixou
  de existir sem limpeza ou movimentação de dados: C: tinha 39,27 GiB livres antes do
  build. O AVD existente iniciou com `sys.boot_completed=1`, Android 36, serial
  `emulator-5554`. Seus dados graváveis foram criados em
  `C:\Users\tiago\.android\avd\tudo_aqui_macacu_e2e.avd\userdata-qemu.img`; o arquivo
  persistiu após desligamento normal. Não houve `-wipe-data`, snapshot import/export,
  reinstalação do Emulator ou alteração de configuração persistente. O armazenamento
  retornou a 44,88 GiB livres ao final.
- Somente o serial `emulator-5554` foi usado; o ASUS `127.0.0.1:21503` permaneceu
  conectado, sem comandos dirigidos a ele. A VPN de sink do flavor `searchLocal` foi
  aprovada no diálogo do AVD e ficou ativa durante o teste. Reverses 9097, 8087, 5007 e
  5077 foram instalados somente nesse serial e removidos no encerramento.
- Reutilizamos Android Emulator 37.2.12.0, a imagem Android 36 Google APIs x86_64 já
  instalada, Firebase CLI 15.32.1, os Emulators já baixados e as dependências em cache.
  Nenhum download ou instalação de dependências ocorreu. Firebase Auth, Firestore, a
  função Functions `e2eNoop` local e a ponte administrativa foram vinculados somente a
  `127.0.0.1`, no projeto `demo-universal-search`; não houve acesso hospedado. O Firebase
  Emulator usou Temurin 21.0.12.1 por ambiente de processo; o build Flutter/Gradle usou
  o Microsoft JDK 17.0.20.1 existente, sem alterar o Java global.
- `flutter drive --no-pub --flavor searchLocal` compilou e instalou o target de
  `integration_test/hybrid_admin_establishments_test.dart`. O Auth Emulator aceitou o
  login sintético. O fluxo real do `ContentEditor` chegou à criação: consulta ao
  Firestore Emulator com Admin SDK confirmou um documento `establishments` com
  `catalogVersion=1` e um evento `catalog_outbox` em `pending`, com o mesmo
  `outboxOperationId`/`operationId`. Isso comprova uma gravação atômica real no Emulator
  pelo backend; o Admin SDK ignora Rules, portanto não comprova autorização do SDK
  cliente.
- A integração Flutter não concluiu e não recebe aprovação: durante a leitura cliente
  subsequente, o driver permaneceu aguardando e o Firestore Android registrou repetidos
  streams gRPC `UNAVAILABLE`/`Channel shutdownNow invoked`. A tentativa foi interrompida
  sem retry. O harness não produziu resumo final de testes; nenhum número de aprovação
  E2E é atribuído. Edição, publicação, despublicação, exclusão, cenários de usuário
  comum/revogado e o fluxo real do `InitialContentImporter` não foram alcançados. A
  causa de rede ainda precisa ser isolada; a interação entre a VPN sink e o transporte
  nativo gRPC é uma hipótese, não uma causa confirmada. A ponte teve preflight OPTIONS
  204 e ficou disponível em loopback.
- Regressão executada nesta sessão: `flutter analyze --no-pub` sem problemas; 75 testes
  Flutter passaram nos arquivos `content_editor_persistence_test.dart`,
  `content_editor_gallery_test.dart`, `initial_content_importer_test.dart` e
  `hybrid_admin_establishments_repository_test.dart`; Functions `npm test` **196/196**;
  `npm run check` aprovado. O build temporário foi restaurado ao APK original por
  SHA-256 (`9882417D…62D281`) e SHA-1. Nenhum arquivo de código foi alterado; esta
  atualização do plano é o único arquivo versionado modificado nesta retomada.
- Os serviços temporários, portas e processos criados foram encerrados; o AVD foi
  desligado normalmente. Seus dados e a instalação/debug state do app não foram limpos.
  O arquivo temporário com credenciais sintéticas foi removido. A instalação de teste
  permanece no AVD dedicado e pode conter estado local de sessão sintética; não deve ser
  confundida com uma conta real. O APK de build preexistente foi restaurado. Estado Git
  antes desta anotação: branch `codex/supabase-search-pilot`, HEAD
  `f767b17ba781d4931c9b241ebcc04ea06174b52e`, 142 entradas locais, zero staged; a
  anotação acrescenta uma alteração local e nenhuma mudança staged.
- Pendência mínima: corrigir/diagnosticar a conectividade gRPC do SDK cliente ao
  Firestore Emulator sob a VPN obrigatória, sem desativar o isolamento; depois executar
  uma nova rodada autorizada que complete o harness, incluindo o importador. Até lá, a
  etapa 07.5.7 segue **IMPLEMENTAÇÃO LOCAL PREPARADA — ATIVAÇÃO BLOQUEADA**. A etapa
  07.5.6 continua bloqueada por autenticação de máquina/IAM e agendamento hospedado, que
  não foram validados nesta sessão.

#### Fechamento da execução (22/10/2026)

- Resultado final: **Flutter E2E local passou pelo bridge e pela API REST autenticada do
  Firestore Emulator**. A execução final de `flutter drive` terminou com `All tests
  passed`. O Auth Emulator emitiu token sintético e o app executou criação e edição reais
  no `ContentEditor`, conflito de versão, despublicação reversível, republicação, tombstone
  lógico e negação de exclusão física via cliente. O usuário comum, token inválido e Admin
  revogado foram recusados pelo endpoint local.
- O widget real `InitialContentImporter` executou importação e replay. A consulta local ao
  estado persistido encontrou 11 documentos `modelo-*` aceitos pela taxonomia; todos
  tinham `catalogVersion=1` e evento V2 correspondente (`operationId` igual a
  `outboxOperationId`). Replay preservou quantidade, versão e operação. O teste também
  confirmou leitura de estabelecimentos permitida ao Admin e leitura de `catalog_outbox`
  negada com HTTP 403. A prova de Rules foi feita pela API REST com ID token de cliente,
  não pelo Admin SDK.
- A instrumentação mostrou que o SDK Firestore Android mapeia `127.0.0.1` para
  `10.0.2.2`; sob a VPN sink, streams gRPC retornam `UNAVAILABLE`. Para concluir a rodada
  sem relaxar o isolamento, o harness usou REST autenticado em loopback para as leituras
  verificáveis por Rules. A fixture injeta apenas a leitura REST do importador e o estado
  de capacidade UI para o widget; cada gravação continua passando pela autorização real
  do endpoint. A hidratação do estado Admin via callable da UI e o transporte gRPC nativo
  permanecem sem comprovação.
- Correção relacionada: `recordAdminAudit` era awaited sem limite apesar do contrato
  best-effort. Foi limitado a 3 s e `TimeoutException` é absorvida com log sanitizado,
  evitando que auditoria secundária prenda o retorno do save. Um seam opcional de dados/ID
  foi adicionado ao editor para o harness; o fluxo padrão continua usando snapshots
  Firestore. O importer aceita lookup injetável somente para teste, mantendo como padrão
  o SDK Firestore.
- Estado persistido consultado no Emulator após o teste: 14 estabelecimentos, 11 modelos
  V2 válidos, 11 pares modelo/outbox, 22 eventos de outbox e dois tombstones de cenários
  sintéticos anteriores. Tudo foi efêmero; não houve export nem acesso hospedado. O
  Emulator Functions mostrou aviso de timeout ao carregar o source `e2eNoop`; nenhuma
  callable foi usada nesta prova.
- Regressão final: **75/75** testes Flutter direcionados passaram; `flutter analyze
  --no-pub` não encontrou problemas; Functions **196/196** (`npm test`) e `npm run check`
  passaram. A regressão da galeria encontrada durante a rodada foi corrigida preservando
  o contrato dos snapshots usados pelo código legado; o teste afetado passou isoladamente
  e na suíte.
- AVD existente foi desligado normalmente após remover apenas reverses deste teste; não
  houve wipe, limpeza de dados ou alteração do ASUS. O APK de build foi restaurado ao
  artefato original por SHA-256/SHA-1, o arquivo de credenciais sintéticas foi removido,
  e a instalação `searchLocal` permaneceu no AVD dedicado para preservar seus dados. Java
  global continuou JDK 17; Temurin 21 foi usado somente nos processos Firebase.
- Conclusão: a etapa **07.5.7 segue IMPLEMENTAÇÃO LOCAL PREPARADA — ATIVAÇÃO BLOQUEADA**.
  HYBRID_ADMIN_ENABLED continua falso, Rules principais não foram publicadas e não houve
  deploy. Antes de ativar, ainda faltam validação do transporte nativo gRPC/VPN,
  hidratação real da capacidade Admin no importador, compatibilidade de clientes antigos
  e as pendências da 07.5.6 (IAM, autenticação de máquina e agendamento hospedado).

### 07.5.7I — Callable Admin, Firestore SDK nativo e compatibilidade (22/10/2026)

- Estado: **VALIDADO LOCALMENTE; ATIVAÇÃO BLOQUEADA**. Execução no AVD dedicado `emulator-5554`, flavor `searchLocal`, projeto `demo-universal-search`. Auth/Firestore/Functions Emulator e ponte local ficaram somente em `127.0.0.1` (9097/8087/5007/5077); a VPN sink foi confirmada ativa e os reverses ADB foram limitados a esse serial. Nenhum serviço hospedado foi acessado.
- A capacidade administrativa do Flutter foi hidratada pelo `AdminAuthorization` via `SecureBackend` e pelo callable `manageAdminJob` real no Functions Emulator, usando ID token sintético do Auth Emulator e a resposta validada (`status=available`, lista de itens). O cliente local envia o protocolo HTTP callable diretamente ao endpoint `127.0.0.1:5007`; o handler é o mesmo exportado por `functions/index.js` e executa a verificação central de claim, versão/autorização atual e revogação. Não se trata de mock do handler. O App Check aceito foi fixture sintética exclusiva do Emulator, não atestação de produção.
- A tentativa exploratória com o plugin Flutter `cloud_functions` não completou: o log mostrou remapeamento de `127.0.0.1` para `10.0.2.2`, capturado pela VPN sink; `admin.authorization.callable` expirou após 20 s. O SDK Firestore não teve esse problema: o teste desabilitou cache persistente, manteve `automaticHostMapping:false` e usou `adb reverse`; leitura server-only, batch atômico com `getAfter()`, leitura do documento-fonte e negações de escrita sem par, listagem da outbox, leitura comum e exclusão física passaram. Portanto gRPC nativo Firestore está comprovado neste AVD/configuração; o transporte do plugin de Functions não está. O caminho local existente de callable HTTP permaneceu como caminho E2E aprovado.
- No Flutter E2E (1/1), `ContentEditor` utilizou a capacidade hidratada sem injeção de estado Admin sintético. Criação/edição pelo editor, confirmação por leitura do SDK, importação e replay do `InitialContentImporter` passaram. Usuário comum e Admin revogado foram recusados pelo callable/estado de UI; logout removeu a capacidade; a conta desativada foi recusada pelo Auth Emulator. As Rules V2 foram exercitadas pelo SDK cliente, não pelo Admin SDK. A suíte callable Node separada passou com Auth e App Check obrigatórios, usuários comum/anônimo negados, Admin versionado, projeções e paginação, gravação pareada, operação e revogação.
- Evidência do teste Flutter: 21 marcadores de início, todos concluídos; marcadores positivos adicionais cobrem negações esperadas; driver encerrou com `All tests passed`. `InitialContentImporter` usou seu lookup padrão via Firestore SDK, persistiu e releu o fixture `modelo-1`; replay não duplicou o item.
- Verificações: Flutter direcionado **81 aprovados, 1 ignorado** (teste condicional fora do modo normal local); `flutter analyze --no-pub` sem problemas; Functions `npm test` **196/196**; `npm run check` aprovado; integração `functions/integration/admin_job_management_emulator.js` concluída com todos os grupos reportados como PASS; `dart format --output=none --set-exit-if-changed` sem alterações pendentes; `git diff --check` limpo.
- Compatibilidade: versão declarada no checkout `0.1.3+4`; isso não comprova a versão distribuída/instalada pelos usuários, que permanece desconhecida sem consulta às lojas/telemetria. `HYBRID_ADMIN_ENABLED` conserva default `false` e só foi habilitada no build de teste local. As Rules principais seguem intactas. A candidata V2 permite somente escrita administrativa pareada e nega exclusão física; clientes antigos que gravam estabelecimentos diretamente, sem outbox, serão bloqueados após publicação da candidata. Com Rules atuais, clientes legados ainda podem gravar sem outbox, então sua alteração não sincroniza até migração.
- Ativação recomendada (ainda não executada): inventariar versões distribuídas; disponibilizar backend autenticado suportado por todas as operações de estabelecimentos/importador; liberar versão mínima compatível com editor/importador via endpoint; observar adoção; então publicar Rules estritas em janela controlada, mantendo caminho de rollback sem reabrir gravações sem outbox. Não habilitar a flag global nem publicar Rules antes disso.
- Não comprovado nesta etapa: caminho `cloud_functions` SDK no Android sob a VPN sink; callable indisponível/falha de rede, sessão restaurada/capacidade expirada no E2E; distribuição real das versões antigas; IAM/agendamento hospedados do consumidor 07.5.6. Os testes unitários de autorização cobrem timeout/erro/estado ausente; isso não substitui a falha de callable em dispositivo.
- O primeiro start não sanitizado foi encerrado imediatamente ao se perceber que o CLI podia carregar `.env.local`; não se leu nem registrou nenhum valor. A execução retomada usou cópia temporária do código de Functions sem arquivos `.env*` e placeholders fictícios. O arquivo de ambiente original não foi modificado.
- A flag híbrida permaneceu desativada por padrão, Rules principais não foram publicadas e não houve deploy, commit ou push. Antes do encerramento, os processos Emulator/ponte/AVD iniciados pela tarefa serão desligados e os diretórios temporários removidos com preservação dos processos e dados anteriores.

#### Fechamento da execução 07.5.7I

- Firebase CLI e descendentes iniciados nesta rodada encerrados; ponte PID 23936 encerrada após confirmar o caminho do script; AVD `tudo_aqui_macacu_e2e` (PID 22188) desligado normalmente. Os reverses ADB 9097/8087/5007/5077 foram removidos individualmente. Nenhuma porta local da rodada permaneceu escutando.
- As duas pastas temporárias desta execução foram removidas após destacar somente as junctions que apontavam ao repositório e ao `functions/node_modules`; o conteúdo de `functions` e `node_modules` do projeto foi preservado. Contas e dados de Emulator eram efêmeros, sem exportação ou snapshots.
- O Java global continuou em 17.0.20.1; Temurin 21.0.12.1 foi usado apenas nos processos Firebase. O ASUS não foi usado. Branch `codex/supabase-search-pilot`, HEAD `f767b17ba781d4931c9b241ebcc04ea06174b52e`; inventário final: 143 caminhos locais, zero staged. Sem commit/push.

### 07.5.7J — Migração compatível dos produtores e versionamento (22/10/2026)

- Estado: **PREPARAÇÃO LOCAL; ATIVAÇÃO BLOQUEADA**. A conferência inicial desta execução encontrou branch `codex/supabase-search-pilot`, HEAD `f767b17ba781d4931c9b241ebcc04ea06174b52e`, 252 caminhos em `git status --short --untracked-files=all` e zero staged. A contagem difere da referência histórica de 143; todos os arquivos preexistentes foram preservados.
- Inventário de versões: o único número verificável no checkout é `pubspec.yaml` `0.1.3+4`; Android deriva `versionName`/`versionCode` do Flutter. Codemagic contém fluxos APK debug e previews/simuladores iOS, não evidência de publicação em loja. Não foi localizado gate de versão mínima nem Remote Config para esse fluxo. Os clientes e builds realmente distribuídos, faixas/canais, rollout e adoção por versão são **desconhecidos**. Não se consultaram Play Console, App Store Connect, Codemagic remoto, telemetria ou serviço hospedado.
- Dados necessários para fixar versão mínima: Android — package ID de produção, versionCodes ativos por faixa (produção, aberta/fechada/interna), percentual de rollout, instalações/usuários ativos por versionCode em 30 e 90 dias, política de distribuição direta de APK e versão mínima atualmente suportada. iOS — confirmar primeiro se há distribuição; se houver, bundle ID, builds ativos por faixa/versão e adoção equivalente no App Store Connect. Demais canais precisam fornecer artefato/versionamento e adoção comprováveis. Sem esses dados não se escolhe um mínimo nem se conclui que clientes antigos deixaram de operar.
- Produtores de `establishments` identificados:

  | Caminho | Comportamento atual | Outbox/versão e risco |
  |---|---|---|
  | `ContentEditor` com `HYBRID_ADMIN_ENABLED=false` (padrão) | Criação por `.add`, edição por `update` e exclusão física pelo SDK Firestore; fluxos de outras coleções continuam separados | Sem outbox. `shouldBlockLegacyEstablishmentWrite` bloqueia registros com marcadores de ciclo de vida, mas registros antigos/novos sem marcadores ainda podem receber escrita legada enquanto as Rules atuais forem permissivas |
  | `ContentEditor` com opt-in híbrido | `FirebaseSupabaseAdminEstablishmentsRepository` envia HTTP para `manage-establishments`, com ID token Firebase, requestId estável enquanto o editor permanece aberto e payload público allowlisted. `create/update/republish/delete` passam pelo backend; salvamento `published=false` envia patch de atualização explicitamente desativado. Exclusão confirmada é lógica; registros com tombstone não podem ser republicados | Backend revalida identidade/autorizações, pré-condiciona por updateTime/versão e grava documento + evento V2 na mesma transação. A primeira edição de um documento sem `catalogVersion` usa expectedVersion `0` e o migra para versão `1`. O opt-in permanece debug-only e desligado por padrão |
  | `InitialContentImporter` com flag desligada | Faz uma leitura da coleção, preserva IDs `modelo-*` já existentes e grava os faltantes em um único batch direto do cliente | Sem outbox; o batch inteiro não tem versionamento/tombstone e falha parcialmente de forma opaca ao serviço |
  | `InitialContentImporter` com opt-in híbrido | O serviço valida a lista/payload, consulta o estado de cada ID no servidor, cria um item por chamada autenticada e permite retomar após falha. Marcadores versionados permitem reconhecer commits anteriores; legacy/inconsistente entra em conflito; tombstone é ignorado sem republicação | Cada item tem transação canônica/outbox e versão 1. O lote é deliberadamente item a item: sucessos anteriores permanecem confirmados e o UI informa quantos serão reconhecidos ao retomar. Não há uma transação atômica do lote inteiro |
  | Endpoint `manage-establishments` | Único escritor híbrido de estabelecimentos; não é Firebase Callable. Firebase ID token é validado no servidor, e a autorização Admin é consultada/revalidada ali | `create/update/unpublish/republish/delete` usam versão monotônica, outbox V2 e operação idempotente; `deletedAt` é reservado a tombstone. Falha de autorização/Firestore não faz fallback para cliente ou escrita direta |
  | Callable `manageAdminJob` | Mantém sua finalidade própria de autorização/capacidade e gestão de vagas; não grava `establishments` | Não é produtor da projeção V2. A sua chamada usa o protocolo Firebase Callable no caminho normal autorizado, separado do HTTP do escritor de estabelecimentos |
  | Imagens | O editor armazena URLs na operação de metadados; o serviço de upload existente (`WorkerImageUploadService`, e caminhos callable de outras telas) envia bytes fora da transação de estabelecimento | Upload e metadados não são atomicamente acoplados; um upload concluído seguido de save falho pode deixar asset órfão, mas ele ainda não se torna projeção sem URL gravada. Não foi ampliado o escopo do upload nesta etapa |

- Compatibilidade observada/esperada:

  | Cliente/registro | Rules principais atuais | Candidata V2 | Resultado da migração |
  |---|---|---|---|
  | Cliente antigo escreve diretamente registro sem marcadores | Pode continuar gravando conforme a política atual local | Escrita administrativa sem par canônico/outbox é negada | Enquanto a versão distribuída for desconhecida, publicar V2 pode interromper esse cliente; medir adoção e migrar produtores primeiro |
  | Novo editor, flag híbrida desligada | Mantém rota direta antiga | Escrita direta sem evento negada | O default ainda não é compatível com V2 para gravação; não publicar Rules estritas antes da ativação coordenada |
  | Novo editor, opt-in híbrido, Admin ativo | HTTP autenticado ao backend | O backend servidor realiza a transação confiável; Rules de cliente não são usadas como prova desse caminho | Compatível com outbox; testes locais anteriores cobriram o endpoint/Editor, mas não autorizam produção |
  | Primeiro save de registro legacy (sem versão/outbox) pelo backend | Leitura de origem permitida conforme Rules atuais | Escrita direta cliente continua negada; backend confiável valida `expectedVersion=0` e cria par V2 | Migração gradual por edição administrativa, preservando o ID original e campos antigos |
  | Registro com `catalogVersion`/`outboxOperationId` ou tombstone, cliente antigo tenta editar/excluir fisicamente | Pode depender da Rule principal vigente; o app atual tem bloqueio local | Cliente sem par/cliente não autorizado é negado | Não confiar no gate Flutter como segurança; Rules/endpoints precisam fechar o caminho |
  | Registro despublicado | Pode haver atualização legacy sem evento | Backend atualiza publicação/atividade, sem `deletedAt`; republicação é explícita/versionada | Reversível enquanto não há tombstone |
  | Registro logicamente excluído | Exclusão legada pode remover o documento antes de migrar | Físico negado e `deletedAt` permanente | Republicação comum negada; reconciliação não pode ressuscitar |
  | Cliente offline com escrita legada pendente volta após Rules V2 | A escrita pode ser aceita antes da ativação | A escrita sem par será recusada; não existe fallback seguro para Firestore direto | Avisar/atualizar cliente antes da janela; testar mensagens e fila offline. Não relaxar Rules para acomodar fila incompatível |
  | Admin revogado | Estado local de UI pode ter atraso | Backend consulta estado/versão atuais e nega | O estado de UI/capacidade nunca substitui autorização server-side |

- Transporte: o escritor híbrido usa `http.Client` direto para `POST /functions/v1/manage-establishments` no endpoint Supabase aprovado, com bearer Firebase ID token e chave pública de acesso quando remoto; nenhum `service_role` é aceito. A execução local validada usou a ponte loopback do demo. O timeout anterior do plugin `cloud_functions` sob a VPN refere-se à callable de capacidade `manageAdminJob`, não prova falha nem sucesso do HTTP do escritor. O transporte nativo Callable no Android distribuído permanece pendente sob a rede real suportada. `HybridAdminRuntime` continua `kDebugMode`, `HYBRID_ADMIN_ENABLED=false` por padrão e sem fallback: o release operacional ainda não foi habilitado/preparado para acionar esse adaptador.
- Compatibilidade/rollout recomendado: (1) obter inventário de lojas/canais e adoção sem consultar contas nesta etapa; (2) escolher uma versão mínima com base em dados e publicar uma versão compatível em faixa controlada, incluindo editor/importador, tratamento de offline/erros e transporte; (3) validar o endpoint e observabilidade/autorização em homologação; (4) acompanhar versões ativas e confirmar que nenhum produtor crítico sem outbox permanece; (5) somente então autorizar versão mínima e publicação de Rules V2; (6) habilitar processamento com limites conservadores após 07.5.6 homologada. Não inferir que compile-time debug flag equivale a Remote Config ou rollout remoto.
- Rollback: não retornar silenciosamente para gravação direta. Se houver problema, pausar o consumidor e interromper novas operações híbridas com erro claro; manter eventos pendentes e os dados já escritos. Restaurar processamento apenas após correção/reconciliação. Se Rules V2 já estiverem publicadas, manter a negação de escrita direta sem outbox; reabrir Rules antigas pode permitir perda de sincronização e não é um rollback de segurança. Migração de clientes incompatíveis requer versão atualizada ou bloqueio explícito de operações administrativas.
- Cobertura adicionada nesta execução: teste Flutter garante que o primeiro save híbrido de um estabelecimento legacy preserva o ID e usa expectedVersion 0; teste do handler verifica atualização do documento sem versão para versão 1 com outbox V2 na mesma transação e preservação de campos legados. Testes direcionados foram executados; não se repetiu o E2E já aprovado nem se consultaram serviços/lojas hospedados.
- Limitações: o teste de produção/de distribuição não foi executado; não se alteraram `ContentEditor`, importer, Rules principais/candidatas, runtime flags ou autenticação. Rules candidatas já têm validação reportada em etapa anterior, mas sua publicação não está aprovada. Consumidor 07.5.6 segue sem IAM/identidade de máquina/agendamento homologados. A importação normal ainda usa batch legado enquanto a flag estiver desligada.
- Próxima ação mínima para encerrar preparação antes de homologação: registrar com autorização os versionCodes/builds efetivamente distribuídos e a adoção por canal; então preparar um plano de release compatível e decidir se o app receberá atualização obrigatória antes das Rules V2. Não acessar contas de loja nem mudar configuração/flag nesta etapa.

### Segurança e identidade do consumidor — 07.5.6C (22/10/2026)

- Implementação local: `catalog_outbox_consumer_config.mjs` exige flag explícita,
  `FIREBASE_PROJECT_ID`, JSON de service account coerente com o mesmo projeto, URL
  HTTPS e segredos completos. Falta ou divergência retorna apenas `enabled=false`; o
  entrypoint não escolhe mais o projeto de produção por constante. Isso é fail-closed
  de configuração, não valida credencial real nem protege uma chave válida comprometida.
- Invocador permanece HMAC dedicado (90 s, POST/caminho/corpo fixos); a chave
  publishable não é autorização. HMAC, Firebase e PostgreSQL continuam identidades
  separadas. Sem nonce persistente, replay dentro da janela ainda pode gastar uma
  invocação limitada. O SQL de agendamento permanece todo comentado.
- WIF não foi implementado: o runtime Supabase Edge disponível não fornece evidência
  de token OIDC de workload atestado e aceito pelo Google. Recomendação de segurança
  mais forte: consumidor em Cloud Run Job/Cloud Scheduler com service account anexada
  (ADC), sujeito a mudança de hospedagem e billing. Se Edge for mantido, conta de
  serviço dedicada com chave em secret manager e IAM mínimo é uma alternativa com
  risco residual de chave estática, que exige aceitação e rotação.
- IAM REST mapeado em `docs/supabase-outbox-processor.md`: begin/rollback requer
  `datastore.databases.get`; `runQuery` requer `datastore.entities.get` e `.list`;
  commit inicial do checkpoint requer `.create`; demais commits de lease, evento e
  checkpoint requerem `.update`; `.delete` não é usado. Permissões de entidade não
  restringem coleção, então o escopo ainda pode alcançar outros documentos do banco.
  Sem IAM real criado nem validado.
- O writer PostgREST atual continua com `service_role`; trocar pelo `sb_secret` não
  reduz privilégios, pois ambos mapeiam para acesso server-side elevado/BYPASSRLS. A
  opção candidata é driver Deno Postgres por transaction pooler com login dedicado,
  sem grants de tabela e somente EXECUTE de wrappers privados de allowlist. Nenhuma
  migration SQL foi criada por não haver `psql`/Supabase CLI disponível para validar
  e por o runtime/driver ainda não estar homologado.
- Testes desta etapa: configuração **4/4 Node**; checkpoint **10/10 Node**; template
  e gate fail-closed **2/2 Node**; handler Deno **3/3**; Deno 2.9.7 `check`, `lint` e
  `fmt --check` passaram. Firestore Emulator/PostgreSQL não foram iniciados; sem
  credenciais, IAM hosted, SQL role ou Edge Runtime real.
- Git: baseline desta etapa foi 259 caminhos, zero staged; a execução criou somente
  os dois módulos de configuração/teste acima. Contagem final observada: 261 caminhos,
  zero staged; branch e HEAD permaneceram iguais à baseline.
- Estado: **PREPARADA LOCALMENTE — HOMOLOGAÇÃO BLOQUEADA**. Próximo passo é escolher
  entre hospedar o consumer sob identidade gerenciada Google (mais seguro, potencial
  custo/billing) ou aceitar risco e processo operacional da chave Firebase no Edge;
  em paralelo, obter PostgreSQL local isolado antes de materializar e testar o contrato
  do role SQL restrito. Não ativar cron/flag nem configurar segredos nesta fase.

### PostgreSQL com privilégios mínimos — 07.5.6D/07.5.6E (preparação em 22/10/2026)

- Estado: **PREPARADA LOCALMENTE — PRIVILÉGIOS NÃO VALIDADOS EM POSTGRES**. A
  baseline foi branch `codex/supabase-search-pilot`, HEAD
  `f767b17ba781d4931c9b241ebcc04ea06174b52e`, 143 entradas compactas de status e
  zero staged. Todos os arquivos anteriores foram preservados.
- RPCs privadas existentes: `public.apply_establishment_projection_v2(jsonb)` e
  `public.apply_establishment_tombstone_v2(jsonb)`. Ambas validam allowlists,
  versionamento/replay e tombstone em transação, com locks por ID/operação. Antes
  desta migration candidata pertenciam a `postgres`, tinham `search_path=''` e
  EXECUTE para `service_role`; as tabelas não concedem leitura ou mutação direta a
  `service_role`. O risco era a chave ampla do serviço, não um bypass direto às
  tabelas do catálogo.
- Migration incremental candidata
  `supabase/migrations/20261024000100_restrict_catalog_writer_v2.sql`: prepara a
  role executora `catalog_writer_v2` (NOLOGIN, limite 2, sem privilégios
  administrativos/BYPASSRLS ou grants de tabela), a identidade de conexão
  `catalog_writer_v2_login` (LOGIN+INHERIT, limite 2, sem senha, sem privilégios
  administrativos/BYPASSRLS) e a role proprietária `catalog_writer_v2_owner`
  (NOLOGIN, sem BYPASSRLS). O LOGIN é membro somente do executor; herda as duas
  permissões EXECUTE sem precisar de `SET ROLE`, e não é membro do owner ou
  `service_role`. As funções SECURITY DEFINER passam a pertencer ao owner, com
  políticas RLS específicas e grants limitados a SELECT/INSERT/UPDATE na projeção
  e SELECT/INSERT/UPDATE em tombstones; UPDATE em tombstone é necessário para
  `SELECT FOR UPDATE` e continua bloqueado por trigger. Grants de schema CREATE são
  removidos depois da transferência. A preparação revoga `PUBLIC`, `anon` e
  `authenticated`, mas mantém temporariamente EXECUTE de `service_role` para não
  quebrar o consumidor atual.
- A revogação legada foi movida para
  `supabase/operations/cutover_catalog_writer_v2.sql`, fora de `migrations`, com
  precondições para papel LOGIN seguro, membership esperada, ausência de acesso a
  tabelas e ausência de outras funções SECURITY DEFINER; qualquer falha aborta a
  transação. Essa operação só pode ser executada depois do driver e do consumidor
  restrito comprovados e da aprovação de implantação. Assim uma aplicação normal
  das migrations não corta acidentalmente o transporte PostgREST vigente.
- Testes PostgreSQL preparados em
  `supabase/tests/database/catalog_writer_role_v2.sql`: 52 asserções planejadas para
  atributos, membership, herança e `SET ROLE`, RPCs autorizadas, compatibilidade
  temporária do `service_role`, negação de DML direto em relações de aplicação, RLS,
  owner, replay, tombstones e payload inválido. A suíte de escritor V2 preserva o
  grant legado na fase de preparação. O harness de concorrência usa a role executor;
  a suíte de snapshots ainda usa `service_role` apenas nas três RPCs privadas de
  snapshot, fora das RPCs do writer.
- O adapter `catalog_postgres_writer_v2.mjs` usa somente duas strings SQL fixas e
  JSONB parametrizado, retornando o mesmo contrato `rpc` esperado pelo writer e
  processor existentes. Testes Node com query simulado: **6/6**; contrato de
  migration/escritor/corte manual: **10/10** no arquivo de contrato focal; total
  focal executado nesta etapa: **16/16**. A query injetada ainda precisa provar
  timeout/cancelamento real, TLS e conexão no driver concreto.
- Bloqueio observado: `psql`, `postgres`, `initdb`, `pg_ctl` e Supabase CLI não foram
  encontrados em PATH, instalação PostgreSQL convencional ou Temp; `pg`, `postgres`
  npm packages e `psql.exe` não estavam nos caches locais consultados. Consultas
  `docker ps -a` e `docker image ls` falharam porque o Engine está parado; Docker
  permanece desligado e não foi iniciado. Nenhum driver PostgreSQL Deno foi
  localizado/instalado. O entrypoint do consumer ainda exige `service_role` e chama
  PostgREST; ele permanece intacto. A preparação preserva essa rota, sem fallback no
  novo adapter. A autenticação real por senha do papel LOGIN e a conexão pelo pooler
  também não foram exercitadas.
- PostgreSQL não foi executado: **0 asserções SQL validadas nesta etapa**. Não declarar
  sintaxe/migration ou privilégios aprovados, conexão autenticada, integração
  PostgreSQL, homologação hospedada ou prontidão para produção. Próxima ação: obter
  PostgreSQL isolado disponível e executar as migrations V1/V2, snapshot e preparação
  do role em banco descartável; rodar as suítes SQL incluindo as 52 asserções novas;
  testar password authentication com segredo aleatório somente no banco efêmero e
  verificar direct/shared transaction pooler. Depois integrar um driver Deno fixado,
  sem `service_role`, e só então rodar o consumer contra o destino local.
- Verificação de regressão então registrada: Node compartilhado **240 aprovados, 0 falhas e 6 condicionais ignorados (246 total)**, Functions **196/196**,
  `npm run check` aprovado, Deno 2.9.7 `check`, `lint` e `fmt --check` do adapter
  aprovados, `git diff --check` aprovado. O conjunto focal adaptador/contratos foi
  reexecutado após as mudanças desta etapa: **16/16**. Esses resultados não incluem
  os 52 testes pgTAP, que continuavam pendentes antes da execução da etapa 07.5.6F.

### Validação PostgreSQL e login restrito — 07.5.6F (22/10/2026)

- Estado: **SQL VALIDADO LOCALMENTE; HOMOLOGAÇÃO HOSPEDADA PENDENTE**. O estado
  inicial foi branch `codex/supabase-search-pilot`, HEAD
  `f767b17ba781d4931c9b241ebcc04ea06174b52e`, 143 entradas compactas e zero staged.
  O Docker Engine iniciou nesta tarefa; imagem já em cache
  `public.ecr.aws/supabase/postgres:15.19.0.004`, digest
  `sha256:1d141ea194ba9c8d14c64cb93e72704887cd4b011732f122ace1576d29635c17`.
  PostgreSQL reportou 15.19; `pgtap` 1.3.3, `unaccent` 1.1 e `pg_trgm` 1.6
  estavam disponíveis na imagem.
- Um banco descartável foi aplicado com seis migrations em ordem: V1, hardening,
  catálogo V2, writer V2, snapshot/reconciliação e preparação de privilégios. Antes
  do SQL, `docker inspect` confirmou `NetworkMode=none`, PortBindings/PublishedPorts
  vazios, nenhum mount e container não privilegiado; limites: 3 GiB, 2 CPUs e 256
  PIDs. Não foi usado volume ou porta do host.
- Seis suítes TAP passaram: **28/28**, **48/48**, **93/93**, **49/49**, **49/49** e
  **52/52**, total **319/319**. O harness de concorrência com duas sessões PostgreSQL
  independentes passou **11/11**, incluindo observação de B esperando o advisory lock
  enquanto A mantinha a transação aberta, e estado final persistido na versão vencedora.
- O login `catalog_writer_v2_login` autenticou por TCP em `127.0.0.1` com senha
  aleatória criada só dentro do banco efêmero. O papel conectou e aplicou as duas
  RPCs; direct SELECT/INSERT/UPDATE/DELETE nas duas tabelas, a RPC de snapshot e
  `SET ROLE catalog_writer_v2_owner` falharam com SQLSTATE `42501`. O estado persistido
  confirmou projeção e tombstone fictícios. Um controle negativo concedeu SELECT
  temporariamente à role numa relação de snapshot: a asserção de “sem acesso a outras
  relações” falhou sozinha como esperado; o grant foi revogado e sua ausência foi
  confirmada antes do cleanup.
- Dois ajustes foram necessários apenas nos testes: a asserção de políticas V2 agora
  discrimina políticas de cliente das políticas internas do owner; os testes de
  permissão não usam `throws_ok` sob sessão superusuária como prova de negação, pois
  isso não representa uma autenticação real. O teste de escritor e o de snapshots
  recebem USAGE de `extensions` só dentro da transação pgTAP, revertida ao final.
- Regressão final: Node compartilhado **240 pass / 0 fail / 6 skipped (246 total)**;
  Functions **196/196**; `functions/npm run check`; teste focal do writer **16/16**;
  `git diff --check` aprovado. Os seis skips Node dependem de Firebase Emulator ou
  integração PostgreSQL/Firestore; esta etapa não os ativou.
- Limitações: o teste não valida Supabase hospedado, pooler compartilhado/transação,
  TLS do driver, IAM Firebase, consumidor Edge com a nova identidade ou revogação
  do EXECUTE legado `service_role`. O `service_role` foi mantido e o script manual
  de cutover não foi executado. Ainda não há driver Deno concreto no consumer.
- Cleanup: somente os containers criados nesta tarefa foram removidos; sem volumes
  ou portas novos. Os dois volumes preexistentes foram preservados. O estado final
  do Docker e do Git é registrado no relatório da execução; sem commit ou push.

### Driver PostgreSQL Deno e fluxo local completo — 07.5.6G (22/10/2026)

- Estado: **INTEGRAÇÃO LOCAL COM POSTGRESQL REAL VALIDADA; HOMOLOGAÇÃO HOSPEDADA PENDENTE**.
- Implementado `supabase/functions/_shared/catalog_postgres_driver.mjs`: driver
  concreto `postgres.js` injetável, somente para as duas RPCs privadas V2 existentes,
  JSONB parametrizado, limite de payload, timeout/cancelamento, conexão única,
  statements preparados desativados para compatibilidade com pooler de transação e
  TLS com validação de certificado no modo hospedado. A validação local aceita apenas
  `catalog_writer_v2_login` em loopback; hosted exige
  `catalog_writer_v2_login.<project-ref>` no pooler transacional Supabase na porta
  6543. Não existe fallback para `service_role`.
- `consume-catalog-outbox/index.ts` compõe esse driver usando a dependência fixada
  `npm:postgres@3.4.7`, presente em `deno.lock`. `deno.json` conserva o lockfile.
  Configuração incompleta ou falha ao compor o driver deixa o consumidor desabilitado.
- Evidência E2E: o consumidor Deno foi chamado com HMAC sintético, leu e confirmou
  eventos no Firestore Emulator `demo-universal-search` em `127.0.0.1:18087`, conectou
  realmente como `catalog_writer_v2_login` ao PostgreSQL 15.19 descartável e os dados
  foram verificados por uma segunda conexão de teste. Aplicadas as seis migrations
  locais até a role restrita. A senha foi aleatória e limitada ao banco efêmero.
  O banco foi iniciado com diretório de dados tmpfs e sem volumes persistentes; a
  migration foi montada somente para leitura. A imagem em cache foi usada sem pull.
- A integração cobriu: publicação e confirmação Firestore após commit SQL; ID
  `modelo-*` e operação/versão persistidos; ausência de sentinel privado na projeção;
  replay duplicado idempotente; versão nova e evento antigo superseded; falha SQL com
  retry sanitizado e recuperação; commit SQL seguido de falha na confirmação
  Firestore e recuperação por replay; dois workers simultâneos com uma única escrita.
- Um defeito concreto do driver foi corrigido durante a validação: `postgres.js`
  serializava novamente um valor JSONB recebido como string, persistindo escalar JSON
  em vez de objeto. O driver agora decodifica o JSON validado e envia um valor tipado
  OID 3802; a suíte confirma raiz JSONB de objeto e preservação UTF-8 de `Comércio`.
  As migrations foram aplicadas por arquivo via `psql -f` em mount read-only para
  evitar alteração de caracteres pelo pipeline do PowerShell.
- Testes desta execução: integração Deno→Firestore Emulator→PostgreSQL **1/1**;
  testes Deno do handler/config **3/3**; testes Node shared **247 aprovados, 0 falhas,
  6 condicionais ignorados**; Functions `npm test` **196/196**; `npm run check`
  aprovado; Deno `check` e `fmt --check` aprovados; driver/config em Node **13/13**.
  Os seis skips shared são testes condicionais de outros serviços locais e não anulam
  a integração real desta etapa. `deno lint` padrão foi tentado e falhou nas regras
  `no-import-prefix`, `no-explicit-any` e `require-await` no entrypoint/harness; o
  repositório não tinha script Deno lint configurado. É uma pendência de lint, não
  falha de type-check, formatação ou execução.
- Limitação observada: PostgreSQL emitiu um `TimeoutNegativeWarning` isolado de
  `postgres.js` durante execução bem-sucedida; o fluxo completou e o teste verificou
  persistência, mas a origem interna desse aviso merece revisão antes de produção.
  Esta validação não comprova TLS, pooler, IAM, índices, secrets, Edge Runtime gerenciado
  ou serviços hospedados; esses pontos permanecem pendentes. Não houve mudança de
  flags, Cron, Rules, deploy, cutover, commit ou push.
- Cleanup: somente o container e a rede rotulados desta execução foram removidos;
  zero listener permaneceu nas portas 18087/25439. Imagem e volumes preexistentes
  foram preservados. Resultado restrito ao ambiente local; nenhuma sincronização
  hospedada foi executada.

### Estabilização do consumidor e preparação de homologação — 07.5.6H (22/10/2026)

- Estado: **ESTÁVEL LOCALMENTE; HOMOLOGAÇÃO HOSPEDADA PENDENTE**. O import map
  Deno declara `postgres` como `npm:postgres@3.4.7` no `deno.json` fixado por
  `deno.lock`; entrypoint e teste de integração usam o specifier curto. O teste
  estrutural da agenda foi ajustado para conferir tanto o import quanto o pin no
  import map, em vez de exigir o URL npm dentro do entrypoint.
- `deno lint` foi executado sem desativar regras globais nos três arquivos do
  consumidor/driver/teste de integração; passou. `deno check`, `deno fmt --check`
  e os testes Deno do handler/configuração também passaram.
- TLS local foi comprovado em PostgreSQL 15.19 descartável com certificado
  sintético criado pela API .NET já disponível, sem instalador nem certificado
  persistido no Windows. A sessão de confiança validada retornou `ssl=true` em
  `pg_stat_ssl`; o certificado não confiável e `sslmode=disable` foram rejeitados.
  O container usou apenas a imagem já em cache, publicou a porta em
  `127.0.0.1:25440`, manteve dados em tmpfs e removeu o próprio container ao final.
  Isso comprova a exigência TLS do PostgreSQL local, mas não testa TLS do pooler
  Supabase, trust chain hospedada ou conexão Deno→pooler. Testes unitários existentes
  confirmam que o driver hosted define `rejectUnauthorized: true`.
- Aviso observado anteriormente: `TimeoutNegativeWarning` de `postgres.js` 3.4.7
  sob compatibilidade Node do Deno. A inspeção da dependência local encontrou o
  agendamento `closedDate + delay - performance.now()` em `src/index.js`; se a
  tentativa de reconexão ocorrer depois do prazo calculado, Deno recebe duração
  negativa e a reduz para 1 ms. O fluxo 07.5.6G persistiu os dados e recuperou a
  operação; não foi reproduzido nem mascarado nesta rodada. Não há correção local
  apropriada sem patch/upgrade da dependência ou alteração do comportamento de
  reconexão. Manter como aviso conhecido; avaliar atualização fixada de `postgres.js`
  em tarefa separada e repetir E2E antes de adotá-la.
- Testes executados nesta rodada: `deno lint` **3 arquivos aprovados**; `deno check`
  **2 arquivos aprovados**; Deno handler/config **3/3**; shared Node **247 aprovados,
  0 falhas, 6 condicionais ignorados (253 total)**; driver/config/agenda Node **13/13**;
  Functions **196/196** e `npm run check` aprovado; TLS local **3/3** (CA confiável,
  CA não confiável e plaintext); `git diff --check` aprovado. O E2E completo da seção
  07.5.6G não foi repetido, pois as mudanças desta etapa se limitaram ao import map,
  lint e teste estrutural; sua execução anterior continua sendo a evidência local do
  fluxo integrado, não uma validação hospedada.
- Preparação executável para homologação: os testes de configuração/driver aceitam
  apenas o papel dedicado `catalog_writer_v2_login.<project-ref>`, pooler transacional
  Supabase na porta 6543, Firebase project/conta de serviço correspondentes, segredo
  HMAC presente e TLS validado; rejeitam `service_role`, endpoint direto, ref divergente
  e `sslmode=disable`. Rodar esses testes offline não autentica em serviço algum. A
  homologação real ainda precisa validar a identidade Firebase e seus IAM mínimos,
  provisionamento dos secrets, pooler/ref TLS real, índices hospedados e uma sincronização
  canário em ambiente de homologação, com autorização própria.
- Nenhum acesso hospedado, alteração de flag, ativação de Cron, deploy, commit ou push.
  O consumidor permanece fail-closed/desabilitado por padrão. A etapa 07.5.6 não está
  homologada e não está pronta para produção.

### Runner de homologação do consumidor — 07.5.6I (22/10/2026)

- Estado: **RUNNER PREPARADO LOCALMENTE; HOMOLOGAÇÃO REAL NÃO EXECUTADA**. Criados
  `tools/catalog-outbox-homologation.mjs`, o CLI Deno correspondente e testes offline.
  O preflight requer Firebase de staging com sufixo explícito, identidade da service
  account aprovada por e-mail exato e chave RSA pertencente ao mesmo projeto, ref
  Supabase aprovada distinta da ref de produção, pooler transacional e LOGIN
  `catalog_writer_v2_login.<ref>`, chave `anon`/publishable, HMAC e atestação de
  ambiente exclusivo. Rejeita projeto demo/produção e credenciais `service_role`,
  token de administração Supabase e credencial Google implícita.
- A canário executável verifica TLS/identidade SQL, grants das duas RPCs e ausência de
  DML direto nas tabelas; fila e checkpoint ociosos; rejeição HMAC inválido; commit
  atômico de estabelecimento e evento V2 exclusivamente sintéticos; consumo/ACK no
  Firestore; replay idempotente no escritor; projeção pública allowlisted; e negação
  de SELECT direto com chave pública. Não apaga o par sintético. Se houver falha após
  a criação, retorna IDs `modelo-homologation-*` para recuperação manual segura.
- O Consumer recebeu opt-in explícito de homologação para projeto Firebase terminado
  em `-staging` ou `-homologation`, sem alterar o pin canônico de produção. A flag não
  foi habilitada em nenhum ambiente e não houve chamadas hospedadas.
- Os testes Node focados do runner/config/Firestore REST passaram **34/34**. Deno
  2.9.7 `check` passou para CLI e entrypoint do consumer; `deno lint` passou em
  cinco módulos de runtime e `deno fmt --check` passou nos três arquivos do runner.
  `functions/npm test` passou **196/196** e `functions/npm run check` passou.
  `node --check` e `git diff --check` passaram. Um preflight Deno com chave RSA
  sintética e variáveis isoladas passou sem permissão de rede; outro com configuração
  ausente foi recusado sem imprimir segredos. Durante o preflight funcional foi
  encontrada e corrigida a ausência da ref Supabase aprovada na allowlist de env do
  CLI. Os testes do runner também rejeitam privilégios administrativos, membership
  adicional, CREATE no schema `public`, RPC ausente e DML direto.
- A canário não enumera todos os grants IAM da service account: operações reais
  demonstram as permissões usadas, mas a ausência de permissões IAM adicionais requer
  revisão efetiva dos grants por pessoa autorizada. A checagem de fila/checkpoint não
  é lock distribuído contra produtores que iniciem depois; a atestação de ambiente
  exclusivo e a pausa operacional de consumidores concorrentes são pré-condições.
  Supabase/Firebase hospedados, Rules de cliente, índice real, Edge runtime gerenciado,
  deployment, cron e cutover permanecem não verificados.
- Procedimentos e modelos de deploy/rollback não executados estão em
  `docs/catalog-outbox-homologation.md`. Rollback pausa futuras invocações; não desfaz
  projeções já confirmadas. O próximo passo é uma autorização específica de
  homologação, provisão segura das credenciais de staging e revisão IAM, seguida da
  execução manual do runner em ambiente isolado. Não está homologado nem pronto para
  produção.

### Homologação real em staging — 07.5.6J (22/10/2026)

- Estado: **BLOQUEADO — acesso hospedado não autorizado nesta solicitação**. O pedido
  exige autorização explícita antes de qualquer chamada remota e declara que não a
  concede por si só. Nenhum Firebase ou Supabase hospedado foi acessado; não houve
  deploy, canário, ativação de flags/Cron, publicação de Rules ou cutover.
- A existência e o isolamento de projetos Firebase/Supabase exclusivos de staging
  permanecem **não verificados**: esta etapa não consultou contas nem serviços
  hospedados. A configuração local/documentação do runner define os requisitos, mas
  não constitui prova da existência dos projetos nem da separação de produção.
- O runner executável permanece o preparado na 07.5.6I. Ainda é necessária uma
  autorização explícita que nomeie os projetos de staging e permita as verificações
  hospedadas descritas no runner, além da provisão segura — sem valores em chat ou
  repositório — da identidade Firebase de staging, grants IAM efetivos revisados,
  credencial do login PostgreSQL restrito, HMAC e configuração de runtime Edge. A
  homologação também exige confirmação operacional de exclusividade do ambiente e
  pausa de workers concorrentes; a revisão IAM deve identificar e remover/justificar
  privilégios excessivos antes da canário.
- Nenhum teste local foi repetido, pois esta etapa tinha como objetivo a validação
  hospedada e o runner e os testes offline já estão registrados na 07.5.6I. A etapa
  continua bloqueada, sem evidência de IAM real, TLS/pooler hospedado, grants
  hospedados, runtime Edge ou sincronização real em staging. Próximo passo: fornecer
  autorização específica para os recursos de staging identificados e preparar as
  credenciais pelo mecanismo seguro aprovado; então executar primeiro o preflight e
  a revisão IAM, e só depois decidir se a canário pode prosseguir.

- Atualização após disponibilização de staging: autorização específica posterior
  permitiu criar o Firebase `macacu-staging-261022` (Spark, sem billing confirmado
  pelo responsável; Firestore Standard em `southamerica-east1`, regras padrão
  fechadas, Auth email/senha habilitado) e o Supabase `rmhnaduzkykyudqnsdyf`
  (sa-east-1, PostgreSQL 17.11). As seis migrations V1/V2 foram aplicadas somente
  nesse Supabase novo e vazio. A migration do papel restrito precisou de ajuste
  local: membership `SET` temporário para transferência do owner e execução das
  alterações de ACL como o novo owner; a membership temporária foi revogada. A
  inspeção confirmou owner e `SECURITY DEFINER` nas duas RPCs privadas, negação de
  EXECUTE para `anon`/`authenticated`, ausência de DML direto para o executor e
  preservação das RPCs públicas. A conexão de login não foi provisionada e seu
  password não foi inspecionado nem exibido.
- Testes desta atualização: runner offline **7/7**, Functions **196/196** e
  `npm run check` aprovado; probes SQL de role/ownership foram executados em
  transações revertidas. Não houve canário, deploy de Edge Function, IAM, criação de
  credenciais ou acesso ao projeto Supabase piloto/produção. O ambiente ainda não
  está homologado: faltam identidade de máquina Firebase e IAM revisado, credencial
  segura do login PostgreSQL, função Edge no staging, HMAC/secrets e validação real
  de TLS/pooler pelo runner. A atualização local permanece sem staged; o workspace
  já estava amplamente alterado antes desta rodada.

- Continuação local: reutilizado Deno **2.9.7** portátil e Supabase CLI já cacheados,
  sem download. Corrigido o gate de staging para o ID real `macacu-staging-261022`,
  cuja parte numérica vem depois do marcador `staging`: o runner, a configuração do
  consumidor e o adaptador Firestore agora exigem o marcador e a correspondência do
  ID explicitamente aprovado; o consumer recebe essa allowlist por variável própria.
  Teste regressivo reproduziu a rejeição anterior e passou após o ajuste.
- Verificação local: preflight Deno com chaves e credenciais **sintéticas** retornou
  `ok`, `networkUsed: false` e `canaryArmed: false`; isso valida apenas formato e
  configuração local. `deno check` passou para o runner e o consumer; Deno lint/fmt
  passou em ambos; Deno consumer **3/3**; testes compartilhados **257 aprovados,
  0 falhas, 6 condicionais ignorados**; `git diff --check` passou. A função Edge
  ainda não está implantada no staging e não há evidência de IAM, TLS/pooler ou
  sincronização hospedada. Nenhuma credencial foi criada ou acessada; canário segue
  bloqueada até existir provisionamento seguro e deployment de staging autorizado.
- Continuação de preparação: leitura do Supabase staging confirmou estado
  `ACTIVE_HEALTHY`, PostgreSQL 17.11 e **nenhuma Edge Function implantada**. O comando
  do runner foi endurecido: agora nega leitura de `SUPABASE_SERVICE_ROLE_KEY`,
  `SUPABASE_ACCESS_TOKEN` e `GOOGLE_APPLICATION_CREDENTIALS`; os três nomes foram
  removidos da allowlist de ambiente. A documentação passou a usar os IDs reais de
  staging e listar os secrets do consumer sem service role. `deno check`, lint,
  fmt, os 8 testes Node do runner e `git diff --check` passaram. Ainda faltam
  identidade Firebase dedicada com IAM revisado, secrets seguros do login SQL e HMAC,
  ref Supabase de produção confirmada por fonte confiável e deploy explícito da
  função no staging; nenhuma canário foi executada.
- Atualização autorizada de staging: a função `consume-catalog-outbox` foi implantada
  somente em `rmhnaduzkykyudqnsdyf`, usando a CLI 2.121.0 já disponível e o import map
  versionado. A primeira tentativa falhou no bundler porque o CLI não inferiu o
  import map; a repetição explícita com `--import-map supabase/functions/deno.json`
  concluiu e a listagem remota confirmou `ACTIVE`, versão 1, `verify_jwt=false`.
  Nenhum schedule foi criado e nenhuma requisição de processamento/canário foi enviada.
  O handler usa HMAC próprio e a composição permanece fail-closed sem os secrets
  obrigatórios; nenhum secret foi configurado.
- A identidade Firebase de staging e o password do login restrito PostgreSQL continuam
  pendentes. Atualização: foi obtido temporariamente o Google Cloud CLI 590.0.0 do
  arquivo versionado oficial (SHA-256 conferido), com configuração OAuth isolada em
  `%TEMP%`. No projeto `macacu-staging-261022` foi criada a service account
  `catalog-outbox-consumer@macacu-staging-261022.iam.gserviceaccount.com`. A role
  predefinida inicial foi substituída por `projects/macacu-staging-261022/roles/catalogOutboxWorker`,
  customizada com oito permissões necessárias de metadados e entidades get/list/create/update,
  sem `datastore.entities.delete`; a policy de projeto confirmou somente essa role
  para a service account. Uma leitura de metadados do `(default)` como a própria conta
  confirmou acesso a Firestore Native em `southamerica-east1`, sem ler documentos.
  Uma chave de usuário foi enviada ao Secret Store do Supabase staging por arquivo
  temporário com ACL restrita; o segredo foi configurado sem exibir seu valor. A
  revogação OAuth das configurações gcloud temporárias passou. A ferramenta de shell
  bloqueou a remoção dos arquivos temporários próprios, então a chave/env permanecem
  sob ACL somente do usuário em `%LOCALAPPDATA%\Temp\macacu-staging-consumer-credential`;
  o SDK e a configuração OAuth temporária também permanecem em `%TEMP%` para limpeza
  local futura. O consumer tem apenas
  `CATALOG_CONSUMER_ENABLED=false`, `FIREBASE_PROJECT_ID` e a credencial Firebase de
  staging configurados, portanto permanece explicitamente desligado.
- A função continua sem password do login `catalog_writer_v2_login`, URL pooler TLS,
  HMAC ou referência confiável do Supabase de produção para a proteção anti-confusão
  de ambiente. Nenhum preflight hospedado ou canário foi executado. Não houve schedule;
  a função permanece `ACTIVE`, versão 1 e `verify_jwt=false`, protegida pelo handler
  HMAC quando habilitada, mas hoje responde indisponível por estar desabilitada.
  Próximo passo: provisionar o password do login SQL por canal seguro, confirmar a ref
  Supabase de produção por fonte confiável, então configurar TLS/pooler e HMAC e revisar
  a chave IAM longa para rotação (Google informa que chaves gerenciadas pelo usuário
  não expiram por padrão). Canário depende de autorização específica.
