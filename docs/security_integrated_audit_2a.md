# Segurança 2A — auditoria integrada e preparação para implantação

## Resumo executivo

**Decisão: impedir a publicação das correções de segurança no estado atual.** O conjunto local funciona nos cenários exercitados, mas não está preparado para implantação direta. As configurações normais conservam contratos legados deliberadamente; ativar somente as Rules locais interromperia clientes existentes e poderia bloquear o Admin. Os novos gateways ainda são exclusivos do emulador.

Esta auditoria não implantou nada, acessou dados reais, alterou contas reais, gerou APK, criou commit ou fez push. Foi acrescentado somente um teste diagnóstico de integração e este relatório. Os arquivos de aplicação e configuração existentes foram preservados. As fixtures foram criadas exclusivamente em `demo-universal-search`; nenhum banco inteiro foi apagado.

Bloqueios principais:

1. Coordenar Rules, backend e atualização do aplicativo; a configuração normal ainda não oferece as proteções completas de 1B–1D.
2. Tornar obrigatório o procedimento centralizado de revogação. Revogar somente no Auth deixou um token antigo autorizado pelas Rules no teste real do emulador.
3. Corrigir e validar assinatura/distribuição: o build release aponta para assinatura debug e o patch Kotlin do GitHub Actions não corresponde ao bloco atual.
4. Resolver testes incompatíveis com a invocação atual do CI e atualizar o teste Auth antigo para o contrato 1D, sem afrouxar validações.
5. Validar App Check real, dependências, runtime suportado, orçamento, compatibilidade e dados legados antes de qualquer autorização para produção.

## Escopo e evidências

Foram inspecionados Flutter, Rules, módulos Node, Worker, configurações Android, autenticação, App Check, pipelines e documentos das etapas anteriores. Foram utilizados Auth `127.0.0.1:9097`, Firestore `127.0.0.1:8087` e Functions `127.0.0.1:5007`, exclusivamente no projeto demo já em execução. Não houve login no Firebase Console nem consulta a produção.

Os logs e snapshots de diagnóstico estão em `C:/Users/tiago/Documents/Codex/2026-09-11/pr/work/security-2a`. O arquivo `baseline.json` registra hashes anteriores dos arquivos existentes incluídos no inventário. A comparação final não identificou modificações nesses arquivos. O inventário exclui artefatos gerados, dependências instaladas e arquivos ignorados; não equivale a uma análise completa do histórico Git ou de segredos externos.

### Integração das proteções

| Área | Proteção confirmada localmente | Limite ou dependência de implantação |
|---|---|---|
| Auth | Visitante anônimo reutiliza sessão; troca para conta cadastrada; logout; isolamento de dados por UID | Anonimato automático está condicionado ao modo local; produção ainda permite visitante sem Auth. Persistência nativa em disco e OAuth real não foram exercitados |
| Admin | Claim booleana `admin`, `adminVersion`, conta não anônima, estado enabled/version/pending | Fallback por e-mail permanece na configuração normal; não remover antes de provisionar e validar a conta autorizada |
| Revogação | Procedimento preparado fecha estado, renova versão/claims e revoga tokens; token antigo perde acesso | Revogação isolada no Auth não altera `admin_authorizations`; Rules e Worker não executam automaticamente `verifyIdToken(..., true)` |
| Rules | Variante local exige estado administrativo atual, visibilidade por documento e escrita validada | `firebase.json` referencia `firestore.rules`, e não `firestore.claims-local.rules`; não confundir arquivo local com regra implantada |
| Functions | Gateways locais exigem Auth/App Check, validam entrada, quotas e fontes atuais | Exportação e execução protegidas por `localOnly()`; não disponíveis como backend de produção |
| Worker | JWT validado, limite por UID, arquivo validado; modo estrito consulta estado antes/depois de ler corpo | Modo padrão continua `legacy-transition`; estado remoto usa projeto real fixo e foi testado com transporte simulado |
| Notificações | Coleções pública/privada, destinatário UID, leitura de terceiros negada, legado direcionado restrito | Conversão de legados e entrega FCM real pendentes; envio não tem garantia de idempotência |
| Conteúdo | Publicação/ativação/expiração, campos opcionais tratados; Admin gerencia restritos | Listagens públicas estritas dependem do backend; conteúdo já baixado não é revogado retroativamente |
| Busca | Índice privado, termos/prefixos, limite, filtros, IDs originais e revalidação da origem | Sem ativação/backfill real; requisitos de índices reais e attestation pendentes |
| Operações de usuário | Schema, autoria, datas, referências, deduplicação e quotas no gateway | Escritas normais antigas continuam diretas; clientes antigos precisam de transição coordenada |
| Flutter | Adaptadores locais sem fallback inseguro; erros não autorizam escrita direta | Testes de widgets não comprovam aparência/fluxos nativos completos no MEmu |

