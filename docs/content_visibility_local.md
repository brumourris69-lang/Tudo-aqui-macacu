# Segurança 1C — visibilidade pública, somente local

Atualização posterior: a [etapa 1D](user_data_security_local.md) acrescenta
validações e gateway local para gravações de usuários, preservando esta política
de visibilidade. Consulte a matriz de escrita da etapa 1D para o estado atual.

## Escopo e decisão

Preparado para `demo-universal-search`, Auth 9097, Firestore 8087 e Functions 5007. Nenhum deploy, acesso a dados de produção, migração real, alteração de claims reais, APK, commit ou push foi realizado nesta etapa. As alterações anteriores permanecem preservadas.

Decisão do usuário: preservar os documentos sem novos campos e preparar listagens por backend com revalidação. Não foram introduzidos campos obrigatórios de normalização nos documentos antigos. As Rules não filtram consultas e não é possível consultar genericamente a ausência de um campo opcional. Por isso, as novas Rules locais autorizam leitura individual elegível e restringem listagens diretas ao Admin. A variante local usa `listPublicContent`; a configuração normal mantém suas consultas anteriores até uma ativação coordenada futura.

## Matriz de visibilidade

P = `published` deve ser booleano `true`. A = `active` ausente é aceito, mas, se existir, deve ser booleano `true`. E = `expiresAt` ausente é aceito; se existir, deve ser Timestamp estritamente posterior ao relógio do servidor. Valores nulos, tipos incorretos e validade vencida são negados. A e E são verificações defensivas dos campos opcionais; não significam que cada editor exponha todos esses controles.

| Coleção | Publicação | Ativação | Expiração | Legado aceito | Agendamento de publicação |
|---|---|---|---|---|---|
| establishments | P | A | E | Sem active/expiresAt; open não interfere | Não implementado |
| ads | P | A; editor possui controle | E | Sem campos opcionais | Não implementado |
| offers | P | A | E | Sem campos opcionais | Não implementado |
| coupons | P | A | E | Sem campos opcionais | Não implementado |
| routes | P | A | E | Sem campos opcionais | Não implementado |
| jobs | P | A | E | Sem campos opcionais | Não implementado |
| events | P | A | E | Sem campos opcionais | Não implementado; eventDate/date/startsAt são datas do evento |
| news | P | A | E | Sem campos opcionais | Não implementado |
| utilities | published ausente permitido; se existir, true | active obrigatoriamente true | E | Sem published/expiresAt | Não implementado |
| alerts | P | A | E | Sem campos opcionais | Não implementado |
| polls | P | A | E | Sem campos opcionais | Não implementado |
| links | P | A | E | Sem campos opcionais | Não implementado |
| health | P | A | E | Sem campos opcionais | Não implementado |
| transport | P | A | E | Sem campos opcionais | Não implementado |
| trash_collection | P | A | E | Sem campos opcionais | Não implementado |
| useful_phones | P | A | E | Sem campos opcionais | Não implementado |
| pharmacy_duties | P | A | E | Sem campos opcionais | Não implementado |
| emergency_contacts | P | A | E | Sem campos opcionais | Não implementado |
| resolver_subjects | P | A | E | Sem campos opcionais | Não implementado |
| public_places | P | A | E | Sem campos opcionais | Não implementado |
| notifications | P e targetEmail exatamente vazio | A | E | Sem active/expiresAt; destinatário ausente/direcionado continua restrito | Não implementado |

`publishedAt` é metadado de publicação, não um contrato de agendamento. Não foi inventado um campo de início de publicação. Se essa funcionalidade for introduzida, exige política, consultas e testes próprios antes da ativação.

Exceções preservadas:

- `private_notifications`: destinatário UID autenticado não anônimo e published=true, ou Admin autorizado. Contrato de escrita atual não admite active/expiresAt; bloco de regras preservado da etapa 1A.
- `home_pages/published`: configuração pública da Home; outros documentos são administrativos. Flags de componentes embutidos controlam apresentação, não substituem a proteção dos documentos de conteúdo de origem.
- `business_search_index`, controles de frequência e estado administrativo não são coleções públicas.
- Perfis, favoritos, dispositivos, votos, propostas, métricas, avaliações, fila de push e auditoria conservam suas permissões anteriores.

## Problemas e correções locais

As permissões públicas anteriores baseadas apenas em published/active não garantiam retirada de conteúdos vencidos ou desativados. Esconder dados no Flutter não impede leitura direta. Exigir campos opcionais em consultas diretas também impediria consultas legítimas de documentos antigos.

