# Arquitetura — Tudo Aqui Macacu

Este documento descreve a arquitetura real do projeto no momento atual. Ele não representa uma refatoração já concluída. A migração para uma estrutura modular será gradual.

## Arquitetura atual

O projeto Flutter tem uma estrutura simples de arquivos Dart em `lib/`:

- `main.dart`: inicializa Flutter, Firebase, FCM em background e define uma tela amigável para erros de runtime.
- `redesigned_app.dart`: concentra a maior parte do aplicativo, incluindo UI, navegação, modelos, helpers, acesso ao Firestore, Admin, Home, busca, mídia, métricas e telas públicas.
- `admin_audit.dart`: grava logs na coleção `admin_audit_logs`.
- `core/config/firestore_collections.dart`: constantes dos nomes de collections Firestore.
- `core/media/media_url_service.dart`: helpers puros para URLs de imagem, Cloudinary e galeria.
- `core/utils/external_url.dart`: helper puro para validar schemes externos permitidos.

O arquivo `redesigned_app.dart` ainda é o centro do aplicativo. Ele será separado em etapas pequenas, sempre com testes, sem mudar comportamento visual ou schema sem uma etapa própria.

## Inicialização

A inicialização fica em `main.dart`:

- `WidgetsFlutterBinding.ensureInitialized()`;
- `Firebase.initializeApp()`;
- `FirebaseMessaging.onBackgroundMessage()`;
- `ErrorWidget.builder` com `AppRuntimeErrorView`;
- `runApp(const RedesignedApp())`.

A splash/loading Flutter e a preparação inicial ficam em `AppStartupGate`, `SplashLoadingScreen` e `SplashProgressBar` dentro de `redesigned_app.dart`.

## Firebase Auth

A autenticação usa Firebase Auth e Google Sign-In.

Partes principais:

- `AuthGate`: observa `FirebaseAuth.instance.authStateChanges()`.
- `GoogleLoginView`: executa login Google e autenticação Firebase.
- `syncUserProfile()`: sincroniza dados básicos do usuário em `users/{uid}`.
- `isAdminUser()`: ainda mantém compatibilidade por e-mail admin no cliente. A segurança real deve permanecer nas Firestore Rules e Custom Claims.

## Firestore

O app usa Firestore diretamente em muitos widgets e helpers. As constantes de collections agora ficam em `FirestoreCollections`, mas a camada de dados ainda não foi separada em repositories.

Principais usos:

- perfil e favoritos em `users`;
- Home configurável em `home_pages`;
- estabelecimentos em `establishments`;
- conteúdo local em `events`, `news`, `jobs`, `routes`, `alerts`, `offers`;
- utilidades em `utilities`;
- métricas em `metrics`;
- admin/auditoria em `admin_audit_logs`;
- notificações em `notifications` e `push_queue`.

## FCM e Cloud Functions

O FCM no cliente fica em `PushService`:

- pede permissão;
- salva token em `users/{uid}/devices/{token}`;
- remove token no logout;
- ouve mensagens em foreground.

A Cloud Function em `functions/index.js` observa `push_queue/{queueId}` e envia notificações para devices ativos.

## Cloudinary e mídia

O app usa Cloudinary via URL, sem API Secret no Flutter. Os helpers puros ficam em `core/media/media_url_service.dart`:

- normalização de URL;
- otimização Cloudinary;
- parsing de várias URLs;
- deduplicação;
- escolher capa;
- mover/remover imagem.

Campos atuais ainda usados pelo app incluem `logoUrl`, `imageUrl`, `galleryUrls` e `backgroundImageUrl`.

## Home

A Home fica principalmente em:

- `HomeView`;
- `HomePageConfig` em `lib/features/home/models/home_page_config.dart`;
- `WelcomeHero`;
- `HomeSectionsQuickEditor`;
- `HomeEditor`.

A configuração remota usa `home_pages/published` e `home_pages/draft`.

## Empresas

Empresas/comércios aparecem em:

