# Contrato do catálogo público Supabase V2

## Fonte e taxonomia

Firestore continua sendo a fonte oficial. `public_establishment_catalog_v2` é uma projeção pública derivada; esta migration não lê nem copia documentos e não implementa sincronização.

A taxonomia conserva os 19 rótulos da configuração administrativa do aplicativo:

| Categoria | Grupo V2 | Tipo |
| --- | --- | --- |
| Comércio; Onde comer?; Saúde; Imóveis; Veículos; Pets; Beleza; Academias; Educação; Hospedagem; Tecnologia | `commerce` | `establishment` |
| Serviços; Profissionais | `services` | `establishment` |
| Empregos; Turismo; Notícias; Eventos; Promoções; Serviços úteis | `other` | `other_content` |

As três RPCs V2 são para estabelecimentos: nunca retornam `other_content`. A classificação acompanha o catálogo em `lib/redesigned_app.dart`, a política `BusinessSearchPolicy` e `functions/test/fixtures/business_search_parity.json`. O Admin ainda permite escolher categorias de conteúdo ao editar um estabelecimento; como editor e sincronização estão fora desta etapa, esses documentos precisam ser encaminhados a seu módulo próprio ou colocados em quarentena na integração futura. Não serão convertidos silenciosamente nem aparecerão como negócios.

## IDs e campos

