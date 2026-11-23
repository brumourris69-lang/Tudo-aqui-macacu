# Exclusão de conta — revisão técnica e operação Beta/Spark

Este documento descreve o comportamento do código local nos caminhos Beta e de
distribuição Firebase Spark;
não comprova a configuração hospedada nem significa que o atendimento externo
esteja operacional. O fluxo exige a sessão da própria conta, confirmação no
aplicativo e reautenticação recente. A identidade no Firebase Auth é removida
somente depois da limpeza autorizada dos dados. Para passos operacionais, use
também o [checklist interno de revisão](privacy-drafts/operational-deletion-checklist.pt-BR.md).

## Dados cobertos pelo fluxo do aplicativo

- Perfil `users/{uid}` e favoritos da subcoleção `favorites`.
- Dispositivos vinculados ao UID, registros de contato, métricas históricas e
  notificações/filas endereçadas ao UID ou e-mail atual quando as Rules permitem
  confirmar a titularidade.
- Cota de envio em `contact_message_limits/current`, quando a janela atual de
  24 horas já terminou.
- Mensagens em `contact_messages`, propostas em `business_proposals`, avaliações
  em `reviews` e votos em `polls/*/votes/*` cujo campo `uid` corresponda à conta.
- Preferências e lembretes de eventos locais vinculados ao UID neste aparelho.
- Identidade da conta no Firebase Authentication. Para contas Apple configuradas,
  o código de autorização temporário é usado para revogar o token Apple antes da
  exclusão da identidade; ele não é persistido.

As operações usam consultas limitadas e exclusão paginada. A cota é conferida e
excluída primeiro, usando o horário do servidor nas Rules. Se ainda estiver
dentro das 24 horas, o aplicativo grava imediatamente
`account_deletion_requests/{uid}` com somente UID, horário do servidor,
`retryAfter` e estado `pending`. A gravação não remove os dados remotos nem a
identidade Auth. A cota permanece intacta e as Rules bloqueiam novas mensagens
enquanto houver um pedido pendente. O aplicativo limpa os lembretes e preferências
locais após confirmar a gravação do pedido; se essa limpeza falhar, informa que o
pedido foi registrado, mas que a limpeza local não terminou.
Essa limpeza alcança somente a instalação que enviou o pedido; dados locais em
outros aparelhos não podem ser apagados remotamente e precisam ser removidos ao
sair da conta ou desinstalar o aplicativo nesses aparelhos.

O documento é acessível por `get` somente ao próprio usuário e por leitura
paginada a Admins autorizados; usuários não podem editar ou descartar pedidos.
Uma segunda tentativa com a mesma conta reutiliza o pedido pendente. Depois de
`retryAfter`, o usuário pode reautenticar e concluir a exclusão no aplicativo:
os dados próprios são limpos, o perfil e o pedido são removidos juntos e o Auth
é excluído por último. A Rule exige que a cota já não exista e que perfil e pedido
sejam removidos na mesma gravação. Falhas deixam o Auth ativo e nunca são
apresentadas como exclusão concluída.

## Conclusão manual de pedidos pendentes

O inventário do que o MVP pode criar, as gravações bloqueadas, as limitações de
registros legados e o procedimento mínimo para limpeza operacional estão em
[Exclusão no Spark — escopo e operação histórica](account-deletion-spark-runbook.md).

Não há trabalhador automático, prazo de atendimento configurado nem aviso de
conclusão. O titular do app designou a si mesmo como operador inicial, usando
o e-mail de contato do app, e aprovou revisar a fila diariamente com meta
interna de até 7 dias corridos. Essa meta é um alvo operacional, não SLA público,
prazo legal ou promessa. Um suplente foi designado e recebeu um papel IAM
personalizado no projeto de distribuição. Foi observado que sua conta abre o
IAM do projeto e vê o papel. Em 14/11/2026, o responsável informou que o
suplente confirmou MFA e acesso à planilha; isso não foi verificado
independentemente. O fluxo de exclusão ponta a ponta ainda não foi testado.

O pedido fica em `account_deletion_requests/{uid}`. Seus campos são somente
`uid`, `requestedAt` (horário do servidor), `retryAfter` e `status: pending`.
Não há e-mail, senha, mensagem de contato nem cópia de documento nesse registro.
O próprio usuário pode ler somente o seu pedido. Um Admin do aplicativo tem
leitura paginada limitada pelas Rules, mas a interface atual não oferece uma
fila. Para a rotina manual, o operador precisa autenticar-se com uma identidade
Google individual e MFA. O papel personalizado foi concedido somente no projeto
de distribuição `tudo-aqui-macacu`; ele não concede acesso ao projeto Beta.
Ser Admin dentro do aplicativo não concede acesso IAM nem substitui essa
autorização.

