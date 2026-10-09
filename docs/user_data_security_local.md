# Segurança 1D — validação e abuso, somente local

## Resultado e escopo

Preparado e testado exclusivamente em `demo-universal-search`, Auth 9097, Firestore 8087 e Functions 5007. O gateway novo só é exportado e executado quando o backend confirma projeto demo, Functions Emulator e Firestore loopback. O Flutter só o utiliza no ambiente local com as verificações nativas existentes de searchLocal/VPN. Configuração normal, `firestore.rules` de produção e Firebase Console não foram alterados nesta etapa.

Não houve deploy, alteração de dados/contas reais, migração real, APK, commit ou push. As proteções de notificações privadas, claims, revogação e visibilidade permanecem preservadas. Nenhum banco local inteiro foi apagado: testes criaram fixtures identificadas por execução e removeram somente suas contas Auth de teste.

## Diagnóstico anterior às alterações

Referências: `firestore.claims-local.rules`, `redesigned_app.dart` (syncUserProfile, PushService, favorite, ContactView, BusinessProposalView, ReviewForm, PollsView), `metrics_service.dart`, `Business` e interfaces administrativas ContactInbox/ReviewManager.

- Perfis: campos displayName/email/photoUrl/role/createdAt/updatedAt, merge no login. `changedKeys()` ignorava campos incluídos e removidos. Timestamps não eram obrigatórios. role do perfil não autoriza Admin.
- Favoritos: subcoleção do UID, documento pelo Business.favoriteKey (ID original ou nome legado), campos id/name/updatedAt. A interface remove também o nome legado quando necessário. Não há contrato de favoritos exclusivamente por referência a Firestore: existem modelos demonstrativos sem ID.
- Contato: name/contact/message/email/createdAt/read; mensagem obrigatória na interface, nome/contato podem ser vazios. Rules aceitavam documentos arbitrários porque os verificadores de strings permitiam campos ausentes.
- Propostas: a interface grava **details**, não description; name/details são obrigatórios, contact opcional em conteúdo. status inicial pending. A validação antiga verificava o nome de campo errado e permitia campos arbitrários.
- Avaliações: business era apenas nome; message, stars inteiro 1..5, userId, status pending e createdAt. Rules não validavam stars nem campos adicionais, e não era possível verificar seguramente a referência pelo nome.
- Métricas: action/target/targetType/createdAt, ações permitidas no Flutter. Rules tinham lista de ações mas permitiam falta de campos opcionais e não impunham frequência. target é identificador ou rótulo conforme o fluxo; não é sempre referência a um documento.
- Votos: opção string e updatedAt, documento por UID. A interface usa set e **permite mudar a opção**; não implementa voto imutável. Rules não verificavam existência/publicação da enquete, opção, autoria de campos ou validade.
- Dispositivos: token no ID, platform android, active true, updatedAt. O modo searchLocal já desativa FCM; normal mantém registro e remoção no logout. Token é metadado privado, não deve ser exposto em logs.

## Matriz de permissões local atual

Conta cadastrada = Auth válido não anônimo. Visitante anônimo não recebe acesso a recursos de conta. Admin = política atual de claim booleana + adminVersion + estado habilitado, sem pending; Admin revogado perde permissões administrativas inclusive com token antigo.

| Coleção/caminho | Criar | Atualizar | Excluir | Ler |
|---|---|---|---|---|
| users/{uid} | Próprio usuário com contrato estrito; Admin mantém exceção confiável anterior | Próprio usuário via safeUserUpdate; Admin mantém gestão anterior | Próprio usuário ou Admin, política anterior preservada | Próprio usuário ou Admin |
| users/{uid}/favorites/{id} | Gateway, UID do token | Gateway; id/name e data do servidor | Gateway do dono; Admin direto | Dono ou Admin |
| contact_messages/{id} | Gateway, conta cadastrada | Admin, somente read booleano | Admin | Admin |
| business_proposals/{id} | Gateway, conta cadastrada | Admin, somente status permitido | Admin | Admin |
| reviews/{id} | Gateway, conta cadastrada e estabelecimento elegível | Admin, somente status permitido | Admin | Admin |
| metrics/{id} | Gateway, conta cadastrada | Admin, política anterior | Admin | Admin |
| polls/{pollId}/votes/{uid} | Gateway, enquete elegível e opção válida | Gateway do votante; pode trocar opção | Sem operação de remoção no fluxo atual; escrita direta negada | Admin, política anterior |
| users/{uid}/devices/{token} | Gateway do dono | Gateway do dono | Gateway do dono; Admin direto | Dono ou Admin |
| user_operation_limits e user_operation_dedup | Somente backend confiável | Somente backend confiável | Somente backend confiável | Sem acesso pelo SDK cliente, inclusive Admin Flutter |

