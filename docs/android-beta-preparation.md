# Preparação do Beta Android

## Isolamento local

- Flavor: `beta`, pacote `br.com.tudoaquimacacu.tudo_aqui_macacu.beta`.
- O flavor nunca consome o `google-services.json` da raiz. Para um teste conectado, usa somente `android/app/src/beta/google-services.json`.
- Quando a configuração Beta estiver ausente, a tarefa Google Services do flavor é desativada e o app bloqueia a inicialização antes do Firebase. Não há fallback para produção.
- Quando o arquivo existir, Gradle exige um ID dedicado de Beta (`macacu-beta-YYMMDD-<6 hex>` ou os formatos isolados terminados em `-beta`/`-testing`), que o project ID coincida, que exista o pacote Android Beta e um cliente OAuth web válido.
- Antes de inicializar o Firebase, o app confere project ID nativo, app ID Firebase, sender ID e OAuth web client ID. Depois da inicialização, confere novamente a identidade efetiva do Firebase.
- Projeto aceito pelo gate: Firebase isolado com o padrão dedicado de Beta ou sufixo `-beta`/`-testing`; produção, staging compartilhado e `demo-universal-search` são recusados.
- A configuração incompleta abre a tela de bloqueio do Beta antes de inicializar Firebase. Não há fallback para produção.
- O writer híbrido Supabase permanece desabilitado nesse flavor.

## Configuração necessária para um teste hospedado autorizado

Antes de compilar uma versão conectada, registrar no projeto Firebase isolado um app Android com o pacote Beta e configurar o provedor Google do Authentication. Obter o `google-services.json` desse app e guardá-lo localmente em `android/app/src/beta/google-services.json` (o arquivo deve permanecer fora do Git). Configurar o build explicitamente:

- `BETA_FIREBASE_ENABLED=true`
- `BETA_APP_CHECK_ENABLED=true`
- `BETA_FIREBASE_PROJECT_ID`
- O mesmo `BETA_FIREBASE_PROJECT_ID` como propriedade Gradle (`-PBETA_FIREBASE_PROJECT_ID=...`) e dart define (`--dart-define=BETA_FIREBASE_PROJECT_ID=...`).

As opções Firebase e o cliente OAuth web são lidos do arquivo próprio do flavor; não os passe como defines independentes, pois isso permitiria misturar configurações de projetos diferentes. O cliente OAuth de produção é recusado. O build Beta release continua bloqueado; este preparo não autoriza distribuição.

Exemplo de compilação local conectada (somente depois de existir o projeto Beta aprovado e o arquivo local): defina o ID no ambiente do processo Gradle e passe o mesmo valor como define Flutter. Substitua o nome de exemplo pelo ID realmente aprovado:

```powershell
$env:BETA_FIREBASE_PROJECT_ID = 'macacu-beta-261030-cf4a81'
try {
  flutter build apk --debug --flavor beta --no-pub `
    --dart-define=BETA_FIREBASE_ENABLED=true `
    --dart-define=BETA_APP_CHECK_ENABLED=true `
    --dart-define=BETA_FIREBASE_PROJECT_ID=macacu-beta-261030-cf4a81
} finally {
  Remove-Item Env:BETA_FIREBASE_PROJECT_ID -ErrorAction SilentlyContinue
}
```

O ID neste exemplo é o projeto Beta criado nesta etapa. Se o arquivo ou qualquer identidade não corresponder, o build ou a abertura do app falha sem tentar outro projeto.

O App Check do Beta usa somente **Play Integrity**; não aceita o provedor debug. A chamada ao provider só ocorre depois da identidade Firebase e do Google OAuth passarem no gate. Para validar o fluxo real, registrar o app Android e o certificado de distribuição no Firebase/App Check e instalar por uma faixa de teste compatível com Play Integrity. O APK debug local não comprova App Check hospedado.

## Certificados locais conhecidos

O APK `betaDebug` usa a assinatura Android debug local, não uma identidade de distribuição:

- SHA-1: `6C:68:0E:2D:B9:CE:DF:F4:34:16:62:76:7A:0E:D8:7F:2A:19:9A:AA`
- SHA-256: `A3:08:E1:73:33:32:9A:E3:1F:6C:38:25:3F:62:35:4D:9A:E2:5B:97:74:12:26:AA:5C:EF:83:09:B1:CB:6C:56`

Esses fingerprints são apenas para diagnóstico local. Não autorizam cadastrar OAuth, App Check ou alterar qualquer projeto hospedado. A assinatura da Beta distribuída terá de ser identificada e validada separadamente; o build release Beta continua bloqueado.

## Estado da preparação hospedada — 30/10/2026

- Projeto Beta criado sem associação de faturamento: `macacu-beta-261030-cf4a81` (número `194904519821`). O Console confirma o plano Spark, sem custo mensal.
- App Android registrado: `br.com.tudoaquimacacu.tudo_aqui_macacu.beta` (`1:194904519821:android:ed055b73b6fb72b3a31ec4`). Foram adicionados somente os SHA-1/SHA-256 do certificado debug local acima; não existe certificado release cadastrado.
- `android/app/src/beta/google-services.json` foi obtido novamente após ativar Google Authentication e está ignorado pelo Git. O arquivo foi conferido localmente sem revelar valores: ID/projeto, número e pacote correspondem ao Beta, há um cliente OAuth web e não há cliente OAuth de produção.
- Authentication: e-mail/senha e Google estão ativados no projeto Beta. O nome público do app foi definido como “Tudo Aqui Macacu Beta”; o e-mail de suporte público foi escolhido com autorização do responsável. O Console criou o cliente OAuth web e a configuração Beta foi atualizada.
- Builds `betaDebug` isolado e conectado foram aprovados. O conectado utilizou explicitamente o ID do projeto Beta e o arquivo Firebase exclusivo do flavor; não há fallback para produção.
- App Check: o app Beta já aparece no App Check, mas ainda está “Não registrado”. A tela de registro do Play Integrity exige aceitação dos Termos de Serviço das APIs Google e da Play Integrity. Essa aceitação não foi feita pelo agente. O provedor não foi registrado e o enforcement permanece desligado. A assinatura registrada no Firebase é apenas a debug local; a assinatura de distribuição e a configuração no Play Console ainda precisam ser verificadas.
- A configuração gerada pelo Gradle para `betaDebug` foi comparada ao `google-services.json`: projeto, número, Firebase App ID, pacote e cliente OAuth web correspondem.
- **Correção 30/10/2026:** o bloqueio do APK foi identificado como divergência falsa de projeto. O Android lia `applicationInfo.metaData` antes de pedir ao `PackageManager` que carregasse os metadados (`GET_META_DATA`); por isso, o ID nativo vinha ausente e a comparação fail-closed rejeitava a configuração antes do Firebase. `MainActivity` agora busca os metadados explicitamente, preservando a comparação entre o ID compilado e o ID nativo. O AVD isolado confirmou correspondência de projeto, pacote, Firebase App ID, sender ID e OAuth Web Client ID.
- A inicialização passou no mesmo AVD: ambiente, identidade nativa, configuração, Firebase, identidade Firebase, preparação do App Check, autenticação inicial e autorização administrativa terminaram com `result=ok`. A Home abriu. O carregamento de anúncios mostrou estado de erro/retry porque esse conteúdo não estava disponível no Beta; isso não impediu o restante da inicialização.
- Cadastro por e-mail/senha pelo APK, sessão autenticada após reinício do processo e logout confirmado foram exercitados. A conta sintética foi removida do Authentication; a lista do Console ficou vazia. A leitura do perfil no Firestore foi negada pelas Rules atuais, e a rotina de sincronização interrompe a gravação quando a leitura falha; não houve documento de perfil confirmado. **Um login explícito após sair não foi validado nesta execução.**
- Google Login no dispositivo não foi testado: não há conta Google dedicada de teste autorizada. Nenhuma conta pessoal foi usada.
- O primeiro ID candidato estava ocupado e não foi alterado. O ID final acima foi aceito pela criação oficial; o gate local foi ampliado somente para aceitar o padrão explícito `macacu-beta-YYMMDD-<6 hex>` além dos formatos `-beta`/`-testing`.

App Check: o Console continua mostrando o app como “Não registrado”. A ativação local do provider Play Integrity terminou sem erro, mas o APK não obteve um token forçado; isso **não comprova atestação**. Na tela APIs, Authentication aparece como “Não aplicado” (enforcement desligado). O Console não apresenta um estado explícito para Cloud Firestore enquanto o app não está registrado; portanto, o enforcement de Firestore não pôde ser confirmado apenas por essa tela. Nenhuma configuração foi alterada.

**Estado após a validação 3.3:** a causa de startup foi corrigida e o app iniciou no AVD. Cadastro, restauração da sessão após reinício do processo e logout foram observados com uma conta sintética removida ao final. Login explícito após logout, token/atestado real Play Integrity e enforcement de Firestore continuam sem comprovação. O Console exige registro do app com Play Integrity e certificado SHA-256; os requisitos incluem vincular o projeto no Play Console e registrar o app/certificado no Firebase ([documentação oficial](https://firebase.google.com/docs/app-check/android/play-integrity-provider)). Isso exige configuração pelo titular no Play Console; não aceitei termos nem registrei o app. O enforcement de Authentication está desligado; o status do Firestore permanece inconclusivo na interface atual. O app não usa provedor debug e nenhuma chave/token de depuração foi criado.

## Pré-Beta Android 3.4 — autenticação e conteúdo público

- O APK conectado foi conferido como flavor Beta, com o projeto `macacu-beta-261030-cf4a81`; o gate recusa operações de escrita e qualquer identidade diferente. A rota de leitura pública do Beta foi adicionada ao `SecureBackend` apenas para `listPublicContent` e `getPublicContentDetail`, depois de validar flavor, identidade exata, inicialização e ausência de Local Search/homologação. Não existe fallback para Firestore ou produção.
- No AVD isolado, cadastro sintético, logout, login explícito válido, rejeição de senha incorreta, restauração após encerramento/reabertura do processo e logout final para visitante foram observados. A conta foi removida pela API de Authentication do projeto Beta, e a lista do Console confirmou zero usuários. Os valores de teste foram mantidos em memória e descartados; nenhum perfil Firestore foi criado.
- Após a correção de roteamento, a chamada real ao callable retornou `not-found` para `listPublicContent`. O Console do Firebase informa que Cloud Functions exige upgrade do plano; o projeto continua Spark. Portanto, não existe backend callable implantado disponível no Beta.
- Cloud Firestore `(default)` ainda não existe: a página do Console oferece “Criar banco de dados” e a CLI recebeu 403 informando que a API do Firestore não está habilitada. Não há Ruleset/Release ativo nem dados públicos para consultar. Nenhuma API foi habilitada e nenhum banco, Rules ou função foi criado.
- App Check: o app Android continua “Não registrado” (Play Integrity não configurado). Authentication mostra “Não aplicado”. A linha de Firestore não fornece estado de enforcement sem o registro do app e o banco não existe; esse status permanece indeterminado, não deve ser tratado como desligado. Functions mostra orientação de uso e não há callable hospedado para inspecionar; no código local, `listPublicContent` e `getPublicContentDetail` exigem App Check, mas isso não comprova configuração hospedada.
- Diagnóstico de desenvolvimento: falhas do callable Beta agora registram apenas operação e código, sem mensagem, argumentos, identificadores, tokens ou dados do usuário.
- Verificação local: os testes direcionados de gates Beta, configuração, busca pública e detalhes passaram (24 aprovados, 6 ignorados por condição `LOCAL_SEARCH`); `flutter analyze --no-pub` sem problemas; build `betaDebug` concluído e instalado no AVD; `git diff --check` executado nesta etapa.

**Decisão de conteúdo Beta: NO-GO para estabelecimentos/anúncios reais.** Para disponibilizá-los, o responsável precisa escolher e configurar um plano compatível com Cloud Functions, provisionar o Firestore `(default)` com Rules e dados públicos aprovados, implantar os callables existentes e registrar Play Integrity no App Check. Nada disso foi feito nesta etapa. O login por e-mail/senha funciona no Beta; Google Login real e atestação Play Integrity continuam pendentes.

## Pré-Beta Android 3.5 — pacote mínimo do backend (30/10/2026)

### Superfície e dependências

- O catálogo do app usa somente `listPublicContent` e `getPublicContentDetail`, em `southamerica-east1`. O preflight bloqueia qualquer destino que não seja `macacu-beta-261030-cf4a81`, verifica hashes e gera apenas uma sugestão de comando; não chama Firebase CLI, rede ou deploy.
- As duas Functions V2 usam Node.js 22, `firebase-admin` e `firebase-functions`; executam com 256 MiB, timeout de 15 s, concorrência 4 e máximo de 2 instâncias. Ambas exigem Firebase Auth **e** App Check (`enforceAppCheck: true`), revalidam estado/expiração na origem e retornam projeções por allowlist. Listagem aceita coleções da allowlist pública do código, páginas de até 40 documentos e limita a varredura a 80; detalhes aceitam IDs exatos de documentos. A lista disponível é intencionalmente uma capacidade do backend e não uma aprovação para carregar todos os domínios com dados reais.
- Não há outro callable essencial para a leitura do catálogo. Escrita administrativa, favoritos/agenda, upload, push, jobs administrativos e gatilhos de indexação não fazem parte deste pacote e não devem ser incluídos no deploy mínimo.
- A conta visitante do app hoje não obtém sessão anônima; os callables recusam chamadas sem `request.auth.uid`. Para navegação pública sem login será necessário habilitar Auth anônimo no Beta e implementar/validar a sessão anônima, ou aprovar outra estratégia de autenticação equivalente. A validação local com usuário anônimo do Auth Emulator não comprova essa configuração hospedada.
- A origem precisa ser o Firestore `(default)`, Standard, na região selecionada pelo responsável. Os callables usam Admin SDK; por isso, as Firestore Rules não os autorizam. Para o primeiro teste isolado, o banco deve permanecer em modo bloqueado para clientes (deny-all). **Não publicar `firestore.rules` como parte deste pacote:** a regra candidata permite `get` público de alguns documentos visíveis e Firestore Rules não filtram campos de um documento. As leituras do app devem passar pela projeção do callable. Antes de abrir acesso direto a qualquer coleção, revisar separação física e privacidade dos documentos.

### Índices e fixtures

- Os queries de listagem combinam filtro de igualdade (`published == true`, ou `active == true` para `utilities`) com `orderBy(documentId)`, cursor e limite. Eles usam índices de campo único automáticos do Firestore; não há índice composto adicional exigido por esses dois callables. `firestore.indexes.json` contém índices de outras funcionalidades; não publicar esse arquivo para validar somente o catálogo. A disponibilidade de índices automáticos e de qualquer consulta futura ainda precisa ser observada no banco hospedado.
- Após uma autorização própria para canário, preparar somente documentos fictícios em coleções necessárias ao teste: um registro público por coleção, e variações não publicado/inativo/tombstone/expirado para conferir exclusão. Para `events`, exigir `published: true` e `active: true`; `utilities` usa `active: true`. Inserir sentinelas privados e comprovar que não aparecem na projeção. Guardar IDs aleatórios da execução e remover somente esses IDs; verificar limpeza. Nenhuma fixture hospedada foi criada nesta etapa.
- O runtime grava contadores por UID em `public_content_rate_limits` e `public_content_detail_rate_limits`, cada um com `expiresAt` de 24 h. Esse campo não apaga dados sozinho: TTL exigiria política própria e as exclusões TTL também podem ser cobradas. Não foi configurado TTL nem índice hospedado.

### Verificação local executável

Use somente o script existente, que exige portas livres, Firebase CLI 15.32.1 e Java portátil já presentes, força `demo-universal-search`, loopback e Auth/Firestore/Functions Emulators, remove seletores de credenciais do processo e não importa/exporta dados:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-public-backend-emulator.ps1
node tools/beta-backend-preflight.mjs --project macacu-beta-261030-cf4a81 --preflight-only
```

