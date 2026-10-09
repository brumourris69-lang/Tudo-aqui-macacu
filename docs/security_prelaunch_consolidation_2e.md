# Segurança 2E — arquitetura pré-lançamento consolidada

Data: 09/10/2026. Contexto fornecido pelo proprietário: aplicativo não lançado, um único testador, registros de desenvolvimento, sem clientes reais ou versões públicas antigas a preservar.

## Resultado e limites

Consolidada localmente a política administrativa, as Rules canônicas, as listagens públicas e as operações de usuários. Não há mais autorização por e-mail/role nem fallback de gravação direta no build normal. Busca Universal e isolamento continuam no ambiente autorizado.

**Não é uma autorização para publicar.** O build normal passa a depender dos gateways seguros e permanece bloqueado para essas operações até a configuração/ativação autorizada. Isso é intencional: não conservar uma rota insegura para compensar backend ainda não implantado. O `searchLocal` continua funcional com os mesmos contratos no Emulator. Não houve alteração remota, Console, conta real, migração, remoção de registros existentes, release, commit, push ou workflow remoto.

As etapas 1A–2D foram preservadas. Seus relatórios são registros históricos: referências antigas à Fase A com fallback, Rules divergentes e gravações normais diretas foram superadas por este documento. Compatibilidade com aplicativos antigos distribuídos deixa de ser requisito, conforme a nova instrução; preservação dos dados existentes continua obrigatória.

## 1. Arquitetura consolidada

| Fronteira | Contrato definitivo preparado |
| --- | --- |
| Identidade | Firebase Auth; Google na interface atual, e-mail/senha como suporte SDK/testes; visitante anônimo não é conta cadastrada nem Admin |
| Admin | Token válido, `admin: true`, `adminVersion` não vazio e estado `admin_authorizations/{uid}` com `enabled: true`, `pending: false`, versão correspondente |
| Firestore | `firestore.rules` é a fonte canônica do build normal e do Emulator; estado de Admin não pode ser escrito por clientes |
| Functions | Claim e estado atual, com verificação de revogação Auth nas operações administrativas que recebem token bruto; gateways públicos/de usuário exigem Auth, App Check, validação e quotas |
| Worker | JWT verificado, claim booleana e estado lido por REST com o token do próprio chamador; revalidação antes do upload; nenhuma condição por modo legado |
| Conteúdo público | Listagens paginadas no backend com estado atual, relógio do servidor e projeção de campos públicos; Rules bloqueiam listagens diretas para não-Admin |
| Documento público selecionado | Get direto autorizado pelas Rules somente se elegível; BusinessRepository também revalida antes de abrir o perfil |
| Usuário | Perfil legítimo validado por Rules; favoritos, contato, propostas, reviews, métricas, votos e dispositivos pelo gateway com autoria e datas derivadas no servidor |
| Notificações | `notifications` pública, `private_notifications` por UID; destinatário autorizado e Admin podem ler privadas publicadas |
| Busca | Índice privado, candidatos limitados, revalidação da origem e ID original; interface e ativação continuam como antes |

`SecureBackend` centraliza o transporte das listagens e operações de usuários. Em `searchLocal`, reutiliza o transporte isolado existente. O transporte SDK Functions da variante normal está preparado, mas `productionAuthorized` permanece false. No servidor, os gateways podem ser registrados no demo ou, futuramente, com projeto oficial e opt-in explícito `SECURE_BACKEND_ENABLED=true`, sem flags de Emulator. Nenhuma configuração desse opt-in foi aplicada. Essa trava de ativação não é um mecanismo alternativo de autorização administrativa.

## 2. Legado identificado e removido

Referências foram rastreadas em Flutter, Rules, Functions, Worker e testes antes das alterações. As implementações substitutas eram as políticas estritas e gateways já testados nas etapas anteriores.

- Removidos `legacyAdminEmail`, `adminEmail` de autorização, `ADMIN_CLAIMS_ONLY`, opção de ignorar estado atual no Flutter e atalho por e-mail.
- Removidos `isLegacyAdmin`, `claimsOnlyMode`, `legacy-transition` e condicionais do Worker que deixavam de consultar o estado administrativo no modo normal.
- Substituído o conteúdo permissivo de `firestore.rules` pela política estrita já preparada, incluindo `affectedKeys()`, operações de usuários protegidas, estado versionado e visibilidade.
- Removidos `_productionQuery` e listeners públicos normais que só filtravam publicação/ativação parcial. Todos os consumidores de `getPublicContent`/`watchPublicContent`, inclusive notificações públicas, utilizam a mesma política backend.
- Removidos dez callbacks de escrita direta dos pontos de contato, propostas, avaliação, voto, favoritos, dispositivos e métricas. A assinatura `writeUserOperation` não aceita mais callback de fallback.
- Removidas expectativas de teste que concediam Admin por e-mail/role ou esperavam escritas diretas de dispositivos. Os testes agora exigem claim/estado, gateway e vínculo de UID/token.

