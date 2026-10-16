# Home e navegação principal — desenho aprovado

## Objetivo

Modernizar a Home do Tudo Aqui Macacu e revisar a navegação principal mantendo a arquitetura Flutter, a identidade azul, laranja e branca, os destinos já existentes e todas as alterações locais. A entrega deve melhorar leitura em telas pequenas, acessibilidade, feedback de carregamento/falha e preservação do estado, sem reimplementar busca, alterar segurança de produção ou inventar dados municipais.

## Estado existente e decisões

- `CityShell` já usa `IndexedStack` e `NavigationBar` com Início, Explorar, Utilidades, Favoritos e Perfil. Manter as cinco abas, seus destinos e o estado entre trocas.
- `HomePageConfig` já controla ordem, visibilidade, títulos, limites, categorias e identidade visual. Manter esses campos e o editor existente; não introduzir drag-and-drop nem um segundo painel.
- `WelcomeHero` já usa marca, localização, `HomeWeatherChip` e o campo que abre `UniversalSearchPage`. Tornar a composição mais compacta, manter a busca existente e adicionar atalho de perfil conectado à aba Perfil.
- A Home já lista categorias de `homeCatalog` e `ExploreView` encaminha destinos por `openDirectory`. Apresentar as oito áreas prioritárias aprovadas usando categorias/destinos existentes. O rótulo “Utilidades da Cidade” pode ser visual, mas a categoria interna “Serviços úteis” continua sendo usada para roteamento.
- `ExploreView` tem grade fixa de três colunas e ilustração de 90 px. Usar duas colunas em telas estreitas e três em telas maiores, com textos legíveis e targets acessíveis.
- A seção Turismo da Home atualmente abre `TourismCategoryView` com lista vazia. Reutilizar o fluxo carregado de `TourismHomeView` e sua navegação por categoria; não criar leitura Firestore por cartão nem alterar a busca segura.
- A configuração publicada da Home é lida por stream. Diferenciar carregamento e falha, oferecer nova tentativa e manter conteúdo recebido durante falha de atualização. No `HomeEditor`, falha ao carregar não pode habilitar salvamento/publicação de defaults como se fossem dados carregados.
- Preservar a consulta atual da busca universal, `SecureBackend.productionAuthorized`, allowlists, Rules, Functions e todos os gates de produção. Não adicionar chamadas externas nem consulta por cartão.

## Experiência proposta

1. Cabeçalho compacto com marca e slogan, localização, previsão existente e atalho de perfil; em larguras estreitas o clima pode ocupar uma linha secundária para evitar truncar marca/localização.
2. Busca atual como ação principal, mantendo `UniversalSearchPage` e seus controles.
3. Atalhos para Comércio local, Onde comer, Serviços, Profissionais, Empregos, Turismo, Utilidades da Cidade e Eventos, usando os objetos de categoria e funções de navegação existentes. Os ícones e nomes permanecem reconhecíveis e configuráveis.
4. Banners, destaques, ofertas, utilidades, empregos, eventos e Turismo continuam como seções existentes. Ordem, visibilidade, títulos e limites publicados continuam sendo a fonte de apresentação. Ajustes de espaçamento e hierarquia não mudam contratos de dados nem preenchem conteúdos ausentes com fatos inventados.
5. A barra inferior mantém suas cinco abas e o `IndexedStack`. Toque na aba ativa e Voltar do sistema devem ter comportamento previsível; sair da edição Home continua protegido pela guarda existente.
6. Erros de stream exibem mensagens acionáveis e retry quando suportado. Estados vazios só representam carregamentos concluídos sem itens. A Home continua acessível mesmo quando a configuração não carrega, usando defaults visuais apenas como fallback não editável até a recuperação.
7. Editor administrativo existente mantém rascunho/publicação explícitos, ordem, visibilidade, títulos, limites, textos e imagens. Nenhuma publicação ocorre automaticamente.

## Testes e limites

- Widget tests cobrirão grade responsiva, escala de texto, semântica das abas, troca de aba, retorno à Home/estado preservado, retry da configuração, falha segura do editor e navegação por categoria de Turismo com itens carregados.
- Testes existentes de configuração, edição de título, agenda, turismo e módulos relacionados serão preservados e executados direcionadamente.
- Usar fakes/injeções locais para streams e callbacks; não iniciar Firebase Emulator nem MEmu.
- Não acessar Firebase real, migrar dados, instalar dependências, alterar Rules/Functions ou gates de produção, fazer deploy, commit ou push.
- Nenhum conteúdo factual novo sobre Cachoeiras de Macacu será criado.

## Bloqueios conhecidos para produção

A revisão Firebase encontrou regras e projeções existentes em `routes` que podem disponibilizar mais campos do que a interface mostra. Esta implementação de UI não corrige nem encobre esse risco. A revisão de Rules/projeções e compatibilidade de clientes deve ocorrer em tarefa separada e não é condição para esta alteração local.

## Revisão de consistência

O desenho reutiliza as implementações atuais, não cria sistema paralelo de busca/administração e não altera backend ou acesso a dados. A única integração funcional prevista é encaminhar o atalho de Turismo pelo fluxo já existente que carrega os locais. As mudanças de layout e testes ficam na Home, no shell e nas superfícies de navegação diretamente relacionadas.
