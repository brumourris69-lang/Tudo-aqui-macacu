# Exclusão no Spark — escopo e operação histórica

Documento técnico interno para revisão. Não é política pública nem prova de
que o projeto Firebase hospedado foi inspecionado. Não executar a rotina em
produção sem autorização IAM individual com MFA, projeto e banco confirmados,
registro operacional aprovado e revisão jurídica. O titular do app foi
designado operador inicial; isso não concede acesso IAM.

## Dados que o MVP Spark pode criar

O caminho de distribuição Spark usa escrita direta de cliente sujeita a
Firestore Rules para os registros pessoais do núcleo comercial:

| Registro | Caminho/vínculo | Limpeza pelo titular |
| --- | --- | --- |
| Perfil | `users/{uid}` | Sim; Auth é excluído depois |
| Favorito | `users/{uid}/favorites/{id}` | Sim, por caminho próprio |
| Mensagem de contato | `contact_messages/{id}`, campos `uid` e `email` | Sim, consulta paginada pelo UID |
| Cota de contato | `users/{uid}/contact_message_limits/current`, campo `uid` | Sim, depois do vencimento de 24 horas |
| Pedido pendente de exclusão | `account_deletion_requests/{uid}` | O titular lê o próprio; só conclui após vencer a cota |
| Lembretes/preferências do app | Armazenamento local por UID | Só a instalação que executa a limpeza |

A rotina valida que Auth e Firestore pertencem à mesma identidade Firebase,
reautentica o titular, limpa páginas limitadas e só então exclui a identidade
Auth. Uma interrupção antes do Auth deixa a conta disponível para nova tentativa.
O aplicativo não reporta conclusão enquanto uma etapa remota falhar.

Métricas não são persistidas pelo caminho Spark. Favoritos e contatos são os
únicos envios de usuário habilitados no MVP comercial; ambos carregam vínculo
de proprietário validável pelas Rules.

## Gravações fechadas no MVP 1.0

Vagas, votos, propostas, avaliações e push remoto permanecem adiados. Os flags
de build só podem habilitá-los em debug; no profile/release são sempre falsos.
As chamadas de gravação também bloqueiam essas operações antes do backend, e as
Rules Spark rejeitam criação direta de propostas, avaliações e votos. O catálogo
`jobs` deixou de ser gravável por cliente/Admin e `job_private` ficou somente
para leitura administrativa enquanto Vagas estiver fora do lançamento. A
criação de `push_queue` já é negada pelas Rules Spark, inclusive para Admin.
Portanto, ocultar telas não é a única proteção.

Dados antigos dessas áreas podem continuar existindo. Quando possuem vínculo
`uid`/`userId` íntegro, o titular ainda pode removê-los pelo fluxo paginado. Um
documento com identificadores conflitantes bloqueia a exclusão automática e
precisa de revisão operacional; nunca escolher um proprietário por suposição.

## Dados históricos fora do alcance confiável do cliente

Estes são formatos encontrados no código legado, não evidência de que existam
documentos hospedados:

1. **Votos de enquetes antigas sem campo `uid`.** Os documentos têm o UID como
   ID, mas o cliente só conhece os IDs das enquetes públicas. O operador com
   IAM pode enumerar os IDs canônicos em `polls`, consultar exatamente
   `polls/{pollId}/votes/{uid}` e apagar apenas quando o ID confere e não há
   campo `uid` conflitante. Nunca excluir outro documento de votos ou consultar
   por conteúdo aproximado.
2. **`user_operation_limits`.** O ID legado é
   `SHA-256(uid + ':' + operação)` e o documento tem `expiresAt`, mas não guarda
   UID. O código legado mantinha a janela por até 48 horas. O operador pode
   calcular somente as chaves das operações conhecidas, consultar o caminho
   exato e verificar que `expiresAt` venceu. Se ainda estiver ativo, preservá-lo
   para não remover um controle ant abuso; manter o pedido em acompanhamento
   até o vencimento. Não há política TTL declarada para essa coleção no índice
   local, então não presumir remoção automática.
3. **`user_operation_dedup`.** O ID é
   `SHA-256(uid + ':' + operação + ':' + payload serializado)` e não há índice
   reversível para associá-lo a uma conta. No código legado a deduplicação
   expira em até 60 segundos (métricas, 5 segundos). Não tentar adivinhar
   payload nem apagar por hash aproximado. Um operador pode remover somente
   documentos com `expiresAt` vencido em varredura paginada da coleção inteira;
   como o registro expirado já não protege deduplicação ativa, a ação é
   idempotente. Os registros ainda válidos permanecem até expirar e impedem
   marcar esse pedido como concluído enquanto forem classificados como dados
   sujeitos à exclusão.
4. **Notificações de e-mail antigo.** O cliente agora encontra notificações
   endereçadas ao e-mail atual mesmo quando `targetUid` está ausente. Um endereço
   anterior não é inferido: o operador só pode usar um endereço histórico já
   verificado e disponível num registro autorizado. Não buscar por nomes nem
   apagar mensagens por semelhança.
5. **Registros com proprietário ausente/conflitante.** A limpeza automática
   para com falha e preserva Auth. O operador deve verificar a origem e a
   titularidade por evidência independente antes de qualquer exclusão.
6. **Cadastro comercial sem vínculo de conta.** Estabelecimentos e projeções
   são conteúdo compartilhado, administrado pelo Admin, e não carregam o UID do
   comerciante como proprietário. Se um cadastro de profissional autônomo
   incluir telefone ou outro dado que possa identificá-lo, a exclusão de uma
   conta de morador não o encontra nem deve apagar a empresa automaticamente.
   Uma solicitação do próprio comerciante exige análise separada do cadastro,
   decisão documentada sobre despublicar/editar e preservação dos dados de
   outros clientes; esse vínculo e procedimento ainda não existem no produto.

