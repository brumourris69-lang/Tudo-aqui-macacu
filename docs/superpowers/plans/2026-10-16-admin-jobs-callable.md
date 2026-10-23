# Callable administrativa de vagas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Substituir o fluxo administrativo Flutter de vagas por uma callable única com listagem paginada, consulta, criação, edição e exclusão autorizadas no servidor.

**Architecture:** Uma callable v2 `manageAdminJob` valida Auth, App Check e a autorização Admin versionada e executa operações em `jobs`/`job_private` com projeções e validação explícitas. O Flutter usa um repositório injetável para a callable; `ContentManager` usa páginas só para `jobs` e mantém os outros módulos inalterados. Os gates existentes continuam fechados para o app normal e nenhum recurso remoto é alterado.

**Tech Stack:** Node.js 22, Firebase Admin SDK 13.10.0, Firebase Functions v2, Flutter/Dart e testes locais com fakes.

**Spec:** `docs/superpowers/specs/2026-10-16-admin-jobs-callable-design.md`

## Global Constraints

- Usar somente o projeto existente `tudo-aqui-macacu`; não criar ou configurar outro projeto.
- Não acessar nem modificar Firebase real; não publicar Functions ou Rules.
- Não alterar `productionAuthorized`, `SECURE_BACKEND_ENABLED`, Rules ou allowlists de produção.
- Não expandir staging; preservar o código staging atual.
- Nenhum fluxo Admin Flutter de vagas lê `jobs` ou `job_private` diretamente.
- Todas as cinco operações exigem Auth, App Check, claim Admin e autorização ativa com versão compatível.
- `manageAdminJob` fica na allowlist Flutter local/demo, mas fora das allowlists normal de produção e staging.
- Respostas públicas não incluem dados privados; somente a operação Admin `get` retorna os oito campos privados permitidos.
- Não instalar dependências, iniciar Emulator/MEmu, gerar APK, executar migrações, commit ou push.
- Preservar todo o estado Git e arquivos não rastreados preexistentes.

## Review Focus

- Admin revogado, pendente ou com versão divergente nunca chega a consultar vagas; testar antes de qualquer leitura de `jobs`.
- Cursor adulterado, malformado ou repetido não pula validação, duplica itens nem excede o limite; testar paginação de `list`.
- Registro legado sem `job_private` não preenche os campos a partir de `jobs` e bloqueia `get`/`update`; testar caminho do editor.
- Falha ou resposta perdida de create/update/delete não vira sucesso visual nem atualiza apenas um documento; testar erro e atomicidade no fake de transação.
- O transporte normal permanece bloqueado antes da rede, enquanto a injeção de fake continua funcional; testar gate sem alterar produção.

---

### Task 1: Fixar o contrato e os limites da callable em testes Node

**Files:**
- Create: `functions/test/admin_job_management.test.js`
- Modify: `functions/admin_job_management.js` (criado na Task 2)

**Interfaces:**
- O módulo será construído por `registerAdminJobManagement({ admin, onCall, HttpsError, authorizeAdmin, now })` e retornará `{ manageAdminJob }`.
- O handler aceita `{ operation, jobId?, pageSize?, cursor?, publicData?, privateData?, auth, app, rawRequest }`.
- `authorizeAdmin` segue a assinatura `authorizeCurrentAdmin(auth, {db, firebaseAuth, rawToken})`; o fake retorna autorização válida ou falha controlada e o fake Firestore instrumenta queries, transações e coleções acessadas.

- [x] Escrever testes para rejeitar Auth/App Check ausentes, Admin inválido/revogado, envelope com campos extras, IDs inválidos, tipos/limites inválidos e cursor inválido.
- [x] Escrever testes para `list` limitado a 40, ordenação estável por `updatedAt desc` e ID, cursor, ausência de dados privados e páginas sem repetição.
- [x] Escrever testes para `get` retornando os campos públicos editáveis e somente os oito campos privados; vaga ou documento privado ausente deve produzir o erro definido na spec.
- [x] Escrever testes de create/update/delete para pares de documentos, colisão, legados, limpeza explícita, falha de transação e ausência de coleções fora de `jobs`, `job_private` e `admin_authorizations`.
- [x] Executar `node --test test/admin_job_management.test.js` em `functions/` e confirmar que falha por callable ausente/comportamento não implementado.

### Task 2: Implementar `manageAdminJob` e suas transações

**Files:**
- Create: `functions/admin_job_management.js`
- Modify: `functions/admin_authorization.js` somente se o helper precisar expor uma função pequena reutilizável para autenticação/estado central
- Test: `functions/test/admin_job_management.test.js`

