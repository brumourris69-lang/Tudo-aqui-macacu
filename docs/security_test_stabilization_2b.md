# Segurança 2B — estabilização dos testes e CI

## Resultado

As cinco falhas da auditoria 2A foram reproduzidas antes das alterações. As quatro falhas Flutter eram de configuração da execução; o teste Auth tinha expectativas anteriores à Segurança 1D. Não foi identificada regressão nesses cinco casos. Foram corrigidos a invocação do CI e o contrato do teste, sem alterar código de aplicação, Rules, autorização, assinatura, distribuição, secrets ou configuração de produção.

Todas as suítes obrigatórias abaixo passaram localmente. Nenhum workflow remoto foi disparado, nenhum APK foi gerado e não houve deploy, acesso a dados reais, commit ou push. As alterações locais anteriores foram mantidas, incluindo os documentos da auditoria 2A.

## Diagnóstico das cinco falhas

Reprodução Flutter: `flutter test`, comando anterior de `.github/workflows/main.yml`. Resultado: 256 aprovados e quatro falhas em `test/local_native_gate_test.dart`.

| Teste | Causa exata | Classificação / correção |
|---|---|---|
| local test build uses the exact demo and loopback | Sem `LOCAL_SEARCH_EMULATORS=true`, enabled é false; host padrão é 10.0.2.2, e o teste exige loopback 127.0.0.1 | Configuração. Executar a suíte local com defines explícitos |
| local weather never invokes the external HTTP client | No modo normal, o serviço usa o cliente HTTP **simulado** fornecido pelo teste; houve uma chamada ao mock, não uma chamada comprovada à API real | Configuração. Exercitar a política de bloqueio no modo local |
| production Android variant refuses local flags | Sem flag local, o estado nativo normal é coerente e prepare não lança StateError | Configuração. Testar a combinação de flags locais com variante nativa normal usando os defines exigidos |
| verified native local isolation installs the HTTP deny policy | Mock nativo informa variante local, mas Dart está em modo normal; prepare rejeita a inconsistência | Configuração. Alinhar modo Dart com o cenário nativo simulado |
| Registered profile/favorites remain allowed by current rules | Teste antigo criava perfil contendo apenas role/email e esperava 200; a Rules 1D exige schema completo e timestamps do servidor. Em seguida esperava escrita direta de favorito, agora vedada para impedir bypass de quota | Expectativa desatualizada. Perfil parcial e favorito direto devem receber 403; perfil completo e favorito pelo gateway devem funcionar |

A rejeição de perfil incompleto foi reproduzida no Auth/Firestore Emulator, antes de editar o teste. Os asserts de segurança não foram afrouxados: o teste corrigido acrescenta explicitamente o caso negativo dos contratos antigos, preserva os demais cenários e amplia a execução Auth de 13 grupos previstos anteriormente para 14.

Os testes Flutter normais usam mocks/fakes e não inicializam um projeto Firebase real. A inspeção não encontrou chamadas diretas a initializeApp/FirebaseAuth.instance/FirebaseFirestore.instance/FirebaseFunctions.instance nos testes Flutter. A suíte local também usa doubles para plugins nativos; não equivale a execução visual Android. Os scripts de integração usam SDKs reais direcionados ao Emulator, projeto demo explícito e hosts loopback. Não são utilizados usuários ou credenciais de produção.

## Correções

### Separação Flutter

O workflow agora executa duas etapas obrigatórias:

```sh
flutter test --exclude-tags search-local
flutter test --dart-define=LOCAL_SEARCH_EMULATORS=true \
  --dart-define=LOCAL_SEARCH_PROJECT=demo-universal-search \
  --dart-define=LOCAL_SEARCH_HOST=127.0.0.1 \
  test/local_native_gate_test.dart test/local_network_isolation_test.dart \
  test/local_universal_search_test.dart test/public_content_test.dart \
  test/user_operations_test.dart
```

A exclusão da tag na suíte normal não remove cobertura: os oito testes da suíte nativa local são executados obrigatoriamente na segunda etapa. Os testes de conteúdo/operações que possuem ramos conforme o ambiente são exercitados nos dois modos. Os demais testes de segurança continuam na suíte normal.

`dart_test.yaml` registra a tag search-local, sem skip ou exclusão global. O antigo comando isolado `flutter test`, sem os defines, continua inadequado para misturar cenários mutuamente incompatíveis de variante. O comando padrão do **CI corrigido** é o par acima; não se mascararam falhas com skips condicionais ou testes enfraquecidos.

### Auth antigo

`functions/integration/auth_emulator.js`:

- Exige exatamente `demo-universal-search` antes de inicializar Firebase.
- Confirma 403 para perfil parcial e escrita direta de favorito.
- Cria perfil completo com displayName/email/photoUrl/role e transforms REQUEST_TIME para createdAt/updatedAt.
- Chama `submitUserOperation` com operação favorite e Auth/App Check locais, depois confirma a leitura autorizada do favorito.
- Preserva testes de visitante, UID, logout, reentrada, Google sintético, Auth/App Check inválidos e ausência de privilégios administrativos.

Não houve alteração nas Rules, no gateway ou no fluxo de autenticação para acomodar o teste.

### Segurança obrigatória no GitHub Actions

Foi adicionado o job `security-tests`, e o job existente `build` agora depende dele por `needs`. Não há continue-on-error ou condição que torne os testes de segurança opcionais. O job executa:

