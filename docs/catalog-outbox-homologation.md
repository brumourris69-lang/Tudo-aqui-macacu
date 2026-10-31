# Homologação controlada do consumidor de outbox

Este runner prepara e valida uma canário sintética no **ambiente Supabase/Firebase de homologação**. Ele não é um simulador: `--canary` faz chamadas hospedadas, cria um documento `establishments/modelo-homologation-*` e um evento V2 pareado, invoca o consumidor, verifica confirmação e replay no PostgreSQL. Não há exclusão automática. Reserve uma homologação isolada e aceite que os registros canário permanecerão como evidência; use o fluxo administrativo de exclusão lógica/tombstone aprovado para removê-los posteriormente, nunca apague diretamente.

## Execução local sem rede

Use o Deno portátil já disponibilizado e os imports em cache; não é necessário instalar dependências:

```powershell
$DenoExe = 'C:\Users\tiago\AppData\Local\Temp\codex-deno-edge-05-2-1c5bc9c9e3374846aa487d154af00072\deno-2.9.7-portable\deno.exe'
& $DenoExe run --cached-only --config supabase/functions/deno.json --allow-env=CATALOG_HOMOLOGATION_ENVIRONMENT,CATALOG_HOMOLOGATION_EXCLUSIVE_ENVIRONMENT,CATALOG_HOMOLOGATION_NO_PRODUCTION_SUPABASE,CATALOG_HOMOLOGATION_ENABLED,CATALOG_HOMOLOGATION_CONFIRM,FIREBASE_PROJECT_ID,FIREBASE_PRODUCTION_PROJECT_ID,CATALOG_HOMOLOGATION_APPROVED_FIREBASE_PROJECT_ID,CATALOG_HOMOLOGATION_APPROVED_FIREBASE_SERVICE_ACCOUNT_EMAIL,FIREBASE_SERVICE_ACCOUNT_JSON,SUPABASE_PROJECT_REF,SUPABASE_PRODUCTION_PROJECT_REF,CATALOG_HOMOLOGATION_APPROVED_SUPABASE_REF,SUPABASE_PUBLISHABLE_KEY,SUPABASE_URL,CATALOG_DATABASE_CA_CERT,CATALOG_DATABASE_URL,CATALOG_CONSUMER_HMAC_SECRET --deny-env=SUPABASE_SERVICE_ROLE_KEY,SUPABASE_ACCESS_TOKEN,GOOGLE_APPLICATION_CREDENTIALS tools/catalog-outbox-homologation.deno.ts --preflight
```

O preflight é offline. Ele valida formato, destino Supabase aprovado, sufixo de staging, chave RSA da service account e formato da URL do login SQL restrito; não prova identidade remota, IAM, TLS remoto, conexão, grants, RPC ou isolamento real. No runner local, se a organização acessível não lista produção, declare `CATALOG_HOMOLOGATION_NO_PRODUCTION_SUPABASE=true`. Essa declaração só substitui a comparação com uma ref de produção: a ref real do staging precisa coincidir com a ref aprovada e com a ref de staging confirmada e fixada no código (`rmhnaduzkykyudqnsdyf`). Ela registra a ausência de produção **na conta/organização consultada**, não prova que não exista produção em outra conta. O Edge Function não precisa de um secret extra para essa declaração: seu runtime só infere esse caso para o par exato de projetos de staging fixados no código.

## Pré-condições e autorização para a canário

Não forneça valores de produção ao processo. Configure os seguintes valores **somente no ambiente temporário do processo**, obtidos por canal seguro; nunca salve-os em `.env`, shell history ou repositório:

