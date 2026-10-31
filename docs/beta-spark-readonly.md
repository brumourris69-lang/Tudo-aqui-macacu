# Beta Spark: Firestore direto, sem Functions ou Storage

Esta configuração prepara localmente a variante Beta para Spark. Ela não cria
serviços, altera projetos hospedados nem publica Rules. `firebase.beta.json`
inclui somente as Rules Beta e a configuração de Hosting para arquivos estáticos;
não declara Cloud Functions, índices de busca, backfill ou TTL.

## Dados públicos

Visitantes usam o SDK cliente do Firestore sem conta. As leituras paginadas
consultam apenas `beta_public_catalog/{coleção}/items/{id}`. Essa projeção
separada contém uma lista explícita de campos públicos; os documentos canônicos
e dados privados não são legíveis por usuários comuns. O app limita páginas a
40 documentos e interrompe listagens acima de 400. Conteúdo em rascunho,
inativo ou excluído não deve ter projeção.

## Edição administrativa no Spark

Os editores existentes da Home, comércios, turismo, eventos, utilidades e vagas
gravam diretamente no Firestore com SDK cliente. Cada publicação grava o
documento canônico e a projeção permitida na mesma transação. Rascunhos,
desativações e tombstones removem a projeção na mesma operação. Exclusões do
Beta são lógicas; registros tombstonados não podem ser restaurados pelo cliente.

Admin exige **ambos**: custom claims `admin` e `adminVersion` assinados fora do
aplicativo, mais `/admin_authorizations/{uid}` provisionado fora do aplicativo
com `enabled: true`, `pending: false` e a mesma versão. As Rules verificam a
autorização em cada gravação; o cliente não pode criar ou editar esse registro.
As Rules permitem leitura e alteração de conteúdo somente a Admin. Provisionar
claims e o registro administrativo continua sendo uma tarefa operacional fora
do aplicativo.

Vagas guardam contatos e detalhes privados em `job_private/{id}`; somente a
projeção pública allowlisted pode ser lida por visitantes. Favoritos e itens da
Minha Agenda continuam em `users/{uid}/favorites`, isolados por conta. Contato,
propostas, avaliações e votos são gravações diretas limitadas e moderadas;
métricas de servidor, tokens push e envio remoto de notificações ficam desligados
no Spark. Lembretes locais do dispositivo não dependem de Functions.

## Navegação, busca e mídias

A busca global e os pontos de entrada de busca na Home e em Explorar Macacu ficam
fora da variante Beta. A busca avançada, índices, backfill, callables, gatilhos e
TTL pagos permanecem no código legado para uma atualização futura, sem serem
usados por esta configuração. O conteúdo é acessado pelas categorias já
existentes.

O editor Beta aceita URLs HTTPS de mídias já hospedadas; seleção local seguida
de upload e atalhos para upload externo ficam desativados. `public/media/` é o
diretório reservado para arquivos estáticos que poderão ser incluídos no
Firebase Hosting gratuito. O Hosting precisa ser habilitado no projeto Beta e
publicado separadamente, mediante autorização. Não há upload pelo app e nenhum
segredo de upload está embutido. Um futuro upload direto requer avaliação
separada de autenticação, tamanho, tipos, moderação e custo.

## Regras de publicação e limites

`firestore.beta.rules` foi exercitado localmente com Auth/Firestore Emulators e
SDK cliente: 39/39 assertions passaram, incluindo visitante, escrita Admin
autenticada, revogação, projeção pública, Eventos, isolamento de favoritos e
agenda, edição de payload completo, transação de rascunho, publicação,
despublicação, tombstone permanente e negação de exclusão física. Isso é
evidência local, não homologação hospedada nem revisão independente. O Firebase App Check
é uma proteção adicional: o gate do aplicativo não comprova enforcement no
serviço nem atestação real do Play Integrity.

Para uso gratuito, Firestore precisa permanecer dentro das cotas Spark vigentes.
Acima das cotas ou para recursos incompatíveis, o produto pode deixar de atender
sem faturamento; não há garantia de custo zero fora dos limites do plano.

Antes de lançar, testar com SDK cliente Admin/usuário/visitante, confirmar a
projeção de ponta a ponta, provisionar Admin fora do app, conferir App Check,
limites do plano, cotas, região, retenção e política de dados. Nenhuma operação
hospedada está autorizada por este documento.