## Achados, gravidade e prioridade

Gravidade indica impacto se a condição alcançar produção. Uma omissão confirmada no código não significa que tenha sido explorada. A configuração efetivamente implantada permanece desconhecida.

| ID / prioridade | Gravidade e evidência | Impacto e correção recomendada, não executada |
|---|---|---|
| A01 / P0 | **Crítica, incompatibilidade confirmada.** `firebase.json`, `firebase.search-emulator.json`, `firestore.rules:9–14,64,186`, `functions/index.js:20–27`, adaptadores locais Flutter | Deploy isolado das Rules estritas rompe listagens/escritas antigas; deploy normal não ativa os gateways preparados. Criar e testar uma configuração de produção explícita, preservando as travas demo. Coordenar backend, clientes e Rules |
| A02 / P0 | **Alta, reproduzida.** `functions/admin_authorization.js:4–7`, `firestore.claims-local.rules:9–19`, `workers/image-upload/src/admin-state.js`; novo teste integrado | Após `revokeRefreshTokens` isolado, Admin SDK rejeitou token, mas Rules ainda permitiram leitura restrita porque estado/versão continuavam válidos. O procedimento gerenciado bloqueou a leitura. Tornar estado central o primeiro passo obrigatório de qualquer retirada de Admin; restringir e auditar caminhos alternativos de IAM/Console. Remoção isolada de claim ou desativação de conta têm risco análogo a investigar; não foram reproduzidas nesta auditoria |
| A03 / P0 | **Alta, configuração confirmada.** `android/app/build.gradle.kts:38–43`, `.github/workflows/main.yml:92` | Release usa `signingConfigs.debug`. Patch CI procura `getByName("release") {`, ausente no arquivo que usa `release {`; cria configuração sem vinculá-la corretamente. Corrigir sob autorização e verificar certificado/manifesto do artefato futuro. Nenhum artefato release foi gerado ou inspecionado agora |
| A04 / P0 | **Alta, lacuna de validação confirmada.** `lib/core/auth/app_check_setup.dart:20–40`, transporte local, opções das Functions | App Check local é fixture, não atestação. Ativação real permanece impedida pelas guardas atuais. Validar Android/iOS em staging real autorizado antes de enforcement; não copiar a fixture para produção |
| A05 / P1 | **Alta, falha de pipeline reproduzida.** `.github/workflows/main.yml:59`, `test/local_native_gate_test.dart`, `functions/integration/auth_emulator.js:103` | `flutter test` sem defines mistura testes de variante local; quatro falhas. Teste Auth antigo cria perfil parcial e espera escrita direta de favorito, incompatíveis com 1D. Separar suítes/flags e atualizar expectativas mantendo as proteções |
| A06 / P1 | **Alta, dependências afetadas confirmadas; exploração no aplicativo não demonstrada.** `functions/package.json`, grafo instalado, auditorias npm | Snapshot de dependências de produção: 9 pacotes afetados (2 alta, 7 moderada), incluindo cadeia firebase-admin/node-forge. Ausência de lockfile Functions impede instalação reproduzível. Revisar alcance, atualizar de forma controlada, gerar lock e repetir testes; não aplicar `npm audit fix` indiscriminadamente |
| A07 / P1 | **Alta, prazo de suporte confirmado.** `functions/package.json:5` configura Node 20 | Node 20 está descontinuado e tem retirada prevista para 30/10/2026. Preparar runtime suportado e compatibilidade antes de implantar; runtime real implantado não foi consultado |
| A08 / P1 | **Alta potencial, depende dos documentos reais.** `firestore.claims-local.rules`, `functions/public_content.js` | Get público elegível entrega documento inteiro; Rules não ocultam campos. Projeção segura do backend não protege get direto se a origem contiver dados privados. Inventariar e separar dados privados fisicamente antes de liberar acesso; fixtures demonstram exclusão na projeção, não ausência de dados privados em produção |
| A09 / P1 | **Média/alta potencial; omissões confirmadas.** `functions/index.js:98+`, `functions/notification_delivery.js:32` | Trigger de push não possui ledger transacional de entrega nem revalida publicação da notificação de origem antes de enviar. Repetição do evento pode repetir push; retirada posterior pode não cancelar item enfileirado. Broadcast lê todos os devices ativos sem paginação. Definir idempotência, política de cancelamento e fanout limitado antes de escala |
| A10 / P1 | **Média, diferenças confirmadas.** `functions/home_image_upload.js`, Worker | Upload por Function não tem App Check obrigatório nem quota por UID equivalente ao Worker; limites de instâncias não são rate limiting. Chamada direta por Admin autorizado pode contornar quota do Worker. Uniformizar política por rota e proteger contra conta comprometida; não há prova de upload anônimo permitido no modo estrito |
| A11 / P1 | **Média, risco operacional confirmado.** `functions/public_content.js`, repositório de conteúdo | Polling de 30 s, até 10 páginas por carregamento e quotas por UID elevam custos e podem produzir erro ao superar teto. Revisar orçamento, paginação visível e estratégia de atualização antes de ativar |
| A12 / P2 | **Média, defesa incompleta contra abuso.** `functions/user_operations.js`, Rules de users | Quotas por UID/janela não limitam múltiplas contas nem volume global; perfil ainda permite operações diretas legítimas sem quota. Dedup/contadores têm validade lógica, sem TTL implantado. Avaliar retenção, limites globais e alertas; métricas não comprovam atividade humana |

