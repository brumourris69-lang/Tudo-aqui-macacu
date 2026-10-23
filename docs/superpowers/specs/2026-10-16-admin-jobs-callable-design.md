# Callable administrativa para vagas — especificação arquitetural

**Estado:** desenho aprovado; implementação local concluída e verificada
**Data:** 2026-10-16
**Escopo:** desenvolvimento local para o projeto Firebase existente `tudo-aqui-macacu`; nenhuma alteração remota é autorizada por esta especificação.

## 1. Objetivo e limites

Substituir as operações do cliente Flutter que leem ou gravam `job_private` e que gravam `jobs` por uma única callable administrativa. A callable autentica e autoriza cada chamada no servidor e executa em uma transação Firestore as mudanças correspondentes aos documentos públicos e privados.

O endpoint público continua separado: listagens usam `listPublicContent`, e detalhes públicos de estabelecimentos, rotas e utilidades usam `getPublicContentDetail`. O contrato público de vagas continua restritivo e sem fallback para leitura direta do Firestore. Esta especificação não libera `getPublicJob` em produção, não altera `productionAuthorized`, não modifica Rules e não acessa Firebase real.

O código de staging existente será preservado, mas esta entrega não adicionará infraestrutura de staging nem dependerá de outro projeto Firebase. O projeto esperado para a futura configuração normal é `tudo-aqui-macacu`; o gate de produção permanece fechado até uma autorização separada.

## 2. Estado local considerado

- `AdminJobRepository` atualmente implementa `readPrivate`, `create`, `update` e `delete` por acesso cliente ao Firestore. `create`, `update` e `delete` usam batch cliente para os pares `jobs/{id}` e `job_private/{id}`.
- O editor administrativo carrega `job_private` ao editar uma vaga. Se o documento privado estiver ausente, identifica o registro legado e bloqueia a edição; falha de leitura também bloqueia o salvamento.
- `ContentManager` lista `jobs` por stream direto do Firestore. Essa consulta será substituída por páginas da mesma callable, para que o fluxo administrativo de vagas não dependa de leitura direta de `jobs` nem de `job_private`.
- `authorizeCurrentAdmin` já verifica claim Admin, `adminVersion`, documento central `admin_authorizations/{uid}` habilitado/não pendente e versão correspondente; quando recebe o token bruto, verifica também revogação via Firebase Auth.
- O registro de `listPublicContent` e `getPublicContentDetail` já é condicionado pelos gates existentes. `getPublicJob` permanece restrito a staging/demo.
- As Rules locais permitem operações Admin diretas em `job_private`; o Rules candidate previamente revisado mantém essa coleção totalmente bloqueada. A callable usa Admin SDK e, portanto, não requer abrir acesso cliente a `job_private`.

## 3. Contrato da callable

Nome proposto: `manageAdminJob`, região `southamerica-east1`, callable v2.

Todas as solicitações têm envelope estrito `{ operation, jobId?, pageSize?, cursor?, publicData?, privateData? }`. Campos extras, tipos inválidos, IDs com barra, IDs vazios, IDs excessivamente longos e payloads acima do limite definido na implementação são rejeitados. Respostas usam `{ status, jobId?, items?, nextCursor?, publicData?, privateData? }`. Nenhum campo privado é incluído em respostas de listagem ou em qualquer endpoint público.

As cinco operações exigem o mesmo fluxo de Firebase Authentication, App Check, claim Admin e autorização central versionada. A autorização é verificada antes de qualquer consulta de vaga; o helper existente também valida revogação do token.