## Preparação de homologação Spark — estado em 2026-10-31

### Evidências locais disponíveis

- Regras candidatas: `firestore.beta.rules`; SHA-256 esperado:
  `E87EA73BC2797C34C5DBFD60DBB42C273838AA583EFC68265214F55CD8E61BEB`.
- `firebase.beta.json` referencia somente esse arquivo de Rules e Hosting
  estático. Não inclui `functions`, `storage`, configuração de índices ou TTL.
- `tools/beta-backend-preflight.mjs` é um preflight legado de Functions: exige
  um conjunto de callables, backfill/índices e TTL e produz um comando de deploy
  de Functions. Ele **não é compatível com a etapa Spark** e não foi executado
  nem deve ser usado para autorizar publicação Spark.
- No Spark, a documentação oficial do Firebase lista Cloud Functions como
  indisponível. Cloud Storage para Firebase também requer Blaze para novo
  acesso ao bucket; o Beta não pode depender dele. Firestore Standard no Spark
  inclui uma base gratuita por projeto e, hoje, quotas de 1 GiB armazenado,
  50 mil leituras/dia, 20 mil gravações/dia, 20 mil exclusões/dia e 10 GiB/mês
  de transferência; exceder quota pode suspender aquele produto até o próximo
  período, então isso não é capacidade ilimitada nem garantia operacional.
  TTL, PITR, backup, restore e clone de Firestore exigem billing. Firebase
  Hosting estático é opcional (até 10 GB de arquivos e 10 GB/mês de
  transferência sem custo); se usado, controlar esses limites. O fluxo Beta
  pode usar URLs HTTPS já existentes e não precisa publicar Hosting para ler
  os dados do catálogo.
- Em `BetaPublicCatalog`, listas filtram `visibility == public`, ordenam por
  ID, usam páginas de até 40 e param em 400; detalhes usam a mesma projeção
  pública. A edição Spark grava canônico e projeção na transação. Rascunhos,
  conteúdo inativo e tombstones retiram a projeção.
- As leituras/escritas Beta exercitadas por `SecureBackend` recusam callables;
  o repositório Beta de vagas também lê a projeção Firestore e o editor usa
  `SparkAdminJobRepository`. Upload/seletor de arquivo local está desativado
  para Beta. URLs HTTPS pré-existentes são aceitas. `cloud_functions` ainda
  consta nas dependências compartilhadas e há código legado para outros
  flavors; isso não equivale a uso pelo caminho Beta. O projeto Spark não
  recebe ou publica Functions por esta configuração.
- Testes Flutter direcionados já executados sequencialmente na etapa anterior:
  82 aprovações em testes de Home/Admin, editor/persistência e estabelecimentos.
  O teste integrado de ciclo Admin no Android não foi executado. A suíte ampla
  anterior terminou por falta de memória (813 passaram, 24 ignorados e 10 não
  concluíram); não é aprovação completa da suíte.
- Nesta revisão Spark 1.8 foram executados, sem paralelismo, os testes de
  `beta_environment`, `spark_admin_content_repository`, `home_admin_edit`,
  `content_editor_persistence`, `beta_flavor_contract`,
  `beta_public_backend_gate`, `public_content`,
  `public_content_detail_repository`, `favorites_experience`,
  `my_agenda_view`, `tourism_admin_manager`, `tourism_admin` e
  `tourism_editor`: **96 passaram** e **6 foram
  ignorados** no teste de detalhes. O de Home confirmou os botões de edição,
  edição direta de atalhos e bloqueio da interface Admin para usuário comum.
  Não se deve somar estes lotes como resultado de uma suíte completa.
- O harness de Rules SDK cliente anterior comprova transações e o contrato das
  Rules, mas não instancia `SparkAdminContentRepository` Dart real contra o
  Emulator. O teste de repositório Flutter executado nesta rodada cobre a
  projeção allowlist/tombstone, não um ciclo de transações Dart ponta a ponta.
  Essa integração fica pendente para um aparelho físico autorizado ou teste de
  integração local dedicado; o ciclo visual Android também não foi observado.
- `flutter analyze --no-pub`: aprovado, sem issues. Preflight estático local:
  hash da Rules, alvo da configuração, projeto e pacote Beta conferidos; passou.
  `git diff --check`: passou (Git emitiu avisos de normalização LF/CRLF em
  arquivos preexistentes). Não foram compilados APKs nem executados Emulators
  ou AVD nesta rodada.