- `Business` em `lib/features/businesses/models/business.dart`;
- `BusinessCard`;
- `BusinessAvatar`;
- `BusinessProfile`;
- `PublishedBusinessStrip`;
- `PublishedBusinessList`.

A coleção principal é `establishments`. A lista local `businesses` ainda existe como fallback/conteúdo inicial.

Fluxo de dados público de empresas:

`Business UI → BusinessRepository → Cloud Firestore / establishments → Business model`.

Permanecem fora do `BusinessRepository`: favoritos, métricas, reviews, propostas de empresa e o CRUD genérico do Admin.

## Utilidades

Utilidades ficam em:

- `UtilityItem` em `lib/features/utilities/models/utility_item.dart`;
- `ResourcesHub`;
- `UtilityCard`;
- `UtilitySubAreaPage`;
- `UtilityInfoPage`;
- `UtilityManager`;
- `UtilityEditor`.

A coleção principal é `utilities`.

## Turismo

Turismo fica em:

- `TouristSpot` em `lib/features/tourism/models/tourist_spot.dart`;
- `TourismHomeView`;
- `TourismCategoryCard`;
- `TourismCategoryView`;
- `TouristSpotCard`;
- `TouristSpotDetailView`.

A coleção usada é `routes`.

## Notícias, eventos e empregos

Conteúdo local reaproveita componentes como:

- `FirestoreContentList`;
- `FirestoreContentScaffold`;
- `LocalContentCard`;
- `LocalNewsView`;
- `CityAgendaView`;
- `LocalJobsView`.

Collections principais: `news`, `events`, `jobs`.

## Busca

A busca usa:

- `GlobalSearchView`;
- `CitySearch`;
- `SearchResultGroup`;
- `SearchResultItem`.

Ela consulta múltiplas collections e também usa dados locais/fallbacks.

## Favoritos

Favoritos ficam em `users/{uid}/favorites`. O app já prefere ID estável quando disponível, especialmente para estabelecimentos.

## Perfil

A área de perfil fica em `ProfileView` e integra login/logout, admin e preferências básicas.

## Admin

O Admin está concentrado em:

- `AdminView`;
- `AdminContentHub`;
- `AdminSettingsHub`;
- `ContentManager`;
- `ContentEditor`;
- `HomeEditor`;
- `UtilityManager`;
- `UtilityEditor`;
- `AdminAuditView`;
- `NotificationComposer`;
- `AdminMetricsView`.

Ainda não existe um `AdminRepository`; os editores fazem Firestore diretamente.

## Métricas e audit logs

- Métricas públicas/comerciais: `recordMetric()` grava em `metrics`.
- Auditoria administrativa: `recordAdminAudit()` grava em `admin_audit_logs`.

## Arquitetura alvo

Direção futura recomendada:

```text
lib/
  core/
    config/
    theme/
    navigation/
    services/
    widgets/
    media/
    utils/

  features/
    auth/
    home/
    businesses/
    utilities/
    tourism/
    content/
    search/
    favorites/
    profile/
    admin/
    notifications/
```

Essa migração será gradual. Não criar pastas ou camadas sem necessidade real. A regra desejada é:

- `core` contém helpers puros, tema, config e widgets genéricos;
- `features` pode depender de `core`;
- `core` não depende de `features`;
- nenhuma feature deve recriar helpers de mídia, URL externa ou nomes de collections.

## Como criar nova feature futuramente

Antes de criar uma nova feature:

1. verificar se já existe collection/campo equivalente;
2. reutilizar `FirestoreCollections`;
3. reutilizar helpers de mídia em `core/media`;
4. preservar campos legados quando existirem;
5. adicionar teste para parsing/helper novo;
6. rodar `dart format .`, `flutter analyze` e `flutter test`.

## O que não duplicar

- nomes de collections em string literal;
- helpers de Cloudinary;
- parsing de galeria;
- validação de URL externa;
- lógica de favoritos por nome/título;
- formulários grandes sem verificar `ContentEditor`/`UtilityEditor`.

