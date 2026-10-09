# Android local isolado — etapa 4F.2

O flavor **searchLocal** é exclusivo de debug, com ID
`br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal`. O Gradle registra o flavor
somente quando uma tarefa SearchLocal é solicitada (ou `-Psearch-local=true`).
Os builds normais continuam sem flavor, com o mesmo applicationId, configuração
Google e nomes de APK anteriores. Não existe default-flavor global que afete iOS
ou os scripts do Codemagic. A configuração Firebase de produção não foi copiada
nem modificada.

## Proteções antes do Flutter

- O manifesto local remove FirebaseInitProvider, o provider do plugin Messaging,
  serviços e receivers FCM. Coleta automática Firebase, Messaging, Analytics e
  Crashlytics ficam desativadas. Não há Storage configurado para o app demo.
- A tarefa GoogleServices do flavor fica desabilitada. O APK não contém recursos
  google_app_id, google_api_key ou default_web_client_id de produção.
- Os providers restantes foram inspecionados no manifesto mesclado: FileProvider
  de imagens, ProcessLifecycleInitializer e ProfileInstallerInitializer. São
  serviços locais de arquivos/ciclo de vida/perfil de execução; não há
  inicializador EmojiCompat, download de fontes nativo ou outro provider Firebase.
- O único launcher é SearchLocalGateActivity. Antes de criar o FlutterEngine e
  registrar plugins, ele estabelece SearchLocalVpnService e verifica as três
  portas locais em uma thread de trabalho. Se isso falhar, Flutter não inicia.
- A VPN Android usa addAllowedApplication exclusivamente para o ID de teste,
  capturando IPv4, IPv6 e DNS. Os pacotes são descartados, sem qualquer proxy,
  forwarding, gravação de payload ou envio externo. Outros apps não entram nela.
  Loopback permanece local. Revogação, destruição ou falha do túnel encerra o
  processo de teste. Não iniciar se houver outra VPN que precise ser preservada.
- O MEmu usado não possui o match owner do iptables. A tentativa de configurar
  firewall por UID foi abandonada e sua cadeia sem referências foi removida;
  o aplicativo não foi iniciado sob essa proteção incompleta.

## Proteções Dart

O canal nativo confirma variante e VPN antes de Firebase.initializeApp. Exige
LOCAL_SEARCH_EMULATORS=true, debug, projeto exatamente demo-universal-search e
host 127.0.0.1. Divergência não tem fallback para produção. Todos os FirebaseApps
existentes são conferidos e sua coleta automática fica desativada.

Auth (9097), Firestore (8087, sem persistência) e Functions (5007, regiões padrão,
us-central1 e southamerica-east1) usam emuladores com automaticHostMapping=false.
Isso é necessário: os SDKs normalmente transformam 127.0.0.1 em 10.0.2.2.

Antes da Home, o app valida uma sessão anônima no Auth local, lê somente
home_pages/published via Source.server e confere HTTP 404 na raiz do servidor
Functions. Esta última é uma verificação de transporte, não uma execução da
callable searchBusinesses. Não cria conteúdo fictício, índice ou backfill.

HttpOverrides recusa qualquer conexão HTTP fora dessas três portas e do host
local antes de abrir o socket, incluindo imagens externas. O manifesto permite
HTTP claro somente a 127.0.0.1. Clima, uploads Worker/Functions, login Google e
links externos têm bloqueios explícitos locais. Push não é ativado. Poppins é
empacotada somente no flavor local, com licença OFL, e o Google Fonts não faz
downloads nesse modo. A versão normal mantém os serviços anteriores.

App Check não troca tokens com produção. A callable continua com a política
estrita anterior; a validação de App Check real e a política de transporte para
a futura integração da interface não foram alteradas nesta etapa.

## Execução

Inicie somente o projeto demo com a configuração separada:

```powershell
..\work\firebase-tools.exe emulators:start --only firestore,functions,auth --project demo-universal-search --config firebase.search-emulator.json --non-interactive
```

É necessário usar o Node 20 e Java 21 locais preparados anteriormente. Os
parâmetros .env.local/.secret.local do backend usam valores fictícios local-demo
e LOCAL_TEST_ONLY, nunca credenciais reais. Permanecem ignorados pelo Git.
Não executar firebase use, login ou deploy.

```powershell
flutter build apk --debug --flavor searchLocal --dart-define=LOCAL_SEARCH_EMULATORS=true --dart-define=LOCAL_SEARCH_PROJECT=demo-universal-search --dart-define=LOCAL_SEARCH_HOST=127.0.0.1
.\tools\start-search-local.ps1
```