As sete famílias de gravação protegidas (favoritos, contatos, propostas, avaliações, métricas, votos, dispositivos) não aceitam gravações diretas que contornem o gateway. Admin cria usando o mesmo contrato quando atua nesses fluxos. Não há endpoint para elevar privilégios. Revogar Admin não remove automaticamente os direitos normais da conta cadastrada; desativar a conta inteira é operação diferente.

## Validações implementadas

### Perfil

Criação exige exatamente displayName/email/photoUrl/role/createdAt/updatedAt; role=user, e-mail igual ao token Auth (ou vazio se inexistente), strings com máximos 120/180/2048 e datas do servidor iguais a request.time.

Atualização usa **affectedKeys()**, abrangendo alteração, inclusão e remoção. Somente displayName/email/photoUrl/updatedAt podem mudar. role e createdAt existentes são imutáveis. Campos essenciais não podem desaparecer. Campos desconhecidos de documentos antigos podem permanecer, mas não ser alterados, acrescentados ou removidos pelo dono. Um createdAt ausente pode ser preenchido uma vez com request.time; o sync local faz esse reparo explicitamente. Datas inválidas existentes exigem correção administrativa autorizada, sem exceção insegura. A autorização administrativa continua independente de campos do perfil.

### Gateway submitUserOperation

Envelope aceita somente operation/payload. Cada operação exige todas as suas chaves e recusa chaves adicionais. Textos são tipados, limitados e normalizados com trim. Autoria, e-mail autenticado, status inicial, read, active e timestamps são derivados no servidor; o cliente não os escolhe.

| Operação | Payload obrigatório | Validações principais |
|---|---|---|
| contact | name, contact, message | Strings até 120/180/2000; message não vazia; servidor acrescenta userId/email/read=false/createdAt |
| proposal | name, contact, details | Strings até 160/180/2000; name/details não vazios; userId/status=pending/createdAt do servidor |
| review | businessId, message, stars | ID até 200, sem barra; mensagem não vazia até 2000; stars inteiro 1..5; origem atual publicada/ativa/não expirada; nome público copiado da origem; userId/status=pending/createdAt do servidor |
| metric | action, target, targetType | Ação na lista existente; strings até 60/200/60; sem count/score arbitrários; userId e createdAt do servidor |
| vote | pollId, option | ID até 200 sem barra; opção não vazia até 200; enquete existe, publicada, active quando presente, expiresAt válido/futuro quando presente, opção pertence a options; documento no UID do token |
| favorite | id, name | Strings não vazias até 200; ID sem barra; documento sob UID do token; updatedAt do servidor |
| unfavorite | id | Identificador válido; somente caminho do UID autenticado; ausência já é sucesso idempotente |
| device | token, platform | Token não vazio até 1500, sem barra; platform android/ios/web; token coincide com ID; active=true e updatedAt do servidor |
| removeDevice | token | Mesmo contrato do ID; somente caminho do UID autenticado; ausência idempotente |

Votos e avaliações leem a origem dentro da mesma transação que grava o resultado. Mudança concorrente da origem causa retry e nova validação. Business.open não interfere. A validade das enquetes é expiresAt; não existe contrato de abertura agendada e não foi inventado um. Datas de evento/publicação não são usadas como janela de votação.

Favoritos conservam IDs/nome legados e não exigem que um bookmark antigo continue apontando a conteúdo publicado. O bookmark não concede acesso ao perfil; a leitura do conteúdo continua protegida pela etapa 1C. Métricas aceitam rótulos porque os fluxos existentes usam tanto IDs quanto nomes. Não são prova confiável de visitas, avaliação ou atividade humana.