| Variável | Requisito |
|---|---|
| `CATALOG_HOMOLOGATION_ENVIRONMENT` | `staging` |
| `CATALOG_HOMOLOGATION_EXCLUSIVE_ENVIRONMENT` | `true`; atestação operacional de que o projeto é dedicado à homologação e sem workers/produtores concorrentes |
| `CATALOG_HOMOLOGATION_ENABLED` | `true` |
| `CATALOG_HOMOLOGATION_CONFIRM` | `RUN STAGING CANARY <firebase-staging-id> <supabase-ref>` exatamente |
| `FIREBASE_PROJECT_ID` | `macacu-staging-261022`, diferente de `tudo-aqui-macacu` e `demo-universal-search` |
| `FIREBASE_PRODUCTION_PROJECT_ID` | `tudo-aqui-macacu` |
| `CATALOG_HOMOLOGATION_APPROVED_FIREBASE_PROJECT_ID` | Deve ser exatamente `macacu-staging-261022` |
| `CATALOG_HOMOLOGATION_APPROVED_FIREBASE_SERVICE_ACCOUNT_EMAIL` | E-mail exato da service account de staging, aprovado por canal independente |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | JSON de service account do mesmo projeto de staging; credencial longa e privilegiada, armazenada apenas em secret manager/ambiente controlado |
| `SUPABASE_PROJECT_REF` | `rmhnaduzkykyudqnsdyf` for local execution; the hosted Edge Function derives the same fixed staging ref from Supabase's built-in `SUPABASE_URL` |
| `SUPABASE_PRODUCTION_PROJECT_REF` | Ref de produção confirmada, se existir e estiver acessível |
| `CATALOG_HOMOLOGATION_NO_PRODUCTION_SUPABASE` | No runner local, use `true` somente quando a listagem de leitura da organização acessível não mostrar projeto de produção; não pode ser combinada com uma ref de produção. Não é necessário como secret no Edge Function |
| `CATALOG_HOMOLOGATION_APPROVED_SUPABASE_REF` | Deve ser exatamente `rmhnaduzkykyudqnsdyf` |
| `CATALOG_DATABASE_URL` | Pooler transacional TLS na porta 6543, usuário `catalog_writer_v2_login.<ref>`, sem `service_role` |
| `CATALOG_DATABASE_CA_CERT` | Certificado CA oficial de banco baixado das configurações do projeto staging; TLS exige `rejectUnauthorized=true` e usa esse CA. É material público de confiança, não uma senha |
| `SUPABASE_PUBLISHABLE_KEY` | Chave publishable ou JWT com role `anon`; não é autorização do consumidor |
| `CATALOG_CONSUMER_HMAC_SECRET` | Segredo dedicado com pelo menos 32 bytes, igual ao configurado no consumer de staging |
| `SUPABASE_URL` | Optional for the local runner; in hosted Edge Functions it is provided by Supabase and must resolve to `https://rmhnaduzkykyudqnsdyf.supabase.co` |

Do not create a custom `SUPABASE_PROJECT_REF` secret: Supabase reserves the
`SUPABASE_` prefix. The hosted consumer reads the platform-provided `SUPABASE_URL`,
extracts the 20-character project ref only from an exact HTTPS `*.supabase.co`
origin, and rejects a mismatch with any explicit ref. Homologation is also
hard-pinned to `rmhnaduzkykyudqnsdyf`; a no-production declaration cannot redirect
the function to the paused pilot or another project.

O projeto Firebase de staging foi confirmado como Spark, sem billing, pelo responsável.
O projeto Supabase de staging é `tudo-aqui-macacu-staging` (`rmhnaduzkykyudqnsdyf`),
PostgreSQL 17.11 em `sa-east-1`. Antes da canário, confirme por fonte confiável a ref
Supabase de produção; não use `zzxvcunuwbhglzzklsrl` como ref de produção sem essa
confirmação.

### Secrets necessários no consumer Supabase