`firestore.claims-local.rules` agora verifica publicação, ativação e expiração em cada get público. Listagens diretas exigem Admin atual. Esse Admin continua exigindo claim booleana, conta não anônima e versão habilitada em `admin_authorizations`, sem estado pending. O token antigo de Admin revogado é recusado. Admin autorizado continua podendo ler, corrigir e republicar conteúdos inelegíveis.

`listPublicContent` lê páginas limitadas da coleção de origem, aplica a política compartilhada no servidor e retorna somente campos públicos explicitamente permitidos. Não copia documentos completos, não consulta coleção privada arbitrária, não usa um índice desatualizado como prova de visibilidade e não busca a coleção inteira sem limite. Exige Auth e App Check, inclusive para visitante com Auth anônimo. Erros internos são sanitizados e não há fallback de leitura insegura.

A projeção inclui os campos de apresentação existentes: nome/título, descrição/resumo, categoria/subcategoria, localização/endereço público, imagens públicas, contatos comerciais, horários, serviços/produtos, promoção, datas públicas, campos de ofertas/empregos e destino/links. Não inclui ownerEmail, privateNotes, targetEmail, roles, tokens ou mapas administrativos arbitrários. O conjunto exato está em `functions/public_content.js`. Timestamps são codificados explicitamente e restaurados no Flutter. IDs e referências originais são preservados.

## Consultas Flutter e Busca Universal

O adaptador público substitui consultas somente quando `LocalSearchEnvironment.enabled`, sujeito às verificações nativas de searchLocal, VPN, projeto demo e endereço loopback existentes. Não desativa isolamento, Auth ou App Check. A versão normal conserva as consultas anteriores. As consultas administrativas continuam diretas.

Foram adaptados o BusinessRepository, fluxo público de NotificationRepository e os pontos públicos em redesigned_app: anúncios, eventos, alertas, ofertas, utilidades, listagens genéricas, enquetes, turismo/rotas e agregadores. O fluxo privado por UID e o envio de notificações não foram substituídos. O adaptador usa envelopes de dados próprios, não snapshots falsos do SDK.

A Busca Universal mantém seu índice privado, paginação, filtros e IDs. A política Node de elegibilidade é compartilhada com a listagem; o backend da busca continua revalidando os documentos originais. Expiração é avaliada no instante da consulta, mesmo sem evento novo. Abrir BusinessProfile usa o documento original e permanece sujeito às Rules locais. Business.open continua indicando somente aberto/fechado.

## Custos e limites

- Por chamada de listagem: até 40 resultados e 80 documentos candidatos de origem; uma transação de frequência com aproximadamente uma leitura e uma escrita, mais retries quando houver concorrência. Consultas vazias também podem gerar cobrança mínima em produção.
- Não há segunda leitura de origem por candidato: a própria leitura atual da origem é a revalidação. Não há escrita de índice nessa listagem.
- Controle de 120 chamadas/minuto por UID; maxInstances=2, concurrency=4 e timeout=15s. Isso não substitui proteção global contra abuso e criação de múltiplos UIDs anônimos.
- Para preservar telas de listagem existentes, o Flutter encadeia no máximo dez páginas: até 400 resultados/800 candidatos por carregamento e dez transações de frequência. Ao exceder o teto, sinaliza erro, sem truncamento silencioso nem consulta ilimitada.
- Streams locais usam atualização serial a cada 30 segundos e cancelamento ao encerrar a assinatura. Custos de polling e paginação visível devem ser refinados antes de ativar em produção.
- O índice composto candidato de notifications (published, targetEmail e nome do documento) foi preparado somente no JSON local. O emulador não comprova todos os requisitos de índices do Firestore real; validar planos de consulta antes de futura implantação autorizada.

## Validação executada

Somente projeto demo e dados fictícios, sem limpar o banco inteiro ou remover fixtures de outras sessões:

- Flutter Analyze: sem problemas.
- Suíte Flutter normal: 251 testes aprovados.
- Testes Flutter com LOCAL_SEARCH_EMULATORS=true: 20 aprovados, incluindo isolamento, rede, busca, filtros, paginação, perfil e decodificação pública. Aviso não bloqueante preexistente de tag search-local não cadastrada.
- Node Functions + Worker: 67 aprovados, incluindo limite de varredura, frequência, falha fechada e projeção pública.
- Integração real Auth/Firestore/Functions Emulator: 48 cenários aprovados em 21 coleções. Inclui leitura individual, listagem negada, Admin, visitantes, campos opcionais, tipos inválidos, vencimento, datas futuras de eventos, paginação, Auth/App Check inválidos, busca com filtros e índice artificialmente desatualizado, e Admin revogado com token antigo.
- Integração de notificações: 12 aprovados; transporte FCM simulado, sem envio real.
- Integração de autorização/revogação administrativa: 9 aprovados, incluindo token antigo e regrant.