- O APK/fluxo visual não foi validado nesta etapa. Não iniciar o AVD sobrecarregado.
- Nenhuma consulta ou gravação hospedada foi feita para este checklist. Logo,
  existência do Firestore `(default)`, Rules ativas, região, providers Auth,
  enforcement App Check, cotas atuais do projeto e existência de dados Beta
  continuam **não confirmados**. O arquivo local de configuração não comprova
  o estado remoto.

### Verificação de consulta e índices

Nas rotas Beta atuais, `visibility` é o único filtro da projeção pública e a
ordenação é por `FieldPath.documentId`; detalhes combinam o marcador público e
ID do documento. O cliente administrativo de vagas ordena somente pelo ID.
Essas consultas usam índices de campo único/ID que o Firestore mantém por
padrão; a inspeção estática não encontrou combinação que exija índice composto
adicional. Consultas sem filtro/ordenação composta (por exemplo `orderBy` de
um único campo) também não exigem um índice composto. Isso não substitui um
teste no banco hospedado: se filtros ou ordenações forem adicionados, seguir o
erro de índice e revisar o índice antes de publicar. Os índices de busca e
configurações TTL de `firestore.indexes.json` pertencem a outros caminhos e
não são referenciados por `firebase.beta.json`.

### Checklist executável — antes de pedir autorização de configuração

1. **Confirmar o destino em toda sessão:** o único ID permitido é
   `macacu-beta-261030-cf4a81`. Não use alias/default. Verifique a conta e o
   ID no Console e na CLI; interrompa se qualquer saída indicar outro projeto.
2. **Plano e custos:** confirmar Spark e ausência de faturamento vinculado.
   Se uma função necessária depender de Blaze, não migrar plano: a variante
   Spark não deve depender dessa função. Conferir cotas Firestore antes de
   abrir o Beta e limitar leituras/paginação no app. No Spark, exceder cotas
   gratuitas pode interromper o serviço; orçamento/alertas de Cloud Billing
   não substituem limites de consumo e podem exigir Blaze, portanto não ativar
   faturamento para obtê-los neste plano.
3. **Firestore:** se autorizado, criar o banco `(default)` uma única vez,
   escolher Standard e região compatível com usuários, Auth e latência. Região
   é uma decisão de criação difícil de reverter. Confirmar a tela de região e
   identidade do projeto antes de confirmar criação.
4. **Auth e App Check:** habilitar somente provedores planejados (e-mail/senha
   e Google, se necessários) e confirmar pacote/SHA e cliente OAuth Beta.
   Verificar o estado App Check separadamente para Authentication, Firestore e
   Functions. Não habilitar enforcement até a atestação real do app de teste
   ser comprovada; não substituir por debug provider em distribuição.
5. **Rules e projeção:** obter o Release/Ruleset que estiver ativo e guardar
   cópia exata antes de qualquer publicação. Provisionar uma conta Admin
   sintética fora do cliente: custom claims assinadas (`admin` e
   `adminVersion`) **e** `/admin_authorizations/{uid}` com `enabled: true`,
   `pending: false`, `version` correspondente. Não existe autoelevação pelo
   app. Use mecanismo administrativo confiável/impersonação temporária e
   privilégio mínimo; nunca embutir chave de serviço no app nem commitá-la.
6. **Conteúdo:** com autorização, criar somente fixture sintética. Publicar
   pelo editor transacional para gravar canônico e projeção; verificar acesso
   de visitante e negação de rascunho/privado. Não importar dados pessoais
   nesta homologação.
7. **Conferir candidato:** antes do deploy, executar:

   ```powershell
   $target = 'macacu-beta-261030-cf4a81'
   if ($target -cne 'macacu-beta-261030-cf4a81') { throw 'Projeto inesperado' }
   $rulesHash = (Get-FileHash -LiteralPath .\firestore.beta.rules -Algorithm SHA256).Hash.ToUpperInvariant()
   if ($rulesHash -cne 'E87EA73BC2797C34C5DBFD60DBB42C273838AA583EFC68265214F55CD8E61BEB') { throw 'Hash das Rules divergiu' }
   $config = Get-Content -Raw .\firebase.beta.json | ConvertFrom-Json
   if ($config.firestore.rules -cne 'firestore.beta.rules') { throw 'Config aponta para Rules inesperadas' }
   if ($config.PSObject.Properties.Name -contains 'functions' -or $config.PSObject.Properties.Name -contains 'storage') { throw 'Config inclui serviço fora do escopo Spark' }
   ```

   Rever identidade e Release ativos imediatamente antes da publicação. Se
   configuração, hash ou Release divergirem, parar e não publicar.