O Edge Function `consume-catalog-outbox` foi implantado no projeto de staging
`rmhnaduzkykyudqnsdyf` (versão 1, `verify_jwt=false`) sem agendamento. Nenhum secret
de ativação foi configurado e nenhuma canário foi executada; o consumer permanece
explicitamente desabilitado (`CATALOG_CONSUMER_ENABLED=false`) e não processa eventos.
Foi criada a service account de staging
`catalog-outbox-consumer@macacu-staging-261022.iam.gserviceaccount.com`, vinculada
somente à role customizada `projects/macacu-staging-261022/roles/catalogOutboxWorker`.
Ela contém permissões de metadados e entidades get/list/create/update, sem permissão
de exclusão; uma leitura de metadados do Firestore como a própria conta passou. Sua
chave foi guardada como secret do Edge Function; nenhum valor foi exibido. O consumer
está implantado na versão 19, sem agendamento. O URL do banco, HMAC e as referências
aprovadas de staging estão configurados; `CATALOG_CONSUMER_ENABLED` permanece `false`.
Antes de uma canário autorizada, configure somente os
seguintes secrets/variáveis no projeto `rmhnaduzkykyudqnsdyf`:
`CATALOG_CONSUMER_ENABLED=true`,
`CATALOG_DATABASE_MODE=hosted`, `FIREBASE_PROJECT_ID=macacu-staging-261022`,
`FIREBASE_SERVICE_ACCOUNT_JSON`, `CATALOG_CONSUMER_HOMOLOGATION=true`,
`CATALOG_HOMOLOGATION_PRODUCTION_FIREBASE_PROJECT_ID=tudo-aqui-macacu`,
`CATALOG_HOMOLOGATION_APPROVED_FIREBASE_PROJECT_ID=macacu-staging-261022`,
`CATALOG_HOMOLOGATION_PRODUCTION_SUPABASE_REF=<ref de produção verificada>`,
`CATALOG_HOMOLOGATION_APPROVED_SUPABASE_REF=rmhnaduzkykyudqnsdyf`,
`CATALOG_DATABASE_URL` (login `catalog_writer_v2_login`, pooler TLS),
`CATALOG_DATABASE_CA_CERT` (CA oficial do banco staging) e
`CATALOG_CONSUMER_HMAC_SECRET` (segredo aleatório dedicado de pelo menos 32 bytes).
O runtime fornece `SUPABASE_URL`; não tente cadastrar um secret `SUPABASE_PROJECT_REF`.
Não configure service role, access token Supabase ou `GOOGLE_APPLICATION_CREDENTIALS`.
O handler continua fail-closed com configuração ausente; agendamento permanece
desativado nesta homologação manual.

Verifique o destino com `--preflight` primeiro. Leia e revise a confirmação de canário antes de armar `--canary`. Permita somente as variáveis acima ao Deno; a opção `--allow-net` é necessária para a canário e permite rede de processo, portanto execute-a em uma máquina/sessão controlada. O runner fixa os hosts Firebase, Supabase e pooler derivados dos IDs/ref, usa TLS com validação de certificado, timeouts limitados e respostas/logs sanitizados. Não passe `--allow-all`.

Com a configuração temporária definida, execute:

```powershell
& $DenoExe run --cached-only --config supabase/functions/deno.json --allow-env=CATALOG_HOMOLOGATION_ENVIRONMENT,CATALOG_HOMOLOGATION_EXCLUSIVE_ENVIRONMENT,CATALOG_HOMOLOGATION_NO_PRODUCTION_SUPABASE,CATALOG_HOMOLOGATION_ENABLED,CATALOG_HOMOLOGATION_CONFIRM,FIREBASE_PROJECT_ID,FIREBASE_PRODUCTION_PROJECT_ID,CATALOG_HOMOLOGATION_APPROVED_FIREBASE_PROJECT_ID,CATALOG_HOMOLOGATION_APPROVED_FIREBASE_SERVICE_ACCOUNT_EMAIL,FIREBASE_SERVICE_ACCOUNT_JSON,SUPABASE_PROJECT_REF,SUPABASE_PRODUCTION_PROJECT_REF,CATALOG_HOMOLOGATION_APPROVED_SUPABASE_REF,SUPABASE_PUBLISHABLE_KEY,SUPABASE_URL,CATALOG_DATABASE_CA_CERT,CATALOG_DATABASE_URL,CATALOG_CONSUMER_HMAC_SECRET --deny-env=SUPABASE_SERVICE_ROLE_KEY,SUPABASE_ACCESS_TOKEN,GOOGLE_APPLICATION_CREDENTIALS --allow-net=firestore.googleapis.com,oauth2.googleapis.com,rmhnaduzkykyudqnsdyf.supabase.co,<POOLER_HOST>:6543 tools/catalog-outbox-homologation.deno.ts --canary
```

Substitua os dois últimos placeholders por hosts literais extraídos da URL/ref aprovadas antes de executar; não rode o texto com `<...>` sem substituição. A autorização de rede fica limitada aos hosts listados, mas a máquina ainda pode acessar esses serviços durante o processo.