O teste Emulator verifica fixtures e projeção pública, campos privados excluídos, paginação, visibilidade, negação de escrita direta e chamadas sem Auth/App Check ou com entrada inválida. As negativas com Admin SDK são separadas dos cenários SDK cliente/Rules. O token App Check aceito pelo Emulator é sintético e **não** comprova Play Integrity, enforcement hospedado nem permissões de IAM de produção. O Emulator também não comprova índices publicados.

O arquivo `functions/beta-backend-release-lock.json` fixa o destino, a allowlist de duas Functions e SHA-256 dos arquivos de configuração, Rules candidatas, código e dependências. O hash candidato Firestore registrado é `ddc454413e66107a2087265c3bc9012f7343f90e67a491c353e64e49a75d13b8`. Recalcular e revisar o lock após qualquer edição; não tratar hash aprovado como autorização para publicar Rules. Antes de uma futura publicação, conferir manualmente o ID explícito no Console e interromper se algum arquivo/hash diferir.

Se billing, banco bloqueado, Auth anônimo e App Check apropriado estiverem autorizados e prontos, o único comando de Functions preparado é:

```powershell
firebase deploy --only functions:listPublicContent,functions:getPublicContentDetail --project macacu-beta-261030-cf4a81
```

Não executar esse comando sem autorização explícita de implantação. Não usar `--only functions`, pois publicaria outros exports. Antes: executar o preflight, verificar duas vezes o projeto e hashes, confirmar região, build Node 22 e identidade de runtime. Depois: confirmar nomes/região/App Check, fazer a canária separadamente autorizada e acompanhar logs. Rollback de código deve indicar versões anteriores das mesmas duas Functions e verificar a versão atualmente ativa antes de substituir; nunca remover funções ou voltar projeto/regras inteiras automaticamente. O comando de publicação, rollback e canário continuam não executados.