### Procedimento de publicação e reversão (não executado)

Publicação exige autorização explícita posterior. Depois do backup hospedado e
do preflight aprovado, a única forma prevista para Rules candidatas é usar o
ID literal, sem alias:

```powershell
firebase deploy --only firestore:rules --config .\firebase.beta.json --project macacu-beta-261030-cf4a81
```

Esse comando é apenas referência; **não foi executado**. Após a publicação,
consultar o Release e Ruleset ativos, validar que correspondem ao candidato,
depois executar SDK cliente como visitante, usuário comum, Admin, Admin
revogado e duas contas isoladas. Confirmar que projeções, rascunhos e
tombstones obedecem ao contrato.

Para reversão, usar o arquivo de Rules hospedadas salvo antes da publicação e
uma configuração Firebase temporária que aponte explicitamente para esse
backup. Antes de reverter, consultar o Release ativo de novo. Só reverter se
ele ainda corresponder ao Ruleset publicado por esta execução e não houver
mudança concorrente. Em caso de divergência, **não sobrescrever**: interromper
e escalar ao responsável do projeto. Após reversão autorizada, confirmar por
leitura Release/Ruleset/hash. Não existe lock local que impeça uma publicação
externa.

### Roteiro de aparelho físico isolado

Quando um aparelho de teste dedicado for autorizado (ASUS e MEmu permanecem
fora do escopo): conferir modelo/Android, pacote/flavor Beta e projeto exibido
pela tela de diagnóstico sem registrar tokens; remover contas e dados pessoais
do aparelho; instalar build Beta de debug; confirmar conectividade e App Check
real; entrar com Admin sintético e criar conteúdo sintético, salvar rascunho,
editar, publicar, abrir como visitante em sessão separada, despublicar e
tombstonar. Conferir estado canônico/projeção no Console sem expor dados.
Testar usuário comum e Admin revogado; encerrar removendo fixtures/contas
criadas para a execução. Guardar apenas logs redigidos e resultados. Não usar
esse roteiro como prova até executá-lo em dispositivo.

### Decisão e autorizações pendentes

**NO-GO para configuração hospedada agora; GO para solicitar autorização
específica da próxima etapa.** Ainda faltam confirmação remota de Spark,
Firestore `(default)`/região, Auth, App Check e Rules ativas; autorização
específica para criar o banco se ausente, configurar Auth/App Check, provisionar
Admin sintético, publicar/reverter Rules e criar/remover fixtures; e acesso a
um aparelho físico isolado para prova final. Nenhuma dessas operações foi
realizada aqui. Não declarar o Beta pronto para produção.

### Homologação controlada Spark Beta — 31/10/2026

- Projeto confirmado por ID explícito: `macacu-beta-261030-cf4a81`, número
  `194904519821`, ativo. O Console e o Firebase MCP confirmaram plano Spark e
  billing desabilitado. O alias `default` no checkout normal aponta para
  produção; não foi usado. O único alvo de publicação foi um diretório temporário
  isolado com `.firebaserc` explícito para o Beta e `firebase.json` contendo
  somente Firestore Rules.
- Criado o Firestore Standard `(default)` em `southamerica-east1`, sem billing.
  O banco foi confirmado vazio no Console. O Release inicial tinha deny-all;
  snapshot bruto salvo fora do repositório em `firestore.previous.rules`, SHA-256
  `ECF30F940747DCC3C5BA4993093E9A11AC9FC5DF7E14B2A1512D2446923D84EB`.
- O candidato local `firestore.beta.rules` conferiu SHA-256
  `E87EA73BC2797C34C5DBFD60DBB42C273838AA583EFC68265214F55CD8E61BEB`.
  Uma primeira chamada de deploy com escopo `firestore:rules` reportou sucesso,
  mas a leitura continuou em deny-all; nenhum estado foi avançado com base nesse
  retorno. Repeti com o escopo suportado `firestore` e a configuração isolada,
  confirmei o texto candidato via leitura hospedada e executei os testes abaixo.
