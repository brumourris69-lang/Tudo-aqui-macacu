# Backend administrativo híbrido — Estabelecimentos

## Escopo entregue nesta etapa

`supabase/functions/manage-establishments/index.ts` expõe um endpoint administrativo para `create`, `update`, `unpublish`, `republish` e `delete` lógico. Não há exclusão física nem sincronização hospedada automática. As alterações canônicas ficam no Firestore; a mesma transação grava `catalog_outbox/{requestId}`.

O runtime aceita apenas o projeto Firebase fixo `tudo-aqui-macacu`. O `FIREBASE_SERVICE_ACCOUNT_JSON` é lido em runtime e nunca fica no repositório. Sem a credencial, a função falha fechada antes de qualquer requisição externa.

## Contrato HTTP

Método: `POST /functions/v1/manage-establishments`, `Content-Type: application/json`, `Authorization: Bearer <Firebase ID token>`. O corpo tem limite de 32 KiB e aceita somente as propriedades indicadas abaixo. `uid`, email, claims, versão, timestamps, estado da outbox e outros campos de servidor enviados pelo cliente são rejeitados.

```json
{"operation":"create","requestId":"UUID estável da operação","entityId":"modelo-1","data":{"title":"Nome","category":"Comércio","description":"Descrição"}}
{"operation":"update","requestId":"UUID estável da operação","entityId":"id-firestore","expectedVersion":3,"data":{"title":"Nome atualizado"}}
{"operation":"unpublish","requestId":"UUID estável da operação","entityId":"id-firestore","expectedVersion":4}
{"operation":"republish","requestId":"UUID estável da operação","entityId":"id-firestore","expectedVersion":5,"data":{"title":"Nome atualizado","published":true}}
{"operation":"delete","requestId":"UUID estável da operação","entityId":"id-firestore","expectedVersion":6}
```

`create` aceita um ID original opcional (por exemplo `modelo-1`) e gera UUID no servidor quando omitido. IDs seguem os limites de documento Firestore: até 1500 bytes UTF-8, sem `/`, `.` ou `..`, e sem nomes reservados `__...__`, salvo `__idN__`. `update` exige a versão atual; documentos legados sem `catalogVersion` começam na versão zero. `unpublish` grava `published=false` e `active=false`, não preenche `deletedAt` e não apaga o documento. `republish` é uma operação explícita, versionada, pode incluir o patch editado e rejeita tombstones. `delete` grava tombstone lógico permanente, despublica e cria evento versionado. Uma edição de legado preserva campos antigos não classificados e pode remover `expiresAt` sem gravar `null`.

Resposta de sucesso contém somente `result`, `operationId`, `entityId`, `version` e `replayed`. Um `requestId` repetido pelo mesmo autor retorna o recibo existente sem nova escrita; um ID já usado por outra identidade ou recibo inválido resulta em conflito. Os códigos estáveis são `invalid_request`, `unauthenticated`, `permission_denied`, `conflict`, `backend_unavailable` e `internal`. Respostas e erros não incluem documentos, token, email, credencial, corpo de erro do Google ou detalhes de Firestore.

## Autenticação e autorização

O gateway Supabase não pode validar um Firebase ID token como JWT Supabase. Por isso, somente `[functions.manage-establishments]` define `verify_jwt = false` em `supabase/config.toml`; o handler valida o bearer Firebase com a assinatura RS256, JWKs oficiais do Secure Token, `aud`, `iss`, tempo e provedor não anônimo. O endpoint não confia em UID/email/versão fornecidos no corpo.

Depois da validação, o handler lê `admin_authorizations/{uid}` por Firestore REST usando OAuth de uma service account e exige `enabled=true`, `pending=false`, uma versão central válida e ausência de `revoked`/`revokedAt`. Essa leitura ocorre dentro da mesma transação Firestore que lê o documento alvo e grava a fonte/outbox; mudança da autorização conflita com a transação. A versão não é comparada com custom claims: esta arquitetura não depende de claims emitidas por Cloud Functions.