O fluxo Spark não cria hoje limites/deduplicações de Cloud Functions. As
estruturas acima são apenas potencial histórico de versões/caminhos anteriores;
não afirmar presença ou ausência sem consulta hospedada autorizada.

## Procedimento auditável para pedido pendente/legado

**Estado operacional: ainda não validado ponta a ponta.** O titular do app foi
designado operador inicial e aprovou revisão diária com meta interna de até 7
dias corridos, sem promessa pública. Em 14/11/2026, informou que um teste
manual de ida e volta do e-mail funcionou, sem verificação independente. Não há
trabalhador automático no Spark.
O documento `account_deletion_requests/{uid}` contém somente UID,
horário do servidor, `retryAfter` e `status: pending`; Rules não permitem ao
cliente alterar estado. O titular pode voltar ao app, reautenticar e concluir
quando a cota vencer. Pedido pendente não é exclusão concluída.

Quando os acessos individuais, a caixa e o controle operacional forem testados
e aprovados:

1. Um operador individual autorizado por IAM/MFA confirma, em duas verificações
   independentes, o projeto e banco `(default)`, consulta a fila paginada por
   `status == pending` e registra apenas o UID, data e etapa necessária no
   controle restrito aprovado. Não exportar conteúdo de mensagens.
2. Se `retryAfter` ainda estiver no futuro, não tocar na cota nem excluir Auth.
   Acompanhar diariamente conforme a meta interna aprovada e revisar `retryAfter`.
   A meta de até 7 dias é um objetivo operacional, não SLA nem garantia.
3. Após o vencimento, confirmar o UID e o papel `user` no Auth/perfil. Admins,
   UID divergente, dados conflitantes ou identidade ambígua vão para revisão
   separada; não autoexcluir nem desativar autorização Admin por esse fluxo.
4. Remover em lotes pequenos somente registros de propriedade comprovada:
   perfil, favoritos, contatos, cota vencida, registros indexados pelo UID,
   votos legados pelo caminho exato, notificações verificadas e registros
   históricos de operação que já venceram. Repetir consultas e confirmar zero
   remanescentes em cada categoria. Uma falha mantém o pedido em aberto.
5. Excluir a identidade Firebase Auth pelo UID exato somente depois da limpeza
   Firestore verificada. Se Auth já não existir, verificar os documentos antes
   de avançar. Remover o pedido Firestore por último.
6. Registrar no controle restrito somente operador, UID/pedido, datas, códigos
   de etapa e resultado; nunca senha, token, conteúdo, payload ou cópia de
   documento. Guardar falha como `partial_failure`, preservar o pedido e
   retomar do início; passos concluídos são repetíveis.
7. Comunicar conclusão apenas após confirmar Firestore e Auth. O usuário pode
   concluir pelo app depois do vencimento; se não o fizer e não houver operador
   autorizado, o pedido permanece pendente sem automação nem prazo garantido.

O titular está designado como operador inicial e aprovou a rotina diária com
meta interna de até 7 dias. O responsável relata teste manual de ida e volta do
e-mail bem-sucedido em 14/11/2026, sem verificação independente. A planilha
privada está criada; em 14/11/2026, foi concedido Editor ao suplente, e os
metadados confirmam essa permissão. Em 14/11/2026, o responsável informou que
o suplente abriu a planilha e confirmou MFA; esses fatos não foram verificados
independentemente. Um suplente foi indicado pelo responsável e recebeu no projeto de distribuição
`tudo-aqui-macacu` o papel personalizado
`projects/tudo-aqui-macacu/roles/accountDeletionOperator`. O papel concede
`firebaseauth.users.get`, `firebaseauth.users.delete`,
`datastore.entities.get`, `.list`, `.delete`, `datastore.databases.get`,
`.getMetadata` e `.list`. Ele não concede criação/alteração de usuários ou
documentos, IAM, publicação de Rules ou deploy. Seu escopo de leitura/exclusão
abrange todos os usuários Auth e documentos Firestore do projeto; não é limitado
por UID e não concede acesso ao projeto Beta. O e-mail do suplente permanece
somente no IAM, não neste documento. Foi observado que a conta suplente abre o
IAM do projeto e vê o papel; o responsável também informou MFA ativo e acesso à
planilha, sem verificação independente. Ainda falta ensaio operacional com a
identidade do suplente e aprovação da proposta de apagar linhas
7 dias após conclusão e eventual prazo público após revisão jurídica. A retenção
proposta é distinta da meta de atendimento de até 7 dias. O Emulator aprovou
17/17 assertions sintéticas, registradas em aba separada da planilha; isso não
testa IAM hospedado nem dados existentes em produção.

## Evidência exigida antes de declarar exclusão integral no lançamento

- Validação independente do MFA do suplente, abertura da planilha pela própria
  conta e ensaio operacional com sua identidade; o acesso ao IAM e a permissão
  de Editor foram observados, mas isso não prova a exclusão ponta a ponta.
- Ensaio sintético do operador que cubra pedido vencido, interrupção, retomada,
  Auth já ausente, registros com identificadores conflitantes e varredura de
  registros históricos vencidos.
- Verificação autorizada do inventário dos dados legados em cada ambiente que
  será usado; Emulators vazios não provam que hospedado está vazio.
- Política aprovada para a retenção temporária da cota ativa e para o controle
  operacional; sem definir prazos no código ou na página pública por suposição.

Até essas condições serem cumpridas, o parecer é **NO-GO para afirmar remoção
integral automática no Spark**. O fluxo do app pode confirmar apenas a remoção
dos dados próprios identificáveis que conseguiu verificar e apagar.
