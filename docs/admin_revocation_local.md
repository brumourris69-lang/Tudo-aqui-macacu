# Segurança 1B.1 — revogação administrativa local

## Escopo e risco encontrado

Somente `demo-universal-search`; Auth 9097, Firestore 8087 e Functions 5007.
Nenhuma conta, claim, configuração ou dado real foi acessado ou alterado.
As Rules canônicas e o fallback de produção continuam como estavam na Fase A.
O Worker não foi implantado nem chamado na Cloudflare. Seus testes usam JWTs
assinados por chaves efêmeras locais, mocks e transporte ao Firestore Emulator.

Antes, um token com `admin: true` podia continuar autorizando todas as operações
que dependem de `admin()` nas Rules: estabelecimentos, notícias, eventos,
configuração da Home, notificações públicas/privadas, fila de push e demais
coleções administrativas. O upload callable e o Worker também aceitavam a
claim antiga. Remover a claim e revogar refresh tokens não fazia esses serviços
consultarem automaticamente a revogação de sessões.

## Política preparada

Além de usuário não anônimo e claim booleana `admin: true`, exigir:

- Claim `adminVersion` não vazia.
- Documento `admin_authorizations/{uid}` existente e atual.
- `enabled: true`, `pending: false`, `version` igual à claim.

Cada concessão usa UUID novo. Uma nova concessão não reativa tokens anteriores.
O documento tem somente enabled, pending, version, operationId e updatedAt.
Clientes não podem escrever nem listar essa coleção. Somente o próprio titular
não anônimo com claim Admin pode ler seu documento, inclusive quando desabilitado,
para a UI e para validação do Worker. Não há leitura pública de permissões.
Essa leitura não usa `admin()` para evitar dependência circular nas Rules.

### Concessão e revogação confiáveis

A CLI local e suas proteções de projeto/hosts continuam as mesmas, com dry-run
padrão e confirmação explícita. Não há endpoint para conceder/revogar Admin.

1. Validar alvo, operador, motivo e confirmação; criar auditoria prepared.
2. Transação Firestore: desabilitar estado, gerar versão e marcar pending.
   Se houver operação pendente, recusar sobreposição antes de alterar Auth.
3. Alterar claims preservando as demais; revogação remove admin/adminVersion e
   eventual role administrativa legada, e revoga refresh tokens.
4. Transação com conferência de operationId: finalizar estado. Somente concessão
   reabilita; revogação permanece desabilitada.
5. Registrar auditoria applied. Falha parcial registra failed-review-required.

O bloqueio entra em vigor quando a transação do passo 2 é confirmada, antes de
alterações em Auth. Não existe transação distribuída Auth/Firestore. Falha em
Auth após esse passo mantém estado desabilitado/pending. Recuperação exige
operador confiável conferir Auth, estado e auditoria, e reconciliar manualmente
com versão nova; não apagar pending nem reabilitar automaticamente. A CLI
intencionalmente não oferece bypass desse bloqueio.

Se o primeiro commit Firestore não puder ocorrer, a revogação NÃO foi concluída.
O procedimento informa falha; não se deve anunciar sucesso. Após confirmação do
commit, estado ausente, pendente, inválido ou indisponível nunca concede acesso.
Mudanças de claims concorrentes por outras ferramentas ainda devem ser evitadas:
Firebase Auth não fornece compare-and-swap das custom claims. Toda alteração
administrativa deve seguir o procedimento central, sem manipulação avulsa.

## Verificação por componente

- **Rules locais:** `admin()` consulta o estado atual; a claim isolada não basta.
  O predicado cobre todos os caminhos administrativos existentes. Nenhuma outra
  política de coleção foi ampliada. Rules não executam Admin SDK.