O acesso REST usa credencial somente de servidor e ignora as Firestore Rules como qualquer service account. A aplicação, portanto, é responsável por todas as validações; não se deve tratar a candidata Rules da Etapa 04 como defesa do endpoint. A conta de serviço futura precisa ficar limitada ao projeto correto e ao acesso Firestore mínimo praticável. Não há credencial local disponível, então o fluxo OAuth/Firestore foi exercitado somente com `fetch` simulado.

**Revogação:** o endpoint honra a revogação refletida no documento central. `revokeRefreshTokens()` isolado não atualiza esse documento e o ID token assinado ainda pode ser aceito até expirar. A operação confiável de revogação deve primeiro desativar/marcar a autorização central; a sincronização com Firebase Auth permanece uma responsabilidade operacional. O registro versionado central não deve ser alterado por cliente.

## Escrita transacional e outbox

Cada mutação lê autorização, recibo e fonte na mesma transação e envia todas as escritas em uma única `documents:commit` com o identificador de transação. Criação da fonte usa `exists=false`; atualização usa `updateTime`; `requestId` é a chave estável e exclusiva do evento. Conflito ou falha da transação não produz uma gravação parcial segundo o contrato atômico do Firestore.

O evento server-owned usa `schemaVersion=2`, `operationId=requestId`, `entityType=establishment`, `entityId`, `authorUid` derivado do token verificado, versão, `operation=reconcile`, `state=pending`, `attemptCount=0`, campos de lease/retry inicialmente nulos e timestamps `REQUEST_TIME`. O corpo do cliente não pode definir esses campos. Eventos V1 antigos continuam legíveis pelo protocolo/adaptador. A função não conclui nem apaga eventos; somente o consumidor confiável pode avançar o estado.

## Projeção pública

`projectPublicEstablishment` prepara a allowlist da linha interna da tabela Supabase: `id`, `name`, `summary`, `category`, `subcategory`, `image_url`, `published`, `active`, `expires_at` e `deleted_at`, junto aos metadados internos de versão/operação exigidos pelo escritor V2. As RPCs públicas não retornam controles de visibilidade nem metadados internos. Busca e detalhe V1/V2 mantêm projeções explícitas testadas por pgTAP. Telefones, WhatsApp, Instagram, localização/endereço, mapas, dados administrativos, dados de proprietário e chaves desconhecidas não entram na projeção. O processador local usa o protocolo e adaptador do escritor V2; o runtime Edge e o transporte HTTP PostgREST ainda não foram homologados.

As RPCs V1 permanecem limitadas aos IDs `pilot-*` e ao conjunto de filtros V1; a migração V2 acrescenta RPCs que aceitam IDs originais e sua taxonomia aprovada. O sincronizador deve sempre usar o escritor V2. Categorias não empresariais continuam fora do catálogo de estabelecimentos, sem conversão implícita.

## Caminhos atuais e bypasses

- `ContentManager` lê `establishments` diretamente para a lista administrativa.
- Com `HYBRID_ADMIN_ENABLED` desligado (padrão), `ContentEditor` e `InitialContentImporter` preservam o caminho Firestore anterior; essas escritas ainda não geram outbox.
- No modo debug opt-in, `ContentEditor` envia criação/edição/republicação pela API, usa `catalogVersion` como precondição, remove campos de servidor do payload e usa `delete` lógico após confirmação. A tela preserva o mesmo request ID enquanto a operação permanece aberta após resposta ambígua.
- No modo debug opt-in, `InitialContentImporter` filtra a taxonomia empresarial, preserva IDs `modelo-*`, lê cada ID da origem e cria cada documento pelo endpoint com evento atômico. Outras categorias são ignoradas como estabelecimentos.
- `recordAdminAudit()` registra auditoria separadamente; não torna a escrita canônica e outbox atômicas.

Essa integração é somente um caminho de desenvolvimento, desligado por padrão. Ela não substitui ainda a rota do painel em uso: habilitar a API remota requer runtime Edge validado, endpoint autorizado, política de deploy, IAM/segredos e coordenação das Rules. Não publique as Rules candidatas enquanto os clientes que ainda gravam diretamente forem suportados.

