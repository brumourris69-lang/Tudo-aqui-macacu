# Busca Universal — Etapa 4E (08/10/2026)

## Diagnóstico anterior

- Login visual disponível: Google, com GoogleSignIn + FirebaseAuth.signInWithCredential.
- Não existe tela de e-mail/senha no repositório. O suporte SDK foi preparado sem criar nova tela.
- Visitante: `currentUser == null`, CityShell com chave `guest`, favoritos em memória; perfil mostra convite de login. Não havia Auth anônimo.
- Sessão de conta persistida pelo SDK Firebase Auth e observada por `authStateChanges`; logout desativa dispositivo FCM, desconecta Google e Firebase.
- Perfil/favoritos/dispositivos eram sincronizados quando havia User. Admin visual usa e-mail legado; Rules usam claims admin/role ou e-mail legado; upload também exige e-mail legado verificado quando não há claim.
- App Check não existia no Flutter. A callable de busca local já exigia contexto de Auth + App Check e recusava Auth anônimo.
- Risco encontrado: Rules `signedIn()` aceitavam qualquer Auth, portanto ativar anonymous sem ajuste liberaria recursos de contas cadastradas.

## Alterações

- `GuestSession` coordena criação única/reuso, espera operação anônima pendente antes de login cadastrado, impede criação durante troca de conta/logout e evita repetição automática após falha.
- `AppAuth.ensureVisitor` espera a restauração inicial do SDK e só cria anônimo se não houver sessão. Ativo **somente** com opt-in debug `LOCAL_SEARCH_EMULATORS=true`, projeto `demo-*` correspondente e host local permitido. Produção mantém visitante sem Auth nesta etapa.
- Login Google continua usando a mesma credencial e fluxo visual. Método para e-mail/senha preparado sem nova interface. Não ocorre vinculação/mescla automática de contas: login em conta existente mantém UID/favoritos dessa conta.
- Logout local volta a uma sessão anônima; no fluxo normal permanece signOut anterior. Favoritos de visitante continuam apenas em memória, sem migração automática. Null→anonymous conserva chave `guest` e não reinicia CityShell. Login cadastrado muda para a chave do UID como antes.
- `isRegisteredUser` exclui `isAnonymous`; aplicado a perfil, favoritos, saudação, sincronização de perfil, métricas, avaliações, votação, contato e identificação visual de Admin. Auditoria/push não são executados para anônimos; FCM não é inicializado no modo demo.
- `firestore.rules`, apenas no arquivo local: `signedIn()` exige provedor diferente de anonymous. Como todas as permissões de conta dependem dele ou de `isOwner`/`admin`, essas permissões continuam bloqueadas para visitantes. Leitura pública segue igual. Nenhuma regra foi implantada.
- Upload adiciona recusa explícita de anonymous, inclusive diante de claim admin indevida. Os demais critérios de administrador foram preservados.
- Busca local aceita Google/e-mail/anonymous com Auth válido, revalida publicação/atividade/expiração e mantém limites de frequência e leituras.

## App Check e isolamento

- Adicionado `firebase_app_check 0.3.2+10`, compatível com a família Firebase Core já usada. Não foi atualizada a família inteira de pacotes Firebase.
- Provedores preparados: Android Play Integrity; Apple App Attest com fallback DeviceCheck; debug providers para desenvolvimento. Nenhum token de depuração fixo no app.
- `AppCheckSetup` é desativado por padrão e bloqueia ativação no projeto real nesta etapa. As opções nativas estão preparadas, **não ativadas nem atestadas**.
- Não há emulador de App Check. Em modo demo não há troca de tokens de debug com Firebase real. Testes de callable estrita usam JWT fictício gerado em tempo de execução, aceito pelo comportamento oficial `skipTokenVerification` do Functions Emulator; não é um token de debug registrado nem comprova atestação.
- Backend estrito por padrão (`LOCAL_SEARCH_REQUIRE_APP_CHECK` ausente): App Check obrigatório, cabeçalho ausente/malformado bloqueado.
- Exceção opt-in `LOCAL_SEARCH_REQUIRE_APP_CHECK=false`: permitida **somente dentro da barreira demo+loopback de registerLocalSearch**. Permite cliente do emulador sem token App Check; Auth, Rules, revalidação e quotas permanecem obrigatórios. Nenhuma exportação de busca é habilitada para projeto real.
- Bootstrap Flutter demo usa FirebaseOptions fictícias, desliga cache Firestore persistente e aponta Auth/Firestore/Functions aos emuladores. Falha de configuração demo interrompe startup; não volta silenciosamente ao projeto real.

Referência de provedores/configuração manual: https://firebase.google.com/docs/app-check/flutter/default-providers

## Testes executados