`id` conserva exatamente o ID do documento Firestore. A validação segue os limites oficiais: UTF-8, até 1.500 bytes, sem `/`, `.` ou `..` isolados, e sem o padrão reservado `__.*__`, exceto IDs de importação Datastore expostos como `__idN__`. Não exige prefixo, caixa, alfabeto ou remoção de espaços. Fontes: [Firestore quotas and limits](https://firebase.google.com/docs/firestore/quotas) e [Firestore best practices](https://firebase.google.com/docs/firestore/best-practices).

| Campo público da projeção | Tipo / limite | Origem prevista no documento canônico |
| --- | --- | --- |
| `id` | texto Firestore, até 1.500 bytes | ID original do documento |
| `name` | texto obrigatório, 1–140 caracteres | `name`; legado aceita `title` como alias |
| `summary` | texto, até 3.000 caracteres | `shortDescription` ou `description` |
| `category`, `subcategory` | enumeração exata dos 19 rótulos; subcategoria até 120 | categoria/subcategoria originais, sem inferência por palavras |
| `location` | texto opcional, até 240 | `location` ou legado `address` |
| `artwork` | inteiro de 0 a 18 | índice dos 19 sprites presentes no app |
| `image_url`, `logo_url` | HTTPS, até 2.048 caracteres | URLs públicas validadas |
| `gallery_urls` | até 20 URLs HTTPS | `galleryUrls` |
| `featured`, `is_open` | booleanos | `featured`; `open` (ausente conserva o default true do modelo Flutter) |
| `maps_url` | HTTPS ou coordenada `geo:`, até 2.048 | `maps`/`mapsUrl` |
| `hours` | texto até 500 | horário público |
| `services`, `products` | até 40 textos de 160 caracteres cada | listas públicas |
| `additional_info` | texto até 3.000 | informação adicional pública |
| `promotion_title`, `promotion_description` | 180 e 1.000 caracteres | conteúdo promocional público |
| `phone`, `whatsapp`, `instagram` | valores validados e opcionais | só quando `publicContactApproved == true` |

A tabela não contém e as RPCs nunca retornam emails, campos Admin, endereço bruto duplicado, `public_contact_approved`, estados de publicação, atividade, expiração, exclusão, versão, ID de outbox ou texto de indexação. Contatos não aprovados devem estar nulos na projeção; contatos aprovados ainda precisam passar pelos validadores de telefone, WhatsApp e Instagram.

## RPCs

Todas usam `SECURITY DEFINER`, proprietária explícita `postgres`, `search_path` vazio, nomes qualificados, sem SQL dinâmico, execução concedida somente a `anon`, RLS habilitada/forçada sem políticas e nenhum privilégio direto para `anon` ou `authenticated`.

* `search_public_establishments_v2(query, category_group, page_size, cursor_id)`: grupos `all`, `commerce`, `services`; 1–4 termos normalizados de 3–24 caracteres, consulta até 80 caracteres; 1–40 resultados por página. A ordenação por ID sob collation `C` é determinística.
* `list_public_establishments_v2(category_group, page_size, cursor_id)`: mesma faixa de grupos e tamanho; ordena por nome e ID com collation `C`.
* `get_public_establishment_v2(id)`: recebe o ID Firestore sem transformação e retorna zero linhas se o documento não estiver publicamente disponível.

A busca V2 requer termos com pelo menos três caracteres para tornar utilizável o índice trigram; a V1 continua aceitando seu contrato atual. Cursores são posições de paginação, não credenciais nem proteção contra extração de informação pública. Listadores limitam a página, verificam que o cursor aponta para um registro atualmente elegível e aplicam o mesmo grupo. Índices parciais separam ordenação por grupo e listagem global por nome/ID; registros expirados permanecem na projeção interna e podem aumentar o trabalho de varredura até uma reconciliação/manutenção autorizada.

As três operações exigem `published=true`, `active=true`, `deleted_at IS NULL`, validade temporal (`expires_at IS NULL OR expires_at > statement_timestamp()`) e `content_kind='establishment'`. Despublicar (`published=false`) é reversível quando uma nova versão posterior for aplicada. Exclusão lógica usa `deleted_at` e cria um tombstone permanente; eventos posteriores, inclusive versões maiores, não podem ressuscitar o ID.

## Versão, outbox e sincronização pendente

Cada linha guarda `catalog_version` e `outbox_operation_id` apenas para controle interno. Atualizações devem avançar a versão estritamente e trocar o ID de operação. Triggers serializam mudanças pelo ID; o tombstone registra versão, operação e horário e bloqueia replays/ressurreição. As tabelas ficam sem privilégios de cliente. Esta etapa ainda não implementa um escritor/Supabase Edge Function para aplicar eventos nem a reconciliação Firestore-outbox-Supabase. A próxima integração deve aceitar somente projeções allowlisted da outbox, tratar replay idempotentemente e manter o tombstone em uma transação.

## Compatibilidade e riscos

As migrations e RPCs V1 não são substituídas. A projeção V2 possui campos para diretório, busca, detalhes, destaques e perfil. O app piloto Flutter segue ligado à V1 nesta etapa.

O contrato de IDs da função Edge existente ainda limita IDs a `[A-Za-z0-9_-]{1,128}` e as validações administrativas atuais só aceitam as 13 categorias comerciais/serviços; antes da sincronização será preciso ampliar o validador de IDs e roteá-las sem tratar as seis categorias `other` como negócios. O contrato de leitura antigo V1 continua restrito aos IDs `pilot-*` e não deve ser reusado para dados Firestore reais.

Sem sincronização ativa, armazenamento é apenas da migration, índices e testes. Cada linha futura duplicará somente a projeção pública (URLs, não imagens binárias), mais uma coluna de busca e índices GIN trigram, B-tree por grupo/nome/ID, listagem global e expiração. O custo de consultas é limitado por páginas de no máximo 40; buscas de 1–2 caracteres são rejeitadas para evitar caminhos sem seletividade trigram. Uma linha típica deve ocupar poucos KB mais índices; os limites independentes de campos permitem payload agregado da ordem de 100 KB em um registro extremo, antes de overhead de índices. Isso é um limite aproximado derivado dos caps, não uma medição. Tamanho real e custo dependem da distribuição dos documentos, índices e taxa de busca e precisam ser medidos com fixtures antes da migração. Não há dados hospedados disponíveis ou usados para estimar volume real.

Nada nesta etapa publica Rules, migrations, Functions ou dados.
