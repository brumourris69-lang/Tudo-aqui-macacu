# Segurança 2D — App Check e dependências

Data: 09/10/2026. Escopo exclusivamente local. Nenhum deploy, enforcement, Console, conta real, credencial, release, commit ou push foi executado. As alterações 1A–2C foram preservadas.

## Resultado executivo

Preparados os provedores Play Integrity e App Attest com alternativa DeviceCheck, renovação automática pelo SDK e erros sanitizados, mantendo a ativação real bloqueada. Corrigida a cadeia vulnerável de `sharp` no ferramental do Worker. Criado o lockfile das Functions e preparado CI com instalações reproduzíveis e runtimes distintos. Todos os testes executados passaram.

**A publicação ainda não está autorizada tecnicamente:** Functions mantém advisories; atestação real não foi comprovada; permanecem as pendências de implantação coordenada e revogação identificadas em 2A. Aprovação de testes locais não equivale a proteção App Check real.

## 1. Estado do App Check por serviço

| Serviço/caminho | Configuração encontrada | Pendência |
| --- | --- | --- |
| Flutter oficial | `AppCheckSetup.enabled` false por padrão; entrada agora também exige autorização explícita, atualmente false | Autorizar futuramente configuração real, revisar ordem de inicialização e validar aparelhos oficiais |
| Flutter searchLocal | Modo Emulator retorna antes de acessar o SDK App Check, mesmo com `LOCAL_SEARCH_APP_CHECK=true` | Nenhuma troca de token real deve ser adicionada ao ambiente demo |
| `searchBusinesses` | Exportado somente no ambiente demo; exige Auth e `request.app.appId`; `enforceAppCheck` acompanha política local, true nos testes | Implantação futura separada; a possibilidade local explícita de desligar a exigência não deve ser transportada para produção |
| `listPublicContent` / `submitUserOperation` | Exportados somente no ambiente demo; Auth + App Check obrigatório, quotas e revalidação existentes | Integrar/implantar somente após plano coordenado anterior |
| `uploadHomeImage` | Auth/Admin/revogação existentes; callable sem `enforceAppCheck` | Preparar cliente e proteção App Check em etapa autorizada, além de quotas |
| Worker de upload | JWT Firebase/Auth + autorização administrativa atual; sem verificação App Check | Backend personalizado precisa receber/verificar App Check separadamente; não basta JWT Auth |
| Firestore direto | Security Rules continuam indispensáveis; exigência App Check é configuração do serviço, não filtro Flutter nem `request.auth` | Estado implantado/enforcement desconhecido, pois Console não foi acessado |
| Firebase Authentication | Login Google/e-mail/anônimo separado de App Check | Verificar suporte/configuração e métricas reais antes de enforcement; anônimo não é Admin nem atestação |
| Gatilhos Firestore e push FCM | Execução confiável no servidor, não requisição cliente com App Check | Proteger gravações que disparam eventos; App Check não resolve autorização, duplicidade ou fanout de push |
| Storage/Analytics/Crashlytics Flutter | Sem dependências desses plugins no `pubspec.yaml` atual | Não afirmar proteção de serviços não integrados; Admin SDK pode ter dependências transitivas de Storage |
| Cloudinary | Upload mediado pelos backends existentes | Proteger fronteiras de upload; não enviar credenciais ao Flutter |

O projeto demo usa fixtures de App Check aceitas pelo Emulator. Testes verificam rejeição de ausência/token inválido e aceitação da fixture; não verificam Play Integrity, App Attest, DeviceCheck ou prevenção real de fraude. Firebase Auth, Custom Claims, estado de autorização e Security Rules continuam necessários independentemente do App Check.

## 2. Android

Identificador oficial preservado: `br.com.tudoaquimacacu.tudo_aqui_macacu`. Variante isolada: sufixo `.searchlocal`. Nenhuma configuração Gradle, assinatura, certificado ou `google-services.json` foi alterada em 2D.

