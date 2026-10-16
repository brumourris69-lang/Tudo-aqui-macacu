# Contenção de leitura direta e ambiente de homologação

## Objetivo

Preparar uma contenção local para leituras diretas de documentos Firestore completos em `establishments`, `routes`, `utilities` e `jobs`, preservando temporariamente a autorização administrativa publicada, e criar uma variante Android de homologação independente de produção e do Emulator local.

Esta especificação não autoriza acesso ao Firebase real, criação de projeto remoto, execução de Emulator, deploy, migração, instalação de dependências, alteração de usuários, publicação, commit ou push. As Rules principais usadas pelo aplicativo permanecem inalteradas.

## Evidências e limites do diagnóstico

O snapshot somente de leitura obtido na auditoria anterior indicou Rules publicadas que permitem leitura de documentos completos por `get` e `list` em várias coleções públicas. A regra publicada de `utilities` também libera leitura por `active == true`, sem exigir publicação. Um documento de `establishments` tinha os nomes de campos `phone`, `whatsapp`, `instagram`, `maps`, `link`, `additionalInfo` e `source`; não tinha `publicContactApproved`. Nenhum valor do documento é reproduzido nesta especificação.

Esse snapshot remoto não está guardado no repositório. A inspeção local encontrou somente `firestore.rules` e `firestore.claims-local.rules`, que são iguais entre si, mas usam autorização Admin por claim versionada e documento `admin_authorizations`; isso difere da autorização Admin por e-mail que foi observada nas Rules publicadas. Portanto, os arquivos locais não são uma cópia fiel das Rules remotas e não podem ser usados para reconstruí-las.

As leituras remotas anteriores não confirmaram as Functions implantadas; a lista foi negada por permissão. A configuração implantada de Auth, App Check e Admin também tem limites de confirmação descritos no relatório da auditoria. Não presumir qualquer estado remoto além das observações acima.

## Contenção das Rules

Depois de uma autorização separada para obter uma cópia integral e verificável das Rules publicadas — ou de o proprietário fornecer essa cópia — preparar um artefato candidato separado, sem modificar `firestore.rules`, `firestore.claims-local.rules`, `firebase.json` ou a configuração normal do Emulator.

O candidato deve remover `get` e `list` públicos para `establishments`, `routes`, `utilities` e `jobs`. Cada match que hoje permite leitura precisa ser revisto; não basta acrescentar uma regra restritiva, pois permissões correspondentes são combinadas por OR. A regra específica de `utilities` e qualquer match genérico ou recursivo que alcance as coleções protegidas precisam ser atualizados no candidato. Os documentos `job_private` continuam acessíveis somente ao Admin. Coleções fora do escopo mantêm exatamente a política publicada, salvo se uma sobreposição demonstrável exigir correção para evitar acesso alternativo às quatro coleções.

O predicado `admin()` da cópia publicada deve permanecer byte a byte ou semanticamente idêntico durante a contenção temporária, sem criar um novo caminho de Admin nem ampliar a lista de administradores. O candidato não pode ser concluído enquanto a cópia fiel não estiver disponível. Não copiar identificadores pessoais da política remota para documentação, logs ou testes.

Como a regra Admin remota contém um identificador de conta e não há snapshot fiel local, nenhum Rules candidate completo será reconstruído ou gravado agora. Quando houver nova autorização de leitura ou o proprietário fornecer a cópia, preferir uma alteração mínima em forma de patch contra essa fonte verificada; não salvar o identificador em arquivos rastreados, documentação, logs ou fixtures. Se não for possível revisar e testar a política exata sem expor esse identificador, interromper e solicitar uma decisão antes de criar o artefato.

A contenção interrompe leituras diretas de clientes atuais e antigos. O aplicativo normal local ainda está fechado pelo gate de backend e pode depender de Firestore direto em algumas telas; Functions implantadas e compatibilidade das versões antigas não foram confirmadas. O comportamento esperado de versões antigas é erro ou conteúdo indisponível até uma versão cliente compatível. Não criar fallback direto como recuperação.

## Ambiente de homologação Android

Adicionar, após revisão da especificação e plano, um flavor `staging` inicialmente limitado a `stagingDebug`, com `applicationId` distinto, rótulo visual de homologação e configuração Google Services obrigatória fornecida fora do repositório depois da criação autorizada de um projeto Firebase separado. Ausência ou divergência de configuração deve fazer o build/inicialização falhar; nunca usar configuração de produção, `searchLocal` ou valores falsos que pareçam válidos.

O bootstrap de staging valida o flavor, pacote e `projectId` esperado. Auth, Firestore, Functions e App Check usam exclusivamente o projeto de staging. O ambiente demo permanece dedicado a Emulator/loopback. O app normal mantém seu gate fechado e a configuração oficial inalterada.

O gate backend de staging é independente: o servidor só registra contratos públicos quando o ID exato do projeto staging e um opt-in de staging explícito coincidirem, sem hosts Emulator e sem credenciais do projeto real. `SECURE_BACKEND_ENABLED` continua restrito ao fluxo de produção atual; `productionAuthorized` permanece `false`. `getPublicJob` pode ser registrado em staging apenas sob esse gate separado e nunca por meio do registro demo ou da allowlist de produção.