O papel `projects/tudo-aqui-macacu/roles/accountDeletionOperator` contém oito
permissões: `firebaseauth.users.get` e `firebaseauth.users.delete`;
`datastore.entities.get`, `.list` e `.delete`; e `datastore.databases.get`,
`.getMetadata` e `.list`. Não permite criar/alterar usuários ou documentos,
alterar IAM, publicar Rules ou fazer deploy. O escopo é o projeto inteiro:
permite ler dados Firestore e excluir qualquer usuário Auth ou documento
Firestore do projeto, não somente o registro de uma pessoa específica. O
endereço do suplente fica apenas no IAM e não é copiado para esta documentação.
O vínculo do papel não comprova que o suplente consegue entrar ou executar o
procedimento.

### Rotina proposta para o operador

1. Para solicitações da distribuição Spark, abrir `tudo-aqui-macacu`, confirmar
   o ID do projeto e o banco `(default)`; o papel do suplente não dá acesso ao
   Beta. Consultar `account_deletion_requests` com `status == pending`, ordenar por
   `requestedAt` e conferir `retryAfter`. O titular do app é o operador inicial
   e aprovou revisar a fila diariamente, com meta interna de buscar concluir em
   até 7 dias corridos, sem garantia.
2. Selecionar um pedido pelo ID/UID exato. Não copiar dados para fora do Console.
   Não iniciar a limpeza antes de `retryAfter`; até lá o usuário ainda pode
   concluir a exclusão por conta própria no aplicativo.
3. Para um pedido vencido que não foi concluído pelo usuário, conferir a
   identidade Auth pelo UID. Apagar somente documentos que pertencem exatamente
   a esse UID: favoritos em `users/{uid}/favorites`; mensagens, propostas e
   avaliações filtradas pelo campo `uid`; votos encontrados por grupo de
   coleções `votes` e filtrados por `uid`; a cota em
   `users/{uid}/contact_message_limits/current`; e então o perfil
   `users/{uid}`. Nunca apagar projeções públicas, conteúdo da cidade ou dados
   de outro UID.
4. Excluir a identidade no Firebase Authentication pelo mesmo UID, depois da
   limpeza Firestore. Se Auth já informar que esse usuário não existe, confirmar
   a ausência pelo UID e continuar a verificação idempotente; não procurar nem
   apagar conta por e-mail aproximado.
5. Só depois de confirmar a limpeza e a ausência da identidade Auth, apagar o
   documento de pedido. Não há operação de status “concluído” nas Rules.
6. Registrar em controle operacional restrito apenas UID/ID do pedido, data,
   operador, resultado ou tipo de falha; não registrar conteúdo, senha, tokens
   ou documentos. Esse registro também contém identificador pessoal. A planilha
   privada está criada e compartilhada com o suplente como Editor. Os metadados
   confirmam a permissão. O responsável informou que o suplente abriu a planilha;
   essa confirmação não foi verificada independentemente. A aba de pedidos reais
   segue vazia e o ensaio sintético está separado. O MFA
   da conta primária foi confirmado pelo titular, sem verificação independente.
   O titular propôs excluir a linha 7 dias corridos após a conclusão, ainda
   pendente de revisão operacional e jurídica.

As operações do Console usam credenciais privilegiadas e ignoram Firestore
Rules. A rotina exige conferência independente de projeto, UID e propriedade em
cada etapa; não deve ser executada por conta pessoal compartilhada ou por
credenciais embutidas no aplicativo. Se qualquer passo falhar, deixar o pedido
na fila, registrar a etapa que falhou e retomar do início: as exclusões de
documentos já ausentes são repetíveis. Se Auth já foi removido, terminar apenas
após verificar os documentos restantes e então remover o pedido. Nunca remover
o pedido no começo nem informar conclusão antes da verificação final.

**Ainda pendente:** validar independentemente a confirmação de MFA e acesso à
planilha, e ensaiar o procedimento ponta a ponta com autorização apropriada. O papel IAM
do suplente permite leitura e exclusão em todo o projeto, sem restrição por UID;
ele não recebeu acesso Beta. O titular confirma que a verificação em duas
etapas da conta Google usada na planilha está ativa; a informação não foi
verificada independentemente e não prova acesso IAM ao projeto. O responsável
propôs apagar cada registro 7 dias corridos após a conclusão; é uma proposta de
retenção, distinta da meta de processamento de até 7 dias, ainda pendente de
revisão operacional e jurídica. Uma planilha
privada vazia foi criada; as permissões observadas estavam restritas à conta
proprietária e o titular informou que consegue abri-la. O titular também relatou
que o teste manual de ida e volta do e-mail funcionou, sem verificação
independente. A designação do titular como operador e a meta interna diária/de
até 7 dias foram aprovadas, mas não existe SLA automático no Spark; pedidos podem
exceder a meta ou permanecer pendentes enquanto o processo não estiver
operacional.

