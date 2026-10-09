# Busca Universal — etapa 4G

Integração exclusiva da variante Android `searchLocal`, no projeto
`demo-universal-search`. Produção permanece interface-only. Nenhum deploy,
alteração de regras/backend implantado, commit, push ou APK release.

## Transporte e segurança

`LocalUniversalSearchRepository` implementa o contrato existente, usando o
protocolo HTTPS callable (HTTP somente no loopback do emulador). Antes de cada
pesquisa e abertura de perfil verifica o projeto demo e o canal nativo da VPN.
Endpoint: `http://127.0.0.1:5007/demo-universal-search/southamerica-east1/searchBusinesses`.
Auth usa o ID token da sessão Firebase Auth local existente, sem criar outra
sessão nem trocar usuários cadastrados por visitantes.

Functions Emulator não possui emulador de atestação App Check. O transporte
gera um JWT sintético de teste com validade de cinco minutos, como as suítes de
integração anteriores. Esse token é aceito pelo emulador, **não** por produção.
Não é uma credencial ou token de depuração fixo. A callable continua com
`enforceAppCheck: true` e a política do backend continua exigindo `request.app`.
Ausência e token malformado são rejeitados nos testes. Isso NÃO comprova Play
Integrity/App Attest real; sua validação continua pendente para produção.

A VPN nativa bloqueia IPv4/IPv6 externos antes de Flutter/Firebase iniciarem;
o deny policy Dart continua vigente. Não foram liberados endpoints externos.
Auth 9097, Firestore 8087 e Functions 5007 acessíveis somente por adb reverse.
Imagens externas são rejeitadas pelo adaptador; os fixtures não têm imagens.
O placeholder é usado. A autorização de imagens reais continua pendente.

## Interface e navegação

Reutiliza UniversalSearchBar/Page, UniversalSearchRepository, SearchResult e
BusinessProfile. Dois caracteres, debounce 350 ms, limite de dez resultados,
cursor, erro/retry, limpeza, carregamento e geração para descartar respostas
antigas. Filtros Todos/Comércios/Serviços; demais desabilitados com “em breve”.
Cada resultado é explicitamente apresentado em ambiente de testes fictícios.

BusinessRepository resolve somente o documento selecionado, Source.server,
revalidando published/active/expiresAt com BusinessSearchPolicy. ID original
preservado; indisponível não abre perfil. A Home fornece os mesmos saved e
callback favorite existentes; nenhum modelo/navegação de perfil duplicado.
A busca usa consulta limitada ao índice e revalidação no servidor, sem scan
de estabelecimentos no dispositivo.

## Fixtures

`functions/integration/seed_search_local.js` exige os quatro guardas de ambiente
local antes de inicializar Admin SDK. Grava somente oito documentos demo:

- local-eletronica-vieira: Eletrônica Vieira / Tecnologia
- local-padaria-central: Padaria Central / Onde comer?
- local-oficina-macacu: Oficina Macacu / Serviços
- local-barbearia-modelo: Barbearia Modelo / Beleza
- local-eletricista-modelo: Eletricista Modelo / Profissionais
- local-unpublished, local-inactive, local-expired: inelegíveis

Não chama synchronize manualmente: espera os cinco índices reais criados pelo
gatilho e verifica a ausência dos três inelegíveis. Fixtures estáveis permanecem
no emulador para o usuário conferir. A suíte search_emulator limpa o banco
demo; executar o seed novamente depois dela. Nunca apontar esses scripts para
um projeto real.

## Validação executada

- Flutter Analyze: nenhuma ocorrência.
- 51 testes Flutter (busca UI/contrato/base/infraestrutura/paridade/sessão).
- 8 testes Flutter adicionais com flags locais (VPN, variante, weather/upload).
- 37 testes Node (busca e upload existente).
- 19 grupos reais search_emulator; 13 grupos reais auth_emulator.
  A subprova de política sem App Check dessa suíte anterior é um objeto isolado;
  não configura nem enfraquece a callable executada, testada com proteção true.
- Gatilho: cinco fixtures indexados, três inelegíveis ausentes.
- APK debug compilado/inspecionado e instalado exclusivamente no MEmu.
- Log de bootstrap confirma demo + três serviços + FCM off + VPN ativa.
- Provas sob run-as do UID 10073: HTTP para TEST-NET 192.0.2.1 e
  2001:db8::1 expirou bloqueado; loopback 5007 retornou Not Found esperado.
- Acessibilidade MEmu confirma pesquisa “eletronica” → Eletrônica Vieira,
  abertura do perfil existente e descrição fictícia.
- “modelo”: Comércios → Barbearia Modelo; Serviços → Eletricista Modelo.
- Consulta sem correspondência → Nenhum resultado encontrado.
- Retirada temporária somente do reverse 5007 → erro seguro; reverse restaurado
  e Tentar novamente → Padaria Central. Nenhuma liberação externa ou VPN off.
- Paginação/acentos/limites e segurança validados nas suítes; paginação não foi
  exercitada pela interface do MEmu, pois os cinco fixtures cabem numa página.
- Captura screencap permanece inteiramente preta. Não há aprovação visual.
  A árvore de acessibilidade comprova os elementos, não aparência/pixels.

Não há sessão Hot Reload disponível sob essa VPN; foi recompilado/reinstalado
somente o debug local com o launcher seguro existente. O launcher encerra o
processo local para atualização e restabelece sua VPN antes de iniciar Dart;
nenhuma execução Flutter sem a proteção é permitida.

## Arquivos desta etapa

- lib/features/search/repositories/local_universal_search_repository.dart (novo)
- lib/features/search/pages/universal_search_page.dart
- lib/features/businesses/repositories/business_repository.dart
- lib/redesigned_app.dart (somente passagem dos callbacks à busca)
- functions/integration/seed_search_local.js (novo)
- test/local_universal_search_test.dart (novo)
- lib/features/search/SEARCH_LOCAL_INTEGRATION.md (novo)

Pendências: conferência visual pelo usuário, atestação App Check real antes de
produção e eventual política de imagens. Nenhuma ativação de produção autorizada.