Também há risco de cadeia de suprimentos nos actions por tags e Flutter stable sem versão fixa; CI não executa as suítes Node/Worker/Emulator de segurança. Auditoria Worker encontrou 3 pacotes de tooling com alta gravidade, pertencentes à cadeia wrangler/miniflare/sharp; `--omit=dev` não reportou vulnerabilidades. Não são três explorações independentes confirmadas no endpoint. Functions completo reportou 13 pacotes afetados (6 alta/7 moderada), incluindo dependências de desenvolvimento. Os números são de pacotes afetados, não de ataques independentes.

## Políticas integradas e cenários adversos

### Admin e identidade

Não se utiliza `users.role` como autoridade. A conta cadastrada não recebe Admin durante login. Visitante anônimo não recebe permissões de conta cadastrada mesmo com claim administrativa forjada no teste. Rules impedem escrita cliente em `admin_authorizations`; leitura limitada do próprio estado permite detectar retirada de acesso, sem conceder capacidade de alteração.

No modo estrito, Functions verificam estado e, nas operações administrativas preparadas, token revogado via Admin SDK. Worker valida assinatura/audience/issuer/tempos do JWT e consulta estado por REST; não tem equivalente automático de revogação do Admin SDK. A consulta de estado falha fechada, sem cache prolongado de autorização. A validade depende de atualizar esse estado em toda revogação.

A ferramenta de concessão/revogação atual é deliberadamente limitada ao demo. Um procedimento para contas reais precisa ser preparado em ambiente confiável, com confirmação explícita de UID/ação, registro de auditoria e recuperação independente. Não basta remover a trava demo do script.

