# Identidade visual Tudo Aqui Macacu — proposta

## Intenção

Unificar a apresentação do aplicativo em torno da identidade azul e laranja, Poppins e do símbolo existente de localização, montanhas e rio. Aplicar o acabamento premium dos botões recentes com gradientes e relevo discretos, sem reconstruir fluxos ou alterar conteúdo.

## Escopo e limites

- Manter o arquivo de logo atual e o nome Tudo Aqui Macacu.
- Centralizar marca, cores, gradientes, superfícies, tipografia e formas em componentes/tokens Flutter reutilizáveis.
- Aplicar a identidade por checkpoints: fundação visual; Home e navegação; áreas públicas; Administração e Conta; acabamento responsivo e regressão.
- Preservar navegação, dados, permissões, editores, Firebase, autenticação e regras de negócio.
- Sem serviços hospedados, publicação, alterações de dados, dependências novas, APK, commit ou push, salvo pedido posterior.

## Abordagens consideradas

1. Criar um símbolo e uma logo novos. Rejeitada neste ciclo: muda o reconhecimento da marca e não é necessária para unificar o app.
2. Preservar o símbolo e centralizar a identidade em componentes e tokens; aplicar tela por tela. **Escolhida:** mantém reconhecimento e permite validar mudanças em etapas pequenas.
3. Redesenhar todas as telas de uma vez. Rejeitada: aumenta o risco de regressões e impede revisão visual entre etapas.

## Checkpoints propostos

1. Componente de marca e tokens globais, com testes de tema e responsividade.
2. Home, cabeçalhos e navegação.
3. Estabelecimentos, Explorar, Utilidades e Eventos.
4. Administração, autenticação, Conta, Favoritos e Minha Agenda.
5. Revisão visual responsiva, regressões e análise estática.

Cada checkpoint será apresentado para revisão antes de avançar ao seguinte. A implementação começa após aprovação desta proposta.