Não se alterou o design da Home, busca, Admin ou perfil de estabelecimento. Mudanças no arquivo principal Flutter limitam-se aos fluxos de autorização/dados. Falha na remoção do dispositivo pelo backend não impede limpeza local do token e logout.

## 3. Legado mantido com justificativa

- `firestore.claims-local.rules` e `firestore.search-local.indexes.json`: cópias de compatibilidade dos testes/documentação, idênticas às fontes canônicas por teste obrigatório. Nenhuma configuração de execução aponta para elas; não constituem políticas alternativas.
- Campos opcionais ausentes de ativação/validade preservam os contratos de cada coleção. Campos presentes inválidos falham fechados. Isso evita inventar dados ou migrar registros para manter leitura legítima.
- `targetEmail: ''` permanece como marcador vazio de comunicado público. Não contém destinatário privado. Documentos antigos com e-mail não vazio ou classificação ausente continuam restritos ao Admin; não foram convertidos, apagados ou republicados.
- Resolução de e-mail em **filas antigas privadas** permanece exclusivamente no backend. Ausência/ambiguidade de destinatário retorna nenhum dispositivo, jamais broadcast. Novas filas criadas por cliente/Admin aceitam UID ou broadcast, não e-mail de destinatário.
- A UI de criação pode continuar recebendo e-mail para localizar a conta pelo Admin; o documento privado e a nova fila são gravados com UID. Isso não concede permissões pelo e-mail.
- Chaves antigas de favoritos e campos desconhecidos de perfis existentes permanecem quando válidos/imutáveis; não são fontes de autorização.
- Adaptador de snapshot usado por fixtures do carrossel permanece referenciado; não é uma consulta pública de produção.
- Scripts demo, VPN, ferramentas de captura, testes adversos, isolamento nativo e flavor `searchLocal` foram preservados. Não foram removidos por serem exclusivos de desenvolvimento.

## 4. Admin: provisionamento, revogação e recuperação

Flutter usa claim + versão + estado servido pelo Firestore, recusando cache, erro de comunicação, estado ausente, pendente, desabilitado ou versão antiga. Claim sem versão é recusada antes de consultar o estado. Rules verificam o mesmo contrato por `get`; Functions e Worker usam `currentAdminState` compartilhado no servidor. Não há concessão automática no login ou pelo campo `users.role`.

Preservados `functions/admin_claim_management.js` e `functions/scripts/admin_claims_local.js`: operador confiável, dry-run, confirmação de projeto/UID/ação, auditoria, preservação das demais claims e transações. A ferramenta continua deliberadamente limitada ao demo, sem endpoint público e sem credencial no Flutter.

Provisionamento antes do primeiro lançamento, **somente mediante autorização futura**:

1. Identificar o UID correto por procedimento confiável, sem inferir autorização pelo e-mail apresentado no aplicativo.
2. Preparar operador/ambiente IAM de confiança, backup de claims/estado e auditoria. Não basta remover a trava demo do script atual.
3. Gravar estado desabilitado/pendente com nova versão, atribuir `admin: true` e `adminVersion`, finalizar estado habilitado e não pendente. Concessão parcial permanece bloqueada.
4. Renovar o ID token no app, comprovar claim/versão e acesso às operações administrativas antes de aplicar Rules/Worker estritos remotamente.
5. Ensaiar revogação: desabilitar estado **primeiro**, trocar versão/remover claims e revogar refresh tokens; testar token antigo e renovado.

Recuperação administrativa: usar acesso IAM independente do app; confirmar UID/projeto e revisar auditoria/operationId. Em operação pendente/falha, manter `enabled=false`, corrigir a causa no ambiente confiável, registrar decisão de recuperação e encerrar a operação pendente de forma auditada antes de uma nova concessão com nova versão. Não reutilizar versão antiga, não habilitar estado parcial, não reintroduzir fallback por e-mail. Esse procedimento foi documentado; nenhuma recuperação de conta real foi executada e um launcher de produção ainda precisa de preparação/autorização própria.

