# Checklist interno — pedidos de privacidade e exclusão

Antes de tratar registros antigos ou afirmar exclusão integral, consulte o
[runbook Spark de escopo e limpeza histórica](../account-deletion-spark-runbook.md).
Ele distingue as gravações atuais do MVP dos dados históricos sem vínculo
consultável pelo titular; a existência de um esquema no código não prova que há
documentos hospedados.

**RASCUNHO PARA REVISÃO OPERACIONAL E JURÍDICA — NÃO PUBLICAR.**

Este checklist descreve o fluxo observado no código local do Beta e uma proposta
de operação manual. Não comprova configuração hospedada, não cria uma fila de
atendimento e não significa que o canal externo esteja operacional.

## A. Aprovações necessárias antes de aceitar solicitações externas

- [x] O responsável informou Bruno Araújo Maurício, pessoa física, como responsável pelo app e pelo canal de privacidade.
- [ ] Confirmar em revisão jurídica que Bruno é o controlador conforme as decisões efetivamente tomadas sobre finalidades e meios; manter o e-mail oficial como canal de contato. Não publicar endereço físico sem necessidade confirmada.
- [ ] Verificar se o enquadramento permite dispensa de encarregado; se não permitir, formalizar a indicação e divulgar os contatos.
- [x] O titular do app designou a si mesmo como operador inicial, usando o
      e-mail de contato do app. Não compartilhar contas.
- [x] O responsável designou um suplente e recebeu confirmação para conceder
      um papel IAM personalizado somente no projeto de distribuição
      `tudo-aqui-macacu`; o endereço do suplente fica apenas no IAM.
- [x] Criado e vinculado `projects/tudo-aqui-macacu/roles/accountDeletionOperator`.
      O papel permite ler/excluir dados Firestore e excluir usuários Auth em
      escopo de projeto inteiro (não por UID); não permite criar/alterar dados,
      mudar IAM, publicar Rules ou fazer deploy. Não dá acesso ao Beta.
- [ ] O suplente completar o ensaio operacional com sua própria identidade.
      Foi observado que a conta abre o IAM do projeto e vê o papel. Em
      14/11/2026, o responsável informou que o suplente confirmou MFA; isso não
      foi verificado independentemente. O ensaio 17/17 no Emulator foi conduzido
      pelo agente e não testa a permissão IAM hospedada.
- [x] O responsável confirma que a verificação em duas etapas da conta Google
      usada para acessar a planilha está ativa; confirmação informada pelo
      responsável, sem verificação independente.
- [x] A autorização Firebase IAM individual do suplente foi atribuída no
      projeto de distribuição; a conta primária mantém seus acessos existentes.
- [x] Foi observado login com a conta suplente no Console e acesso à página IAM
      do projeto, onde o papel aparece atribuído. Isso não valida MFA nem a
      execução de exclusões.
- [x] O responsável informou que o suplente abriu a planilha e confirmou MFA em
      14/11/2026; a confirmação não foi verificada independentemente.
- [ ] Ensaiar a execução operacional com a identidade do suplente antes de
      aceitar pedidos reais. O teste Emulator não valida IAM hospedado.
- [x] O responsável informou que tem acesso a `tudoaquimacacuapp@gmail.com`.
- [x] O responsável informou em 14/11/2026 que o teste manual de envio,
      recebimento e resposta pela caixa foi bem-sucedido. Resultado informado
      pelo responsável, sem verificação independente; isso não comprova
      monitoramento contínuo nem registro automático de pedidos.
- [ ] Aprovar um processo externo funcional (formulário ou canal de atendimento
      operado), verificação proporcional de titularidade, confirmação de
      recebimento e comunicação de conclusão/impedimento.
- [x] Planilha privada de acompanhamento criada. Em 14/11/2026, foi concedido
      Editor ao suplente; os metadados confirmam a permissão e o responsável
      informou que o suplente abriu a planilha. Isso não foi verificado
      independentemente. A aba de pedidos reais segue
      vazia; o ensaio sintético está registrado em aba separada. Não há acesso
      público. Isso não autoriza iniciar atendimento real.
- [x] Acesso de Editor à planilha foi autorizado pelo responsável e concedido
      ao suplente para atualizar o controle.
- [ ] Aprovar o prazo de retenção dos registros operacionais, que poderão
      conter UID e datas. Proposta informada pelo responsável: apagar os registros
      7 dias corridos após a conclusão. Isso é distinto da meta de atendimento
      de até 7 dias e continua pendente de revisão operacional e jurídica.