- **66 testes Flutter passaram**: 9 novos de sessão/política/perfil e 57 existentes de busca/base/paridade/Home/Admin. Analyze: nenhum problema.
- **37 testes Node passaram**, incluindo anonymous permitido na busca e preservação dos testes existentes de uploads.
- Firestore/Functions/Auth reais locais em `demo-universal-search`: **19 grupos de regressão da busca passaram**.
- **13 grupos de Auth/Rules passaram duas vezes**, com política App Check estrita e com exceção local explícita (26 execuções):
  - SDK Firebase Auth anônimo sem dados pessoais/perfil Firestore;
  - reuso de sessão e refresh com o mesmo UID;
  - callable de busca permitida ao visitante;
  - perfil, favoritos Firestore, dispositivos, métricas, avaliações, votos, contato, proposta e Admin negados ao visitante;
  - leitura pública permitida; origem privada/índice/conta negados;
  - claim admin/role colocada ficticiamente em anonymous não permite escrita administrativa nem upload;
  - troca de visitante para e-mail/senha, UID cadastrado e favorites preservados após logout/login;
  - logout real do SDK emite null; nova sessão visitante tem UID separado;
  - credencial Google fictícia trocada pelo SDK contra Auth Emulator;
  - sem Auth e token malformado negados; ausência/má formação App Check negadas em modo estrito;
  - callable sem App Check aceita Auth apenas no modo demo opt-in;
  - exceção local não elimina a exigência de Auth nem a elegibilidade pública.
- Testes usam Firebase Client SDK como **devDependency** do backend, nunca como nova dependência de execução das functions.
- Falhas intermediárias foram do harness: mock antigo de Admin não declarava isAnonymous e termo fictício ultrapassava o limite de 24 caracteres. Corrigidos os fixtures, sem relaxar a política.

## Limites e pendências manuais

1. Nenhum Firebase Console foi alterado. Emuladores não exigem habilitar provedores no Console.
2. Futuramente, se autorizado: habilitar anonymous e confirmar e-mail/senha no Console. Anonymous real só poderá ser habilitado junto das proteções de conta nas Rules; as atuais regras implantadas ainda não receberam esta alteração local.
3. Registrar apps em App Check, configurar certificados Android SHA-256/Play Integrity, capacidades Apple/App Attest/DeviceCheck e tokens debug privados quando necessário. Não ativar enforcement global automaticamente; preparar/validar cada serviço antes.
4. Não foram validados Play Integrity, App Attest, DeviceCheck, assinatura/revogação real de App Check, OAuth Google real nem persistência nativa em disco Android/iOS. Os testes Client SDK usam persistência em memória; Flutter testa o contrato de restauração/reuso. Não são equivalentes à validação nativa.
5. O aplicativo instalado no Android pode ter um default FirebaseApp nativo inicializado pelo google-services.json real. Um boot demo com opções distintas pode gerar duplicate-app; a barreira impede fallback para produção. Na próxima etapa, validar bootstrap isolado demo antes de conectar a interface; se necessário, preparar configuração nativa de teste separada, preservando a real. Não foi criado APK para testar isso.
6. GoogleSignIn visual ainda usa o cliente OAuth existente: não acionar OAuth real durante testes exclusivamente demo. O teste de credencial Google nesta etapa foi sintético no SDK/Auth Emulator.
7. Regras legadas de administrador por e-mail/claims, leitura pública de origem sem active/expiresAt, autorização de imagens, TTL e proteção contra abuso com múltiplas contas continuam decisões separadas. Nada foi ampliado aqui.
8. Dependência nativa nova e dart-defines de startup não podem ser plenamente ativados por Hot Reload. Será necessário reconstruir/reiniciar a sessão de desenvolvimento local quando autorizado; não foi gerado APK nesta etapa.

## Próxima etapa local

É seguro avançar para **preparar** a conexão da interface ao emulador, com os gates existentes. Antes de afirmar teste ponta a ponta no Android/iOS: confirmar default FirebaseApp demo, Auth/Firestore/Functions exclusivamente locais, nenhum FCM/OAuth real e nenhum fallback para produção.

Para emuladores: usar `firebase.search-emulator.json`, `--project demo-universal-search`, Node 20/Java 21 e parâmetros fictícios temporários conforme `functions/integration/EMULATOR_RESULTS.md`. Executar sequencialmente:

```powershell
$env:GCLOUD_PROJECT='demo-universal-search'
$env:FUNCTIONS_EMULATOR='true'
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8087'
$env:FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9097'
node functions/integration/search_emulator.js
node functions/integration/auth_emulator.js
```

Reiniciar os emuladores com `LOCAL_SEARCH_REQUIRE_APP_CHECK=false` no ambiente do CLI e do segundo terminal para a segunda execução de `auth_emulator.js`. A suíte de regressão estrita não deve ser executada com essa exceção.