| Operação | Entrada | Resultado e regra |
|---|---|---|
| `list` | opcional `pageSize` (padrão 30, inteiro entre 1 e 40) e `cursor` | Retorna `{status: "available", items: [{id, summary}], nextCursor}`. Ordena por `updatedAt` descendente, seguida do ID para desempate. `summary` contém somente `title`, `published` e `active`; não contém dados privados. O cursor opaco é base64url de JSON estrito `{updatedAt: {seconds, nanoseconds}, id}`, preservando a precisão nativa do Timestamp do Firestore. Cursor inválido resulta em `invalid-argument`. A ordenação preserva o comportamento atual do `ContentManager`, inclusive a semântica do Firestore para documentos sem `updatedAt`. |
| `get` | `jobId` | Retorna `{status: "available", jobId, publicData, privateData}`. `publicData` contém somente campos editáveis aprovados; `privateData` contém somente os oito campos privados aprovados. Vaga inexistente retorna `not-found`; vaga existente sem `job_private` retorna `failed-precondition` para identificar legado sem fallback. A leitura de ambos ocorre na mesma transação. |
| `create` | `jobId`, `publicData`, `privateData` | Em transação, confirma que os dois IDs ainda não existem e cria ambos. Retorna `{status: "created", jobId}`. Colisão rejeita sem sobrescrever. |
| `update` | `jobId`, `publicData`, `privateData` | Em transação, exige que ambos os documentos existam; aplica patches validados aos dois documentos. Campo privado omitido é preservado; campo privado presente e vazio é removido explicitamente. Documento privado ausente bloqueia a edição como legado pendente. Retorna `{status: "updated", jobId}`. |
| `delete` | `jobId` | Em transação, exige a vaga pública existente e remove `jobs/{jobId}` e `job_private/{jobId}` como uma operação. Documento privado ausente é permitido para exclusão explícita de vaga legada; documento público ausente não autoriza apagar um possível órfão privado. Retorna `{status: "deleted", jobId}`. |

### Payloads aceitos

`publicData` aceita somente campos de apresentação e controle já usados pelo editor de vagas: `title` (140 caracteres), `description` (3000), `imageUrl` (HTTPS, até 2048), `artwork` (inteiro seguro), `galleryUrls` (até 20 URLs HTTPS, cada uma até 2048), `category` (120), `location` e `address` (240 cada), `published` e `active` (booleanos), e `expiresAt`. O contrato representa expiração como string ISO 8601 ou `null`; o servidor valida e converte para Firestore Timestamp. `updatedAt` é sempre definido no servidor e não é aceito na entrada. Campos omitidos em update permanecem intactos. Campos desconhecidos ou campos privados dentro de `publicData` são rejeitados.

`privateData` aceita exclusivamente `contact` (320 caracteres), `phone` (64), `whatsapp` (2048), `link` (2048), `instagram` (2048), `maps` (2048), `mapsUrl` (2048) e `additionalInfo` (3000), cada um como string; payload privado total limitado a 16 KiB. Não há promoção automática para contato público. `schemaVersion` e `updatedAt` são metadados geridos pelo servidor e não aceitos como entrada.

Na recuperação de uma criação rejeitada por colisão, o cliente consulta a mesma callable `get` e compara os campos públicos e privados normalizados com o pedido original. Só trata a operação como concluída se os dois documentos existentes correspondem exatamente. Se a vaga existente for diferente e nenhuma tentativa anterior pudesse ter sido concluída, libera a reserva local e exige um novo ID. Se houve uma resposta ambígua anterior, mantém a reserva e bloqueia a criação para evitar duplicação, orientando o Admin a conferir a vaga na lista. Se a reconciliação falhar por indisponibilidade ou autorização, preserva a reserva.

## 4. Autenticação e autorização

1. A callable declara `enforceAppCheck: true`; chamadas sem contexto App Check válido são recusadas pelo runtime.
2. Exige `request.auth.uid` válido e claim administrativa reconhecida pelo `admin_policy`.
3. Chama `authorizeCurrentAdmin` com o `admin_authorizations` do UID, exigindo `enabled == true`, `pending == false` e `version == token.adminVersion`.
4. Passa o token bruto validado pelo runtime a `firebaseAuth.verifyIdToken(token, true)` para confirmar UID e revogação antes de permitir operações administrativas.
5. Nenhuma autorização por e-mail, estado visual Flutter ou dado enviado pelo cliente substitui essa checagem.
6. Ausência de Auth resulta em `unauthenticated`; ausência de App Check é recusada pelo runtime; claim/versão/registro inválido ou revogado em `permission-denied`; indisponibilidade da autorização central falha fechada como `unavailable`.