Moderação de avaliações/propostas admite apenas status pending/approved/rejected. Alterar autoria, estrelas ou dados arbitrários por essa operação é negado. A caixa de contato pode alterar somente read booleano. Documentos legados continuam legíveis/moderáveis pelo Admin sem regravação de campos históricos.

## Frequência, quotas e duplicidade

Rules não possuem rate limiting nativo. O gateway usa contador transacional privado por UID/operação, com janela de minuto e dia UTC. Os valores são orçamentos locais de segurança, sujeitos à revisão antes de produção:

| Operação | Por minuto | Por dia UTC |
|---|---:|---:|
| contact | 5 | 20 |
| proposal | 3 | 10 |
| review | 5 | 20 |
| metric | 120 | 2000 |
| vote | 30 | 300 |
| favorite e unfavorite, separadamente | 60 | 500 |
| device e removeDevice, separadamente | 10 | 30 |

Contatos/propostas/avaliações idênticos do mesmo UID são deduplicados por 60 segundos; métricas idênticas por 5 segundos. A chave é hash do UID, operação e payload validado em ordem canônica, sem conteúdo pessoal bruto no ledger. Repetições concorrentes retornam o mesmo ID e gravam um único documento. Repetições também consomem quota; não são uma forma de invocar sem limites de gravação. Não se impõe arbitrariamente uma avaliação por estabelecimento, regra que não existia no produto.

Favoritos/dispositivos/votos mantêm IDs estáveis e evitam regravar conteúdo idêntico. Trocar o voto atualiza o mesmo documento, sem incrementar um contador público. Erros, limites e indisponibilidade nunca fazem fallback para escrita direta. Falhas internas são sanitizadas. A função exige Auth e enforceAppCheck, maxInstances=2, concurrency=4, timeout=15s. A fixture App Check local não é atestação real.

## Impacto Flutter e compatibilidade

`writeUserOperation` reutiliza o transporte isolado existente. Na versão normal executa a gravação original; na variante local chama o gateway. Foram adaptados contato, proposta, avaliação, voto, favoritos, métricas e caminhos de dispositivos. FCM continua desligado no searchLocal: dispositivos foram testados com tokens fictícios, sem registro ou envio real.

Campos de autoria/status/data do Flutter não são enviados como autoridade ao gateway. Avaliações locais passam business.id; avaliações antigas por nome permanecem intactas. Modelos demonstrativos sem ID Firestore não podem criar avaliações locais verificadas: não se inventa referência. Mensagens de erro nos formulários/votos evitam exceções sem tratamento. Métricas falham discretamente, sem quebrar navegação ou imprimir payload/token. Não houve alteração de layout, filtros, favoritos locais de visitante ou navegação.

Legados não foram excluídos nem migrados. Perfis com role ausente ou datas inválidas podem exigir reparo administrativo; campos desconhecidos ficam congelados. Bookmarks legados por nome podem ser removidos pelo proprietário. IDs acima dos novos limites ou opções de enquete acima de 200 caracteres exigem revisão antes de produção. A população real é desconhecida, pois não houve acesso a produção.

## Custos adicionais estimados

Estimativas de documentos por chamada válida, sem retries:

| Operação | Leituras | Escritas |
|---|---:|---:|
| Novo contato/proposta/métrica | 2 (quota + dedup) | 3 (quota + conteúdo + dedup) |
| Nova avaliação | 3 (quota + dedup + estabelecimento) | 3 |
| Repetição deduplicada de criação | 2; avaliação 3 | 1 (quota) |
| Voto/favorito/dispositivo | 3 para voto, 2 para favorito/dispositivo | 2 quando muda; 1 se idêntico |
| Remoção favorito/dispositivo | 2 | 2 se existe; 1 se ausente |
| Quota excedida | 1 | 0 |
| Payload/Auth/App Check rejeitado antes da transação | 0 | 0 |

Há uma execução de Function por chamada. Transações concorrentes podem repetir leituras. Perfis permanecem com escrita direta, acrescida das verificações de Rules; verificações administrativas podem adicionar leitura de estado conforme a política 1B.1. Não foi ativado faturamento. TTL não foi implantado: expiresAt dos documentos operacionais prepara retenção futura, mas não apaga nada automaticamente. Custos de limpeza/TTL e plano de Functions devem ser aprovados antes da ativação.

