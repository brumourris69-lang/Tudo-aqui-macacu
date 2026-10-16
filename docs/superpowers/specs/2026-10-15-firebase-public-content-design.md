# Contratos públicos seguros do Firebase

## Objetivo e limites

Preparar localmente as leituras públicas de Estabelecimentos, Turismo/rotas, Utilidades e Empregos com projeções explícitas, sem acesso a Firebase real, Emulator, migração ou publicação. O aplicativo normal permanece fechado pelo gate `SecureBackend.productionAuthorized == false`; Rules e índices permanecem inalterados.

## Contratos de listagem

`listPublicContent` mantém Auth, App Check, quota por UID, paginação limitada e validação de publicação/atividade/expiração. Sua resposta continua sendo `{items: [{id, data}], nextCursor}`. A projeção passa a selecionar campos por coleção; chaves desconhecidas e mapas arbitrários são sempre omitidos.

| Coleção | Campos públicos projetados | Condições e exclusões |
| --- | --- | --- |
| `establishments` | `name`, `title`, `category`, `subcategory`, `description`, `shortDescription`, `location`, `address`, `artwork`, `iconKey`, `imageUrl`, `logoUrl`, `galleryUrls`, `featured`, `open`, `hours`, `services`, `products`, `additionalInfo`, `promotionTitle`, `promotionDescription`, `published`, `active`, `expiresAt`, `createdAt`, `updatedAt`, `maps`, `mapsUrl` | `maps`/`mapsUrl` somente HTTPS ou `geo:` sem credenciais. `phone`, `whatsapp` e `instagram` somente quando `publicContactApproved == true`, após validação do formato. O marcador nunca é retornado. Outros campos de contato e chaves desconhecidas são omitidos. |
| `routes` | `title`, `name`, `description`, `shortDescription`, `category`, `type`, `location`, `address`, `imageUrl`, `galleryUrls`, `additionalInfo`, `maps`, `mapsUrl`, `link`, `published`, `active`, `expiresAt`, `createdAt`, `updatedAt` | Links e mapas são validados conforme o destino HTTPS/geo; galeria limitada a três URLs HTTPS. Campos desconhecidos e qualquer mapa administrativo são omitidos. |
| `utilities` | `name`, `title`, `iconKey`, `description`, `category`, `order`, `destinationType`, `destination`, `active`, `published`, `expiresAt`, `updatedAt` | O destino é validado por tipo (`internal`, `url`, `phone`, `whatsapp`, `map`). Documento sem `destinationType`/`destination` válidos é omitido; `link` legado nunca é fallback. |
| `jobs` | A allowlist atual e estrita `JOB_FIELDS`, preservada | `contact`, `phone`, `whatsapp`, `link`, `instagram`, `maps`, `mapsUrl`, `additionalInfo`, `salary`, datas não aprovadas e campos desconhecidos seguem ausentes. `job_private` nunca é lido pela projeção pública. |

Os demais tipos consumidos atualmente por `listPublicContent` mantêm o comportamento existente nesta entrega, para limitar regressões. A futura classificação dessas coleções não faz parte deste escopo.

## Contato comercial explícito

O editor administrativo de Estabelecimentos apresenta uma opção desmarcada por padrão para autorizar a exibição pública de telefone, WhatsApp e Instagram. O valor é gravado em `publicContactApproved`. Documentos antigos sem esse marcador não publicam canais de contato automaticamente. Desmarcar a opção remove esses canais da resposta pública sem apagar seus valores administrativos. A validação omite individualmente canais malformados.

## Detalhes públicos

Registrar `getPublicContentDetail` sob o mesmo gate seguro já usado por `listPublicContent`. Aceita exatamente `{collection, id}` para `establishments`, `routes` ou `utilities`; nunca aceita `jobs` nem `job_private`. Exige Auth não vazia e App Check, aplica quota própria por UID, valida ID e coleção, lê um único documento, revalida visibilidade na hora da chamada e retorna `{status: 'available', id, data}` ou `{status: 'unavailable'}`. Erros internos são sanitizados. Usa a mesma allowlist e validação de destino da listagem.

`getSearchTourismSpot` continua demo-only e passa a reutilizar a mesma projeção de `routes`. `getPublicJob` continua demo-only e separado. Nenhuma callable demo é incluída na allowlist normal.

## Flutter

Adicionar um repositório injetável de detalhe público que chama `SecureBackend.invoke('getPublicContentDetail', ...)`. `SecureBackend` só aceita o nome da operação; no app normal o gate existente falha antes de qualquer chamada. Em `searchLocal`, o transporte passa por `LocalUniversalSearchRepository.invokeLocal`, que verifica isolamento/projeto antes da rede. `BusinessRepository.getPublicBusiness` usa esse repositório e deixa de executar `DocumentReference.get`; streams de listagem continuam pelo backend público existente. Não existe fallback direto para Firestore. Administração continua usando seus caminhos atuais protegidos pelas Rules.

## Segurança, compatibilidade e implantação

Não editar Rules, índices, gates, Functions implantadas ou credenciais. Rules atuais ainda permitem leitura direta de documentos visíveis em algumas coleções e clientes antigos podem depender disso; esta entrega apenas remove a leitura direta do cliente atual. O risco legado persiste até uma etapa futura coordenada.

Ordem futura: inventariar/backup; auditar dados e aprovar contatos publicáveis; publicar Functions seguras com gates cuidadosamente autorizados; distribuir cliente compatível e medir erros/adoção; testar contratos e Rules em Emulator; só então aprovar Rules restritivas. Rollback: desativar a nova rota segura e restaurar versão anterior de Functions/app sem remover dados; Rules não são alteradas nesta fase, então não requerem rollback aqui. Não presumir compatibilidade de versões antigas sem evidência de adoção.

## Validação desta entrega

Testes unitários Node cobrem allowlists, validação de destinos, visibilidade, Auth, App Check, quota, contratos e gates. Testes Flutter cobrem decodificação, erro indisponível, uso da operação segura e falha fechada antes da rede. `npm test`, `npm run check`, `flutter analyze --no-pub`, testes Flutter direcionados e `git diff --check` são locais e não iniciam serviços. Os testes integrados do Emulator ficam preparados/pendentes de autorização específica.