Depois da conclusão, a cota, o perfil, os dados pessoais cobertos, a identidade
Auth e o pedido são removidos. Enquanto o pedido aguarda a janela e a execução,
permanecem a conta Auth e os dados remotos já descritos, além do documento
`account_deletion_requests/{uid}`. Esse documento da fila no Firestore é removido
ao concluir; a linha separada do controle operacional tem proposta de retenção
por 7 dias corridos após a conclusão, ainda pendente de revisão. Não há limpeza
automática no Spark.

## Dados que permanecem

- Conteúdo compartilhado da cidade, publicações administrativas e projeções
  públicas não pertencem exclusivamente ao usuário e não são apagados.
- `admin_authorizations` e registros de auditoria são protegidos. Uma conta
  Admin não pode se excluir pelo aplicativo; um responsável deve desativar e
  tratar essa conta separadamente.
- A exclusão da conta Firebase não apaga a conta Google ou Apple do usuário.
- Arquivos históricos fora do escopo Beta, dados em outros projetos ou dados
  sem UID verificável não são removidos por este fluxo.

Não há, no código atual, um prazo formal de retenção para registros de auditoria.
Esse prazo e a base aplicável precisam ser definidos na política de privacidade
antes do lançamento. Este documento descreve o comportamento técnico e não
substitui revisão jurídica nem uma política pública validada.

## Pedidos externos e acompanhamento — proposta pendente

As páginas em `docs/privacy-drafts/` são rascunhos locais. A configuração
existente `firebase.beta.json` já usa Firebase Hosting estático e aponta para
`public/`, mas os rascunhos ficam fora dessa pasta; não alterei a raiz pública
nem a configuração de deploy. A página de índice permite revisar os dois
documentos localmente. Hosting estático usa a cota sem custo do Spark; exceder
os limites do plano não deve ser resolvido ativando Blaze sem nova autorização.

O titular do app foi designado operador inicial e confirmou acesso à caixa
`tudoaquimacacuapp@gmail.com`. Em 14/11/2026, informou que um teste manual de
ida e volta do e-mail funcionou; não houve verificação independente. Um
suplente recebeu papel IAM personalizado no projeto de distribuição. Foi
observado que sua conta abre o IAM do projeto e vê o papel; MFA e execução de
exclusões não foram verificados. O papel permite leitura e exclusão no projeto
inteiro, sem restrição por UID. A planilha de acompanhamento foi compartilhada
com o suplente como Editor em 14/11/2026; os metadados confirmam a permissão,
mas a abertura pela conta suplente não foi testada. A revisão
diária e a meta interna de até 7 dias corridos foram aprovadas, mas não são
prazo público nem garantia. O link `mailto:` abre um aplicativo de e-mail; não
envia a mensagem nem registra ou confirma automaticamente um pedido. Não
apresentar o processo como operacional até aprovar o controle restrito e sua
retenção e validar a conclusão ponta a ponta. Modelos e roteiro estão no
[checklist interno](privacy-drafts/operational-deletion-checklist.pt-BR.md).

Se aprovado, o procedimento externo proposto é:

1. O solicitante enviaria uma mensagem contendo apenas o endereço da conta e o
   pedido; a página deve pedir que não envie senha, token, documento ou outros
   dados sensíveis.
2. O operador localizaria no Firebase Authentication o usuário pelo endereço
   exato e confirmaria que ele está verificado. Como confirmação de controle da
   caixa, o operador responderia ao endereço verificado e aguardaria uma
   confirmação explícita. Sem correspondência exata ou endereço verificado,
   não excluiria conta por nome, UID fornecido ou informação aproximada;
   orientaria o solicitante a usar o fluxo autenticado do aplicativo. Contas
   Admin exigem processo separado, sem autoexclusão.
3. Só depois de confirmar a titularidade, o operador criaria um registro
   operacional restrito e mínimo: referência do pedido, UID, recebimento,
   vencimento da cota quando aplicável, estado, operador e código de resultado
   ou falha. Não copiaria o conteúdo da mensagem. O registro pode conter dado
   pessoal e seu local de guarda, acesso e prazo de retenção ainda precisam de
   aprovação.
4. Um operador com autorização IAM própria e MFA conferiria o projeto correto
   (`tudo-aqui-macacu` para a identidade de distribuição; Beta é separado),
   banco `(default)`, UID, propriedade de cada documento e vencimento antes de
   qualquer remoção. O papel do suplente não concede acesso ao Beta. As etapas
   e a recuperação de falha parcial estão descritas acima. O pedido só seria
   marcado concluído depois da verificação da limpeza Firestore e da remoção da
   identidade Auth. O operador enviaria confirmação apenas depois disso.
