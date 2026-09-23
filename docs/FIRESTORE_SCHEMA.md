# Schema Firestore — Tudo Aqui Macacu

Este documento registra as collections realmente encontradas no projeto. Ele descreve o estado atual e padrões futuros desejados. Não representa uma migração já executada.

## Collections atuais

### `users`

Finalidade: perfil básico do usuário autenticado.

Leitura: próprio usuário e admin.

Escrita: próprio usuário com campos limitados; admin conforme regras.

Campos observados:

- `displayName`;
- `email`;
- `photoUrl`;
- `role`;
- `createdAt`;
- `updatedAt`.

Relações:

- subcollection `favorites`;
- subcollection `devices`.

### `users/{uid}/favorites`

Finalidade: favoritos do usuário.

Leitura/escrita: dono do usuário; admin para leitura/remoção conforme regras.

Campos observados:

- `id`;
- `name`;
- outros campos de compatibilidade a confirmar.

Padrão desejado: usar ID estável do documento do conteúdo favoritado.

### `users/{uid}/devices`

Finalidade: tokens FCM por usuário.

Campos observados:

- `token`;
- `platform`;
- `active`;
- `updatedAt`;
- `lastError` pela Cloud Function quando necessário.

ID: token FCM.

### `home_pages`

Finalidade: configuração dinâmica da Home.

Documentos observados:

- `published`;
- `draft`.

Campos observados:

- `heroTitle`;
- `slogan`;
- `greeting`;
- `location`;
- `searchPlaceholder`;
- `logoUrl`;
- `backgroundType`;
- `backgroundImageUrl`;
- `backgroundStart`;
- `backgroundEnd`;
- `sectionOrder`;
- `sections`;
- `sectionTitles`;
- `sectionLimits`;
- `categoryOrder`;
- `categoryIcons`;
- `updatedAt`;
- `publishedAt`.

### `ads`

Finalidade: banners/anúncios.

Leitura pública quando `published == true`.

Campos observados:

- `title`;
- `description`;
- `imageUrl`;
- `link`;
- `published`;
- `active`;
- `featured`;
- `expiresAt`;
- `updatedAt`.

### `alerts`

Finalidade: avisos locais.

Leitura pública quando publicado.

Campos observados: `title`, `description`, `published`, `active`, `expiresAt`, `updatedAt`.

### `offers`

Finalidade: ofertas/cupons/destaques comerciais.

Campos observados: `title`, `description`, `imageUrl`, `link`, `published`, `active`, `featured`, `expiresAt`, `updatedAt`.

### `contact_messages`

Finalidade: mensagens enviadas por usuários.

Campos observados:

- `name`;
- `contact`;
- `message`;
- `createdAt`.

### `admin_audit_logs`

Finalidade: auditoria administrativa.

Campos observados:

- `action`;
- `collection`;
- `documentId`;
- `label`;
- `adminUid`;
- `adminEmail`;
- `createdAt`.

### `utilities`

Finalidade: utilidades e subáreas da cidade.

Campos observados:

- `id`;
- `title`/`name`;
- `description`;
- `iconKey`;
- `destinationType`;
- `destination`;
- `order`;
- `active`;
- `published`;
- `updatedAt`.

### `polls`

Finalidade: enquetes.

Campos observados: `title`, `description`, `published`, opções e campos auxiliares a confirmar.

### `polls/{pollId}/votes`

Finalidade: votos por usuário.

ID: UID do usuário votante.

Schema detalhado: a confirmar.

### `business_proposals`

Finalidade: propostas/cadastros enviados para revisão.

Campos observados:

- `name`;
- `contact`;
- `description`;
- `createdAt`.

### `notifications`

Finalidade: notificações publicadas/listadas.

Campos observados:

- `title`;
- `description`;
- `link`;
- `targetEmail`;
- `published`;
- `updatedAt`.

### `push_queue`

Finalidade: fila para Cloud Function de envio FCM.

Campos observados:

- `title`;
- `description`;
- `link`;
- `targetEmail`;
- `published`;
- `status`;
- `createdAt`;
- campos de resultado: `sentAt`, `recipients`, `successCount`, `failureCount`, `invalidTokens`.

### `reviews`

Finalidade: avaliações pendentes/revisadas.

Campos observados:

- `userId`;
- `business`;
- `message`;
- `stars`;
- `status`;
- `createdAt`.

### `metrics`

Finalidade: métricas agregadas de uso/comerciais.

Campos observados:

- `action`;
- `target`;
- `targetType`;
- `createdAt`.

### `routes`

Finalidade: turismo, roteiros, trilhas e pontos turísticos.

Campos observados:

- `title`/`name`;
- `category`/`type`;
- `description`;
- `location`/`address`;
- `maps`/`mapsUrl`/`link`;
- `imageUrl`;
- `galleryUrls`;
- `additionalInfo`;
- `published`;
- `updatedAt`.

### `events`

Finalidade: eventos locais.

Campos observados:

- `title`;
- `description`;
- `eventDate`/`date`;
- `location`/`address`;
- `contact`;
- `imageUrl`;
- `galleryUrls`;
- `published`;
- `expiresAt`;
- `updatedAt`.

### `news`

Finalidade: notícias locais.

Campos semelhantes ao conteúdo local: `title`, `description`, `imageUrl`, `galleryUrls`, `published`, `updatedAt`.

### `jobs`

Finalidade: vagas locais.

Campos semelhantes ao conteúdo local: `title`, `description`, `contact`, `published`, `updatedAt`.

### `resolver_subjects`

Finalidade: assuntos do guia/Onde Resolver.

Campos observados: `title`, `description`, `published`, `updatedAt`, demais campos a confirmar.

### `transport`

Finalidade: transporte/ônibus.

Campos observados: `title`, `description`, `published`, `updatedAt`, demais campos a confirmar.

### `useful_phones`

Finalidade: telefones úteis.

Campos observados: `title`, `description`, `phone`/`contact` a confirmar, `published`, `updatedAt`.

### `health`

Finalidade: saúde/conteúdo local de saúde.

Campos observados: `title`, `description`, `published`, `updatedAt`, demais campos a confirmar.

### `establishments`

Finalidade: empresas, comércios e serviços locais.

Model Dart atual: lib/features/businesses/models/business.dart.

Leitura pública quando `published == true`.

Campos observados:

- `name`;
- `category`;
- `subcategory`;
- `description`;
- `address`/`location`;
- `phone`;
- `whatsapp`;
- `instagram`;
- `maps`/`mapsUrl`;
- `logoUrl`;
- `imageUrl`;
- `galleryUrls`;
- `featured`;
- `published`;
- `active`;
- `updatedAt`;
- `createdAt`.

## Campos atuais/legados de mídia

Campos realmente utilizados no código hoje:

- `logoUrl`;
- `imageUrl`;
- `galleryUrls`;
- `backgroundImageUrl`;
- `photoUrl`;
- `coverImage` aparece como referência legada/pouco usada.

## Padrões canônicos futuros

Nenhuma migração foi feita nesta etapa. Preferência futura:

### ID

Usar sempre o ID do documento Firestore como identificador principal.

### Publicação

- `published`;
- `active`;
- `featured`;
- `createdAt`;
- `updatedAt`;
- `publishedAt`.

### Mídia

- `logoUrl`;
- `coverUrl`;
- `galleryUrls`.

Compatibilidade necessária: empresas atualmente podem usar `imageUrl` como capa. O app não deve parar de ler `imageUrl` até existir migração segura.

## Regras para mudanças futuras de schema

1. Adicionar campo novo antes de remover campo antigo.
2. Ler campo novo com fallback para legado.
3. Criar teste do parser antes da migração.
4. Migrar dados em lote controlado.
5. Só remover fallback depois que versões antigas do app não forem mais relevantes.

