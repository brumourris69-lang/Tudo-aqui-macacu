# Homologação das Firestore Rules em staging

**Estado:** preparação local; inspeção de leitura do staging em 28/10/2026; nenhum recurso hospedado foi alterado.

## Rules e configurações fixadas

- Os harnesses de SDK cliente exercitados localmente carregam `firestore.rules` pela configuração `firebase.search-emulator.json`.
- `firebase.json` também aponta para `firestore.rules`; esse é o único arquivo de Rules previsto para uma futura publicação em staging.
- `firestore.claims-local.rules` é um espelho byte a byte da fonte testada.
- SHA-256 fixado no preflight: `ddc454413e66107a2087265c3bc9012f7343f90e67a491c353e64e49a75d13b8`.
- `firestore.hybrid-outbox-candidate.rules` e `firestore.hybrid-outbox-v2-candidate.rules` **não** fazem parte deste alvo de staging nem desta homologação.
- `.firebaserc` continua com `tudo-aqui-macacu` como projeto padrão. Não altere o alias: todos os comandos Firebase precisam informar `--project` explicitamente.

O manifesto `tools/staging-rules-preflight.json` fixa os projetos demo, staging e produção, os caminhos de Rules/configuração, as portas de loopback e o hash acima. Ele é um manifesto local de verificação, **não** uma configuração Firebase CLI. O preflight também confirma que Auth e Firestore do perfil de teste escutam em `127.0.0.1`, que a UI do Emulator está desligada e que os dois arquivos de Rules permanecem idênticos.

## Comandos locais reproduzíveis

No PowerShell, a partir da raiz do repositório, rode primeiro o gate offline:

```powershell
node tools/staging-rules-preflight.mjs
```

Ele não inicia a Firebase CLI nem contata Firebase. Para os testes no Emulator, inicie Auth e Firestore em um terminal separado:

```powershell
firebase emulators:start --config firebase.search-emulator.json --project demo-universal-search --only auth,firestore --non-interactive
```

Em outro terminal, execute os harnesses existentes com os destinos de SDK fixados em loopback:

```powershell
$env:GCLOUD_PROJECT = 'demo-universal-search'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8087'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9097'
node functions/integration/favorites_client_rules_emulator.js
node functions/integration/home_pages_rules_emulator.mjs
```

Os harnesses criam somente usuários/documentos sintéticos no Emulator e removem somente as fixtures de IDs criados por eles. Encerrada a prova, pare os Emulators com `Ctrl+C`. Não substitua o projeto por um alias nem remova as variáveis de loopback para tentar alcançar staging.

Validações de regressão locais:

```powershell
npm --prefix functions test
npm --prefix functions run check
git diff --check
```

## Preparação para staging — não executada

O único alvo configurado é `macacu-staging-261022`; produção é `tudo-aqui-macacu`; o projeto de testes é `demo-universal-search`. O comando de publicação preparado, que **exige autorização separada antes de ser executado**, é:

```powershell
node tools/staging-rules-preflight.mjs
firebase deploy --only firestore:rules --config firebase.json --project macacu-staging-261022
```

O parâmetro `--project macacu-staging-261022` é obrigatório. Nunca retire `--project`: o alias padrão local aponta para produção. Antes de uma futura publicação, o responsável deve conferir no Console que o cabeçalho mostra exatamente o ID de staging e guardar a versão atual das Rules de staging para rollback. Depois, deve conferir que a versão ativa contém o mesmo conteúdo e hash fixado.

Os harnesses atuais têm guardas deliberadas para `demo-universal-search` e endpoints de loopback; eles não são comandos de teste hospedado e não devem ser adaptados por remoção dessas guardas. A matriz hospedada precisa de um runner de SDK cliente próprio, com configuração de projeto de staging fixa, contas sintéticas e nenhum segredo privilegiado no repositório. Esse runner ainda não foi preparado nem executado.

## Identidades, permissões e dados

- Projeto Firebase exclusivo de staging, com Authentication e Firestore habilitados; sem dados reais de moradores.
- Operador com a permissão mínima para publicar/consultar Rules de Firestore no projeto de staging; não usar Owner/Editor nem uma chave de service account ampla como atalho.
- Contas sintéticas separadas: Admin autorizado com claim e registro de autorização vigente, usuário comum e Admin revogado. O estado do Admin deve ser configurado pelo fluxo autorizado existente, sem alterar o verificador de produção.
- Testes por SDK cliente para leitura/gravação administrativa, isolamento de Favoritos e Minha Agenda, publicação e visibilidade de Eventos. Cobrir `deleted: true`, `deleted: false`, `deletedAt`, marcador ausente, `deletedAt: null`, rascunho e inativo.
- Nenhum teste hospedado deve ler usuários, conteúdo ou credenciais reais. Criar e apagar somente documentos de fixture identificados pelo próprio teste.

## GO, interrupção e rollback

**GO para a homologação de Rules em staging** somente quando o preflight local passa, o Console confirma o Project ID de staging, a versão ativa das Rules corresponde ao hash aprovado, os perfis sintéticos necessários estão prontos e todos os testes SDK cliente passam sem qualquer concessão indevida.

**Interromper imediatamente** se o hash, o caminho das Rules, a configuração, o Project ID ou a identidade da conta não coincidirem; se algum comando usar o alias padrão; se uma conta comum ou revogada conseguir operação administrativa; se houver vazamento entre usuários; ou se qualquer teste exigir dados reais ou privilégios ampliados.

**Rollback:** manter uma cópia da versão anterior das Rules de staging antes de publicar. Se a homologação falhar, interromper os testes e, mediante autorização específica, restaurar somente essa versão no mesmo Project ID. Não publicar em produção, remover dados, alterar Rules principais por fora deste processo ou ativar Functions/Cron.

## Evidência local existente

Na execução local de 28/10/2026, os harnesses reportaram 37 verificações de Favoritos/Minha Agenda/Eventos e 15 de Home/Estabelecimentos/Utilidades/Turismo aprovadas. A suíte Functions reportou 200/200. Esses resultados são evidência do Emulator e não equivalem a homologação hospedada.