`AppCheckProviderPlan` prepara `AndroidProvider.playIntegrity`. Provedor debug é exclusivamente uma seleção explícita de desenvolvimento; falha de Integrity não causa fallback para debug ou backend desprotegido. Não foram inseridos tokens fixos. O SDK terá renovação automática habilitada após uma ativação futura autorizada; não há `getToken(forceRefresh)` a cada pesquisa.

Antes de ativar: confirmar aplicativo/projeto corretos, certificado SHA-256 efetivamente usado na instalação oficial (inclusive certificado de assinatura do Play quando aplicável, distinto da chave de upload), origem de distribuição e verdicts adequados. Validar instalações Play e outras origens autorizadas, versões antigas, dispositivos sem suporte e visitantes. Aparelhos incompatíveis devem receber erro claro e orientação para versão/dispositivo compatível, sem reduzir a exigência silenciosamente. A mensagem preparada não expõe a exceção original ou tokens.

A documentação exige inicialização do App Check antes de usar serviços protegidos. Na ativação futura revisar a sequência completa, incluindo inicializadores nativos e primeiro acesso Auth/Firestore/FCM; esta etapa não ligou o provedor nem alterou inicialização normal. [Integração Flutter](https://firebase.google.com/docs/app-check/flutter/default-providers), [Play Integrity](https://firebase.google.com/docs/app-check/android/play-integrity-provider).

## 3. iOS

Preparado `AppleProvider.appAttestWithDeviceCheckFallback`: App Attest onde suportado e DeviceCheck como alternativa da plataforma. Provedor debug permanece separado. Não há fallback para debug em caso de falha. Não existem pasta iOS/Podfile/Podfile.lock/entitlements nativos neste checkout; logo não foi possível validar distribuição Apple, capacidades, assinatura ou SDKs CocoaPods efetivamente resolvidos.

Pendentes, mediante autorização: criar/revisar projeto iOS oficial, bundle ID, capabilities e configuração Apple/Firebase, compatibilidade das versões suportadas, aparelhos físicos e distribuição autorizada. Não foram acessadas contas Apple ou chaves reais. [Provedores Flutter e compatibilidade App Attest](https://firebase.google.com/docs/app-check/flutter/default-providers).

## 4. Isolamento e ativação gradual

Modo local continua exclusivo de `demo-universal-search`, Auth 9097, Firestore 8087 e Functions 5007. VPN e bloqueio de rede não foram modificados. Testes Flutter de configuração nativa/rede passaram; teste adicional inicia a preparação App Check com flags locais habilitadas sem SDK real. Não houve execução/Hot Reload, captura ou nova comprovação da VPN no MEmu nesta etapa: não se deve interpretar testes unitários como inspeção de tráfego de um aparelho ativo.

Plano futuro, sem execução nesta etapa:

1. Resolver pendências de dependências, runtime, migração de clientes/regras e autorização administrativa de 2A–2C.
2. Configurar provedores reais somente com autorização, sem enforcement; revisar certificados, distribuição e capacidades Apple.
3. Autorizar preparação do SDK em builds de teste oficiais; validar renovação, falhas, contas cadastradas e visitantes em dispositivos físicos. Debug token somente no ambiente próprio de desenvolvimento, nunca credencial fixa versionada.
4. Observar métricas por serviço/versão e investigar requisições inválidas/desconhecidas; definir critérios de compatibilidade e suporte a clientes antigos. Cliente sem SDK/token pode perder acesso quando enforcement for ativado.
5. Após nova autorização, habilitar exigência gradualmente por serviço/endpoint. Auth, Firestore e callable Functions precisam de avaliação individual; Worker precisa de verificador próprio. App Check não substitui quotas e validação de entradas.
6. Monitorar erros, latência e sucesso de login/pesquisa/upload. Interromper expansão se clientes legítimos falharem. Reversão de enforcement exige autorização operacional; não enfraquecer Rules, Admin ou publicação para compensar falha de atestação.

## 5. Dependências e correções

| Área | Evidência | Ação local / pendência |
| --- | --- | --- |
| Worker/ferramental | `npm audit`: 3 pacotes altos na cadeia Wrangler → Miniflare → sharp | Override específico `sharp: 0.35.5`; lock atualizado; audit completo após correção: zero |
| Functions completo | 13 pacotes sinalizados: 6 altos, 7 moderados | Sem upgrade amplo; lock criado; pendências abaixo |
| Functions sem devDependencies | 9 pacotes: 2 altos, 7 moderados | Não classificar todas as ocorrências como apenas ferramentas de teste |
| Flutter/Dart | 114 versões hosted de `pubspec.lock` consultadas no OSV, nenhum advisory retornado | Nenhuma atualização por idade; ausência de advisory não prova ausência de vulnerabilidade |
| Metadados Pub | 114 pacotes verificados; nenhum marcado discontinued/unlisted | Não equivale a auditoria da manutenção de todos os projetos |
| Firebase nativo | Firebase Core 3.15.2 / BOM Android 33.16.0; App Check 0.3.2+10 inclui dependência legada SafetyNet | Provedor selecionado é Integrity; não foi feita auditoria completa de CVEs Maven/CocoaPods nem removida dependência transitiva por conta própria |
| Node/ferramentas | Functions Node 20; Wrangler instalado exige Node >=22 | Worker CI separado em Node 24; Functions permanece Node 20 até migração autorizada |

`sharp` 0.35.5 corrige o advisory de librsvg, com biblioteca nativa 2.63.2 confirmada na instalação. O cenário de exploração documentado envolve processamento SVG com binários vulneráveis em Linux/glibc; aqui a dependência pertence ao ferramental de desenvolvimento, não ao runtime JavaScript do Worker. Wrangler e Miniflare não foram atualizados como pacotes raiz. [Advisory oficial sharp](https://github.com/lovell/sharp/security/advisories/GHSA-wq5f-xc86-pv6w).

Functions mantém `firebase-admin` 12.7.0, `firebase-functions` 6.6.0 e Firebase JS 11.10.0. Avisos principais: `node-forge` (alto, cadeia Admin), `uuid` (<11.1.1, moderado) e pacotes dependentes; `@grpc/grpc-js` 1.9.16 na árvore de desenvolvimento Firebase JS (alto). O grpc usado pela árvore Admin é 1.14.6. Firestore JS fixa a série `~1.9.0`: uma tentativa de override não resultou em atualização válida e foi removida, sem conservar instalação inconsistente. Não foi imposto grpc fora do contrato do SDK. Os advisories grpc corrigidos em >=1.13.6 exigem atualização do SDK dependente ou override posteriormente validado e autorizado. [Advisory grpc](https://github.com/grpc/grpc-node/security/advisories/GHSA-m9gg-hp2v-232j), [outro advisory grpc](https://github.com/grpc/grpc-node/security/advisories/GHSA-f596-whhp-79r4).

O audit sugere mudanças principais de Firebase Admin e inclusive downgrade principal do Firebase JS; não executar `npm audit fix --force`. Pacotes listados como dependentes não são 13 falhas independentes exploradas. Exploração no fluxo deste aplicativo não foi demonstrada. Resolver a cadeia de produção Admin/forge/uuid e dependências de desenvolvimento em etapa própria com testes. npm também sinalizou uuid 9/10 como versões sem suporte. Nenhum SDK Flutter foi atualizado.

Node 20 mantém a pendência de ciclo de vida identificada em 2A: planejar migração de runtime antes de nova implantação. Alterar Node do job Worker não altera runtime das Functions. [Runtimes e gerenciamento de Functions](https://firebase.google.com/docs/functions/manage-functions).

## 6. Lockfiles e CI

Criado `functions/package-lock.json` v3, ainda local/não commitado, com versões e integridades. A reconciliação da árvore ajustou somente tipos transitivos `@types/send` 1.2.1 → 0.17.6 e removeu cópia duplicada; os SDKs raiz foram preservados. Manifesto Functions permaneceu intacto. Worker mantém lock existente com correção sharp; `pubspec.lock` não foi alterado.

Instalações limpas `npm ci --ignore-scripts --no-audit --no-fund` em diretórios temporários externos ao checkout passaram: Functions 353 pacotes, Worker 38 pacotes desta plataforma. Hashes SHA-256 dos dois lockfiles permaneceram idênticos. Isso valida resolução/instalação sem scripts, não execução de todos os scripts nativos em todas as plataformas. As instalações ativas do Emulator não foram removidas.

CI Functions agora usa `npm ci`; testes Worker obrigatórios têm job Node 24, anterior ao job de segurança Node 20. Builds continuam dependendo dos testes de segurança. Preservados gates, assinatura e autorização release de 2C; sem mudança de secrets, execução remota ou publicação. Adicionados testes App Check no conjunto Flutter local e teste com flag local explícita.

Sem lock CocoaPods neste checkout; não existe prova de reprodutibilidade iOS. Lockfiles npm/Pub não travam por si só todos os artefatos Maven/Gradle ou a versão Flutter estável selecionada pelo CI. A conclusão não promete builds binariamente idênticos.

## 7. Validação executada

| Verificação | Resultado |
| --- | --- |
| Flutter Analyze | Sem problemas |
| Flutter normal (`--exclude-tags search-local`) | 259 passaram |
| Flutter local explícito (seis arquivos, projeto demo) | 29 passaram |
| App Check local com `LOCAL_SEARCH_APP_CHECK=true` | 7 passaram, sem chamada SDK real |
| Node Functions + runner, Node 20 | 58 passaram |
| Worker, Node 24 | 14 passaram |
| Python assinatura/isolamento + verificação estática Android/CI | 8 passaram; verificações estáticas aprovadas |
| Firebase Emulator existente, seis suítes obrigatórias | 107 cenários/grupos passaram (9 + 12 + 48 + 17 + 14 + 7) |
| npm audit Worker completo após correção | 0 avisos |
| npm audit Functions completo / sem dev | 13 / 9 pacotes sinalizados |
| npm ci limpo em cópias isoladas | Ambos passaram; lockfiles estáveis |

Emulator: Auth, Firestore e Functions locais já ativos, `GCLOUD_PROJECT=demo-universal-search`, hosts loopback, `LOCAL_SEARCH_REQUIRE_APP_CHECK=true`. Runner sequencial não limpou o banco nem reiniciou sessões existentes. Fixtures exclusivamente demo. Os testes também preservam notificações privadas, claims, revogação gerenciada, visibilidade, quotas e pesquisa. O cenário que confirma o risco de revogação isolada no Auth continua sendo diagnóstico de pendência, não correção desse risco.

No Windows os globs Node 20 foram expandidos pelo PowerShell em arquivos equivalentes aos globs do CI. Primeiro comando literal não encontrou os globs; foi corrigida apenas a invocação local e a suíte completa passou. Não houve runner GitHub/Linux, cold start remoto, APK/AAB, Play Integrity real, App Attest real, OAuth real, push real ou upload real.

Logs e auditorias: `C:/Users/tiago/Documents/Codex/2026-09-11/pr/work/security-2d/` (`flutter-analyze.log`, `flutter-normal.log`, `flutter-local.log`, `flutter-app-check-local.log`, `node.log`, `worker.log`, `emulator.log`, arquivos audit JSON, `flutter-osv.json`, `pub-maintenance.json` e logs de reprodução). Consultas de auditoria enviaram somente nomes/versões públicos a registros npm/Pub/OSV; nenhuma credencial ou dado Firebase real.

## 8. Arquivos desta etapa

- `lib/core/auth/app_check_setup.dart`: plano de provedores, renovação, guarda de ativação e erro sanitizado.
- `test/app_check_preparation_test.dart`: sete testes novos.
- `functions/package-lock.json`: novo lock local; `functions/package.json` intacto.
- `workers/image-upload/package.json` e `package-lock.json`: override sharp e resolução corrigida.
- `.github/workflows/main.yml`: lock Functions, runtime Worker separado e testes App Check locais obrigatórios.
- `docs/app_check_dependencies_2d.md`: este relatório.

As demais modificações locais pertencem às etapas anteriores e foram preservadas. Não houve Hot Reload porque não foi executada sessão do aplicativo nesta etapa; validação foi automatizada, sem novo acesso à produção.

Segurança 2D preparada e validada localmente. Aguardando autorização para a próxima etapa.