- **Functions:** modo estrito do upload exige `authorizeCurrentAdmin`; lê estado
  sem cache de aplicação. O callable passa também o token original para
  `verifyIdToken(token, true)` quando disponível. Ausência do verificador de estado,
  erro, token revogado ou resultado diferente de true impedem upload.
  `requireAdmin` continua sendo apenas pré-checagem de identidade/claim, não
  autorização suficiente de uma operação. Novas operações privilegiadas deverão
  usar o verificador completo. Busca pública não ganha exigência de Admin.
- **Worker:** primeiro verifica assinatura/issuer/audience/expiração e claim;
  aplica rate limiter; consulta Firestore REST com o próprio ID token. URL e
  projeto são fixos, sem credencial de serviço e sem novo endpoint público.
  As Rules autorizam somente leitura do estado do próprio titular. HTTP 403/404
  negam acesso; timeout, erro ou resposta inválida falham fechados. Não há cache
  permissivo. Revalida novamente após streaming, antes do envio ao Cloudinary.
  Essa verificação é de autorização central; não é introspecção de sessões Auth.
- **Flutter local estrito:** acompanha somente seu estado; cache offline,
  erro, versão divergente e estado desabilitado removem capacidade administrativa
  da UI. Troca de conta/logout invalidam respostas anteriores. Botões não são
  mecanismo de segurança; Rules/servidor continuam independentes.

## Custos e consistência

- Rules: até uma leitura adicional do documento de autorização por avaliação
  administrativa, além da operação original. Leituras dependentes podem ser
  cobradas mesmo se a operação for negada. Repetições no mesmo pedido podem ser
  reutilizadas pelo motor; não presumir isenção ou cache entre requisições.
  Considerar limites de chamadas das Rules em consultas, batches e transações.
- Functions: uma leitura pontual de estado por upload estrito, mais verificação
  Auth de revogação quando há token original. Sem busca de coleção inteira.
- Worker: até duas leituras pontuais por upload aceito, pela revalidação antes
  do efeito externo; normalmente uma quando negado no primeiro teste. Rate limit
  precede leituras de estado para limitar abuso/custo. Sem cobrança de nova
  Function de introspecção. Permanecem custos normais de Worker/Firestore/upload.
- Flutter: listener de um documento para sessão Admin estrita; leitura inicial,
  atualizações e reconexões conforme cobrança do Firestore. Visitante/comum
  sem claim não abre esse listener.
- Concessão/revogação bem-sucedida: normalmente quatro escritas Firestore
  (auditoria preparada, estado bloqueado, estado final, auditoria final), duas
  leituras em transações e operações Auth. Retries/falhas podem adicionar operações.
  Dry-run não grava Firestore. Valores monetários dependem da região/plano/volume;
  nenhum recurso pago foi ativado nesta etapa.

Firestore é a fonte central com leitura atual, sem TTL de autorização. Perda de
disponibilidade reduz disponibilidade do Admin em vez de permitir acesso. Não
há promessa de cancelar operações já autorizadas/em execução antes do commit:
upload já enviado, escrita concluída, dados já baixados e push já enfileirado
legitimamente não são desfeitos. A checagem final do Worker reduz a janela de
recepção, mas nenhum check separado torna um serviço externo transacional.

## Testes e evidências

- Flutter Analyze: sem problemas.
- Suíte Flutter normal: 249 testes aprovados.
- Flutter com `ADMIN_CLAIMS_ONLY=true`: 10 testes relevantes aprovados.
- Node Functions/Worker: 63 testes aprovados, incluindo falhas de comunicação,
  autorização ausente, versão antiga, pending, falha parcial de Auth e revogação
  durante recebimento do upload. Compatibilidade legada de produção preservada.
- Auth/Firestore Emulator reais: 9 cenários administrativos. Admin autorizado,
  comum, visitante, e-mail sem claim, elevação de privilégios, token antigo após
  revogação, token renovado, regrant, estado ausente e escrita do estado negada.
  O teste também exercita o leitor REST do Worker contra Rules reais locais,
  redirecionando somente seu transporte para localhost/demo, inclusive com o
  token original após revogação. O callable real `uploadHomeImage` foi chamado
  somente com payload inválido: Admin autorizado chega à validação de entrada;
  token antigo após revogação é bloqueado antes dela. Nenhuma imagem foi enviada.