- [ ] Definir procedimento para solicitações de correção ou remoção de dados
      pessoais publicados em listagens de estabelecimentos/profissionais.
- [ ] Validar com revisão jurídica as hipóteses preliminares e retenções por
      finalidade abaixo. Não presumir que dado público deixa de ser pessoal.
- [x] Meta interna aprovada: revisar diariamente e buscar concluir em até 7
      dias corridos quando o processo verificado permitir. É uma meta interna,
      não SLA público, prazo legal, prazo máximo de retenção ou promessa.
- [ ] Definir tempos públicos de resposta somente após revisão jurídica e
      validação da capacidade operacional real.

## A1. Fluxo externo mínimo proposto — atendimento manual por e-mail

**Ainda não ativo como processo de exclusão.** O titular do app foi designado
operador inicial e escolheu `tudoaquimacacuapp@gmail.com`. Em 14/11/2026, o
responsável informou que o teste manual de ida e volta do e-mail funcionou; o
resultado não foi verificado independentemente. Um suplente foi indicado e
recebeu um papel IAM personalizado no projeto de distribuição. Em 14/11/2026,
foi observado que sua conta abre o IAM do projeto e vê o papel. O responsável
informou que o suplente confirmou MFA e abriu a planilha; não houve verificação
independente. O papel cobre leitura/exclusão de dados Firestore
e exclusão de usuários Auth em todo o projeto, sem restrição por UID; não dá
acesso ao Beta. A planilha privada foi compartilhada com o suplente como Editor;
os metadados confirmam a permissão, e o responsável informou que o suplente
abriu a planilha. Aprovação de retenção e ensaio operacional continuam
pendentes. O `mailto:` abre um
aplicativo de e-mail; não registra o envio nem cria automaticamente um ticket.
O site estático não tem endpoint de formulário.

Depois de concluir os controles operacionais pendentes:

1. A página apresenta um botão para redigir mensagem ao endereço confirmado e
   texto alternativo para copiar o endereço. Solicita somente o e-mail usado na
   conta e que a pessoa manifeste o pedido. A página informa para não enviar
   senha, token, código de autenticação, documento ou dado sensível.
2. O operador designado monitora a caixa com identidade própria e MFA. Ao receber uma
   mensagem, envia uma resposta neutra de recebimento que não confirma se existe
   conta com aquele e-mail. A mensagem recebida é o início do atendimento, não
   a prova de titularidade nem a confirmação de exclusão.
3. No ambiente e ferramenta autorizados, compara o endereço completo com o
   e-mail exato do Firebase Authentication e verifica `emailVerified`. Não
   procura por nome, UID fornecido pelo solicitante ou correspondência parcial.
4. Se houver correspondência única e verificada, responde somente para esse
   endereço e pede uma confirmação explícita do pedido na mesma conversa. Não
   solicita senha, documento de identidade ou código recebido em outro canal.
   Se a titularidade não puder ser verificada, não exclui a conta; comunica uma
   alternativa autenticada sem revelar se outro endereço possui cadastro.
5. Depois da confirmação, cria um registro mínimo em controle operacional
   restrito: referência aleatória, datas de recebimento/confirmação, estado,
   responsável e, somente após verificação, UID. Não copia o corpo do e-mail.
   Ferramenta, retenção e autorização desse controle ainda precisam de aprovação.
6. Verifica se a pessoa concluiu a exclusão pelo app antes de iniciar uma ação
   manual. Se a conta ainda tiver cota ativa, não remove a cota antes de
   `retryAfter`; a solicitação externa fica pendente no controle aprovado. A
   Rules só aceita criação do documento Firestore pelo próprio usuário
   autenticado em condição de cota ativa. O operador não deve criar esse
   documento por atalho nem alterar Rules.
7. Para pedido abandonado vencido, segue o procedimento manual da seção C,
   usando IAM individual com MFA. Se ocorrer erro parcial, mantém o ticket
   pendente, registra somente etapa/resultado e reavalia. Não escreve no
   documento `account_deletion_requests/{uid}` de modo a interferir com uma
   sessão do usuário.
8. Só comunica “concluído” depois de confirmar a limpeza dos dados abrangidos e
   a remoção da identidade Auth. Caso dados permaneçam por motivo técnico ou
   legal, informa a limitação e o motivo aprovado; não declara eliminação total.