```sh
node --test functions/test/*.test.js workers/image-upload/test/*.test.js scripts/test/*.test.cjs
npx --yes firebase-tools@15.32.1 emulators:exec \
  --only firestore,functions,auth --project demo-universal-search \
  --config firebase.search-emulator.json --non-interactive \
  "node scripts/security_emulator_tests.cjs"
```

O ambiente exige GCLOUD_PROJECT=demo-universal-search, FUNCTIONS_EMULATOR=true, Firestore 127.0.0.1:8087, Auth 127.0.0.1:9097 e LOCAL_SEARCH_REQUIRE_APP_CHECK=true. Functions usa a porta 5007 configurada. Java 21 é instalado somente nesse job; a configuração Java do job de build foi preservada.

O runner valida essas condições antes de carregar SDKs/iniciar filhos, rejeita GOOGLE_APPLICATION_CREDENTIALS e executa sequencialmente seis suítes explícitas: Admin/claims, notificações, conteúdo/busca, operações de usuário, Auth antigo corrigido e auditoria Auth/revogação. Qualquer falha interrompe com status não zero.

O harness search_emulator.js que apaga o banco demo inteiro não faz parte do runner; a cobertura de busca, filtros, índices desatualizados e revalidação permanece nos testes de conteúdo/Auth. Isso evita destruir fixtures de outras sessões locais. Não foram retirados testes que participavam do CI anterior; Node/Worker/Emulator passaram a fazer parte do bloqueio obrigatório do build.

As etapas existentes de geração de artefatos, assinatura e publicação não foram editadas. Adicionar needs apenas impede prosseguir quando os testes de segurança falharem; nenhum build remoto foi iniciado nesta etapa.

## Validação local

| Execução | Resultado |
|---|---|
| `flutter analyze` | Sem problemas |
| Flutter normal, comando corrigido do CI | 252 testes aprovados |
| Flutter local, comando corrigido do CI | 22 testes aprovados; aviso da tag removido pelo registro |
| Node Functions/Worker + guardas do runner | 72 testes aprovados (70 existentes + 2 novos), zero skips |
| Admin claims Emulator | 9 cenários aprovados |
| Notificações Emulator | 12 cenários aprovados |
| Conteúdo/busca Emulator | 48 cenários aprovados em 21 coleções |
| Operações de usuário Emulator | 17 cenários aprovados |
| Auth antigo corrigido Emulator | 14 grupos aprovados |
| Auditoria Auth/revogação Emulator | 7 cenários aprovados |
| Total integração | 107 cenários/grupos nas seis suítes obrigatórias |
| YAML do workflow / gate obrigatório | Parsing local aprovado; needs e ausência de continue-on-error verificados |
| Diff dos arquivos editados | Sem erros de whitespace |

O runner foi executado contra os emuladores locais já ativos; eles não foram interrompidos nem tiveram seu banco limpo. As mesmas suítes/comandos de teste Node e Flutter do CI corrigido foram executadas localmente; no Windows, os globs Node foram expandidos em caminhos equivalentes pelo PowerShell. Não se executou um runner Ubuntu remoto nem um novo cold start de emuladores pelo emulators:exec, para não conflitar com as portas da sessão existente. A inicialização fria do job no GitHub permanece pendente da execução futura autorizada do workflow.

Logs: `C:/Users/tiago/Documents/Codex/2026-09-11/pr/work/security-2b/`: flutter-before.log, auth-before.log, analyze.log, flutter-normal.log, flutter-local.log, node-worker.log e emulator-after.log.

## Arquivos alterados nesta etapa

- `.github/workflows/main.yml` — separação Flutter e job obrigatório de segurança.
- `functions/integration/auth_emulator.js` — expectativas 1D e guard de projeto.
- `dart_test.yaml` — novo, registro da tag local.
- `scripts/security_emulator_tests.cjs` — novo, runner demo fail-closed.
- `scripts/test/security_emulator_tests.test.cjs` — novo, duas verificações das guardas/seleção de suítes.
- `docs/security_test_stabilization_2b.md` — novo, este relatório.

As demais alterações locais do projeto não pertencem a esta etapa e foram preservadas. O relatório 2A permanece como registro histórico, com os resultados anteriores às correções.

## Pendências e riscos restantes

1. Executar o workflow atualizado no GitHub somente após autorização. Dependências, runner Linux, downloads do Emulator e cold start remoto ainda não foram validados nesta etapa; YAML e comandos locais aprovados não são execução remota comprovada.
2. Functions continua sem lockfile versionado. O job usa npm install para o contrato atual; Worker usa npm ci com lock existente. Resolver reprodutibilidade e advisories em etapa própria, sem misturar atualização de dependências nesta correção de testes.
3. Node 20 foi mantido em alinhamento com o backend atual; o prazo de suporte identificado em 2A permanece pendente de atualização autorizada.
4. A aprovação do teste que reproduz revogação isolada no Auth **não resolve o risco**: ele confirma a limitação e o bloqueio pelo procedimento gerenciado. O caminho operacional obrigatório ainda precisa ser preparado para ativação.
5. App Check real, OAuth Google real, persistência nativa, FCM, Worker/Cloudinary reais, assinatura release e compatibilidade dos clientes antigos continuam pendências da auditoria 2A. Nenhuma dessas proteções/configurações foi alterada.
6. Não houve validação visual MEmu nem Hot Reload; somente testes/CI foram alterados, sem mudança de comportamento ou interface do aplicativo.

Segurança 2B concluída. Suíte de testes estabilizada localmente. Aguardando autorização.
