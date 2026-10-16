# Busca Universal: contrato multiconteúdo

Contrato local para `searchLocal`. A pesquisa segue restrita ao Firebase Emulator
`demo-universal-search`; o entrypoint de produção não exporta esses handlers.

| Tipo | Coleção original | Documento do índice | Filtro habilitado | Destino |
| --- | --- | --- | --- | --- |
| `establishment` (`business`) | `establishments` | `establishments__{id}` | Todos, Comércios, Serviços | `businessProfile` |
| `tourism` | `routes` | `routes__{id}` | Todos, Turismo | `touristSpotDetail` |
| `news` | `news` | `news__{id}` | Todos, Notícias | `newsArticle` |
| `jobs` | `jobs` | `jobs__{id}` | Todos, Empregos | `jobDetail` |
| `events` | `events` | `events__{id}` | Todos, Eventos | `eventDetail` |
| `utilities` | `utilities` | Preparado, sem indexador | Desabilitado | `unavailable` |

`SearchResult.identity` combina coleção e ID. O índice compartilhado usa IDs
determinísticos por coleção; IDs iguais em coleções diferentes não colidem.
`Todos` percorre uma única sequência paginada pelo ID do documento do índice,
sem juntar listas no aplicativo.

O backend normaliza acentos e espaços, consulta prefixos e limita o índice a 64
termos de até 24 caracteres. Turismo inclui título, categoria/tipo, descrição e
localização. Notícias inclui título, categoria, resumo, localização e informação
adicional pública, limitando os textos antes da extração de termos. A projeção do
índice não copia campos administrativos. Alterações em `routes` e `news` são
sincronizadas por gatilhos locais idempotentes, que leem o documento atual em
transação e removem a projeção quando o conteúdo deixa de ser público. `jobs`
usa o mesmo processo e o índice `jobs__{id}`.

Cada candidato é revalidado na coleção de origem antes de retornar. Notícias e
rotas exigem `published == true`; `active`, quando presente, precisa ser `true`;
e `expiresAt`, quando presente, deve ser timestamp futuro. Turismo revalida de
novo antes de abrir `TouristSpotDetailView`, com o ID original. Eventos revalida
`events/{id}` por `getSearchEvent` com Auth, App Check e quota, retornando somente
título, descrição, categoria, data de realização, local e capa. A data de
realização não é usada como expiração. `EventDetailPage` mantém a busca na pilha.

Notícias também usa uma tela individual segura; Eventos abre sua tela própria;
Empregos abre `JobDetailPage` após `getSearchJob` revalidar o documento original.

Auth e App Check continuam exigidos no ambiente local. A quota de pesquisa mantém
30 chamadas/minuto e intervalo mínimo de 350 ms por UID. A resolução de Turismo,
Notícias, Eventos e Empregos usam contador separado, com limite de 60/minuto e intervalo de 200 ms. A busca
mantém no máximo 40 candidatos e 20 resultados por chamada. Imagens de busca
continuam omitidas quando não passam pela política de autorização atual; a VPN
local bloqueia carregamentos externos.

Empregos indexa título e descrição e, quando os campos públicos existem, empresa,
localização, categoria e modalidade/tipo (`employmentType` ou `type`). `contact`
e campos administrativos não entram no índice nem na resposta. A elegibilidade
usa `published == true`, `active` opcional verdadeiro e `expiresAt` opcional
futuro; o prazo de candidatura não é expiração. O card usa o ícone existente e
mostra somente os metadados disponíveis. A tela segura não abre WhatsApp ou
links externos. `contact` não é divulgado: o Admin o rotula “Contato ou
responsável”, sem política explícita que autorize sua divulgação como contato
de candidatura.
Utilidades segue desabilitada.