## Testes executados

- Flutter Analyze: sem problemas.
- Flutter normal: **252 aprovados**.
- Flutter com flags locais: **22 aprovados**, incluindo recusa de ambiente nativo inseguro sem fallback direto e preservação de busca/filtros/perfil. Aviso não bloqueante preexistente de tag search-local não cadastrada.
- Node Functions/Worker: **70 aprovados**, incluindo contratos, ausências, campos proibidos, estrelas, tamanhos, IDs, gate de produção e falha de comunicação sanitizada.
- Integração real Auth/Firestore/Functions Emulator da etapa 1D: **17 cenários aprovados**. Cobrem conta legítima/terceiro/visitante/Admin/revogado, affectedKeys, remoção de obrigatórios, legados, Auth/App Check inválidos, bypass direto, autoria/estrelas/referências, opção e validade de enquete, mudança de voto, privacidade, dedup concorrente e quotas em todas as famílias.
- Regressão real de visibilidade/Busca Universal: **48 cenários aprovados, 21 coleções**.
- Regressão real de Admin/revogação: **9 aprovados**.
- Regressão real de notificações: **12 aprovados**, FCM simulado.
- git diff --check: sem erros de whitespace; avisos Git de conversão LF/CRLF já existentes.

Não houve inspeção visual nova no MEmu, APK debug ou Hot Reload. Testes de widgets não equivalem à validação visual interativa. Login Google real e App Check de produção não foram exercitados contra serviços reais.

## Limitações e pendências de implantação

1. As quotas são por UID e operação, não proteção global contra múltiplas contas, dispositivos comprometidos ou ataques distribuídos. Janelas fixas permitem rajadas na fronteira; não são um limitador deslizante. Requisições inválidas ainda podem consumir invocações/CPU, embora não gravem dados. App Check real, observabilidade sem dados pessoais e orçamento global precisam de validação antes de produção.
2. Escritas diretas de perfil mantêm o fluxo atual com schema forte, mas **não têm quota de frequência**. Um dono pode repetir atualizações válidas, leitura e exclusão/recriação do próprio perfil. Não se afirma proteção completa de custo nesse caminho. Leituras autorizadas também não são limitadas por estas quotas. Movê-los para gateway exige planejamento separado de compatibilidade.
3. Quotas diárias não são limite do total histórico de favoritos/dispositivos. Retenção, máximo de dispositivos ativos e limpeza de ledgers devem ser definidos antes de ativação. Não foi inventada exclusão automática de dados legados.
4. Métricas do cliente continuam telemetria não confiável; conta válida pode simular interações dentro da quota. Nenhum contador de nota ou reputação é atualizado pelo usuário. Métricas antifraude exigem fonte confiável no servidor.
5. Não há contrato de abertura agendada de enquetes; apenas elegibilidade e expiração existentes. Limites propostos e dedup precisam de aprovação do produto antes de produção.
6. Admin confiável mantém a gestão anterior de perfis/métricas; a segurança administrativa depende integralmente das claims e estado versionado preparados nas etapas 1B/1B.1. Campos de perfil nunca concedem Admin.
7. As Rules locais novas negam escritas diretas de clientes antigos. Não implantar isoladamente: preparar backend de produção, Auth/App Check real, quotas/custos e uma versão compatível do aplicativo, com estratégia para clientes antigos e rollback. O gateway atual deliberadamente recusa produção.
8. Inventário de legados reais, reparos e eventual migração de avaliações por nome para businessId exigem autorização separada. Não resolver referências ambíguas por suposição.

## Arquivos criados e modificados nesta etapa

Criados:
- functions/user_operations.js
- functions/test/user_operations.test.js
- functions/integration/user_operations_emulator.js
- lib/core/content/user_operations.dart
- test/user_operations_test.dart
- docs/user_data_security_local.md

Modificados:
- firestore.claims-local.rules
- functions/index.js
- lib/features/search/repositories/local_universal_search_repository.dart
- lib/core/services/metrics_service.dart
- lib/redesigned_app.dart
- docs/content_visibility_local.md (referência à etapa seguinte)

O restante da árvore Git contém trabalho preservado de etapas anteriores, não alterações novas atribuídas à etapa 1D.