- Notificações: 12 cenários de integração Auth/Firestore/Functions aprovados,
  com push FCM simulado localmente. Destinatário mantém leitura privada; terceiro
  e Admin revogado não ganham acesso. Público continua público.
- Emulator não reproduz Google/Cloudflare de produção. Não foi feita aprovação
  visual no MEmu nem Hot Reload; nenhuma sessão Flutter interativa estava ativa.

## Pendências para Fase B

A base local é adequada para planejar a Fase B, não para ativá-la automaticamente.
Exige nova autorização, revisão do UID correto e acesso de recuperação, procedimento
confiável de produção (a CLI atual recusa produção), provisionamento do estado e
claim com a MESMA versão, renovação do token e validação de painel/edição/upload.
Só então trocar Rules, ativar modo estrito de Functions/Worker/Flutter e remover
fisicamente os fallbacks, com rollout coordenado para não bloquear o Admin.
Validar comportamento real de REST/App Check/regras, latência, limites e custos.

Enquanto o fallback normal permanecer, não há garantia de revogação central na
versão de produção; isso foi deliberadamente preservado por instrução do usuário.
Revogar/desabilitar somente pelo Console/Auth ou por ferramenta que não atualiza
o estado NÃO garante bloqueio imediato nas Rules/Worker. Deve-se usar o procedimento
central confiável, inclusive em recuperação de incidente.

Firebase Admin SDK/contas de serviço, IAM e acesso ao Firebase Console NÃO são
controlados pela claim do aplicativo nem por Rules. Seus acessos precisam de
gestão IAM própria; não foram alterados. Nada desta etapa revoga credenciais de
infraestrutura. Novos endpoints Admin precisam adotar explicitamente o verificador.

## Arquivos desta etapa

Criados:

- `functions/admin_authorization.js`
- `functions/test/admin_revocation.test.js`
- `workers/image-upload/src/admin-state.js`
- `workers/image-upload/test/admin-state.test.js`
- `docs/admin_revocation_local.md`

Modificados, preservando as alterações locais anteriores:

- `firestore.claims-local.rules`
- `functions/admin_claim_management.js`
- `functions/home_image_upload.js`
- `functions/index.js`
- `functions/test/admin_policy.test.js`
- `functions/test/business_search.test.js`
- `functions/integration/admin_claims_emulator.js`
- `functions/integration/notifications_emulator.js`
- `workers/image-upload/src/index.js`
- `workers/image-upload/test/worker.test.js`
- `lib/core/auth/admin_authorization.dart`
- `lib/redesigned_app.dart`
- `test/admin_authorization_test.dart`
- `docs/admin_claims_migration.md`

`firestore.rules`, `firebase.json`, configurações normais do Worker, Admin e
demais áreas não receberam alterações adicionais nesta etapa. Não houve deploy,
claim real, dado real, APK, commit ou push.

## Atualização local — Segurança 1C

A política versionada de autorização e revogação foi preservada. As Rules
locais agora também restringem conteúdo público inelegível e exigem Admin
para listagens diretas. A nova integração confirmou que o token antigo de
Admin revogado não permite ler conteúdo restrito nem listar coleções.
Consulte [a matriz de visibilidade e os testes](content_visibility_local.md).

## Referências oficiais consultadas

- Sessões/revogação: https://firebase.google.com/docs/auth/admin/manage-sessions
- REST com ID token e Rules: https://firebase.google.com/docs/firestore/use-rest-api
- Chamadas e limites das Rules: https://firebase.google.com/docs/firestore/security/rules-conditions
- Cobrança: https://firebase.google.com/docs/firestore/pricing