## 5. Atomicidade, concorrência e erros

Usar transações Firestore para ler as precondições e gravar/apagar os dois documentos juntos. Em update, a transação confirma existência de ambos antes de aplicar qualquer alteração. Assim, concorrência ou falha de uma gravação não deixa apenas a metade pública ou privada atualizada. A garantia é por vaga/operação; não existe atomicidade global entre chamadas distintas.

Erros externos são mapeados para mensagens controladas sem payload, contato ou documento em logs: `invalid-argument`, `unauthenticated`, `permission-denied`, `not-found`, `failed-precondition`, `aborted` e `unavailable`. Erros inesperados viram `internal` genérico. Logs registram somente operação, resultado/código e identificador de correlação não sensível; não incluem UID, ID do documento, `privateData`, conteúdo de documento ou token.

Uma resposta perdida após commit pode deixar o cliente sem confirmação. O cliente não exibe sucesso sem resposta positiva. Criação recebe ID reservado pelo cliente para permitir repetir a mesma solicitação sem criar outro ID; colisão existente é erro de precondição e requer recarregar a lista, sem tentativa de sobrescrever. A implementação deve testar e documentar esse caso ambíguo.

## 6. Integração Flutter

Manter `AdminJobRepository` como seam de teste e substituir sua implementação por uma implementação callable com `list`, `get`, `create`, `update` e `delete`. `list` retorna páginas de resumos; `get` carrega os dados públicos editáveis e privados. O adaptador não executa operações Firestore em `jobs` nem em `job_private`; toda leitura/escrita administrativa dessas coleções passa pela callable. O transporte usa um callable client injetável para testes e somente o projeto/ambiente ativo expressamente permitido.

`ContentManager` usa a callable apenas quando a coleção é `jobs`; os demais módulos mantêm o comportamento atual. A tela de vagas carrega uma página inicial, oferece ação “Carregar mais” quando `nextCursor` existir e recarrega a primeira página ao retornar do editor. O editor recebe o ID e busca `get`; somente habilita edição após receber ambos os documentos. Erros mantêm o salvamento bloqueado, `failed-precondition` marca o documento como legado e não há fallback para campos privados antigos em `jobs`. Criação, edição e exclusão só exibem sucesso após resposta positiva da callable. Os dados privados permanecem apenas nos controladores administrativos e na resposta autenticada do Admin; não são adicionados ao modelo público, logs, analytics ou navegação pública.

## 7. Registro e gates de ambiente

Registrar `manageAdminJob` junto aos endpoints seguros existentes, sob a mesma decisão de ambiente já usada para `registerPublicContent`: no demo apenas com Emulator e projeto `demo-universal-search`; no projeto normal apenas atrás do gate `SECURE_BACKEND_ENABLED` e de `secureBackendAllowed()`. No Flutter, adicionar a operação somente à allowlist local/demo `LocalUniversalSearchRepository.localOperations`; não adicionar a `SecureBackend.productionOperations` nem à allowlist de staging. Assim, o proprietário pode exercitar o fluxo local isolado, enquanto o app normal e staging falham antes da rede. Não alterar nem ativar `SECURE_BACKEND_ENABLED`, `SecureBackend.productionAuthorized` ou a allowlist de produção. A inclusão da operação no transporte normal e qualquer ativação futura exigem autorização separada.

O endpoint não deve ser registrado como exportação normal de staging nem como função de produção descoberta por um gate novo. A callable não chama serviços externos, não altera Auth/claims e não modifica Rules. Testes unitários injetam dependências; integração Emulator futura exige autorização própria.

## 8. Compatibilidade com Rules restritivas

- A callable usa Admin SDK, que executa no servidor e não depende de permissão cliente para `job_private`.
- `job_private` permanece sem acesso direto de qualquer identidade cliente, inclusive Admin, no Rules candidate acordado.
- As leituras públicas continuam limitadas aos endpoints de projeção; não há fallback Firestore quando rede, Auth, App Check ou gate falhar.
- Todas as leituras e escritas do fluxo administrativo de vagas passam pela callable; o Flutter não depende de leitura direta em `jobs` ou `job_private` para listar, abrir, criar, editar ou excluir vagas.
- Clientes antigos sem transporte callable não poderão administrar vagas caso a Rules publicada restrinja `job_private`; a administração passará a exigir a versão cliente compatível. Sem lançamento do aplicativo, o uso é do proprietário em MEmu, mas não se presume que esteja atualizado.