**Interfaces:**
- `registerAdminJobManagement({ admin, onCall, HttpsError, authorizeAdmin = authorizeCurrentAdmin, now = Date.now }) -> { manageAdminJob }`.
- As operações são exatamente `list`, `get`, `create`, `update` e `delete`.
- `list` usa `pageSize` padrão 30 e máximo 40; cursor base64url codifica `{updatedAt:{seconds,nanoseconds},id}` com a precisão exata do Timestamp; resposta contém `{status, items:[{id, summary:{title,published,active}}], nextCursor}`.
- `get` retorna `{status, jobId, publicData, privateData}`; nenhum outro método retorna `privateData`.
- `create` recebe ID reservado pelo cliente, verifica ausência dos dois documentos e cria ambos; `update` exige ambos e aplica patch; `delete` exige a vaga pública e remove o documento privado se existir.

- [x] Executar os testes da Task 1 e confirmar falhas antes da implementação.
- [x] Implementar validação estrita de entrada, códigos/mensagens controlados e enforcement App Check pelo `onCall` v2.
- [x] Reutilizar `authorizeCurrentAdmin`, incluindo verificação do token revogado; garantir autorização antes de qualquer consulta de vaga.
- [x] Implementar projeções server-side: campos públicos editáveis permitidos e campos privados estritamente limitados aos oito da spec; rejeitar campos extras.
- [x] Implementar `list` com limite, ordenação, cursor validado, resumo allowlisted e sem leitura de `job_private`.
- [x] Implementar `get` com leitura consistente de `jobs/{id}` e `job_private/{id}` e falha controlada para legado sem documento privado.
- [x] Implementar `create`, `update` e `delete` em transações; nunca sobrescrever colisões, nunca atualizar parcialmente e nunca apagar órfão privado por uma solicitação de exclusão de vaga inexistente.
- [x] Garantir logs sanitizados sem UID, ID do documento, dados, tokens ou valores de contato.
- [x] Executar `node --test test/admin_job_management.test.js`; todos os cenários da callable devem passar.

### Task 3: Registrar a callable sob os gates existentes

**Files:**
- Modify: `functions/index.js`
- Modify: `functions/package.json` para incluir `admin_job_management.js` na verificação de sintaxe `npm run check`
- Test: `functions/test/secure_staging_environment.test.js` ou o teste de registro de ambiente existente mais adequado

**Interfaces:**
- `index.js` exporta `manageAdminJob` somente junto do registro normal seguro autorizado por `secureBackendAllowed()`; demo segue exigindo Emulator e `demo-universal-search`.
- O caminho staging não exporta essa callable nesta implementação.

- [x] Adicionar teste de registro que confirme a callable presente no contexto autorizado demo e ausente em staging inválido/normal fechado.
- [x] Executar esse teste e confirmar falha antes de alterar o registro.
- [x] Registrar a callable sem mudar os predicados de `secureBackendAllowed`, `stagingBackendAllowed`, `productionAuthorized` ou allowlists.
- [x] Adicionar `node --check admin_job_management.js` a `npm run check` sem alterar versões/dependências.
- [x] Executar os testes de registro e `npm run check`.

### Task 4: Trocar o repositório Flutter por transporte callable injetável

**Files:**
- Modify: `lib/features/jobs/repositories/admin_job_repository.dart`
- Modify: `lib/features/search/repositories/local_universal_search_repository.dart`
- Modify: `test/admin_job_repository_test.dart`
- Create or modify: `test/admin_job_callable_gate_test.dart`

**Interfaces:**
- `AdminJobRepository.list({int pageSize = 30, String? cursor}) -> Future<AdminJobPage>`.
- `AdminJobRepository.get(String jobId) -> Future<AdminJobRecord>`.
- `AdminJobRepository.create({required String jobId, required Map<String,dynamic> publicData, required Map<String,dynamic> privateData}) -> Future<String>`.
- `AdminJobRepository.update({required String jobId, required Map<String,dynamic> publicData, required Map<String,dynamic> privateData}) -> Future<void>`.
- `AdminJobRepository.delete(String jobId) -> Future<void>`.
- `AdminJobPage` contém itens `{id, title, published, active}` e `nextCursor`; `AdminJobRecord` contém `jobId`, `publicData`, `privateData`.
- Invocação callable é uma função injetável; a implementação padrão usa `SecureBackend.invoke('manageAdminJob', data)`. A operação só entra em `LocalUniversalSearchRepository.localOperations`; continua ausente de `SecureBackend.productionOperations` e `stagingOperations`, falhando antes da rede nesses ambientes. ID de create é reservado localmente sem leitura ou escrita Firestore.