### Visibilidade e notificações

Matriz completa: `docs/content_visibility_local.md`. Vinte e uma coleções foram exercitadas. Regra padrão: `published == true`; `active`, quando presente, deve ser true; `expiresAt`, quando presente, deve ser Timestamp futuro. Nulos/tipos inválidos falham fechados. `utilities` exige active=true e admite published ausente. `Business.open` não é publicação. Datas futuras de evento não são agendamento de publicação; inexiste contrato de início agendado.

Notificação pública exige destinatário explicitamente vazio; documento legado com `targetEmail` direcionado não se torna público por ter published=true. `private_notifications` exige UID destinatário cadastrado e publicação, ou Admin atual. Falta/ambiguidade na resolução de e-mail não causa broadcast. Interface e navegação existentes foram preservadas. FCM foi simulado; nada foi enviado a dispositivos reais.

Listagens diretas restritas são substituídas localmente por backend com projeção pública e revalidação atual. Índice de busca não é legível pelo cliente, não contém documento completo e não decide sozinho a visibilidade. Sincronização transacional lê a origem atual, trata eventos repetidos/fora de ordem e evita escritas redundantes. Expiração é novamente verificada ao pesquisar. `BusinessProfile` mantém ID original e lê origem sujeita às Rules.

### Operações de usuário

Matriz detalhada: `docs/user_data_security_local.md`. Contato, proposta, avaliação, métrica, voto, favorito e dispositivo passam pelo gateway local; escrita direta para contornar quotas é negada. `safeUserUpdate` local usa affectedKeys(), conserva campos essenciais e não permite inclusão/remoção arbitrária. Autoria, status e datas são determinados no servidor.

Avaliação exige estrelas inteiras 1–5 e estabelecimento atual elegível. Enquete existente/elegível e opção pertencente ao documento são verificadas na transação; trocar voto é permitido pelo contrato existente, sem criar voto adicional. Favoritos legados por nome permanecem compatíveis e não concedem leitura de conteúdo restrito. Repetições consomem quota; falha no backend não aciona escrita direta.

Contatos/propostas/avaliações idênticos são deduplicados por 60 s; métricas por 5 s. Quotas minuto/dia UTC: contato 5/20; proposta 3/10; avaliação 5/20; métrica 120/2000; voto 30/300; favorito e remoção 60/500 cada; dispositivo e remoção 10/30 cada. Limites são locais preparados, não uma capacidade global aprovada para produção.

## App Check: o que foi e não foi comprovado

| Nível | Resultado |
|---|---|
| Unitários/mocks | Políticas de presença/validade e falha fechada testadas; transporte e respostas simulados |
| Firebase Emulator | Auth/Rules/Functions reais locais; fixture App Check restrita ao emulador aceita, ausência/invalidez negadas conforme política |
| Play Integrity real | **Não validado**; código de provider existe, ativação real ainda não disponível sob guardas atuais |
| App Attest/DeviceCheck real | **Não validado**; compatibilidade/certificados/device e fallback precisam de staging autorizado |
| Enforcement em produção | **Não ativado nem consultado**; depende de configuração e clientes compatíveis |
| Uploads | Worker não valida App Check; Function de upload também não tem enforcement equivalente aos gateways locais |

Não existe teste local equivalente à attestation real. Google no teste novo usa troca sintética aceita pelo Auth Emulator; não comprova OAuth Google em dispositivo. Login por e-mail foi exercitado via SDK, não por nova tela de UI. Persistência usada foi em memória, sem comprovação de restauração nativa após reiniciar o processo.

## Compatibilidade e distribuição

