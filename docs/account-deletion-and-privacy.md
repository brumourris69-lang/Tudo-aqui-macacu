# Exclusão de conta — escopo Beta

Esta implementação atende ao Beta Firebase Spark. Ela exige a sessão da própria
conta, confirmação no aplicativo e reautenticação recente. A identidade no
Firebase Auth é removida somente depois da limpeza autorizada dos dados.

## Dados removidos na Beta

- Perfil `users/{uid}` e favoritos da subcoleção `favorites`.
- Cota de envio em `contact_message_limits/current`.
- Mensagens em `contact_messages`, propostas em `business_proposals`, avaliações
  em `reviews` e votos em `polls/*/votes/*` cujo campo `uid` corresponda à conta.
- Preferências e lembretes de eventos locais vinculados ao UID neste aparelho.
- Identidade da conta no Firebase Authentication. Para contas Apple configuradas,
  o código de autorização temporário é usado para revogar o token Apple antes da
  exclusão da identidade; ele não é persistido.

As operações usam consultas limitadas e exclusão paginada. Se uma etapa falhar,
a conta Auth permanece ativa e a tentativa pode ser repetida. Algumas gravações
anteriores podem já ter sido removidas; a interface não informa sucesso até que
todas as etapas terminem.

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

## Pedidos fora do aplicativo e publicação

O diretório público de Hosting não contém uma página de exclusão publicada. O
responsável informou `tudoaquimacacuapp@gmail.com` como e-mail do aplicativo; a
caixa postal e o fluxo de recebimento/verificação dos pedidos ainda precisam ser
testados e definidos. Nenhum prazo foi inventado. Portanto, a URL de solicitação
externa exigida para o Google Play continua pendente. As páginas permanecem
rascunhos locais e não foram publicadas.

Antes do lançamento, publique uma página funcional que identifique “Tudo Aqui
Macacu”, permita iniciar um pedido externo de exclusão e explique claramente os
dados apagados, os registros retidos e o tratamento de contas Admin. Registre a
URL no Play Console e mantenha a política de privacidade coerente com este
comportamento e com os dados efetivamente usados em cada plataforma.