- [x] Substituir fakes atuais por testes para os cinco métodos, nomes de operação e contratos de request/response.
- [x] Adicionar teste que inspeciona o transporte e confirma ausência de chamadas Firestore a `jobs`/`job_private`.
- [x] Adicionar testes do gate: operação local/demo allowlisted, operação ausente das allowlists normal e staging, e chamada normal recusada antes da rede; fake do repositório invocado sem rede.
- [x] Executar `flutter test --no-pub test/admin_job_repository_test.dart test/admin_job_callable_gate_test.dart` e confirmar falhas.
- [x] Implementar DTOs, tradução de erros callable e repositório com invoker injetável; normal não faz fallback.
- [x] Adicionar a callable à allowlist demo local, sem tocar nas allowlists de produção ou staging.
- [x] Serializar `expiresAt` para ISO 8601 ou `null`, retirar `updatedAt` do payload de cliente e preservar o patch de campos omitidos.
- [x] Executar os testes do repositório e gate; confirmar que create mantém o ID em falhas ambíguas, reconcilia uma criação já confirmada, libera colisões comprovadamente anteriores à tentativa e bloqueia uma criação potencialmente duplicada quando o payload existente diverge.

### Task 5: Integrar páginas no `ContentManager` e detalhe Admin no editor

**Files:**
- Modify: `lib/redesigned_app.dart`
- Modify: `test/content_editor_persistence_test.dart`
- Create: `test/content_manager_jobs_test.dart`

**Interfaces:**
- `ContentManager` usa `AdminJobRepository.list` somente quando `collection == 'jobs'`; os demais tipos continuam no stream existente.
- Item selecionado abre `ContentEditor` com `jobId` e dados resumidos; o editor chama `AdminJobRepository.get` para buscar os dados atuais.

- [x] Criar testes de widget para loading, erro com nova tentativa, lista vazia, paginação “Carregar mais”, ordenação, ausência de duplicatas e retorno do editor recarregando a primeira página.
- [x] Criar testes do editor para carregar dados atuais, bloquear salvamento em falha/legado, preservar privados omitidos, limpar campos privados explicitamente e não mostrar sucesso antes da resposta.
- [x] Executar `flutter test --no-pub test/content_manager_jobs_test.dart test/content_editor_persistence_test.dart` e confirmar as falhas dos fluxos novos.
- [x] Criar uma ramificação específica para a coleção `jobs` dentro de `ContentManager`, sem mudar o fluxo de outras coleções.
- [x] Adaptar `ContentEditor` para receber ID/dados Admin sem `DocumentSnapshot` para vagas; manter a assinatura e o caminho existente para outras coleções.
- [x] Ao voltar de criar/editar/excluir, atualizar a página inicial; manter filtros/estado se já existentes e evitar consultas duplicadas por rebuild.
- [x] Executar os testes direcionados e verificar que as telas comuns não mudaram de comportamento.

### Task 6: Verificação local consolidada e revisão

**Files:**
- Review: todos os arquivos listados nas Tasks 1–5
- Test: suítes Node e Flutter pertinentes

- [x] Executar em `functions/`: `npm test` e `npm run check` usando Node 22 se já disponível; registrar a versão efetivamente usada.
- [x] Executar na raiz Flutter: `flutter analyze --no-pub` e os três comandos de testes direcionados das Tasks 4–5.
- [x] Executar `git diff --check` e revisar o diff para confirmar que Rules, gates de produção, staging e módulos não relacionados não foram alterados.
- [x] Confirmar por busca estática que o fluxo Flutter Admin de vagas não consulta `jobs` nem `job_private` diretamente.
- [x] Reportar separadamente testes aprovados, falhos, ignorados e integração Emulator pendente. Não iniciar Emulator, acessar Firebase real, gerar APK, instalar MEmu, fazer migração, commit ou push.

## Verification record

- Node.js `v22.23.3`: `npm test` passed (162 passed, 0 failed, 0 skipped); `npm run check` passed.
- Flutter: `flutter analyze --no-pub` passed; focused repository tests passed (71); the full normal suite passed (495 passed, 20 skipped) using `--exclude-tags=search-local`. The searchLocal-tagged tests were excluded because this task did not authorize starting the demo Emulator or local service environment.
- `git diff --check` passed. Static review confirmed the Admin jobs repository has no Firestore dependency and `manageAdminJob` remains outside production and staging allowlists; `productionAuthorized` remains false.
- Final independent read-only review approved the implementation. No Firebase Emulator, real Firebase, deployment, migration, APK build, commit, or push was performed.
## Handoff

A execução foi autorizada pelo proprietário para o método subagent-driven. As Tasks 1–5 foram delegadas com um único escritor por tarefa e revisões independentes. A Task 6 consolida testes, corrige regressões diretamente relacionadas e atualiza este plano com os resultados observados. Nenhuma etapa inclui acesso Firebase real, Emulator, mudanças em Rules ou gates de produção, geração de APK, migração, commit ou push.