| Item | Gravidade da incompatibilidade | Tratamento necessário |
|---|---|---|
| Apps antigos com consultas diretas | Crítica se Rules estritas forem ativadas isoladamente | Atualização compatível antes do corte; política explícita de versão mínima. Não reabrir listagens privadas para manter cliente antigo |
| Apps antigos com escritas diretas | Alta | Gateway no cliente novo antes de negar escrita direta; não é possível garantir quota do gateway mantendo bypass antigo |
| Admin sem claim/versão/estado | Crítica, bloqueio de gestão | Provisionamento autorizado, refresh e validação de painel/servidor antes de remover fallback |
| Visitantes sem Auth em produção | Alta | Preparar anonimato/provider/contrato real e testar permissões antes de exigir gateway autenticado |
| Notificações legadas direcionadas | Alta, confidencialidade | Restringir leitura; mapear destinatário sem ambiguidade; migração autorizada separada. Não apagar nem publicar legados automaticamente |
| Perfis com role ausente ou datas inválidas | Média/alta | Inventário e reparo administrativo autorizado; createdAt ausente tem reparo controlado; campos desconhecidos ficam congelados |
| Avaliações legadas por nome | Média | Preservar leitura/moderação; mapear ID somente com evidência, sem adivinhar estabelecimento |
| Conteúdos sem active/expiresAt | Baixa quando realmente opcionais | Política local aceita ausência; tipos inválidos ou published obrigatório ausente exigem análise, sem exceção pública insegura |
| Imagens CDN, cache e push já entregue | Limitação permanente | Retirada bloqueia novas leituras; não garante apagar cópias anteriores. Definir retenção e privacidade |
| Índices e consultas reais | Alta | JSON local é preparação; Emulator não valida todas as exigências de índices compostos e custos reais |

`searchLocal` tem applicationId `br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal`, apenas debug; não consome google-services de produção, remove inicializadores nativos de Firebase/FCM e exige demo/host local. VPN e política nativa bloqueiam tráfego externo IPv4/IPv6/DNS antes do Flutter; guardas Dart complementam isso. Esses mecanismos foram inspecionados e testados nas suítes locais. Não se confirmou uma sessão MEmu ativa, captura visual ou VPN em execução nesta etapa; não houve Hot Reload ou recompilação.

Codemagic gera APK debug; assinatura customizada de debug não transforma build em release. Os workflows iOS atuais são debug/simulator/sem assinatura de distribuição, e Info.plist é gerado no CI. Certificado efetivo, debuggable=false e configuração de attestation do futuro artefato de produção precisam de validação separada.

Não foram encontrados arquivos secretos rastreados nos padrões inspecionados. Valores de credenciais não foram exibidos. Identificadores de projeto/chaves públicas Firebase e cloud name/API key pública Cloudinary não equivalem a service-account private key/API secret/keystore. Secrets no Console, histórico completo e arquivos ignorados não foram integralmente auditados; isso não é atestado de ausência absoluta de segredos.

## Resultados dos testes desta auditoria

| Execução | Resultado e interpretação |
|---|---|
| `flutter analyze --no-pub` | Sem problemas |
| `flutter test --no-pub` | **256 passaram, 4 falharam**; todos os erros em local_native_gate_test sem defines locais, como no comando atual GitHub |
| `flutter test --no-pub --exclude-tags search-local` | **252 passaram** |
| Suíte local com LOCAL_SEARCH_EMULATORS=true e LOCAL_SEARCH_HOST=127.0.0.1 | **22 passaram**: native gate, isolamento de rede, busca, conteúdo e operações. Aviso não bloqueante de tag não cadastrada |
| Node Functions + Worker (`node --test`, diretórios test) | **70 passaram** |
| admin_claims_emulator | **9 cenários passaram** |
| notifications_emulator | **12 cenários passaram**, entrega FCM simulada |
| content_visibility_emulator | **48 cenários passaram**, 21 coleções; busca, índice desatualizado, paginação, acesso direto e revogação |
| user_operations_emulator | **17 cenários passaram**, validação, autoria, duplicidade, spam/quotas e referências |
| Novo security_audit_auth_emulator | **7 cenários passaram**, incluindo reprodução explícita da limitação Auth-only revocation |
| auth_emulator antigo | **Falhou** ao esperar 200 para perfil parcial; Rules atuais retornaram 403 corretamente. Depois esperaria favorito direto, igualmente incompatível com 1D; parte posterior não executou |