- SDK cliente Firebase JS 11.10.0, sem Auth para o visitante, confirmou leitura
  autorizada das consultas paginadas de `establishments`, `public_places`,
  `utilities` e `events` (todas vazias, pois não havia conteúdo sintético
  publicado). Foram negados: consulta sem marcador público, leitura canônica de
  estabelecimento, leitura de rascunho da Home, leitura/gravação de
  `admin_authorizations`, escrita canônica, escrita de projeção e publicação da
  Home por usuário comum. Duas contas sintéticas de e-mail/senha foram criadas
  pelo SDK, a conta A gravou seu favorito, a conta B não conseguiu listar, ler
  nem gravar favoritos da A. A fixture de favorito e as duas contas foram
  removidas; a rotina de limpeza terminou sem erro.
- **Admin autorizado/revogado não foi testado.** Não há ferramenta conectada de
  Admin SDK/Identity Platform para emitir `admin`/`adminVersion` nem provisionar
  o registro versionado. O Cloud Shell foi apenas aberto até o diálogo inicial;
  não foi iniciado, nenhum termo foi aceito e nenhuma chave foi criada. Sem esse
  canal confiável, não simulei claims nem usei a conta pessoal como Admin. Como
  consequência, não foram criados documentos de conteúdo, não se testaram
  publicação/despublicação/tombstone com Admin e o acesso aos dados públicos
  reais continua sem prova.
- Após essa cobertura parcial, a homologação não atingiu o critério de aprovação.
  Revalidei que o Release ainda correspondia ao candidato desta execução,
  publiquei o backup deny-all pelo mesmo diretório isolado e confirmei por
  Firebase MCP e Console que o estado final voltou ao deny-all acima. O candidato
  permanece apenas local; nenhuma fixture ou conta desta execução ficou.
- Auth: e-mail/senha e Google já estavam habilitados; nenhuma configuração foi
  alterada. App Check: o app Android Beta não estava registrado. Firestore
  constava como **Não aplicado** (sem enforcement). Authentication constava em
  **Monitorando**, com 0% verificado e 100% sem verificação; não é enforcement.
  Não registrei provedor nem alterei os estados.
- Configuração Beta estática: `firebase.beta.json` inclui Firestore Rules e
  Hosting estático; não inclui Functions, Storage nem TTL. O pacote não foi
  implantado e nenhum serviço além de Firestore/Auth já existentes foi alterado.
- Resultado: **NO-GO para homologação hospedada completa e para testes físicos
  como Admin**; **infraestrutura preparada, vazia e fail-closed**. A próxima
  ação indispensável é disponibilizar um procedimento aprovado de Admin SDK com
  credenciais temporárias/impersonação para criar claims e registro de Admin,
  seguido de nova publicação controlada e testes com fixture. Não usar cliente
  para se autoelevar.

### Rechecagem do canal Admin SDK — Spark 2.1 (31/10/2026)

- Reconfirmados o projeto `macacu-beta-261030-cf4a81`, billing desabilitado,
  Firestore `(default)` no estado deny-all e o hash local da candidata
  `E87EA73BC2797C34C5DBFD60DBB42C273838AA583EFC68265214F55CD8E61BEB`.
- Bloqueio concreto: não há `firebase` ou `gcloud` executável no PATH, ADC local
  ou variável `GOOGLE_APPLICATION_CREDENTIALS`. A lista de ferramentas Firebase
  conectadas oferece leitura de projeto/Rules e publicação, mas nenhuma operação
  de Admin SDK, Identity Toolkit Admin, criação de usuários ou custom claims.
  Portanto, não foi possível consultar IAM efetivo nem houve erro IAM negando
  uma chamada: a chamada administrativa não pôde ser feita por falta de canal
  autenticado compatível.
- Não criei contas, claims, registros Admin ou documentos; não publiquei Rules
  nesta rechecagem e não alterei IAM. O estado hospedado continua deny-all.
- Decisão: **NO-GO mantido**. O próximo requisito é disponibilizar um executor
  Admin SDK aprovado com ADC/impersonação temporária, sem chave de serviço
  permanente, e com acesso restrito ao projeto Beta; então repetir a validação
  do Release antes da publicação temporária.