O recebimento pode ser operado sem backend adicional pela caixa oficial e pelo
controle privado já escolhido. Isso não automatiza o registro, a verificação nem
a exclusão. O responsável fará o registro mínimo manual, sem copiar o corpo do
e-mail, e só associará UID depois de verificar titularidade. Apesar do teste de
e-mail relatado, o controle de acesso, a retenção do registro e o ensaio de
ponta a ponta ainda não estão fechados; a página não deve ser declarada como
serviço operacional de exclusão até essas etapas serem aprovadas e testadas.


### Modelos de resposta — rascunhos internos

**1. Confirmação neutra de recebimento**

Assunto: `Recebemos sua mensagem — Tudo Aqui Macacu`

> Olá. Recebemos sua mensagem sobre privacidade. Este aviso confirma somente o
> recebimento do e-mail; não confirma se existe uma conta associada ao endereço
> nem significa que a exclusão foi concluída. Não envie senha, token, código de
> autenticação ou documento. Se precisarmos confirmar que você controla o
> endereço associado à conta, responderemos por este canal. O pedido só será
> concluído depois das verificações e da remoção dos dados abrangidos. Não há
> prazo público confirmado; a meta interna aprovada não é garantia.

**2. Pedido de confirmação de titularidade**

Enviar somente ao endereço exato e verificado associado à conta, depois da
checagem interna. A resposta deve ser uma confirmação explícita do pedido. Se a
checagem não encontrar correspondência única/verificada, usar orientação neutra
para o fluxo autenticado do app, sem revelar a existência de outras contas.

**3. Confirmação de conclusão**

Assunto: `Atualização do seu pedido — Tudo Aqui Macacu`

> Olá. Confirmamos que o pedido de exclusão foi concluído em [data], após a
> verificação de titularidade. Foram removidos [listar somente os dados cuja
> remoção foi efetivamente verificada]. Permanecem [descrever dados/itens e
> motivo aprovado, se houver; caso contrário, remover esta frase após revisão].
> A exclusão da conta do aplicativo não remove sua conta Google ou Apple, dados
> locais em outros aparelhos nem conteúdo público compartilhado que não pertença
> exclusivamente à conta. Para dúvidas, responda a esta mensagem.

Não usar o modelo de conclusão para pedido apenas recebido, pedido ainda
pendente por cota, falha parcial ou dados cuja remoção não foi confirmada.

### Teste manual de e-mail — resultado informado pelo responsável

- [x] O responsável informou ter usado uma segunda conta de e-mail sob seu
      controle; nenhum dado do teste foi verificado independentemente.
- [x] O responsável informou o envio para `tudoaquimacacuapp@gmail.com` com o assunto
      `TESTE DO CANAL DE PRIVACIDADE — NÃO É PEDIDO REAL` e corpo informando que
      é apenas teste e não solicita exclusão de conta.
- [x] O responsável informou que a caixa recebeu a mensagem; verificação de
      spam/quarentena não registrada.
- [x] O responsável informou que respondeu, sem declarar que uma conta
      foi localizada ou excluída.
- [x] O responsável informou que a segunda caixa recebeu a resposta e confirmou
      o recebimento, verificando o caminho de retorno.
- [ ] Registrar somente data/hora e resultados (envio, recebimento, resposta e
      retorno) em controle aprovado. A aba de pedidos reais permanece vazia; a
      aba separada de ensaios contém somente o registro sintético. Não inserir
      pedidos reais até aprovar retenção e validar o processo operacional.
- [ ] Arquivar/remover as mensagens de teste segundo a política do provedor e a
      retenção que o responsável aprovar. Não transformar o teste em pedido real.

**Resultado informado em 14/11/2026:** o responsável disse “tá funcionando”, após
realizar o teste de ida e volta. Registro baseado na confirmação do responsável,
sem acesso independente às caixas. O local aprovado para registrar atendimentos
e o tratamento das mensagens do teste continuam pendentes; portanto, isso
comprova somente o teste de e-mail relatado, não a operação ponta a ponta de
solicitações de exclusão.

## A2. Mapa preliminar de bases legais e retenção — para revisão

**Proposta operacional, não conclusão jurídica.** As finalidades e bases abaixo
devem ser confirmadas pelo controlador e por revisão jurídica antes de remover
os avisos de pendência da política pública.