## Inspeção de leitura do staging — 28/10/2026

- Identidade confirmada antes das consultas: projeto `macacu-staging-261022`, exibido como “Tudo Aqui Macacu Staging”. Produção (`tudo-aqui-macacu`) não foi consultada.
- A Firebase Rules REST API foi usada somente com `GET`: `projects.releases.list`, `projects.releases.get` e `projects.rulesets.get`. Não houve criação, publicação, substituição ou exclusão de Rules.
- O Release Firestore retornado é `projects/macacu-staging-261022/releases/cloud.firestore`, que é o Release padrão do Firestore e vincula o banco `(default)`. `createTime` e `updateTime`: `2026-10-28T14:24:38.111069Z`.
- O Release aponta para o Ruleset ativo `projects/macacu-staging-261022/rulesets/5c2d69e4-283a-444b-93f1-9e2204e095f5`, criado em `2026-10-28T14:24:35.703989Z`. A API retornou uma fonte chamada `firestore.rules` (163 bytes). `attachmentPoint` veio nulo no Ruleset; a associação ao `(default)` é comprovada pelo Release `cloud.firestore`, não por esse campo nulo.
- Backup bruto obtido de `source.files[0].content`, salvo sem normalizar quebras de linha: [Ruleset original](staging-backups/macacu-staging-261022-firestore-default-ruleset-5c2d69e4-20261028.rules). SHA-256: `ecf30f940747dcc3c5ba4993093e9a11ac9fc5df7e14b2a1512d2446923d84eb`; tamanho: 163 bytes. Os identificadores, nomes, timestamps e hash estão em [metadados do backup](staging-backups/macacu-staging-261022-firestore-default-ruleset-5c2d69e4-20261028.metadata.json). A verificação local do backup passou.
- O Ruleset ativo é deny-all (`allow read, write: if false`). Ele **não corresponde** ao candidato aprovado local `firestore.rules` (10.668 bytes; SHA-256 `ddc454413e66107a2087265c3bc9012f7343f90e67a491c353e64e49a75d13b8`). Portanto o staging, no estado lido, bloqueia clientes Firestore; não usar o candidato como se já estivesse publicado.
- O snapshot anterior do Console permanece preservado, sem alteração de conteúdo: 162 bytes, SHA-256 `cd4b3030287ceb2ce9b3ad7cf3d10bb4399dbd8b09aae8c743ec282ffc4b1b70`. Comparado ao conteúdo bruto da API, falta somente uma linha em branco após `rules_version = '2';`. Ele é uma transcrição visual, não uma cópia byte a byte nem uma referência de rollback.
- Verificador local estrito: `node tools/staging-rules-backup-preflight.mjs`. Ele não usa rede nem credenciais e falha se projeto, banco, Release, Ruleset, timestamps, nome do arquivo, tamanho ou SHA-256 não forem os valores fixados. Para comparar um novo snapshot **obtido por GET somente de leitura**, use `node tools/staging-rules-backup-preflight.mjs --verify-release-snapshot <arquivo.json>`. O snapshot deve conter `projectId`, `databaseId`, os objetos `release`, `ruleset` e `sourceFile` retornados/registrados pela captura. Esse comando valida uma captura local e não consulta Firebase nem prova que ela continua atual; faça o GET imediatamente antes de qualquer operação hospedada. Testes: `node --test tools/staging-rules-backup-preflight.test.mjs`.
- Authentication, App Check, contas e documentos não foram consultados nesta rodada. Nenhum recurso hospedado foi modificado; nenhum segredo ou token foi gravado nos artefatos.

### Procedimento de rollback preparado — não executado

O backup original pode ser restaurado apontando o mesmo Release `cloud.firestore` ao Ruleset previamente capturado. **Isso altera Rules hospedadas e exige autorização específica no momento da execução.** Antes de qualquer rollback, o operador deve fazer um novo `GET` do Release e verificar que o projeto continua `macacu-staging-261022`, o nome continua `cloud.firestore`, e o `rulesetName` atual é exatamente o Ruleset que se pretende substituir. Se qualquer um diferir, interromper e revisar; não aplicar uma referência antiga às cegas. Confirmar também com `GET` que o Ruleset original ainda existe e executar o verificador local do backup.

A chamada documentada pela Firebase Rules REST API é `PATCH /v1/projects/macacu-staging-261022/releases/cloud.firestore`, com máscara limitada a `rulesetName` e corpo apontando para o Ruleset original:

```json
{
  "release": {
    "name": "projects/macacu-staging-261022/releases/cloud.firestore",
    "rulesetName": "projects/macacu-staging-261022/rulesets/5c2d69e4-283a-444b-93f1-9e2204e095f5"
  },
  "updateMask": "rulesetName"
}
```