Os cinco scripts de integração compatíveis completaram **93 cenários**. Isso não apaga as falhas da suíte padrão nem do script antigo. No teste local de variant sem defines, os quatro erros foram: enabled false em vez de true; mock de clima recebeu uma chamada em vez de zero; ausência do StateError esperado ao simular flags incompatíveis; e StateError de variante/flags incompatíveis ao instalar deny policy. Com defines apropriados esses cenários passaram.

O novo teste cobre visitante, reuso, transição para e-mail, perfil válido, favoritos pelo gateway, logout, isolamento de UID, retorno à conta, Google sintético e Auth/App Check inválidos. A sétima aprovação significa **risco reproduzido e documentado**, não revogação isolada considerada segura.

Não foi executado o harness search_emulator que limpa o banco demo inteiro: evitou-se apagar fixtures de outras sessões. A integração de busca foi exercitada pelos testes de conteúdo e autenticação atuais. Não houve E2E Worker–Cloudflare–Cloudinary real, envio FCM real, teste visual MEmu, OAuth real, teste nativo de login persistente ou análise completa de CVEs Dart/Android/iOS.

## Custos e dependências

Estimativas abaixo são de operações de documento, não preço final. Não incluem retries, mínimo por consulta vazia, leituras de entradas de índice cobradas, transferência, armazenamento ou execuções rejeitadas. Ler vários documentos em uma RPC não elimina cobrança por documento.

| Operação | Estimativa típica / limite | Onde cresce |
|---|---|---|
| Admin via Rules | Leitura dependente do estado administrativo; cache/reuso por avaliação pode reduzir repetições | Operações administrativas e requisições negadas com avaliação dependente |
| Upload Worker estrito | Até 2 leituras REST do estado, validações JWT; upload e eventual escrita de referência são separados | Uploads por Admin e volume/tamanho no Cloudinary; quota Worker é por localização Cloudflare |
| Function Admin estrita | Leitura de estado + verificação Auth de revogação; escrita/serviço próprio da operação | Invocações e validações, inclusive algumas rejeitadas |
| Busca | Exemplo 5 candidatos/5 origens: **11 leituras + 1 escrita** com quota; teto 40+40+1: **81 leituras + 1 escrita** | Consultas, paginação, candidatos descartados, múltiplos UIDs |
| Sincronização do índice | 2 leituras (origem/índice), 0 ou 1 escrita/exclusão quando necessário | Alterações dos estabelecimentos, eventos repetidos e tamanho dos prefixos |
| Listagem pública | Até 80 candidatos + 1 leitura/1 escrita de quota por chamada; 40 resultados | Até 10 páginas: 800 candidatos + 10 leituras/escritas de quota por carregamento; polling 30 s |
| Contato/proposta/métrica novos | 2 leituras / 3 escritas, incluindo quota e dedup | Usuários e submissões; validade lógica sem TTL não remove documentos |
| Avaliação nova | 3 leituras / 3 escritas, incluindo origem | Submissões e retries concorrentes |
| Voto | 3 leituras / 2 escritas; conteúdo igual evita uma escrita | Votação e troca de opção |
| Favorito/dispositivo | 2 leituras / 2 escritas; conteúdo igual evita uma escrita | Sincronizações repetidas e devices por usuário |
| Duplicata de criação | 2 leituras / 1 escrita; avaliação 3 leituras | Repetições ainda consomem quota |
| Quota excedida | 1 leitura, sem escrita de conteúdo; invocação ainda existe | Abuso e múltiplas contas |
| Push | Direcionado: devices do destinatário, eventualmente até 2 perfis por e-mail; broadcast: todos D devices ativos + lotes de até 500 envios | Base total de dispositivos; não há paginação global atual |