Auth público para chamadas autenticadas pode usar sessão anônima somente no flavor de staging. O Admin de teste é uma identidade fictícia criada e autorizada exclusivamente no projeto staging, usando a política central de claims/versionamento que o código local já espera. Nenhuma conta, claim ou dado real será copiado. App Check de staging usa configuração própria; tokens do provider debug não são embutidos no código nem aceitos em produção. A validação física deve distinguir claramente teste do provider debug e atestação Play Integrity real.

O flavor inicial usa assinatura debug e não tem variante release. Nenhum APK conectado a Firebase real é gerado nesta etapa. A assinatura interna de staging release exige desenho e autorização separados.

## Contratos e dados de staging

Establishments, routes, utilities e jobs reutilizam as projeções explícitas atuais e seus endpoints controlados. Estabelecimentos só publicam telefone, WhatsApp e Instagram com aprovação explícita e validação; utilities sem destino tipado válido são omitidas; Jobs permanecem sem campos administrativos ou não aprovados, e `job_private` nunca entra em respostas públicas. O valor livre de `additionalInfo` e outros campos de texto livre precisa de classificação antes de ser liberado em qualquer projeção.

O banco de staging contém apenas fixtures fictícias criadas especificamente para homologação. É proibida importação, exportação ou cópia de dados de produção ou demo persistente. As Rules de staging preservam autorização Admin versionada e teste de revogação. A criação/configuração do projeto staging é uma dependência externa futura e requer autorização própria.

## Plano de testes

### Estáticos e unitários, sem serviços

- Gate de Rules candidata: comparar os dois arquivos candidatos pertinentes, verificar todos os matches alcançáveis, confirmar bloqueio de leitura pública nas quatro coleções e ausência de regra sobreposta permissiva.
- Matriz Admin: operação autorizada preservada; usuário sem claim, versão ausente/incompatível, autorização revogada ou pendente negada.
- Gate Flutter: flavor staging só aceita seu ID de projeto/pacote; configuração ausente/incompatível falha antes de rede; normal permanece fechado; staging não usa transporte sintético/local; demo não usa endpoints staging.
- Gate Functions: projeto staging exato + opt-in de staging registram endpoints públicos; qualquer projeto inesperado, host Emulator, configuração ausente ou gate de produção isolado não ativa staging; `getPublicJob` não passa a ser exportado para produção.
- Contratos: projeções por coleção, publicação/atividade/expiração, aprovação explícita de contato, destinos seguros, paginação, Auth/App Check e erros sem fallback.

### Integração futura em Emulator

Somente após autorização específica: executar Rules candidatas em instância demo descartável e separada, com Auth/Firestore/Functions em loopback, sem importar/exportar dados. Testar visitante, comum, anônimo, Admin autorizado e revogado; `get`, `list`, `create`, `update`, `delete`; controles públicos fora do escopo; `job_private`; projeções Functions; limpeza exclusiva de fixtures. O teste de App Check sintético do Emulator não certifica atestação Android real.

### Dispositivo físico staging

Após projeto e configuração staging autorizados: verificar o `applicationId`, projeto Firebase, endpoint, assinatura e App Check empacotados; instalar lado a lado sem limpar dados de outras apps; testar Auth, listagem/detalhe, erros/retry, acesso Admin/revogação, rede offline e retorno. Examinar somente logs sanitizados e usar dados fictícios.

## Rollout e recuperação

1. Obter snapshot Rules fiel e resolver os testes de Admin sem copiar valores pessoais para o repositório.
2. Produzir e revisar Rules candidata separada; rodar testes estáticos/unitários.
3. Obter autorização para validar candidata no Emulator demo descartável.
4. Criar/configurar Firebase staging sob autorização separada, inserir apenas fixtures fictícias e validar Functions/Auth/App Check.
5. Implementar/buildar `stagingDebug` e testar em aparelho físico sob autorização própria.
6. Planejar separadamente qualquer publicação de Rules, Functions ou app de produção; esta especificação não autoriza tais ações.

Se a aplicação staging ou o app atualizado falhar, manter o bloqueio público das Rules e corrigir/desativar o fluxo cliente/servidor afetado; não restaurar acesso direto como fallback. Reverter Rules para o snapshot permissivo pode reabrir exposição e exige autorização própria. Se o Admin candidato não funcionar com o predicado preservado, interromper em vez de ampliar a política.

## Critérios de aceite e bloqueios

- Nenhuma leitura pública direta nas quatro coleções no candidato e nenhuma permissão sobreposta que reabra acesso.
- Admin preservado sem expansão e revogação efetiva comprovada em Emulator.
- App normal continua sem acesso ao backend seguro; staging é side-by-side e falha fechado se a configuração divergir.
- Nenhum dado real é copiado ou modificado; nenhum APK real é gerado.
- Rules candidatas não podem ser concluídas sem a cópia remota fiel. O projeto staging remoto não pode ser provisionado nesta etapa.
- Nenhuma alegação de prontidão de homologação/produção antes da validação integrada e autorização de implantação.