As Cloud Functions existentes que ainda atendem fluxos administrativos/de operação são `manageAdminJob` (vagas, sob gate seguro), `uploadHomeImage` (upload administrativo) e o gatilho `deliverPushNotification` (fila de envio). `submitUserOperation` continua sendo callable para operações de usuários e `listPublicContent`/`getPublicContentDetail` seguem servindo conteúdo público; busca local/demo e seus gatilhos não são uma solução de produção Supabase. `admin_claim_management.js` é ferramenta local de operação confiável, não função exportada.

## Configuração do gateway e implantação futura

`verify_jwt=false` é necessário para que o gateway não tente interpretar o token Firebase como token Supabase. A validação Firebase ocorre integralmente no handler. O preflight atual responde `OPTIONS` com origem `*`, mas as respostas POST não incluem `Access-Control-Allow-Origin`; isso basta para Flutter nativo, porém não para Flutter Web. Antes de publicar para uso Web, definir e testar uma allowlist de origens e aplicar cabeçalhos CORS consistentes. Também será necessário confirmar a configuração específica da função na versão/configuração Supabase alvo, prover `FIREBASE_SERVICE_ACCOUNT_JSON` como secret, habilitar Firestore REST, limitar IAM e revisar quotas/limites.

Referências oficiais consultadas: [configuração de Edge Functions e `verify_jwt`](https://supabase.com/docs/guides/functions/function-configuration), [início da transação Firestore](https://cloud.google.com/firestore/docs/reference/rest/v1/projects.databases.documents/beginTransaction), [leitura transacional](https://cloud.google.com/firestore/docs/reference/rest/v1/projects.databases.documents/get) e [commit atômico](https://cloud.google.com/firestore/docs/reference/rest/v1/projects.databases.documents/commit).

O endpoint não adiciona App Check nem rate limit próprio; Auth mais autorização central restringem mutações, mas solicitações inválidas ainda consomem execução e validação de chave. Avaliar proteção de abuso/quota antes de exposição pública. Não armazenar o token Firebase, service-account JSON ou access token em log.

## Testes e limitações desta etapa

Testes Node em `supabase/functions/_shared/*test.mjs` cobrem token/JWK, autorização, operações, replays, concorrência, projeção, rollback/erros sanitizados e formato da transação REST com `fetch` simulado. A CLI Supabase 2.121.0 existe em diretório temporário local, mas Deno não foi encontrado e o Docker Engine está desligado. Como `supabase functions serve` depende do runtime Edge em container, não houve inicialização Deno/Edge nem teste integrado Firestore Emulator. Não ocorreram chamadas a Firebase ou Supabase hospedados, alterações de dados ou migrations.

Pendências para homologação: executar o handler no Supabase Edge Runtime; validar o transporte real PostgREST; resolver identidade de servidor/IAM sem chave estática quando possível; controlar CORS Web, abuso/quotas, revogação e rate limiting; testar o cliente opt-in sem Firebase/Supabase reais; e migrar gradualmente os escritores padrão junto às Rules.

## Estado local da integração administrativa (21/10/2026)

- O endpoint foi ampliado localmente para `republish` com patch editado e `delete` lógico; `unpublish` permanece reversível e não preenche `deletedAt`.
- ID canônico aceita os limites Firestore e o adaptador REST usa percent-encoding nos componentes de caminho; IDs de documento da outbox continuam com validação restrita própria.
- Flutter contém cliente HTTP server-side, payload allowlistado, identidade Firebase não anônima, endpoint fixo/loopback aprovado, timeout, sem retry/fallback, mensagens sanitizadas e opt-in debug desligado por padrão.
- Testes deste ciclo: Node compartilhado 149 aprovados, 0 falhas e 2 testes de integração condicionais ignorados; Functions 185/185; Flutter do cliente 12/12 e ContentEditor 33/33; o resultado final da suíte global deve ser lido no plano mestre.
- Nada foi executado contra os serviços Firebase/Supabase hospedados. Essa evidência é local e não autoriza habilitar o modo híbrido no app instalado.