O inicializador inspeciona o APK, encerra somente o pacote .searchlocal, instala
com --no-streaming, autoriza apenas sua VPN e provisiona adb reverse. Repetições
com -SkipInstall exigem SHA-256 idêntico entre o APK instalado e o verificado.
O MEmu pode reiniciar o transporte ADB ao trocar a VPN; o script reconecta e
restabelece as três portas. Se não conseguir, a inicialização fica bloqueada.

Não usar Hot Reload/Restart para inserir flags ausentes. Mudanças nativas exigem
novo debug local. flutter run neste MEmu perdeu o leitor de logs quando a VPN
reiniciou o transporte ADB; por isso a validação final utiliza o APK instalado
e o launcher verificado. Não há sessão interativa de Hot Reload confirmada.
flutter attach sem flavor também não deve ser usado para recompor assets locais
como se fosse a configuração normal.

## Evidências e limites

- APK debug compilado; inspeção do manifesto/recursos passou.
- Build normal assembleDebug validado com --dry-run, preservando a tarefa
  processDebugGoogleServices e nomes de variantes anteriores, sem gerar APK.
- 68 testes Flutter de rede, visitante, busca existente e Home passaram.
- 8 testes adicionais das flags/canal nativo e bloqueios de serviços passaram
  com defines locais.
- 43 testes de regressão de clima, upload Worker/Functions e botão de upload
  passaram com o modo normal. Total: 119 testes Flutter aprovados.
- 22 testes Node da infraestrutura existente passaram. Não houve deploy.
- Flutter Analyze sem problemas.
- Android confirmou VPN IPv4/IPv6 para o UID do pacote de teste. Conexões por
  esse UID aos endereços reservados 192.0.2.1 e 2001:db8::1 ficaram bloqueadas;
  a porta Functions local foi acessível. Não houve probe a hosts de produção.
- Bootstrap imprimiu LOCAL ISOLATION VALIDATED após as três verificações.
  Home foi confirmada pela árvore de acessibilidade, incluindo título, busca,
  categorias, navegação e estado controlado de clima indisponível. screencap do
  MEmu retornou preto, portanto não é evidência de conferência visual dos pixels.
- Auth local criou somente sessões anônimas de teste; Firestore local continua
  sem coleções/documentos persistidos pelo app. A Busca Universal visual não
  foi conectada e suas consultas não foram ativadas.
- Testado neste MEmu Android 9/API 28. A variante não está validada em iOS,
  aparelhos físicos nem em outros emuladores. Não distribuir este APK.

O ambiente está isolado para a próxima etapa local. Não interpretar esta
validação como autorização de produção, App Check enforcement ou integração.

## Arquivos desta etapa

Modificados:

- .gitignore (parâmetros e logs locais)
- android/app/build.gradle.kts
- android/app/src/main/kotlin/br/com/tudoaquimacacu/tudo_aqui_macacu/MainActivity.kt
- lib/main.dart
- lib/core/config/local_search_environment.dart
- lib/core/media/media_upload_service.dart
- lib/core/services/weather_service.dart
- lib/core/services/external_link_service.dart
- lib/redesigned_app.dart (somente guardas locais de login/logout Google)
- pubspec.yaml (assets Poppins exclusivos do flavor)

Criados:

- android/app/src/searchLocal/AndroidManifest.xml
- android/app/src/searchLocal/res/xml/search_local_network_security.xml
- android/app/src/searchLocal/kotlin/br/com/tudoaquimacacu/tudo_aqui_macacu/SearchLocalApplication.kt
- android/app/src/searchLocal/kotlin/br/com/tudoaquimacacu/tudo_aqui_macacu/SearchLocalGateActivity.kt
- android/app/src/searchLocal/kotlin/br/com/tudoaquimacacu/tudo_aqui_macacu/SearchLocalVpnService.kt
- lib/core/config/local_network_isolation.dart
- assets/fonts/local-poppins/ (9 pesos Poppins e licença OFL)
- test/local_network_isolation_test.dart
- test/local_native_gate_test.dart
- tools/start-search-local.ps1
- tools/test-search-local-apk.ps1
- lib/features/search/SEARCH_LOCAL_ANDROID.md

Arquivos de runtime locais: functions/.env.local e functions/.secret.local
(valores fictícios, ignorados), logs dos emuladores e APK debug em build/.
Os emuladores e o aplicativo local permanecem ativos para conferência. Nenhum
arquivo de regra/backend/índice foi alterado nesta etapa. Alterações anteriores
permanecem no workspace, sem commit ou push.