### Custos e escolha Spark/Blaze

- Cloud Functions exige Blaze e associação a Cloud Billing. Blaze é cobrança por uso, não custo zero; o projeto também pode cobrar recursos do Google Cloud usados no build e runtime. Firestore cobra operações de leitura/escrita/exclusão e armazenamento; o deploy de Functions v2 pode envolver Cloud Build, Artifact Registry e serviços auxiliares. Sem volume, retenção, tráfego e modalidade regional definidos, não há estimativa mensal honesta. Consultar preços e quotas atuais antes de habilitar faturamento: [planos Firebase](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans), [quotas de Functions](https://firebase.google.com/docs/functions/quotas), [preços Cloud Run](https://cloud.google.com/run/pricing) e [preços Firestore](https://firebase.google.com/docs/firestore/pricing).
- Há limites conservadores já no código (máximo 2 instâncias, concorrência 4, timeout 15 s, leituras paginadas e limite de varredura). Para operar, definir alertas de orçamento, observar invocações/erros/latência, leituras Firestore, armazenamento e builds/imagens. Alertas são notificações, não necessariamente teto rígido; confirmar controles disponíveis no plano/serviço antes do uso. TTL não é automático nem gratuito: [TTL Firestore](https://firebase.google.com/docs/firestore/ttl).
- **Spark** evita associar billing, mas não fornece Cloud Functions hospedadas. Alternativa Spark exigiria redesenhar a leitura pública para projeções públicas armazenadas separadamente, Rules somente leitura avaliadas para o schema exato, sem retorno a documentos privados; mudar repositórios Flutter, testes de segurança, provisionamento e talvez estratégia de rate-limit. Não relaxar o callable atual nem expor documentos canônicos como atalho.

### Resultado desta etapa e decisão

- Executado localmente em `demo-universal-search`: `tools/test-public-backend-emulator.ps1` iniciou Auth, Firestore e Functions em loopback. As suítes integradas de visibilidade/projeção (`7` cenários), detalhe (`5` cenários) e busca (`23` cenários) passaram. Foram observados `listPublicContent`/`getPublicContentDetail`, projeção pública e negativas de escrita direta, ausência de Auth/App Check e entrada inválida. Fixtures/usuários são UUID-scoped e removidos pelo runner. O App Check do Emulator é simulado.
- Preflight local: `PASS`, somente leitura local; projeto, funções, hashes e comando permitido impressos sem acessar Firebase. SHA do código e das Rules é verificado contra o lock. Flutter direcionado: `19` passaram e `6` foram pulados pelas condições de ambiente `LOCAL_SEARCH`; sem falhas.
- Functions: `npm test` — 215/215 após corrigir uma asserção estática antiga que esperava a declaração anterior da flag híbrida; `npm run check` passou. Flutter direcionado e `flutter analyze --no-pub` também passaram nesta preparação.
- **GO para pacote local e testes Emulator; NO-GO para implantação/homologação hospedada.** Permanecem: autorizar Blaze; criar o Firestore Standard `(default)` bloqueado; decidir e implementar autenticação de visitante; concluir registro Play Integrity/App Check e provar atestação; preparar fixtures sintéticas e autorização separada para deploy/canário; decidir conteúdo público aprovado. Nenhuma escrita hospedada, billing, Rules, Functions, App Check ou Supabase foi alterada.

## Pré-Beta Android 3.6 — catálogo público sem login (30/10/2026)

- Somente `listPublicContent` e `getPublicContentDetail` aceitam chamadas sem Firebase Auth. Os handlers privados, escrita, operações administrativas e `getPublicJob` continuam exigindo Auth conforme seu contrato. O gate do projeto/flavor Beta continua obrigatório; não há fallback para produção.
- Ambas as funções mantêm `enforceAppCheck: true` e conferem a presença do app validado. Uma visita sem App Check válido é recusada; navegação anônima não significa acesso sem App Check.
- Visitantes são limitados por uma chave SHA-256 de App Check app ID + IP validado pelo runtime. O endereço original não é persistido nem registrado. Usuários autenticados continuam limitados por UID. Cada principal tem limite de 120 solicitações por minuto, com operações transacionais.
- Listagem mantém coleções e campos em allowlists, limite de página de 40, varredura máxima de 80 documentos e resposta máxima de 256 KiB. Detalhes aplicam a mesma projeção pública e limite de bytes. Se um único item exceder o teto, o endpoint o rejeita; se a página atingir o teto, o cursor permite continuar sem pular itens.
- O arquivo local `firestore.indexes.json` declara TTL em `expiresAt` para as duas coleções de limite. A publicação futura precisa incluir essa configuração: ela é necessária para eliminar os registros pseudonimizados expirados. TTL no Firestore é assíncrono e pode gerar custos de exclusão; não representa expiração instantânea. A configuração local não prova que TTL esteja ativo no projeto hospedado.
- A suíte Emulator valida visitante com App Check sintético, usuário autenticado, negativas sem App Check/IP, allowlist/visibilidade e paginação por bytes. Isso não comprova Play Integrity ou App Check hospedado. O projeto Beta continua Spark, sem backend callable hospedado, sem banco Firestore confirmado e sem app Android registrado no App Check; portanto o catálogo local fica pronto para visitantes, mas o acesso Beta hospedado segue **NO-GO** até os requisitos de plataforma serem resolvidos e autorizados.
