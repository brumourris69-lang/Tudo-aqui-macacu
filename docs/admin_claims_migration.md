# Admin por Custom Claims — preparação local (Etapa 1B)

## Estado e política

Nenhuma conta, claim, regra ou serviço de produção foi alterado. As alterações
locais da etapa 1A estão preservadas. Não executar deploy destes arquivos sem
revisão e autorização específica para a Fase B.

Política final preparada: token Firebase validado pelo SDK/servidor, UID válido,
provedor não anônimo e **`admin: true` booleano**. E-mail e `users.role` não são
provas de autorização. A claim `role: admin` também não basta na política nova.
`email_verified` não é requisito adicional quando existe a claim confiável:
quem concede acesso deve verificar previamente a identidade e o UID corretos.
Sem token, token inválido ou conta anônima: negar acesso.

## Divergências encontradas e preparação

| Componente | Antes | Preparação local |
|---|---|---|
| Flutter | E-mail fixo | Cache de claims obtidas por `getIdTokenResult`, associado ao UID, atualizado por `idTokenChanges`; escopo reativo recompõe controles administrativos. |
| Perfil | Login atribuía `role: admin` por e-mail | Login somente cria perfil comum (`role: user`) e não altera role existente. Não concede claims. |
| Firestore | Claim admin, claim role ou e-mail sem confirmação | `firestore.claims-local.rules` aceita somente claim admin em conta não anônima. |
| Functions de upload | Claim admin, role ou e-mail verificado | Política compartilhada; Functions Emulator sempre usa modo estrito. |
| Worker | JWT válido + política de upload antiga | Mesma política compartilhada; modo `ADMIN_AUTHORIZATION_MODE=claims-only` testado com JWTs assinados localmente e chaves de teste. |
| Push/search | Gatilho/Admin SDK e callable de busca | Fila continua protegida por Rules; pesquisa pública continua disponível a visitantes anônimos, sem privilégios administrativos. |

Telas/operações afetadas: entrada do painel no perfil, edição da Home,
importação de exemplos, métricas, configuração de Turismo e uploads. A checagem
Flutter é capacidade visual; o servidor sempre precisa autorizar a operação.

## Fase A — aplicada somente localmente

- `firebase.search-emulator.json` usa `firestore.claims-local.rules`.
  `firebase.json` continua apontando para `firestore.rules`, que mantém o fallback
  de produção anterior. Teste verifica que a cópia preparada difere somente no
  predicado administrativo e preserva integralmente as regras de notificações.
- Flutter em `searchLocal` é estrito. A variante normal suporta claims e mantém
  temporariamente o e-mail legado. Existe flag preparada `ADMIN_CLAIMS_ONLY=true`
  para a ativação futura, ainda não aplicada a builds de produção.
- Functions/Worker mantêm `legacy-transition` na configuração normal. O Worker
  não teve sua configuração implantada alterada. Não confundir testes do modo
  estrito com ativação no Worker real.

## Procedimento local de concessão e revogação

`functions/scripts/admin_claims_local.js` é uma ferramenta de operador confiável,
sem endpoint HTTP/callable. Recusa qualquer projeto diferente de
`demo-universal-search`, Auth diferente de `127.0.0.1:9097`, Firestore não local
ou ausência do marcador Functions Emulator. O operador deve ter acesso à máquina
local de testes. Nenhuma credencial de serviço é incluída no Flutter.

O padrão é **dry-run**. Aplicar exige `--apply` e confirmação literal combinando
projeto, UID e ação. Contas anônimas ou desabilitadas não recebem Admin.
Claims não relacionadas são preservadas. As operações devem ser serializadas
por UID: Firebase Auth não oferece transação com comparação de claims, portanto
não executar esta ferramenta junto com outro gestor de claims.

```powershell
$env:GCLOUD_PROJECT='demo-universal-search'
$env:FUNCTIONS_EMULATOR='true'
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8087'
$env:FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9097'
# UID exclusivamente fictício e previamente conferido no emulador.
node functions/scripts/admin_claims_local.js --uid UID_FICTICIO --action grant --operator operador-local --reason teste
# Aplicar somente após conferir o dry-run e autorizar o alvo local:
node functions/scripts/admin_claims_local.js --uid UID_FICTICIO --action grant --operator operador-local --reason teste --apply --confirm demo-universal-search:UID_FICTICIO:grant
```

Para revogar: usar `--action revoke` e confirmação terminada em `:revoke`.
A operação remove `admin` (e a claim legada `role: admin`, se presente) e chama
`revokeRefreshTokens`. Não modifica `users.role` como autorização.

`admin_claim_changes` é trilha local privada escrita apenas pelo Admin SDK:
projeto, UID alvo, ação, operador, motivo, antes/depois da condição admin,
horários e status prepared/applied/failed-review-required. Clientes não recebem
permissão de escrita. Falha parcial exige revisão antes de repetir; Auth e
Firestore não compartilham uma transação atômica. O nome de operador informado
é registro operacional, não autenticação adicional do executor.