**Limitação preservada e comprovada:** `revokeRefreshTokens()` isolado no Auth não altera automaticamente `admin_authorizations`. Rules e Worker não executam o verificador de revogação do Admin SDK. Um token antigo ainda pode passar quando o estado central foi deixado habilitado. O procedimento gerenciado bloqueia imediatamente o token antigo; caminhos externos de IAM/Console devem ser restritos e operados com esse procedimento. A consolidação não apresenta essa limitação como resolvida.

## 5. Notificações

Novas notificações públicas têm allowlist de campos de conteúdo, sem UID/e-mail de destinatário ou campos arbitrários como `recipientEmail`. Privadas mantêm allowlist e `targetUid`, sem e-mail; consultas do destinatário exigem UID correspondente e publicação. Outros usuários, visitantes e usuários revogados não recebem acesso administrativo.

Novas filas recusam `targetEmail` não vazio e UID inválido; envio por UID e broadcast continuam. O teste de fila antiga por e-mail cria uma fixture via Admin SDK somente no demo, para validar o leitor residual; não mantém permissão de criação por cliente. Criação atômica notificação + fila, gatilho real do Emulator, seleção de dispositivos e navegação/interface foram preservados. FCM continua simulado no demo, sem envio externo.

Pendências anteriores de push permanecem: idempotência do processamento, corrida com retirada de publicação e limites de fanout. Não houve mudança silenciosa na entrega real.

## 6. Visibilidade e índices

| Coleções | Política pública |
| --- | --- |
| establishments, ads, offers, coupons, routes, jobs, events, news, alerts, polls, links, health, transport, trash_collection, useful_phones, pharmacy_duties, emergency_contacts, resolver_subjects, public_places | `published == true`; se `active` existir, precisa ser true; se `expiresAt` existir, precisa ser timestamp futuro |
| utilities | `active == true`; `published`, se presente, precisa ser true; mesma política de validade |
| notifications | Publicação/ativação/validade acima e `targetEmail == ''`; sem destinatário privado |
| private_notifications | Leitura por destinatário cadastrado com UID correspondente e publicada, ou Admin atual; contrato privado separado |
| home_pages | Documento publicado de configuração continua público; rascunhos somente Admin; não se inventou ativação/expiração para esse contrato |

Admin autorizado pode listar/editar restritos, corrigir validade, reativar e republicar. `Business.open` permanece funcionamento aberto/fechado, sem interferir na publicação. Datas de evento não foram convertidas em agendamento de publicação.

Rules não filtram consultas: listas públicas usam backend com páginas limitadas e revalidação. Gets diretos públicos validam o documento inteiro pelas Rules. Não foram inventadas exceções inseguras para dados antigos. O contrato não revoga conteúdo já baixado pelo usuário.

Criado `firestore.indexes.json`, fonte comum das duas configurações: mantém pesquisa por prefixos/grupo e notificações públicas, prepara índice de notificações privadas por publicação/UID e índice de grupo para dispositivos ativos usado no broadcast. Nada foi implantado. O Emulator não comprova exigência/estado dos índices compostos em produção; revisar disponibilidade durante implantação autorizada.

## 7. Operações e Busca Universal

Perfil legítimo continua com Rules de campos/tipos/timestamps, email ligado ao Auth e `affectedKeys()` protegendo inclusão/remoção; `role` não concede Admin. Gateway deriva autoria e datas, valida tipos/limites/referências, aplica quotas e deduplicação transacional. Escrita direta de favoritos/dispositivos/contato/propostas/reviews/métricas/votos por usuários permanece negada. Visitante anônimo pode buscar/ler público, não ganha recursos de conta cadastrada. Admin autorizado mantém gerenciamento permitido pelas Rules.

AppAuth prepara reutilização da sessão anônima e retorno ao visitante também para a futura ativação do transporte normal, sem criar perfil ou substituir sessão cadastrada. A ativação normal continua false; não habilita provedor no Console nem cria conta real.

Busca Universal não foi ativada em produção: campo, UniversalSearchPage, chips, debounce, paginação, índice privado, revalidação, favoritos e navegação para BusinessProfile foram preservados. A suíte local confirma ID original, perfil indisponível, filtro/paginação e segurança. Não foram adicionadas categorias de busca ou resultados inventados.

## 8. Testes e regressões corrigidas

| Verificação final | Resultado |
| --- | --- |
| Flutter Analyze | Sem problemas |
| Flutter normal, excluindo tag search-local | 261 passaram |
| Flutter searchLocal explícito | 30 passaram |
| App Check com flags locais habilitadas | 7 passaram, sem SDK real |
| Node Functions/runner | 61 passaram |
| Worker | 14 passaram |
| Firebase Emulator Auth/Firestore/Functions | Seis suítes, 107 cenários/grupos: Admin 9, notificações 12, visibilidade 48, operações 17, Auth 14, auditoria Auth 7 |
| Verificações release Python | 8 passaram; verificação estática Android/CI aprovada; nenhum artefato release gerado/inspecionado |