| Grupo de dados | Finalidade | Hipótese inicial para revisão | Tratamento/retensão propostos |
|---|---|---|---|
| Conta, autenticação e favoritos | Criar e manter recursos pedidos pelo usuário | Avaliar execução do serviço/contrato ou procedimento solicitado pelo titular | Apagar perfil e favoritos quando a exclusão for concluída; preservar apenas o que tiver justificativa legal aprovada |
| Mensagens de contato | Receber e responder ao contato do usuário | Avaliar execução do serviço solicitado e, conforme o conteúdo, outra base aplicável | Manter enquanto necessário ao atendimento; depois apagar ou anonimizar, salvo retenção específica justificada |
| Pedido externo de privacidade/exclusão | Verificar, acompanhar e comprovar o atendimento | Avaliar exercício regular de direitos e/ou interesse legítimo com análise de necessidade | Registrar referência, datas, estado, operador; UID somente após verificação. Não copiar corpo do e-mail. Prazo após conclusão ainda não definido |
| Logs e auditoria administrativa | Segurança, responsabilização e investigação de falhas | Avaliar interesse legítimo com ponderação, obrigação legal ou exercício regular de direitos conforme cada evento | Acesso restrito e prazo mínimo justificável; prazo numérico pendente |
| Imagens e dados comerciais públicos | Exibir perfil comercial autorizado | Confirmar relação e instruções do estabelecimento/profissional; dados que identifiquem pessoa natural exigem revisão específica | Separados da conta do morador; remoção e retenção conforme validade da publicação e pedido do responsável pelo perfil |
| Lembretes e cache locais | Oferecer funções no aparelho | Verificar necessidade de base separada; sem envio de localização do aparelho no fluxo revisado | Manter no dispositivo enquanto usados; apagar na limpeza local ou remoção do app, sem alcance remoto a outros aparelhos |
| Cópias de fornecedores/backups | Operação dos serviços contratados | Confirmar contratos, papéis e transferências aplicáveis | Usar períodos efetivamente publicados pelos fornecedores; não inventar prazo próprio |

Nenhuma base acima está aprovada apenas por aparecer nesta tabela. A execução
de contrato e o legítimo interesse são hipóteses a avaliar, não opções
automáticas; o legítimo interesse exige análise de necessidade e equilíbrio.
Não fixar números de retenção até conferir obrigações aplicáveis e prazos reais
dos fornecedores.


## B. Tratamento do pedido iniciado no aplicativo

- [ ] Confirmar que a pessoa está na conta que deseja excluir e que a sessão
      foi reautenticada pelo provedor vinculado. Não solicitar senha no suporte.
- [ ] O código bloqueia a autoexclusão de contas Admin; encaminhar para um
      procedimento administrativo separado, ainda pendente de definição.
- [ ] Se não houver cota ativa, o app tenta apagar dados próprios em páginas de
      até 100 documentos, limpa lembretes locais desta instalação e exclui a
      identidade Firebase por último. Considerar concluído somente quando o app
      confirmar o término sem erro.
- [ ] Se a cota de mensagens estiver ativa, conferir a mensagem real da tela:
      o app grava `account_deletion_requests/{uid}` com UID, `requestedAt` do
      servidor, `retryAfter` e `status: pending`; mantém Auth e dados remotos,
      preserva a cota e as Rules bloqueiam novos envios de contato. Lembretes e
      preferências locais desta instalação são limpos após o registro, se essa
      etapa funcionar.
- [ ] Explicar que pedido pendente não é exclusão concluída. Não há trabalhador
      automático, notificação automática, SLA configurado ou prazo máximo de
      retenção para essa fila. Depois de `retryAfter`, a pessoa pode voltar ao
      app, reautenticar-se e confirmar novamente.
- [ ] Um erro após uma etapa pode deixar a conta parcialmente processada. Não
      marcar como concluída nem prometer conclusão; registrar a etapa que falhou
      no controle aprovado e retomar de forma idempotente.

## C. Procedimento manual proposto para pedido abandonado

**Status: parcialmente preparado; não aprovado nem testado com exclusão
operacional hospedada.** O papel IAM do suplente existe somente na distribuição
Spark. A conta abriu o IAM do projeto e o papel foi observado. O responsável
informa que o suplente confirmou MFA e acesso à planilha, sem verificação
independente. A retenção e a auditoria operacional seguem pendentes. A função Admin no app não
concede acesso IAM.

- [ ] Usar identidade individual autorizada e MFA; confirmar o projeto correto
      (`tudo-aqui-macacu` para distribuição; Beta permanece separado) e banco
      `(default)` antes de consultar. O papel criado não dá acesso ao Beta.