5. Falha deixa o pedido no controle como pendente, registra somente a etapa que
   falhou e exige nova revisão. O operador aprovou revisão diária e meta interna
   de até 7 dias; isso não é SLA, prazo legal ou promessa pública. A planilha
   foi compartilhada com o suplente como Editor, mas a abertura pela conta dele
   ainda não foi testada. A aba de pedidos reais continua vazia; o ensaio
   sintético está separado. Até que a retenção seja aprovada e o fluxo do
   suplente seja ensaiado, pedidos continuam sujeitos a esquecimento.

Esse procedimento é uma proposta operacional, não um formulário ou serviço já
funcional. O link externo atual não recebe pedidos. As páginas também não devem
ser copiadas para `public/` enquanto houver avisos de rascunho ou campos
pendentes.

## Requisitos — revisão, não parecer jurídico

**Legislação:** controlador, bases legais, direitos, exceções de retenção,
tratamento de dados de profissionais listados publicamente e tempos de resposta
precisam de decisão do responsável e revisão jurídica. Não presumir que todo
dado seja eliminado automaticamente em qualquer situação.

**Lojas:** Google Play requer caminho no app e um recurso web funcional para
solicitar exclusão, além das declarações de exclusão no Data safety. A página
atual não recebe solicitações. Apple exige que apps com criação de conta
permitam iniciar exclusão dentro do app e disponibilizem política de privacidade
na loja e de forma acessível no app. Consulte as fontes oficiais abaixo.

**Técnica:** o app implementa exclusão dos dados identificados no código e um
pedido pendente ligado à cota de 24 horas. Não existe trabalhador automático.
O titular do app está designado operador inicial e aprovou meta interna de
revisão diária/tentativa de conclusão em até 7 dias. Um papel IAM de suplente
existe no projeto de distribuição; a conta abriu o IAM e a planilha foi
compartilhada como Editor, mas MFA, abertura direta da planilha e ensaio do
processo pelo suplente ainda faltam. A meta não é prazo público; política
e página externa não estão prontas para publicação.

## Checklist de publicação nas lojas

### Google Play

- Referência oficial: [requisitos de exclusão de conta no Google Play](https://support.google.com/googleplay/android-developer/answer/13327111).
- Aprovar e publicar uma Política de Privacidade em URL HTTPS acessível sem
  login; preencher a URL da política e as respostas de Segurança dos Dados com
  os dados da variante efetivamente distribuída.
- Disponibilizar caminho de exclusão no app e recurso web funcional e
  facilmente encontrável para solicitar exclusão sem reinstalar o aplicativo.
  O link deve referenciar “Tudo Aqui Macacu” e refletir o processo real; um
  `mailto:` sem registro, controle operacional e processo manual validado não
  comprova esse requisito. O teste de e-mail relatado pelo responsável não
  valida o recebimento e a conclusão de solicitações reais.
- Responder às perguntas de exclusão e declarar com precisão o que é removido,
  o que permanece e por quê. A meta interna de até 7 dias não deve ser
  publicada como prazo garantido.
- Confirmar que a URL externa e os links diretos permanecem ativos e testados
  antes de preencher o Play Console.

### App Store

- Referências oficiais: [App Review Guidelines, seção de privacidade](https://developer.apple.com/app-store/review/guidelines/) e [orientação Apple para exclusão de conta](https://developer.apple.com/support/offering-account-deletion-in-your-app/).
- Inserir a URL pública da política nos metadados do App Store Connect e manter
  acesso fácil à política dentro do app.
- Manter exclusão de conta iniciável dentro do app, informar eventual demora e
  explicar dados retidos. Se for exigido concluir na web, fornecer link direto
  para a página que realmente viabiliza a conclusão.
- Testar o fluxo nativo iOS, reautenticação e revogação de credencial Apple em
  dispositivo real antes de declarar suporte.
- Confirmar os dados de privacidade do App Store Connect e os canais de contato
  após a revisão jurídica e operacional.

As páginas só podem sair de `docs/privacy-drafts/` para a raiz `public/` depois
da aprovação do controlador, fechamento dos campos pendentes, teste real do
canal, revisão jurídica e conferência do conteúdo da versão distribuída. O
`firebase.beta.json` contém configuração Hosting, mas não fixa o ID do projeto;
o alias padrão em `.firebaserc` é `tudo-aqui-macacu`. Em uma etapa futura,
qualquer publicação destas páginas deverá usar explicitamente o projeto
`macacu-beta-261030-cf4a81` e selecionar somente Hosting, depois de autorização
específica. O comando de deploy permanece fora do escopo desta preparação; não
há domínio público confirmado para informar neste rascunho.