Testes novos/adaptados confirmam ausência de fallback no build normal, claim sem versão negada, Rules/índices canônicos comuns, e-mail/role sem claim negados, token antigo com versão revogada negado e impossibilidade de escolher projeto misto demo/produção. Testes existentes continuam cobrindo alteração de permissões por usuário comum, notificação privada, conteúdo inativo/expirado, campos inválidos, quotas/spam e busca.

Três expectativas estáticas antigas falharam inicialmente porque esperavam `changedKeys`, gravação direta de dispositivos e claim role/e-mail. Foram atualizadas para a política 1D definitiva, sem excluir testes ou relaxar validações. O teste do entrypoint Functions precisou de mock do novo módulo de configuração. O teste visual do Admin passou a usar estado autorizado explícito e espera fora do relógio simulado; nenhuma lógica de autorização real foi substituída por esse mock.

Emuladores existentes exclusivamente `demo-universal-search`: Auth 9097, Firestore 8087, Functions 5007, loopback. Não foram encerrados ou limpos; fixtures apenas locais. VPN/configuração nativa não foram modificadas. Sem execução nova do aplicativo, Hot Reload ou confirmação visual MEmu nesta etapa. Não se anexou sessão de produção para obter HR. Fixtures App Check, Google sintético e FCM simulado não comprovam atestação/OAuth/push reais.

Logs: `C:/Users/tiago/Documents/Codex/2026-09-11/pr/work/security-2e/`: analyze, flutter-normal, flutter-local, flutter-app-check, node, worker e emulator. Inventário de arquivos em `changed-files.txt`. Testes Windows usaram globs expandidos equivalentes ao CI; não houve execução remota Linux.

## 9. Checklist do primeiro lançamento

Tudo abaixo é preparação/pendência; nenhuma etapa remota foi executada.