Flutter demo (somente em próxima sessão autorizada): opt-in `LOCAL_SEARCH_EMULATORS=true`, `LOCAL_SEARCH_PROJECT=demo-universal-search`, `LOCAL_SEARCH_HOST=10.0.2.2` (Android Emulator) ou `127.0.0.1` (simulador iOS/desktop). `LOCAL_SEARCH_APP_CHECK` permanece desligado para demo sem atestação. Nenhuma tela de pesquisa foi conectada nesta etapa.

## Arquivos desta etapa

- Novos: `lib/core/auth/app_auth.dart`, `guest_session.dart`, `app_check_setup.dart`; `lib/core/config/local_search_environment.dart`; `test/guest_session_test.dart`; `functions/integration/auth_emulator.js`; este relatório.
- Modificados: `lib/main.dart`, `lib/redesigned_app.dart`, `lib/admin_audit.dart`, `lib/core/services/metrics_service.dart`, `pubspec.yaml`, `pubspec.lock`, `firestore.rules`, `functions/business_search.js`, `business_search_functions.js`, `home_image_upload.js`, `functions/package.json`, `functions/test/business_search.test.js`, `functions/integration/search_emulator.js`, `test/home_title_edit_pilot_test.dart` (getter faltante no fixture).
- Alterações locais anteriores preservadas. Sem deploy, dados reais, backfill, APK, commit, push ou enforcement em produção.

## Atualização Pré-Beta Android 3.7 — visitante searchLocal sem sessão anônima

O comportamento anterior descrito neste histórico foi substituído em 30/10/2026:
o flavor `searchLocal` agora mantém visitante com `FirebaseAuth.currentUser == null`
e não cria nem recria uma conta anônima durante a navegação pública ou logout.
`AppAuth.ensureVisitor()` ainda verifica explicitamente o projeto demo antes de
retornar, e login sintético por e-mail/senha continua disponível para validar
operações autenticadas. A variante Beta também não cria Auth anônimo.
Qualquer sessão previamente persistida é validada depois de configurar o Auth
Emulator. Um token inválido direciona à recuperação explícita, sem apagar a
sessão ou criar uma conta substituta automaticamente.

Os callables `listPublicContent` e `getPublicContentDetail` aceitam visitante
sem Auth, mas continuam exigindo App Check. A busca textual existente usa
`searchBusinesses`, que permanece autenticado e protegido por App Check; ela não
foi convertida em filtragem local de catálogo nem teve sua autorização reduzida.
Assim, teste de listagem/detalhes sem sessão e teste de busca textual com conta
sintética são cenários separados. O App Check de Emulator é fixture de teste,
não evidência de atestação Play Integrity.

Durante a validação Android, uma sessão registrada antiga, ausente no Auth
Emulator recém-iniciado, foi recusada e encaminhada à recuperação. A opção
confirmada “Continuar como visitante” agora encerra essa sessão local, valida
Firestore/Functions Emulators e abre o app sem Auth; não solicita outro token.
O launcher também verifica as portas em uma única thread de trabalho limitada,
em vez de iniciar uma thread a cada tentativa. Isso reduz acúmulo no Gate, mas
não substitui a validação em AVD de desempenho normal.

## Atualização Pré-Beta Android 3.8 — pesquisa textual pública no searchLocal

O modo `searchLocal` agora escolhe o callable pelo estado real da sessão:
visitantes usam `searchPublicContent`; usuários autenticados continuam usando
`searchBusinesses`. O callable antigo continua exigindo Auth e App Check. A
nova rota só é exportada dentro da barreira demo/loopback, exige App Check,
valida parâmetros e cursor, aplica a mesma cota transacional e lê apenas os
índices permitidos. Para visitantes, as fontes são estabelecimentos, turismo e
eventos; Notícias e Empregos ficam fora porque não fazem parte deste contrato
público de busca/detalhes. A projeção omite campos administrativos e a origem é
revalidada antes de cada resposta para rejeitar conteúdo oculto ou tombstonado.

O cliente não faz leitura direta do Firestore para pesquisar. Também não cria
Auth anônimo: uma sessão ausente seleciona a rota pública; as operações privadas
continuam falhando sem uma conta cadastrada. A fixture App Check sem assinatura
é usada somente pelo Functions Emulator e não comprova Play Integrity hospedado.

No teste real dos Emulators (30/10/2026), a busca pública concluiu o fluxo de
acentos, categoria, eventos, resultados vazios, conteúdo oculto, limite de
parâmetros, página/cursor, revalidação depois de despublicar, falta de App Check
e recusa da rota `searchBusinesses` sem Auth. O harness removeu os documentos,
índices, rate records e usuários criados por UUID. Nenhuma regra foi relaxada.