## Renovação e revogação: limites importantes

**Atualização da etapa 1B.1:** a limitação abaixo descreve a implementação inicial
de 1B e continua aplicável ao fallback de produção. A política local estrita agora
exige também estado central versionado, bloqueando o token antigo após o commit
de revogação. Consulte [admin_revocation_local.md](admin_revocation_local.md) para
o mecanismo, custos, testes, limites e requisitos atualizados de ativação.

- Conceder a claim não modifica tokens já emitidos. Cliente deve renovar com
  `getIdTokenResult(true)`/`getIdToken(true)` ou sair e entrar novamente. O serviço
  Flutter expõe `updateUser(user, forceRefresh: true)` para essa atualização.
- `idTokenChanges` não recebe uma notificação instantânea quando alguém altera
  claims no servidor. Atualização exige renovação efetiva do token.
- Remover claim e revogar refresh tokens bloqueia sessões revogadas nos servidores
  que usam `verifyIdToken(token, true)`. O teste local confirma essa rejeição.
- **Rules Firestore, callable padrão e Worker com validação JWT isolada não
  consultam automaticamente revogação de sessões.** Um ID token antigo ainda
  contém a claim e pode manter acesso até expirar (normalmente até cerca de uma
  hora), embora um token novo já seja negado. Esse comportamento foi confirmado
  no Emulator, não ocultado como teste aprovado de revogação imediata.
- Se revogação imediata for obrigatória, preparar antes da Fase B um estado de
  autorização/revogação somente servidor consultado pelas Rules e pelos serviços,
  e verificação confiável de revogação no Worker/Functions. Worker não possui
  Firebase Admin SDK/credencial confiável configurada para essa consulta hoje.
  Não colocar credenciais administrativas no app nem adicionar endpoint de
  concessão para contornar a pendência. App Check não substitui autorização.

## Fase B — futura, exige autorização separada

1. Conferir projeto real, UID e identidade do administrador autorizado em
   ambiente confiável. Verificar IAM mínimo do operador e acesso de recuperação.
2. Registrar aprovação e atribuir `admin: true` à conta correta via ferramenta
   administrativa confiável, preservando claims existentes. **A ferramenta local
   desta etapa recusa produção e não deve ter seus bloqueios removidos.**
3. Renovar token; confirmar apenas o resultado booleano da claim, sem copiar
   JWT, senha ou credenciais para logs. Confirmar painel, edição, uploads,
   notificações privadas e fila de push com a versão preparada.
4. Somente depois dessas confirmações, autorizar troca das Rules pelo predicado
   estrito, ativação do modo claims-only em Functions/Worker e flag Flutter.
   Eliminar fisicamente os caminhos legados numa revisão de ativação, evitando
   que um default de configuração reintroduza o e-mail futuramente.
5. Testar concessão/revogação em conta controlada, renovação, falha de sessão e
   o comportamento escolhido para tokens antigos. Não revogar a conta principal
   como teste inicial. Definir previamente se a janela do ID token é aceitável.
6. Registrar operação e validar versão/configuração efetivamente implantada.
   Fallback não é removido de produção nesta etapa; o acesso atual foi preservado.

## Validação local realizada

- Flutter Analyze: sem problemas.
- Suíte Flutter normal: 248 testes aprovados.
- Flutter com `ADMIN_CLAIMS_ONLY=true`: 9 testes aprovados.
- Testes Node de Functions: 45 aprovados; Worker: 10 aprovados.
- Integração real com Auth/Firestore Emulator: 7 cenários administrativos aprovados.
- Integração de notificações com as regras locais novas: 12 cenários aprovados,
  com envio FCM simulado exclusivamente no emulador.
- A integração confirmou também a janela de acesso do token antigo após
  revogação; não comprova revogação instantânea em Rules ou Worker.
- Nenhum deploy, alteração de conta real, APK, commit ou push foi realizado.

## Arquivos desta etapa

Modificados:

- `firebase.search-emulator.json`
- `functions/home_image_upload.js`
- `workers/image-upload/src/index.js`
- `workers/image-upload/test/worker.test.js`
- `lib/main.dart`
- `lib/redesigned_app.dart`
- `functions/integration/notifications_emulator.js`

Criados:

- `firestore.claims-local.rules`
- `functions/admin_policy.js`
- `functions/admin_claim_management.js`
- `functions/scripts/admin_claims_local.js`
- `functions/integration/admin_claims_emulator.js`
- `functions/test/admin_policy.test.js`
- `lib/core/auth/admin_authorization.dart`
- `test/admin_authorization_test.dart`
- `test/admin_rules_staging_test.dart`
- `docs/admin_claims_migration.md`

As alterações locais da etapa de notificações foram preservadas. A configuração
normal `firebase.json`, as regras canônicas durante esta etapa e a configuração
implantável do Worker não foram trocadas pela política local estrita.