Confirme previamente que o consumidor hospedado está implantado, desabilitado para agendamento concorrente durante a canário, autenticado com a mesma configuração, e que `catalog_outbox` não contém itens `pending`/`processing` e `catalog_outbox_scan_state/consumer-v1` está sem cursor/lease. O runner verifica fila e checkpoint antes de inserir, mas essa verificação não bloqueia produtores externos que iniciem depois dela. A variável de ambiente exclusiva é uma atestação do operador, não uma trava de exclusividade distribuída. Não rode com tráfego administrativo real ou outro worker ativo.

### O que a canário comprova e não comprova

- Confirma que a credencial Firebase consegue obter token e executar leitura da fila, commit pareado sintético e as atualizações necessárias ao consumer. A service account server-side contorna Firestore Rules; isso não valida Rules de cliente.
- Confirma identidade SQL `catalog_writer_v2_login`, conexão TLS validada, ausência de privilégios de superusuário e DML direto nas duas tabelas, e EXECUTE nas duas RPCs V2 requeridas. Confirma leitura da RPC pública e negação da leitura direta da tabela com chave `anon`.
- Demonstra capacidade IAM das operações usadas, mas não enumera todos os grants IAM da service account nem prova que ela não tenha permissões adicionais. Revise IAM efetivo no console/API Google por uma pessoa autorizada antes da homologação e produção.
- Não prova isolamento do projeto, não substitui revisão de índices, não valida regras de produção, rotação de credenciais ou disponibilidade operacional.
- Se falhar depois da criação do par, o erro informa somente IDs sintéticos para investigação. Preserve-os; não faça limpeza ampla nem exclusão direta.

## Deploy e rollback — comandos preparados, não executados

Os comandos abaixo são modelos para **um projeto de staging explicitamente aprovado**. Confirme a sintaxe com a versão de Supabase CLI escolhida e revise o projeto/ref antes de executar. O deploy do consumer no staging foi autorizado e concluído em 2026-10-22. Este documento não autoriza configurar secrets, executar canário, publicar migrations ou ativar Cron além do escopo explicitamente autorizado.

```powershell
# Revisão de destino, sem mutação
supabase functions list --project-ref <STAGING_SUPABASE_REF>

# Implantar somente após autorização específica
supabase functions deploy consume-catalog-outbox --project-ref <STAGING_SUPABASE_REF>

# Rollback operacional: bloquear novas execuções
supabase secrets set CATALOG_CONSUMER_ENABLED=false --project-ref <STAGING_SUPABASE_REF>

# Se também for necessário voltar o código, entre em uma cópia da revisão anterior
# previamente identificada e revisada; este deploy publica o código desse diretório.
Set-Location <CHECKED_OUT_PREVIOUS_RELEASE_DIRECTORY>
supabase functions deploy consume-catalog-outbox --project-ref <STAGING_SUPABASE_REF>
```

Substitua placeholders antes de executar e confirme `supabase --help`/`supabase functions deploy --help` na CLI escolhida. O rollback operacional pausa novas execuções; o segundo comando só republica o código efetivamente presente no diretório indicado. Nenhum comando desfaz projeções já confirmadas. Corrija/reconcilie dados por operações versionadas/tombstones, não por exclusão de tabela. Nunca use `db reset`, `db push`, deploy de migrations ou remoção de projeto como rollback.

### Atualização do gate de staging (27/10/2026)

- A organização Supabase conectada lista o projeto ativo de staging
  `rmhnaduzkykyudqnsdyf` e o piloto pausado `zzxvcunuwbhglzzklsrl`; nenhum projeto de
  produção aparece nessa conta. O piloto não foi tratado como produção.
- O preflight local registra a ausência de produção com uma declaração explícita. O
  runtime hospedado evita um secret adicional: só permite a homologação para o par
  fixo `macacu-staging-261022` + `rmhnaduzkykyudqnsdyf`, e falha fechado para qualquer
  outro projeto.
- A Edge Function `consume-catalog-outbox` está na versão 23 em staging, com
  `verify_jwt=false` preservado e autenticação HMAC mantida no handler. A implantação
  não alterou secrets, flag ou agendamento. A flag `CATALOG_CONSUMER_ENABLED` estava
  previamente confirmada como `false`; não foi consultada novamente.
- Consulta SQL read-only confirmou ausência do schema `cron` e da extensão `pg_cron`.
  Nenhuma chamada da função ou canário foi executada. Persistência/conexão do pooler
  com o segredo atual ainda precisa de verificação antes de uma canário autorizada.
