# Contrato do escritor privado do catálogo V2

Esta nota registra o contrato antes da migration incremental da Etapa 07.4. O Firestore continua sendo a fonte oficial; as funções abaixo só gravam a projeção pública já validada no PostgreSQL.

## Assinaturas e resultados

- `public.apply_establishment_projection_v2(p_projection jsonb) returns text`: recebe a projeção completa produzida por `projectCanonicalEstablishment`, incluindo `catalog_version` e `outbox_operation_id`. Aceita exclusivamente as chaves V2 explícitas; exige `deleted_at: null`. Retorna `applied` ou `replayed`.
- `public.apply_establishment_tombstone_v2(p_tombstone jsonb) returns text`: recebe somente `id`, `catalog_version`, `outbox_operation_id` e `deleted_at` de uma exclusão lógica. Retorna `applied` ou `replayed`.

As falhas usam SQLSTATE previsível e mensagem genérica; a função não registra nem devolve payloads. A projeção rejeita chaves extras, inclusive campos administrativos ou privados. A despublicação reversível permanece uma projeção normal com `published=false`; somente `deleted_at` não nulo aciona o tombstone permanente.

## Papel e exposição

O `supabase/config.toml` expõe apenas `public` e `graphql_public`. Para manter a chamada futura pelo gateway RPC existente sem ampliar schemas expostos, as funções ficam em `public`, sob propriedade `postgres`, com `SECURITY DEFINER` e `search_path` vazio. O acesso é privado por ACL: `PUBLIC`, `anon` e `authenticated` não recebem `EXECUTE`; apenas o papel servidor `service_role` recebe `EXECUTE`. O acesso direto de `service_role` às duas tabelas V2 também é revogado, deixando a função como único caminho de escrita. Sua credencial permanece exclusivamente no backend; nunca deve ser enviada ao Flutter.

## Concorrência e idempotência

Cada chamada adquire `pg_advisory_xact_lock(hashtextextended(id, 0))`, o mesmo lock de ID já usado pelos gatilhos V2, e um segundo lock de dois inteiros reservado ao operation ID antes de consultar tombstone e linha atual. O primeiro serializa operações concorrentes para o mesmo ID e coordena com os gatilhos; o segundo impede reutilização concorrente de um operation ID em IDs diferentes. Os formatos de lock distintos mantêm as duas classes separadas e ambos permanecem até commit/rollback. Linha atual e tombstone são então lidos com `FOR UPDATE` quando existentes, e a comparação de versão e a gravação ocorrem na mesma transação.

Versão menor é rejeitada. Versão igual só é replay quando operação e conteúdo integral coincidem; caso contrário é conflito. Versão maior atualiza uma linha não tombstonada com nova operação. Tombstones são imutáveis: replay exato é aceito, enquanto qualquer publicação ou tombstone diferente para o mesmo ID é rejeitado. A função de projeção não pode criar nem atualizar uma linha tombstonada.

O lock e as regras de replay serão exercitados pelo SQL e inspecionados estaticamente. Concorrência de sessões independentes ainda requer execução integrada em PostgreSQL; esta etapa não inicia Docker.