## 9. Testes e critérios de aceite

### Unitários de Functions

- Cada operação valida envelope, IDs, campos permitidos, tipo e tamanho.
- `list` valida limites de paginação e cursor, usa ordenação estável e nunca inclui dados privados.
- `get` devolve dados editáveis públicos e privados apenas após autorização, lendo ambos de forma consistente.
- Sem Auth, sem App Check e Admin sem claim/versão/registro/revogado são negados antes da leitura de documentos de vaga.
- Admin habilitado e versão correspondente pode executar cada operação.
- `get` retorna os oito campos privados permitidos, a projeção pública editável e nenhum metadado interno não autorizado.
- Create/update/delete operam atomicamente; colisão, vaga ausente, `job_private` ausente e falha transacional não produzem sucesso parcial.
- Nenhuma operação lê ou grava coleções adicionais além de jobs, job_private e admin_authorizations.
- Erros e logs não contêm valores privados nem tokens.

### Testes Flutter

- O repositório chama a callable correta com payloads estritos.
- Nenhuma chamada usa Firestore para ler `jobs` ou `job_private`, nem para gravar vagas.
- A listagem administrativa pagina, mantém a ordenação existente, carrega mais sem duplicar documentos e atualiza após retorno do editor.
- Resposta positiva, indisponibilidade, permissão negada, registro legado e timeout produzem estados corretos; sem resposta positiva não há sucesso visual.
- Fakes preservam os testes do editor e permitem testar retries e erros sem rede.

### Verificação integrada futura

Com autorização separada, usar somente Emulator descartável `demo-universal-search`, fixtures UUID e limpeza por referência própria. Validar App Check local de teste, identidade Admin autorizada/revogada, transações e Rules candidate. Esse teste não certifica App Check Android real nem autoriza produção.

Critério para encerrar desenvolvimento local: todos os testes unitários e estáticos pertinentes passam; nenhum caminho cliente da implementação nova lê ou grava `jobs`/`job_private`; a operação está permitida somente no transporte local/demo; gates de produção e staging continuam fechados; Rules não são alteradas; e a revisão confirma que respostas públicas seguem as allowlists existentes.

## 10. Sequência de implementação proposta

1. Criar testes Node das cinco operações, autorização, cursores e paginação usando dependências injetáveis.
2. Implementar `manageAdminJob` com validação estrita, autorização e transações.
3. Registrar a callable somente atrás dos gates já existentes, sem habilitar produção ou staging.
4. Adaptar `AdminJobRepository` às cinco operações e retirar acesso direto do cliente a `jobs` e `job_private` no fluxo Admin.
5. Adaptar `ContentManager` e `ContentEditor` para páginas de resumos e carregamento do detalhe administrativo por ID, preservando outros módulos compartilhados.
6. Ajustar testes do repositório, paginação e editor para sucesso, falha, legado, retry e ausência de Firestore direto.
7. Rodar testes Node, `npm run check`, testes Flutter direcionados, `flutter analyze --no-pub` e `git diff --check`.
8. Fazer revisão de segurança e compatibilidade. Não iniciar Emulator nesta sequência sem autorização específica.

## 11. Fora do escopo e autorizações futuras

- Nenhuma consulta, gravação, alteração ou teste no Firebase real.
- Nenhum deploy de Functions ou Rules; nenhum ajuste em `productionAuthorized` ou `SECURE_BACKEND_ENABLED`.
- Nenhuma criação de projeto staging, alteração de Auth/App Check, migração de dados ou instalação de dependências.
- Nenhum início/instalação/limpeza de MEmu, build de APK conectado ao real, commit ou push.
- O plano detalhado foi aprovado e executado localmente pelo método subagent-driven. A revisão e verificação final estão registradas no plano existente; não houve operação remota nem ativação de produção.