Exemplo puramente ilustrativo: 1.000 usuários simultâneos, 5 streams abertos, uma página por stream e polling a cada 30 s geram **600.000 chamadas/hora**. Com 10 documentos por chamada e uma leitura de quota seriam cerca de **6,6 milhões de leituras e 600.000 escritas de quota/hora**, antes de custos adicionais. Não é previsão de tráfego real; demonstra por que o polling não deve ser ativado sem revisão financeira.

Cloud Functions requer Blaze. FCM e App Check não têm cobrança própria de mensagem/validação nessa tabela de produtos, mas Functions/Firestore/armazenamento/egress envolvidos podem custar. Plano, região, utilização e quotas reais não foram consultados. Alertas de orçamento não são um teto automático de gastos. Workers tem plano gratuito e planos pagos; plano efetivo e Cloudinary são desconhecidos. Aprovação financeira deve abranger leituras, invocações, CPU, retenção e limites globais, não somente custo por pesquisa.

Fontes oficiais verificadas: [planos Firebase](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans), [preços Firestore](https://firebase.google.com/docs/firestore/pricing), [Workers](https://developers.cloudflare.com/workers/platform/pricing/), [limites Worker por localização](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/), [runtime Node 20](https://docs.cloud.google.com/functions/docs/runtime-support). Avisos de dependências: [sharp/librsvg](https://github.com/advisories/GHSA-wq5f-xc86-pv6w), [grpc-node](https://github.com/grpc/grpc-node/security/advisories/GHSA-m9gg-hp2v-232j). Os JSONs npm locais contêm a análise de alcance por pacote; não são prova de exploração.

## Matriz de implantação futura — nenhuma fase executada

Cada fase depende de aprovação separada compatível com seu alcance. A sequência abaixo não autoriza mudanças reais.

| Fase / ordem | Trabalho e dependências | Validação para avançar | Interrupção/reversão segura |
|---|---|---|---|
| 0 — preparação local | Corrigir A01–A07; projetar configuração real sem remover guardas demo; lock/runtime/dependências; assinatura; CI com Flutter normal/local, Node, Worker e Emulator | Todas as suítes relevantes verdes; teste de revogação cobre caminho operacional escolhido; artefato futuro verificável | Permanecer local; nenhuma alteração de produção |
| 1 — inventário autorizado | Leitura autorizada de configuração real: regras implantadas, IAM, providers/Auth, Admin UID, documentos legados, campos privados, versões de apps, planos e secrets externos | Inventário sem expor segredos; lista de migrações e orçamento aprovada | Não alterar dados; interromper diante de ambiguidade de titularidade/destinatário |
| 2 — staging real isolado | Projeto não produtivo autorizado para OAuth, App Check real Android/iOS, Worker e upload; certificados apropriados | Auth, attestation válida/inválida, autorização, limites e erros reais testados | Desabilitar staging; nunca apontar searchLocal para produção |
| 3 — preservar Admin | Preparar suporte mínimo de leitura do estado nas Rules reais; ferramenta confiável; atribuir claim+versão+estado somente ao UID aprovado, refresh de token; recuperação IAM independente | Admin atual entra/edita; usuário/e-mail sem claim negados no modo estrito em staging; revogar/reconceder testado | Manter fase de preparação sem remover fallback antes da confirmação. Após corte, recuperar via IAM confiável, nunca abrir Admin por e-mail novamente |
| 4 — backend antes do corte | Implantação autorizada de gateways, sync, índices compostos privados e limites; política Auth/App Check; eventual backfill público autorizado e limitado, separado de migração de dados | Revalidação atual e ID corretos; index inacessível diretamente; capacidade/quotas/custos aceitos | Interromper backfill, manter índice privado; rollback de backend para versão segura compatível. Não abrir leitura do índice |
| 5 — aplicativo compatível | Cliente normal com gateways, visitante Auth e App Check real; assinatura correta; sem flags/fixtures searchLocal | Fluxos completos em staging/dispositivo; versão mínima/adoção e comunicação aprovadas | Pausar distribuição; conservar backend compatível. Não afrouxar segurança para cliente incompatível |
| 6 — migrações e corte coordenado | Migrações reais só com autorização específica: notificações UID, separação de dados privados e reparos legados. Ativar Rules estritas, claims-only Functions/Worker e enforcement por serviço após cliente pronto | Usuário comum não administra; token antigo após revogação gerenciada negado; privados/inativos/expirados bloqueados; ausência de bypass de quotas | Preferir manutenção/read-only temporário; restaurar apenas versões seguras. Nunca reabrir notificação privada, fallback por e-mail ou escrita arbitrária |
| 7 — canário e monitoramento | Pequeno grupo/percentual, erros sem PII/tokens, orçamento, latência, filas, fanout, rejeições e índices | Critérios de erro/custo definidos antes do rollout; Admin e usuários mantêm fluxos autorizados | Parar rollout e produtores/consumidores problemáticos de forma controlada; backups privados e reversão de dados somente autorizados |

**Cloudflare:** provisionar modo estrito somente depois de estado/claim/Rules compatíveis; validar bindings de quota, secrets, URLs e falha fechada. Estado atual usa projeto real fixo, portanto exige revisão explícita para staging. Não criar endpoint público de concessão ou consulta administrativa.

**Firebase Console:** configuração real de providers, App Check/atestação, certificados, enforcement, IAM e eventualmente TTL exige autorização própria. Não assumir que APIs ou regras locais provam esses estados.

**Financeiro:** aprovar Blaze e capacidade real apenas após estimativa com tráfego/região/retenção. Limites de instância e por UID não são teto global de despesas.

**Clientes antigos:** não existe compatibilidade segura automática entre Rules que negam listagens/escritas diretas e versões que dependem delas. Definir versão mínima/atualização obrigatória, janela comunicada e política de indisponibilidade; uma janela transitória com proteções legadas mantém riscos e precisa de aceitação explícita. Não anunciar segurança completa durante essa janela.

## Critérios de autorização e impedimento da publicação

Autorizar somente quando houver evidência de:

- Configuração de produção explícita e testes integrados verdes, sem dependencia de fixtures demo.
- Admin aprovado com claim/versão/estado, refresh e acesso confirmado; revogação obrigatoriamente centralizada e recuperação confiável.
- Consultas/escritas incompatíveis eliminadas no cliente suportado; política de versões antigas aprovada.
- Dados privados separados, notificações legadas tratadas sem publicação acidental e índice privado.
- App Check real validado por plataforma e enforcement compatível; exceções por endpoint documentadas.
- Runtime suportado, dependências/lock revisados e assinatura/certificado/debuggable validados no artefato futuro autorizado.
- Orçamento, fanout/polling, quotas, retenção e monitoramento aceitos; rollback que preserve confidencialidade.

Impedir a publicação enquanto qualquer P0 permanecer, enquanto testes necessários estiverem vermelhos sem resolução, ou se for necessário reabrir acesso privado/administrativo para fazer a transição funcionar. Aprovações visuais ou testes com mocks não substituem esses critérios.

## Arquivos desta etapa e pendências

Criados:

- `functions/integration/security_audit_auth_emulator.js`: diagnóstico integrado SDK/Emulator, contratos atuais e reprodução de revogação fora do procedimento.
- `docs/security_integrated_audit_2a.md`: este relatório e matriz de implantação.

Não foram modificados módulos de aplicação, Rules, Worker, pipelines ou configurações existentes nesta auditoria. Logs e cópia externa do grafo instalado foram gerados em `../work/security-2a`; não se instalou/corrigiu pacote no projeto. O npm audit inicial de Functions falhou por ausência de lock; a análise posterior usa cópia externa do lock interno instalado e não um lock de deployment versionado.

Próximo passo recomendado: autorizar uma etapa exclusivamente local para resolver os bloqueios diagnosticados e preparar a configuração/CI de ativação. Isso ainda não seria autorização para deploy, migração, alteração de claims reais ou enforcement.

Auditoria integrada de segurança concluída. Aguardando revisão e autorização para os próximos passos.