Após aprovação e eventual execução, fazer novo `GET` e confirmar que o Release aponta ao Ruleset original; não considerar o envio do PATCH, sozinho, como prova. A API documenta que `releases.patch` atualiza somente `rulesetName`: [Firebase Rules REST API — releases.patch](https://firebase.google.com/docs/reference/rules/rest/v1/projects.releases/patch).

### Decisão após leitura

**GO somente para manter o backup e preparar uma futura homologação; NO-GO para publicação, canário ou teste hospedado agora.** O Release ativo foi identificado e seu source original está preservado e verificável, mas o conteúdo ativo é deny-all, diverge do candidato aprovado, e as identidades sintéticas e o runner hospedado de SDK cliente ainda não foram preparados. A mudança do Release para o candidato e qualquer criação de contas/fixtures hospedadas exigem autorização própria. App Check também não foi avaliado nesta rodada.

Para a próxima homologação serão necessários: autorização específica para publicar o hash aprovado apenas no projeto staging; contas sintéticas e runner de SDK cliente próprios; teste de leitura/gravação sem dados reais; e autorização separada para eventuais mudanças de App Check. Revalidar o Release imediatamente antes da mudança e preservar o Ruleset original como referência de retorno.

## STAGING 2.2 — runner local preparado (28/10/2026)

Nenhuma chamada hospedada foi feita nesta etapa. Não foram criados usuários, documentos, credenciais ou configurações; nenhuma Rules foi publicada. O runner e seus testes são locais.

### Runner de SDK cliente

Arquivos: `tools/staging-rules-client-homologation.mjs`, `tools/staging-rules-client-homologation.test.mjs` e o modelo propositalmente inválido `docs/staging-rules-homologation-approval.example.json`.

Preflight local, sem Firebase/rede/credenciais:

```powershell
node tools/staging-rules-backup-preflight.mjs
node tools/staging-rules-preflight.mjs
node tools/staging-rules-client-homologation.mjs --preflight
node --test tools/staging-rules-backup-preflight.test.mjs tools/staging-rules-client-homologation.test.mjs
```

O comando `--execute` só inicia após validar: projeto e banco fixados; hash exato do candidato e do backup; Release, Ruleset, hash remoto, horários e arquivo de autorização; ID do app; ausência de variáveis de Emulator, projeto padrão, proxy, token App Check de debug, substituições de runtime/CA/TLS e endpoints alternativos; e credencial ADC por impersonação da identidade dedicada `[identidade redigida]`. Chaves privadas de service account são recusadas. A aprovação expira em até duas horas e deve ficar fora do repositório. O arquivo de exemplo não autoriza execução.

Antes de qualquer criação, o runner faz somente GETs nos endpoints fixos do projeto staging: Firebase Project, Auth config, App Check para Firestore/Auth e Release/Ruleset. Exige email/senha habilitado, App Check `UNENFORCED` para os dois serviços, e conteúdo do Ruleset ativo byte a byte compatível pelo hash SHA-256 com `firestore.rules`. Reconsulta o Release imediatamente antes da primeira escrita e aborta se o Ruleset ou `updateTime` mudou. Não há caminho de fallback para Emulator nem para produção.

Quando autorizado, gera em memória quatro contas com e-mails sintéticos `@example.invalid` (Admin ativo, dois usuários comuns e Admin revogado), senhas aleatórias que nunca são impressas, e fixtures de eventos, favoritos de comércio e agenda de evento com IDs exclusivos. A SDK cliente executa os testes de Admin, publicação, leitura pública, rascunho, inativo, `deleted: true`, `deletedAt`, listagem não permitida, autorização revogada e isolamento entre contas. O Admin SDK é usado apenas para preparar claims/estado de autorização e fixtures, não como prova das Rules. A limpeza confere UID/email e o conteúdo integral de cada documento antes de excluir; se um recurso tiver sido modificado após a criação, ele é preservado e a execução termina com erro de limpeza explícito. O runner não apaga recursos preexistentes e não implementa rollback automático.

### Autorização e ambiente necessários em uma rodada futura

O runner ainda não pode executar: esta etapa não autoriza hospedagem e não existem arquivo de aprovação, app ID/número do projeto confirmados nesta rodada, nem configuração de credencial dedicada confirmada. Antes de uma execução real, a autorização deve especificar projeto, hash do candidato, Release/Ruleset ativo esperado, operações de criação/limpeza de fixtures sintéticas e janela de validade.

Use uma identidade de serviço exclusiva de staging por impersonação, sem chave persistente. As permissões de leitura exigidas pelos preflights são `firebase.projects.get`, `firebaserules.releases.get`, `firebaserules.rulesets.get`, `firebaseauth.configs.get` e `firebaseappcheck.services.get`. A fase de fixtures precisa também de `firebaseauth.users.create`, `firebaseauth.users.update`, `firebaseauth.users.delete` e permissões de escrita necessárias em Firestore (`datastore.entities.create`, `get`, `update`, `delete`). **Essas permissões de dados são concedidas no escopo do projeto e não limitam a identidade a caminhos individuais do Firestore**; por isso use somente uma identidade temporária/dedicada no projeto isolado de staging e encerre/revogue a impersonação após a janela autorizada. Não conceda `firebaserules.releases.update`, permissões de criar/excluir Rulesets, `firebaseappcheck.services.update` ou `firebaseauth.configs.update` ao runner.

Auth, App Check e Rules são confirmados por consultas de leitura imediatamente antes dos testes. Se um dos estados não corresponder à aprovação, o runner interrompe antes de criar contas. App Check enforced não é contornado com token de debug: nesse caso a execução fica NO-GO até haver um método de teste aprovado e compatível com o app registrado.

### Ordem futura — cada alteração hospedada requer autorização própria

1. Executar os três preflights locais e preservar o backup original já verificado.
2. Fazer GET do Release `cloud.firestore` e confirmar projeto staging, `(default)`, Ruleset e `updateTime` esperados. Se mudou, parar e revisar.
3. Após autorização específica de publicação, publicar somente o hash aprovado em `macacu-staging-261022`, com `--project` explícito. Esta etapa não executou publicação.
4. Fazer GET do Release e Ruleset recém-publicados; conferir o novo Ruleset e o hash do conteúdo. Gerar então a aprovação temporária ligada ao Release/Ruleset/`updateTime` exatos.
5. Após autorização específica de criação e remoção de fixtures, executar `node tools/staging-rules-client-homologation.mjs --execute <approval.json>`. Conferir os resultados e exigir limpeza concluída.
6. Em falha de segurança, parar. Não fazer rollback automático; qualquer retorno exige autorização própria, nova leitura e conferência manual.

### Limite técnico do rollback

A REST API `projects.releases.patch` documenta atualização de `rulesetName`, mas o recurso Release não oferece `etag`/precondição compare-and-swap. Logo, um GET seguido de PATCH não consegue impedir tecnicamente que outro operador altere o Release entre as duas chamadas. **Para não sobrescrever uma mudança de terceiro, não existe rollback automatizado seguro com essa API.** O procedimento fica bloqueado se não puder haver janela exclusiva de alteração, com operadores congelando mudanças e conferindo imediatamente antes e depois; se houver qualquer divergência, não enviar PATCH. A ferramenta atual não executa rollback.

O runner usa Firebase client SDK 11.10.0 e Admin SDK 13.10.0 já presentes em `functions/node_modules`; nenhuma dependência foi instalada. As referências oficiais para leitura de Rules, Auth e App Check são [Firebase Rules REST](https://firebase.google.com/docs/reference/rules/rest), [Identity Toolkit projects.getConfig](https://cloud.google.com/identity-platform/docs/reference/rest/v2/projects/getConfig) e [App Check projects.services.get](https://firebase.google.com/docs/reference/appcheck/rest/v1/projects.services/get).

### Decisão STAGING 2.2

**GO para preparação local e para solicitar autorização específica depois de completar os requisitos de identidade/app. NO-GO para executar homologação hospedada agora.** O modo local e os testes de bloqueio estão disponíveis; o modo hospedado só aceita o candidato quando publicado e revalidado, credencial de impersonação dedicada, App Check/Auth confirmados, aprovação temporária válida e autorização de fixtures. A publicação permanece uma ação separada.

### Atualização STAGING 2.6 — leituras hospedadas após login

Consulta somente de leitura realizada em 2026-10-28, sempre com o ID explícito `macacu-staging-261022`. A primeira tentativa de obter token pelo harness local falhou porque o harness passou o objeto da conta à função que esperava o token de atualização; corrigido o harness em memória, sem alterar arquivos de credenciais. As consultas oficiais abaixo retornaram HTTP 200:

| Recurso | Evidência observada |
|---|---|
| Projeto | `macacu-staging-261022`, número `672692860147`, estado `ACTIVE` |
| Aplicativos | 1 Web (`Default Web App`); nenhum Android ou iOS registrado |
| Authentication | configuração acessível; login por e-mail/senha habilitado; nenhum provedor federado listado |
| App Check | serviço Firestore e Identity Toolkit ambos `UNENFORCED` |
| Release Firestore `(default)` | `projects/macacu-staging-261022/releases/cloud.firestore`; updateTime `2026-10-28T14:24:38.111069Z` |
| Ruleset ativo | `projects/macacu-staging-261022/rulesets/5c2d69e4-283a-444b-93f1-9e2204e095f5`; criado em `2026-10-28T14:24:35.703989Z` |

O Ruleset recuperado pela Rules REST API contém um arquivo de 163 bytes. Seu SHA-256 é `ecf30f940747dcc3c5ba4993093e9a11ac9fc5df7e14b2a1512d2446923d84eb`, igual ao backup bruto local. O snapshot anterior do Console tem SHA-256 `cd4b3030287ceb2ce9b3ad7cf3d10bb4399dbd8b09aae8c743ec282ffc4b1b70`, portanto não é byte a byte igual ao Ruleset da API. O candidato local `firestore.rules` continua com SHA-256 aprovado `ddc454413e66107a2087265c3bc9012f7343f90e67a491c353e64e49a75d13b8` e não corresponde ao Ruleset ativo. O Release permanece no Ruleset original deny-all. Nenhuma Rule, conta, configuração ou dado hospedado foi alterado.

Preflights locais reexecutados: `node tools/staging-rules-preflight.mjs` e `node tools/staging-rules-backup-preflight.mjs` passaram. Isso confirma a integridade do backup e do candidato, mas não autoriza publicação ou criação de fixtures. **Decisão: GO para encerrar a inspeção somente de leitura; NO-GO para homologação hospedada**, pois App Check não está enforced, o app Android/iOS ainda não está registrado, e publicação de Rules/criação de contas e documentos continuam fora da autorização desta rodada. Não habilitar App Check nem publicar Rules como parte desta atualização.

## STAGING 3.1 — identidades temporárias e IAM (29/10/2026)

Alterações realizadas somente no projeto Firebase `macacu-staging-261022` (`672692860147`), dentro da autorização desta etapa. Não houve publicação de Rules, criação de usuários/documentos, alteração de Auth/App Check, deploy, nem acesso a produção ou Supabase.

### Identidades criadas

- `[identidade redigida]`
- `[identidade redigida]`

Ambas estão habilitadas e têm **zero chaves gerenciadas pelo usuário**. A API `iamcredentials.googleapis.com` foi habilitada para permitir impersonação sem chave. Nenhum arquivo de credencial foi criado. `firebaseappcheck.googleapis.com` continua desabilitada; não foi habilitada nem alterada.

### Papéis temporários

Todos os vínculos temporários expiram em `2026-11-05T19:32:11Z`.

| Papel personalizado do projeto | Concedido a | Permissões incluídas | Observação |
|---|---|---|---|
| `stagingFirestoreRulesPublisher` | identidade de publicação | 5: `firebase.projects.get`, `firebaserules.releases.get`, `firebaserules.rulesets.get`, `firebaserules.rulesets.create`, `firebaserules.releases.update` | Sem exclusão de Rulesets/Releases nem alteração IAM. A API não fornece condição por Release para restringir a `(default)`; o papel pode afetar outros Releases Firebase deste projeto. |
| `stagingRulesHomologationApi` | identidade de homologação | 9: leitura de projeto, Rules, Auth config e App Check; criação, consulta, atualização e remoção de usuários Auth | Sem alteração de Auth config, App Check ou Rules. A consulta App Check não pôde ser validada porque a API correspondente segue desabilitada. |
| `stagingRulesHomologationFirestore` | identidade de homologação | 4: `datastore.entities.create/get/update/delete` | Vínculo condicionado ao banco `(default)` e à expiração. O IAM não permite limitar essas permissões por coleção aqui; o alcance inclui todas as coleções do banco. Nenhum documento foi criado ou lido nesta etapa. |
| `stagingServiceAccountTokenMinter` | operador atual, nos dois service accounts | somente `iam.serviceAccounts.getAccessToken` | Vínculo condicionado à mesma expiração. Sem `signBlob`, `signJwt`, delegação implícita ou criação de chaves. |

O papel `roles/owner` que já existia para o operador não foi modificado. Assim, embora as identidades de serviço tenham privilégios restritos, a conta humana atual continua tendo privilégios amplos no projeto; esta preparação não prova privilégio mínimo do operador.

### Evidência e limites da validação

- A impersonação de ambas as identidades foi confirmada usando tokens de curta duração mantidos somente em memória. `testIamPermissions` confirmou as cinco permissões esperadas da identidade de publicação e negou exclusão de Rules e alteração de IAM. Para a identidade de homologação, confirmou as permissões de leitura/API e operações Auth previstas e negou alteração de Auth config, App Check e IAM.
- O teste de permissões no recurso de projeto não representa a condição no recurso Firestore. Não foi possível comprovar por chamada de teste a efetividade do vínculo restrito a `(default)`; o Policy Troubleshooter continua desabilitado e não foi habilitado. A política foi lida de volta com a condição exata. Nenhuma escrita ou leitura de documento foi feita.
- O Release `cloud.firestore` continua apontando para `projects/macacu-staging-261022/rulesets/5c2d69e4-283a-444b-93f1-9e2204e095f5`, updateTime `2026-10-28T14:24:38.111069Z`. Não houve mudança no backup nem nas Rules.
- O runner reconhece a identidade de homologação nos testes locais (7/7 aprovados) e o preflight confirma os hashes do candidato e backup. Porém, a execução completa não está pronta: `gcloud` e o arquivo local padrão ADC de impersonação não existem, e o runner requer essa credencial ADC. Não foi criado arquivo a partir de token OAuth pessoal. O App Check REST API segue desabilitado, impedindo a leitura que o preflight hospedado exige.
- Não há mecanismo verificável de exclusividade de mudanças. Os papéis não bloqueiam operadores preexistentes com Owner/Firebase Admin. A REST API de Releases não oferece precondição compare-and-swap. Portanto, publicação temporária e rollback continuam **NO-GO** até haver janela exclusiva confirmada e procedimento contra concorrência que não dependa apenas de um GET seguido de PATCH.

### Revogação após a janela

Até `2026-11-05T19:32:11Z`, os vínculos expiram automaticamente por condição, mas os service accounts e papéis personalizados permanecem criados. Depois dos testes autorizados — ou imediatamente se a homologação for cancelada — remover os vínculos `stagingFirestoreRulesPublisher`, `stagingRulesHomologationApi`, `stagingRulesHomologationFirestore` e os vínculos `stagingServiceAccountTokenMinter`; confirmar ausência de dependências; desabilitar e excluir somente os dois service accounts; então excluir os quatro papéis personalizados. Desabilitar `iamcredentials.googleapis.com` somente após verificar que nenhum outro uso do projeto depende dela. Não remover nem alterar recursos de terceiros.

### Decisão

**IAM preparado parcialmente; homologação hospedada e publicação/rollback: NO-GO.** Identidades dedicadas existem, a impersonação funciona e não há chaves persistentes. Permanecem bloqueios verificáveis: falta um mecanismo de janela exclusiva; permissão condicional de Firestore não foi testada em recurso de banco; API de leitura App Check desabilitada; e o runner ainda não possui bootstrap ADC de impersonação disponível nesta máquina. Nenhuma aprovação formal de Rules foi criada ou simulada.

## STAGING 3.2 — impersonação em memória e verificação somente leitura (29/10/2026)

Esta atualização substitui o requisito anterior de um arquivo ADC persistente. O runner agora usa a biblioteca de autenticação da Firebase CLI 15.32.1 já presente no cache para obter o OAuth atual em memória e chama a IAM Credentials API oficial para impersonar `[identidade redigida]`. Não depende de `gcloud`, não lê ADC, não grava credenciais/tokens e recusa `GOOGLE_APPLICATION_CREDENTIALS`, `FIREBASE_TOKEN`, endpoints de Emulator, proxies e overrides de TLS. A versão diferente da CLI falha fechada.

O fluxo verifica no IAM que o usuário da sessão Firebase CLI atual tem o papel temporário `stagingServiceAccountTokenMinter` no service account, com a condição exata que expira em `2026-11-05T19:32:11Z`. A cada renovação valida novamente essa concessão e só solicita um token OAuth de 10 minutos para a identidade fixa de homologação. Todas as leituras do projeto são feitas com esse token dedicado; o OAuth pessoal é usado apenas em memória para consultar a concessão e solicitar a impersonação. O runner compara a matriz permitida e negada para detectar, entre outras permissões, se acidentalmente recebeu um token Owner.

Modo somente leitura:

```powershell
$env:STAGING_HOMOLOGATION_PROJECT_ID = 'macacu-staging-261022'
$env:STAGING_HOMOLOGATION_CONFIRM = 'macacu-staging-261022'
node tools/staging-rules-client-homologation.mjs --identity-check
Remove-Item Env:STAGING_HOMOLOGATION_PROJECT_ID, Env:STAGING_HOMOLOGATION_CONFIRM -ErrorAction SilentlyContinue
```

Esse modo só lê política IAM, testa permissões, consulta Project/Auth config/Release/Ruleset e verifica o hash do backup. Não cria contas ou documentos, não publica Rules e não toca em App Check. A operação de Rules continua fora deste modo.

### Evidência hospedada desta execução

O comando acima concluiu em `2026-10-29` com `hostedWrites: false`:

- Identidade observada: `[identidade redigida]`; projeto `macacu-staging-261022`, número `672692860147`.
- O vínculo de impersonação foi conferido ao vivo e continua limitado a `2026-11-05T19:32:11Z`. Token curto expirou às `2026-10-29T19:57:57Z`; nenhum token foi impresso ou persistido.
- A identidade acessou Project, configuração Auth, Release e Ruleset com sucesso. Login por e-mail/senha continua habilitado.
- Release segue no Ruleset original `5c2d69e4-283a-444b-93f1-9e2204e095f5`; SHA-256 remoto e backup local coincidem em `ecf30f940747dcc3c5ba4993093e9a11ac9fc5df7e14b2a1512d2446923d84eb`. O candidato local mantém o hash aprovado `ddc454413e66107a2087265c3bc9012f7343f90e67a491c353e64e49a75d13b8`.
- `testIamPermissions` concedeu exatamente as permissões de consulta/Auth e negou alteração de Auth config, App Check, Rules, IAM e operações Firestore no nível do projeto. A negação Firestore no recurso de projeto **não comprova** o vínculo condicional no recurso banco; não houve acesso a documentos nem tentativa de escrita.
- Não há `gcloud` nem ADC persistente local; já não são necessários para o modo de identidade. A API App Check continua desabilitada, portanto a checagem hospedada completa do runner de fixtures ainda deve parar antes de qualquer escrita.

### Janela exclusiva, Release e condição Firestore

Não há lock técnico que impeça Owners ou operadores preexistentes de alterar Rules simultaneamente. A API Firebase Rules não oferece precondição compare-and-swap para atualizar o Release. Antes de eventual publicação/rollback, uma janela exclusiva precisa ser coordenada externamente: responsável nomeado mantém o congelamento de alterações, todos os operadores confirmam pausa, o Release/Ruleset/updateTime é lido imediatamente antes e depois de cada mudança, e qualquer divergência interrompe o procedimento. Esse controle operacional reduz risco, mas **não elimina atomicamente a corrida entre GET e PATCH**; se a ausência de concorrência não puder ser garantida, não publicar nem fazer rollback.

Após autorização específica que permita uma fixture sintética, a condição IAM de Firestore deve ser testada por uma única operação CRUD em documento de ID aleatório, usando o token impersonado e a identidade restrita, no banco `(default)`, seguida de remoção verificada. Isso prova somente o caminho positivo no banco autorizado e não prova restrição por coleção; o papel abrange todas as coleções de `(default)`. Para uma prova negativa de escopo, usar IAM Policy Troubleshooter quando sua API estiver habilitada e autorizada, ou um banco alternativo já existente e aprovado. Não habilitar APIs, criar banco ou escrever fixtures nesta execução. Esse teste de IAM é separado dos testes SDK cliente que verificam Firestore Rules.

### Decisão STAGING 3.2

**GO para autenticação do runner em modo de leitura; NO-GO para homologação com fixtures, publicação e rollback.** A identidade dedicada e sua matriz de permissões foram comprovadas sem ADC persistente. Ainda são requisitos: autorização própria para criar/remover fixtures, leitura App Check (API atualmente desabilitada), prova autorizada do vínculo IAM no banco e janela exclusiva. Nenhum usuário ou documento foi criado e o Release permaneceu intacto.

### Resultado atualizado do runner 3.2 (29/10/2026)

O modo `--identity-check` foi executado novamente após a implementação. Resultado: sucesso, sem escritas hospedadas. Usou a conta dedicada de homologação e confirmou Project `macacu-staging-261022`/`672692860147`, email/senha habilitado, Release original intacto e hash original igual ao backup. O token temporário expirava às `2026-10-29T19:58:58Z`; a concessão e o token nunca foram impressos em forma secreta nem salvos. A matriz também negou criação de service accounts/chaves, `getAccessToken`, `signBlob`, `signJwt`, mudança de IAM/Auth/App Check/Rules e operações Firestore no escopo do projeto.

As verificações locais atuais passaram: `node --check tools/staging-rules-client-homologation.mjs`, 11/11 testes do runner, `--preflight` e `staging-rules-backup-preflight.mjs`. O `git diff --check` não reportou erro. A contagem de entradas no estado local permaneceu 127; os arquivos do runner e este documento já eram não rastreados no estado inicial e continuam preservados.

O modo autenticado só consulta o Release original; a validade do grant é lida do IAM em cada emissão/renovação e também limitada pelo prazo fixo no runner. O modo `--execute` continua exigindo aprovação externa de até duas horas e validações hospedadas completas antes de qualquer fixture. Ele não foi chamado.

### Nota de segurança sobre a primeira implementação

A primeira versão chamou `firebase-tools` `getAccessToken()`. A inspeção do código da CLI mostrou que esse método grava o token renovado no cache global da sessão. Isso ocorreu durante a validação inicial; o arquivo de sessão Firebase local teve sua data de modificação atualizada. Nenhum token foi mostrado, copiado para o repositório ou registrado em relatório, mas a renovação foi persistida no cache global — ao contrário da restrição pretendida. Não reverti o arquivo para cópias antigas do cache, pois isso poderia desfazer um login posterior ou invalidar a sessão. A versão final substitui essa chamada por troca OAuth HTTPS diretamente em memória; uma verificação antes/depois confirmou que a data de modificação do cache permaneceu igual. A limitação/ocorrência fica registrada para transparência.

Na repetição final após ampliar os checks IAM, o runner confirmou que os três vínculos de papéis do projeto ainda correspondem exatamente às duas contas técnicas e às condições originais de expiração/banco. Leu os metadados de ambas as contas e confirmou que estão habilitadas e sem chaves gerenciadas. A checagem de permissões efetivas da conta de homologação passou, incluindo negações de assinatura/chaves, alteração de IAM, Rules, Auth e App Check. O Release/hash e o Auth foram novamente lidos sob o token impersonado; a sessão OAuth local não foi modificada por essa execução final.

## STAGING 3.3 — prova efetiva IAM no Firestore (29/10/2026)

Executada a autorização limitada para exatamente um documento sintético no staging. O runner primeiro confirmou IAM temporário, service accounts habilitadas/sem chaves, Project `macacu-staging-261022` (`672692860147`), Ruleset original ativo e backup íntegro. A conta Owner não foi usada nas operações de documentos: somente o token temporário de `[identidade redigida]` foi enviado ao Firestore REST API.

Resultado da operação:

- Caminho exclusivo criado: `staging_iam_permission_checks/run-02397cca-39c3-4187-8b68-9c71dccb9147`.
- O GET inicial confirmou ausência; create foi aceito; leitura posterior correspondeu exatamente aos campos sintéticos e fingerprint esperados; delete foi aceito; GET final retornou ausência.
- `hostedDocumentsCreated: 1`; `hostedDocumentsRemaining: 0`; `deleteConfirmed: true`.
- O Release continuou no Ruleset original `5c2d69e4-283a-444b-93f1-9e2204e095f5`, com SHA-256 `ecf30f940747dcc3c5ba4993093e9a11ac9fc5df7e14b2a1512d2446923d84eb`, igual ao backup.
- As permissões `datastore.entities.create/get/delete` funcionaram no banco `(default)` sob a condição IAM configurada. Update não foi executado, pois a autorização permitia somente criar, ler e remover um documento.
- `testIamPermissions` no recurso de projeto negou os privilégios de alteração de Rules, Auth, App Check, IAM, chaves/impersonação e permissões Firestore avaliadas nesse escopo. Isso não é prova negativa para outro banco; não foi criado nem consultado outro banco.
- Nenhum usuário foi criado. Nenhuma Rule, Auth, App Check ou configuração IAM foi alterada. O cache global OAuth não mudou durante o comando.

**Limite importante:** Firestore REST com credencial de service account valida IAM e pode ignorar Firestore Security Rules. Portanto, este teste prova acesso IAM de serviço ao `(default)` e limpeza, mas não prova as Rules nem uma restrição por coleção. Não autoriza homologação de Rules nem libera o Beta.

Comando reprodutível, limitado a uma fixture, após preflight:

```powershell
$env:STAGING_HOMOLOGATION_PROJECT_ID = 'macacu-staging-261022'
$env:STAGING_HOMOLOGATION_CONFIRM = 'macacu-staging-261022'
node tools/staging-rules-client-homologation.mjs --firestore-iam-check
Remove-Item Env:STAGING_HOMOLOGATION_PROJECT_ID, Env:STAGING_HOMOLOGATION_CONFIRM -ErrorAction SilentlyContinue
```

### Decisão STAGING 3.3

**GO para a prova IAM CRUD autorizada no `(default)`; NO-GO para publicação/rollback de Rules ou homologação completa.** A única fixture foi apagada e a ausência foi confirmada. Permanecem o bloqueio de janela exclusiva sem CAS e a falta de leitura App Check; Rules e autorização de usuários ainda exigem seus testes separados com SDK cliente.

## STAGING 3.4 — prova IAM de atualização e inventário de publicação (29/10/2026)

### Prova de documento sintético

O preflight confirmou o projeto `macacu-staging-261022` (`672692860147`), banco `(default)`, candidato SHA-256 `ddc454413e66107a2087265c3bc9012f7343f90e67a491c353e64e49a75d13b8` e backup SHA-256 `ecf30f940747dcc3c5ba4993093e9a11ac9fc5df7e14b2a1512d2446923d84eb`. Os testes offline do runner passaram (15/15). Foi executada uma única transação lógica de fixture sintética, sob `[identidade redigida]`:

- Caminho: `staging_iam_permission_checks/run-ec2703fe-90a4-4cfb-9fb0-0a0e22be3e4d`.
- A ausência foi verificada antes da criação; criação e leitura passaram; atualização do marcador/revisão e nova leitura passaram; remoção e GET final 404 foram confirmados (`hostedDocumentsRemaining: 0`).
- O Release foi lido antes e depois e permaneceu em `projects/macacu-staging-261022/rulesets/5c2d69e4-283a-444b-93f1-9e2204e095f5`, com hash igual ao backup. Nenhuma Rule foi publicada/alterada.
- A concessão temporária foi verificada até `2026-11-05T19:32:11Z`; o cache global da Firebase CLI manteve a mesma data de modificação antes/depois.
- Essa prova confirma IAM de servidor, não Firestore Rules de cliente; chamadas REST com credencial de servidor podem ignorar Rules.

### Inventário de quem pode publicar

Consulta somente leitura da política IAM do projeto, definições de papéis e políticas das contas de serviço concluiu. O runner detecta qualquer uma das permissões de criar Rulesets ou criar/atualizar/excluir Releases. Foram encontrados:

- O operador da sessão Firebase CLI tem `roles/owner`, sem condição temporal; pode publicar diretamente e alterar a política IAM.
- `[identidade redigida]` tem o papel personalizado de publicação com condição até 05/11/2026 19:32:11 UTC. O operador atual também pode impersoná-la até esse prazo.
- O agente de serviço Firebase `[identidade redigida]` tem papel sem expiração que inclui publicação de Rules e alteração de IAM.
- `[identidade redigida]` também tem permissões de publicação sem expiração; além disso, o papel `roles/iam.serviceAccountTokenCreator` do projeto permite impersonação em escopo amplo. O serviço técnico pode portanto ser uma via de publicação, embora nenhuma automação de Rules associada tenha sido encontrada na configuração local.
- Não foram encontrados workflows locais de Codemagic/GitHub para publicar Firestore Rules; `codemagic.yaml` contém builds/testes do app, sem deploy de Rules. Isso não exclui automações externas ao repositório.

A leitura cobre políticas diretas do projeto e das contas de serviço listadas. Não expande papéis herdados de pasta/organização nem membros de grupos; logo, não é inventário organizacional total. As definições dos papéis de serviço Firebase foram conferidas também no catálogo oficial IAM, pois a API IAM não retornou esses dois papéis gerenciados ao chamador. Nenhum IAM foi alterado.

### Janela exclusiva e decisão

Procedimento operacional necessário para uma futura janela, em UTC:

1. Responsável: titular da conta `[identidade redigida]`; nomear também um observador. Preencher hora UTC de início e fim, com duração máxima de 30 minutos.
2. Antes do início, o responsável suspende Console/CLI e automações externas que publiquem Firestore Rules; Codemagic/GitHub locais já foram verificados. Todos os demais operadores com `Owner`, Firebase Rules/Admin/Editor, e responsáveis pelos service accounts identificados confirmam a pausa por canal operacional.
3. No início, conferir projeto, banco, Release, `rulesetName` e `updateTime`; abortar se não coincidirem com o snapshot autorizado. Publicação exige autorização própria e janela confirmada.
4. Após a propagação, consultar novamente o Release e validar o Ruleset efetivamente ativo. Ao final, antes de eventual rollback, repetir a leitura e prosseguir somente se o Release ainda for exatamente o criado pela execução e não houver alteração concorrente.
5. Se qualquer identidade não confirmar a suspensão, houver atividade automática não pausável, ou o Release mudar, parar e não publicar nem sobrescrever. Preservar recursos para revisão do responsável.

O runner consegue detectar mudanças entre leituras sequenciais, mas Firestore Rules REST não oferece compare-and-swap no Release; um lock local não impede Console, automação externa nem agentes de serviço. Como existem papéis de publicação sem condição para service agents e operador Owner, a exclusividade não é tecnicamente garantida só pelo runner. **Veredito: GO para prova IAM CRUD; NO-GO para publicação/rollback de Rules e para homologação de Rules.** A alternativa segura é manter o deny-all e executar futuras Rules em outro projeto Firebase isolado sem esses operadores/integrações, ou obter uma janela externa coordenada e verificável, reconhecendo que a corrida entre conferência e publicação permanece possível sem CAS.

Preflight final: `node --check tools/staging-rules-client-homologation.mjs`, 15/15 testes do runner, preflight local, integridade do backup e `git diff --check` aprovados. Estado Git preservado; sem staged, commit ou push.

## STAGING 3.5 — atividade de publicação e risco de concorrência (29/10/2026)

### Auditoria hospedada somente leitura

O runner consultou `entries:list` no Cloud Logging, exclusivamente em `macacu-staging-261022`, para atividade `firebaserules.googleapis.com` nos 90 dias anteriores à consulta (2026-07-31 a 2026-10-29). Foram retornadas duas chamadas de publicação, ambas por `[identidade redigida]`, sem cadeia de impersonação registrada:

- `CreateRuleset` para `projects/macacu-staging-261022/rulesets/5c2d69e4-283a-444b-93f1-9e2204e095f5`, em `2026-10-28T14:24:35.500620Z`.
- `CreateRelease` para `projects/macacu-staging-261022/releases/cloud.firestore`, em `2026-10-28T14:24:37.870774Z`.

O user-agent não veio preenchido nesses eventos; a ferramenta de origem não pode ser distinguida. Isso comprova atividade registrada nessa janela, mas não prova que outras identidades nunca publicaram fora do período ou em eventos não retidos. A leitura final confirmou o Release `cloud.firestore` ainda no Ruleset original `5c2d69e4-283a-444b-93f1-9e2204e095f5`, com `updateTime` `2026-10-28T14:24:38.111069Z`.

### Capacidade, herança e automações

O inventário IAM direto do projeto e as políticas das contas de serviço foram consultados novamente. Permissões diretas capazes de publicar foram encontradas para o Owner `[identidade redigida]`, os agentes `[identidade redigida]` e `[identidade redigida]`, e o publicador temporário `[identidade redigida]` (este último condicionado até `2026-11-05T19:32:11Z`). Esses dados são **capacidade**, não evidência de que cada identidade tenha publicado. A única atividade de publicação observada na janela foi da conta Owner acima.

No IAM direto do projeto não havia membros `group:`. A tentativa de consultar a política efetiva só para o recurso do projeto pelo Cloud Asset Policy Analyzer retornou HTTP 404; a consulta de Service Usage confirmou `cloudasset.googleapis.com` como `DISABLED`. Nenhuma API foi habilitada. Portanto, políticas herdadas de pasta/organização e membros de grupos herdados permanecem **não verificados**. O inventário direto encontrou nenhum grupo, mas isso não permite concluir que não existam grupos herdados.

O repositório local não contém comandos/workflows de publicação de Rules em seus arquivos YAML/JSON; `codemagic.yaml` é de build/teste do aplicativo. Não foi possível consultar automações externas ao repositório, então sua ausência não está comprovada. Os dois logs de atividade não identificam automação: user-agent desconhecido e ator igual ao Owner.

### Comportamento do runner e janela de operação

O runner não contém endpoint `PATCH` do Release nem rotina de publicação ou rollback de Rules. Ele só faz leituras do Release. A execução hospedada compara nome, Ruleset e timestamps antes dos fixtures, e agora repete a comparação ao final. Se detectar mudança persistente durante o conjunto de testes, termina com erro após limpar somente fixtures próprias e declara que não tentou rollback. Isso detecta divergência entre checkpoints; não detecta alteração que seja feita e revertida entre as leituras e não constitui lock.

Se futuramente uma homologação em projeto compartilhado for autorizada, usar uma janela de no máximo 15 minutos em UTC, com coordenador e observador nomeados. O coordenador registra início/fim, pausa as pipelines conhecidas e obtém confirmação explícita de todos os operadores humanos e responsáveis por automações. Antes e depois de cada operação mutável autorizada, consulta o Release e registra `rulesetName`/`updateTime`; monitora o Release entre chamadas. Qualquer nova identidade, evento de publicação, diferença de timestamp, falha de leitura ou falta de confirmação encerra a janela. Não reverter automaticamente. Após divergência, preservar o estado observado e convocar os responsáveis; uma reversão manual exige autorização própria e nova avaliação.

Mesmo com coordenação, Owners e service agents continuam capazes de publicar, e a API não fornece compare-and-swap no Release. Uma pausa confirmada reduz a probabilidade de concorrência, mas não remove a corrida entre leitura e alteração. Não há garantia técnica de exclusividade neste projeto.

### Decisão STAGING 3.5

**NO-GO para publicar Rules neste staging compartilhado.** O histórico recente aponta para um único operador, mas o Owner e service agents mantêm capacidade, a herança/group expansion não pôde ser verificada porque Cloud Asset está desabilitado, e não há condição atômica de Release. Não alterar IAM nem habilitar APIs para contornar isso.

Alternativa de menor risco: solicitar autorização separada para criar um projeto Firebase descartável de homologação, sem dados de usuários, e antes de usá-lo confirmar que a política efetiva não herda grupos/operadores de publicação indesejados. Separar os operadores e integrações do staging atual e usar apenas contas e fixtures sintéticas. O novo projeto não validaria automaticamente que a publicação no staging compartilhado é segura; apenas permitiria testar o candidato em um ambiente hospedado descartável. Não foi criado projeto nesta etapa.

Validação local desta etapa: `node --check tools/staging-rules-client-homologation.mjs`; testes unitários do runner 19/19; `--preflight` e verificador do backup aprovados; `git diff --check` sem erros. Estado Git permaneceu com 127 entradas locais e zero staged. Nenhuma Rule, IAM, conta, fixture hospedada ou recurso de nuvem foi alterado.