Não houve validação visual nova no MEmu nem Hot Reload nesta etapa. Os testes de widgets não equivalem à inspeção visual do aplicativo em execução. App Check do emulador não comprova Play Integrity/App Attest de produção.

## Riscos e compatibilidade restantes

1. Não foi acessada produção: quantidade, tipos e qualidade dos documentos antigos reais são desconhecidos. Ausência de active/expiresAt é suportada; ausência de published em coleções que já o exigem permanece restrita, sem exceção insegura. Admin poderá corrigir esses documentos após procedimento autorizado.
2. Uma leitura pública individual elegível ainda entrega o documento completo pelo Firestore. Rules não ocultam campos. A projeção do backend evita esses campos nas listagens; se documentos públicos reais contiverem informações privadas, será necessária separação física dos dados. Isso é risco potencial que depende de inventário autorizado, não uma exposição nova confirmada em produção.
3. Conteúdo já baixado, caches, favoritos, push entregue ou imagens públicas CDN não podem ser revogados retroativamente pelas Rules. A retirada afeta novas leituras autorizadas; a interface local pode conservar dados até atualizar. Algumas telas existentes exibem estado vazio em erros de carregamento. Não há promessa de remoção instantânea de memória do cliente.
4. Uma alteração após a leitura do servidor pode ocorrer antes da entrega da resposta; não há garantia de atomicidade entre resposta HTTP e mudanças posteriores. Nenhum cache de autorização prolongado foi introduzido.
5. Não existe contrato de agendamento de publicação. Não se deve usar data futura de evento como bloqueio de publicação.
6. Backend novo e Rules restritivas ainda não estão ativos em produção. Implantar apenas as Rules quebraria clientes antigos com listagens diretas. Não remover fallback administrativo de produção antes da Fase B separadamente autorizada.

## Plano de implantação futura — exige autorização separada

1. Inventariar documentos e campos reais com acesso autorizado e sem expor dados privados; preparar correções de tipos/publicação e separação de campos privados, se necessário. Não obrigar active/expiresAt nos legados válidos.
2. Confirmar claims/versionamento/estado do Admin, atualização de token e acesso de recuperação conforme etapas 1B/1B.1 antes de ativar regras estritas.
3. Preparar versão de produção do gateway, limites globais, observabilidade sem dados sensíveis, Auth de visitantes e App Check real; avaliar faturamento, polling e índices. O gateway atual deliberadamente recusa produção.
4. Planejar atualização dos clientes e política de versões antigas. Backend, release compatível e Rules precisam de ativação coordenada, testes e rollback autorizado; não há fase segura em que apenas as Rules novas sejam implantadas para clientes antigos.
5. Tratar notificações legadas direcionadas com revisão e migração privada por UID conforme etapa 1A, sem exclusão automática ou republicação pública.
6. Executar validação controlada de revogação, conteúdo, custos e acesso Admin após autorização. Nenhuma dessas ações foi executada nesta etapa.

## Arquivos desta etapa

Criados:
- functions/content_visibility.js
- functions/public_content.js
- functions/integration/content_visibility_emulator.js
- functions/test/content_visibility.test.js
- lib/core/content/public_content_repository.dart
- test/public_content_test.dart
- docs/content_visibility_local.md

Alterados:
- firestore.claims-local.rules
- firestore.search-local.indexes.json
- functions/index.js
- functions/business_search.js
- functions/integration/notifications_emulator.js
- lib/features/businesses/repositories/business_repository.dart
- lib/features/notifications/notification_repository.dart
- lib/features/search/repositories/local_universal_search_repository.dart
- lib/redesigned_app.dart
- test/admin_rules_staging_test.dart
- test/ad_carousel_test.dart
- docs/notifications_security_local.md
- docs/admin_revocation_local.md

O estado Git também contém trabalho de etapas anteriores. `firestore.rules`, `firebase.json` e as configurações normais de produção não foram alterados pela etapa 1C. Não confundir o manifesto desta etapa com toda a árvore de trabalho acumulada.