- [ ] Localizar pedido pelo ID/UID exato e confirmar `status == pending`, UID
      coincidente e `retryAfter` vencido. Não iniciar limpeza antes do horário.
- [ ] Conferir o usuário no Firebase Authentication pelo UID exato e o perfil
      `users/{uid}`. Se for Admin, interromper e encaminhar ao processo separado.
      Não procurar usuário por e-mail aproximado.
- [ ] Remover somente registros com vínculo verificável ao UID: favoritos em
      `users/{uid}/favorites`; votos em grupos `votes` filtrados por `uid`;
      documentos de `contact_messages`, `business_proposals` e `reviews`
      filtrados pelo mesmo UID; cota em
      `users/{uid}/contact_message_limits/current`; e perfil `users/{uid}`.
- [ ] Não remover conteúdo público da cidade, projeções de estabelecimento,
      banners, autorização Admin ou registros de terceiros como parte desse
      fluxo. Dados pessoais eventualmente presentes em conteúdo público exigem
      revisão e processo próprios.
- [ ] Depois de verificar a limpeza Firestore, excluir a identidade Auth pelo
      mesmo UID. Se já estiver ausente, verificar a ausência e continuar a
      verificação dos documentos restantes.
- [ ] Apagar o pedido pendente somente depois de confirmar as etapas aplicáveis.
      Se qualquer operação falhar, preservar o pedido, registrar apenas etapa e
      resultado mínimo e agendar nova revisão conforme procedimento aprovado.
- [ ] Confirmar o resultado ao solicitante somente após as verificações finais.
      Nunca registrar senha, token, código Apple ou cópia de documento.
- [ ] Esta operação não apaga preferências/notificações locais em outros
      aparelhos, cópias dos provedores de login, backups/logs do fornecedor,
      arquivos Cloudinary ou listagens públicas. Cada item precisa de avaliação
      e procedimento próprio antes de declarar eliminação integral.

## D. Inventário técnico observado no fluxo de exclusão

- Firebase Authentication: UID e identificadores de provedor; podem existir
  e-mail, nome ou foto fornecidos pelo provedor. Excluir a conta Firebase não
  exclui a identidade Google ou Apple.
- Firestore associado ao UID: perfil, favoritos, mensagens de contato,
  propostas comerciais, avaliações, votos, cota de mensagens e pedido pendente.
- Dados locais desta instalação: preferências e lembretes de eventos; o serviço
  tenta cancelar alarmes e limpar as chaves locais. A exclusão não alcança outros
  dispositivos.
- Dados compartilhados: conteúdo público municipal, listagens Basic/Premium,
  projeções, banners, autorizações Admin e auditoria não são apagados pela
  exclusão comum.
- A lista acima descreve as coleções alcançadas pelo código verificado; não é
  garantia de remoção de logs/backups de fornecedores, dados fora do Beta ou
  arquivos de mídia externos.

## E. Revisão de publicação

- [ ] Política final aprovada e publicada em URL HTTPS acessível sem login; URL
      inserida nos metadados da loja e acessível no app.
- [ ] Página externa operacional, com o nome “Tudo Aqui Macacu”, caminho para
      solicitar exclusão, instruções e confirmação real de recebimento. Página
      meramente informativa ou link `mailto:` sem registro e acompanhamento não
      deve ser declarado como serviço operacional.
- [ ] Testar fluxo completo com conta sintética em Emulator, incluindo pedido
      imediato, vencimento, falha parcial, repetição e resultado verdadeiro.
- [ ] Conferir o build final e preencher os formulários de privacidade/segurança
      das lojas com os dados e SDKs efetivamente presentes nessa variante.
- [ ] Para App Store, testar exclusão dentro do app e reautenticação Apple na
      configuração real antes de declarar suporte ao provedor.
- [ ] Registrar aprovação do controlador e revisão jurídica; manter datas de
      vigência e contato final consistentes entre política, app e lojas.

## Referências para revisão (não são parecer jurídico)

- ANPD, direitos dos titulares: <https://www.gov.br/anpd/pt-br/assuntos/titular-de-dados-1/direito-dos-titulares>
- ANPD, perguntas frequentes sobre retenção e atendimento: <https://www.gov.br/anpd/pt-br/acesso-a-informacao/perguntas-frequentes>
- Google Play, requisitos de exclusão de conta: <https://support.google.com/googleplay/android-developer/answer/13327111>
- Apple, requisito 5.1.1(v): <https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion>