- [ ] Aprovar custos e plano Firebase para Functions, quotas, armazenamento de artefatos e tráfego; criar orçamento/alertas. Limite de instâncias não substitui rate limiting nem teto financeiro. [Quotas oficiais](https://firebase.google.com/docs/functions/quotas).
- [ ] Resolver advisories Functions e runtime Node 20 identificados em 2D antes de implantação. Lockfiles e correção sharp permanecem; não foram atualizadas dependências em 2E.
- [ ] Preparar operador confiável de provisionamento/recuperação; confirmar UID, claims, versão, estado e revogação antes de aplicar Rules/Worker remotamente.
- [ ] Revisar backup dos registros de desenvolvimento e inventário remoto somente após autorização. Não migrar/apagar automaticamente; dados direcionados antigos continuam restritos.
- [ ] Configurar provedores Auth autorizados, certificados/domínios/OAuth e visitante anônimo. A tela e-mail/senha não existe atualmente; o helper SDK não deve ser anunciado como fluxo visual pronto.
- [ ] Planejar implantação coordenada Rules, índices, gateways, cliente e Worker. Confirmar consultas e índices reais; não publicar só as Rules e deixar um cliente antigo/direto como versão de lançamento.
- [ ] Ativar gateways normais somente após configurar App Check e conceder autorização separada; hoje `productionAuthorized=false` no Flutter e nenhum opt-in servidor foi aplicado.
- [ ] Busca real exige autorização própria para exportar/sincronizar e conectar a interface normal; não ativar funcionalidades de outras coleções ainda não implementadas.
- [ ] Configurar Play Integrity e App Attest/DeviceCheck reais, validar builds/aparelhos, observar métricas e compatibilidade; enforcement somente com autorização específica. [Functions e App Check](https://firebase.google.com/docs/app-check/cloud-functions).
- [ ] Cloudflare: implantar política de estado obrigatório, conferir projeto fixo e binding de rate limit; preparar proteção App Check própria e ensaiar falha fechada/revogação. REST do Worker precisará de integração adequada antes de enforcement do Firestore.
- [ ] Cloudinary: segredos somente no backend, folder mode autorizado e validação real de respostas/custos; nenhum segredo deve entrar no app/repositório/logs.
- [ ] Corrigir pendências de quotas/App Check da Function de upload e idempotência/fanout do push; ensaiar FCM real somente após autorização.
- [ ] Android oficial: keystore/certificado autorizado, package ID preservado, assinatura/debuggable verificados no artefato; `searchLocal` nunca distribuído. Gates de 2C preservados.
- [ ] iOS: preparar projeto nativo, bundle ID, capabilities, assinatura, entitlements, Podfile.lock e validação física; ausentes neste checkout. CI simulator não comprova distribuição Apple.
- [ ] GitHub Actions: executar workflow somente após autorização; testes obrigatórios, ambiente protegido e secrets em contexto confiável. Validar cold start Linux e pinagem de ferramentas antes do lançamento.
- [ ] Medir custo do polling público (30 s), múltiplas coleções/páginas, quotas, deduplicação e limpeza/TTL operacional. Leituras de estado são necessárias para Admin; Rules podem cobrar leituras dependentes e possuem limites de acesso. [Condições e limites das Rules](https://firebase.google.com/docs/firestore/security/rules-conditions).
- [ ] Publicar política de privacidade compatível com dados efetivamente coletados, retenção e operadores; preparar exclusão de conta/dados associados e tokens. Não foi encontrado fluxo completo de exclusão de conta no app; excluir só `users/{uid}` não resolve Auth, subcoleções e outros registros. Não executar exclusão/migração nesta etapa.
- [ ] Ensaio completo do único proprietário/testador: login, visitante, Admin, pesquisa, publicação/despublicação, notificações e revogação; plano de interrupção/recuperação sem reintroduzir fallback.

## 10. Riscos restantes e próximos passos

Prioridades: dependências/runtime; provisionamento/recuperação confiáveis e operação de revogação central; App Check real; gateways normais e índices; política de uploads/push; privacidade/exclusão; validação de distribuição. Sem clientes antigos, não há necessidade de manter exceções públicas inseguras como estratégia de migração.

Custos podem crescer com páginas de conteúdo, polling, leituras de revalidação, quotas e chamadas de autorização. Um getAll batched reduz viagens de rede, não leituras faturadas. Quotas por UID não eliminam abuso por criação de contas anônimas; App Check, observação de abuso e orçamento continuam necessários. Nenhuma estimativa financeira definitiva ou verificação de faturamento real foi feita.

Gets públicos de origem retornam documentos completos autorizados pelas Rules: antes do lançamento, confirmar que esses documentos não contêm campos administrativos/privados. Projeção do backend não torna segura uma origem que contenha segredos e ainda seja legível diretamente. Esse risco de contrato de dados permanece, sem inspeção de dados remotos.

Não executar recuperação real, remoção de registros, alteração de conta, migração ou implantação com base apenas neste relatório. O menor próximo passo é revisar estas mudanças locais e autorizar separadamente as correções pendentes e o procedimento confiável de provisionamento. Publicação permanece impedida até os critérios externos acima serem atendidos.

## 11. Arquivos alterados nesta etapa

Configuração: `firebase.json`, `firebase.search-emulator.json`, `firestore.rules`, `firestore.claims-local.rules`, `firestore.indexes.json` (novo), `firestore.search-local.indexes.json`.

Backend: `functions/admin_policy.js`, `home_image_upload.js`, `index.js`, `public_content.js`, `user_operations.js`, `secure_backend_environment.js` (novo).

Flutter: `lib/core/auth/admin_authorization.dart`, `app_auth.dart`; `lib/core/content/public_content_repository.dart`, `user_operations.dart`, `secure_backend.dart` (novo); `lib/core/services/metrics_service.dart`; `lib/features/notifications/notification_repository.dart`; `lib/redesigned_app.dart`.

Worker: `workers/image-upload/src/index.js`; testes `admin-state.test.js`, `worker.test.js`.

Testes Node: `functions/test/admin_policy.test.js`, `admin_revocation.test.js`, `business_search.test.js`, `content_visibility.test.js`, `home_image_upload.test.js`, `user_operations.test.js`, `prelaunch_security.test.js` (novo).

Integração: `functions/integration/admin_claims_emulator.js`, `content_visibility_emulator.js`, `notifications_emulator.js`, `user_operations_emulator.js`.

Testes Flutter: `test/admin_authorization_test.dart`, `admin_rules_staging_test.dart`, `guest_session_test.dart`, `home_title_edit_pilot_test.dart`, `security_rules_static_test.dart`, `user_operations_test.dart`.

Documentação: `docs/security_prelaunch_consolidation_2e.md` (novo). Android, iOS, workflows, segredos, dependências, VPN e App Check foram inspecionados/preservados, sem alteração adicional nesta etapa.

Segurança 2E concluída localmente. Arquitetura pré-lançamento consolidada. Aguardando revisão e autorização.
