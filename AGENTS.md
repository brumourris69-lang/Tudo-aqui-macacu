# Tudo Aqui Macacu — instruções para agentes

## Projeto e arquitetura

- Este repositório contém o aplicativo Flutter em lib/, testes em test/, configuração Android em android/, Firebase em firebase.json, firestore.rules, functions/ e configurações locais em firebase.search-emulator.json; há também um Worker em workers/.
- Preserve os padrões e os modelos existentes. A interface principal e seus módulos ficam em lib/; funções de backend usam Node.js. Antes de criar uma abstração, procure uma existente.
- Há o aplicativo Android normal e a variante de desenvolvimento searchLocal, com identificador próprio. O app normal usa sua configuração Firebase normal; searchLocal é destinado exclusivamente ao projeto demo e aos emuladores locais.

## Escopo, autonomia e preservação

- Trabalhe em uma tarefa por vez e faça mudanças pequenas, direcionadas ao pedido. Inspecione o estado do Git e os arquivos relevantes antes de editar; preserve alterações locais e arquivos não rastreados.
- Leituras, inspeções, análise estática e testes locais não destrutivos e proporcionais podem ser feitos sem pedir autorização adicional. Antes de executar testes, confira se scripts ou fixtures apagam ou alteram dados persistentes.
- Peça autorização específica antes de deploy, publicação, release, commit ou push; instalação de dependências ou ferramentas; alteração de credenciais ou configurações sensíveis; acesso a dados reais de produção; alteração, limpeza ou substituição de dados persistentes do Firebase Emulator; instalação, remoção ou limpeza de dados de aplicativos no MEmu; ou testes de segurança ativos.
- Não faça mudanças fora do escopo, nem descarte, reverta, sobrescreva, limpe ou esconda trabalho local para facilitar a tarefa. Não exponha segredos, tokens, dados pessoais ou conteúdo privado em código, artefatos ou logs.

## Firebase, variantes e dispositivos

- Não presuma que uma sessão nova está isolada porque uma sessão anterior estava. Antes de qualquer uso de searchLocal, confirme novamente o projeto demo-universal-search, os emuladores necessários, os endpoints locais e a VPN de isolamento exigida. Se algum controle não puder ser comprovado, pare antes de iniciar operações Firebase.
- Para tarefas locais de Firebase, use explicitamente firebase.search-emulator.json e o projeto demo-universal-search; confira os efeitos do comando antes de executá-lo. Nunca use firebase.json ou a seleção padrão de projeto como prova de que o destino é um emulador. Não faça deploy sem autorização específica.
- Os endpoints Android Emulator usados pelo ambiente local incluem Auth 9097, Firestore 8087 e Functions 5007; confirme valores e encaminhamentos atuais em vez de presumir que continuam ativos. Mantenha a VPN; não libere tráfego externo para contornar problemas.
- Preserve o app normal, seus dados e sua configuração. Não inicie, instale, atualize, desinstale, habilite, desabilite ou limpe dados no MEmu sem autorização específica. Use o launcher protegido do searchLocal quando o fluxo de teste assim exigir.
- Preserve fixtures e exports persistentes. Inspecione scripts de integração antes de rodá-los: alguns podem limpar coleções do emulador. Prefira uma instância temporária isolada quando ela evitar impacto aos dados persistentes.

## Implementação e validação

- Siga a arquitetura Flutter/Firebase existente e a separação entre app normal e searchLocal. Preserve autenticação, autorização administrativa, App Check, regras, publicação e projeções públicas. Não enfraqueça controles de segurança para fazer um teste passar.
- Prefira consultas limitadas e paginadas, debounce onde já adotado, trabalho eficiente em celulares simples e carregamento sob demanda. Não baixe coleções inteiras para filtrar no dispositivo.
- Escolha verificações proporcionais à mudança: flutter analyze e testes Flutter direcionados; testes e npm run check em functions/ ou no Worker quando relevantes. Use Firebase Emulator somente com o projeto demo confirmado. integration_test serve para fluxos ponta a ponta que precisem de dispositivo; não execute testes que alterem MEmu ou dados persistentes sem autorização.
- Após mudanças Flutter, use Hot Reload somente se uma sessão de desenvolvimento ativa e a variante correta estiverem confirmadas. Mudanças de inicialização Dart, código nativo ou Gradle podem exigir Hot Restart ou nova compilação debug. Não gere APK de distribuição como parte de uma tarefa comum.
- Antes de declarar sucesso, confira os resultados reais dos comandos e revise o diff. Relate em português o que mudou, os testes executados, falhas ou limitações e qualquer passo que dependa de autorização. Não afirme validação visual sem observação direta.

## Ferramentas

Use ferramentas somente quando forem adequadas à tarefa; não execute a lista inteira por rotina.

- Context7: consulte documentação oficial atual quando versão, API ou comportamento de Flutter/Firebase/Node exigir confirmação. Baseie decisões no resultado consultado.
- Superpowers: use brainstorming para decisões de design, TDD para funcionalidade ou correção, debugging sistemático para falhas e verificação antes de declarar conclusão, escolhendo apenas o fluxo pertinente.
- Matt Pocock’s Skills: selecione uma skill quando o pedido corresponder claramente à sua finalidade; não invoque skills sem relação com a tarefa.
- Playwright CLI: use para automação de páginas web dentro do escopo autorizado. Não é ferramenta para testar a interface nativa Flutter.
- Flutter DevTools: use para investigar layout, rebuilds, estado ou desempenho quando isso for relevante; não execute por rotina.
- integration_test: use para fluxos ponta a ponta no app quando testes unitários/widget não forem suficientes, respeitando a autorização para dispositivo e ambiente.
- Firebase CLI: use para emuladores e tarefas locais explicitamente limitadas ao projeto demo. Deploy ou operações de produção exigem autorização específica.
- Semgrep: use como análise estática direcionada a mudanças relacionadas à segurança; não substitui revisão nem testes.
- OWASP ZAP: varreduras dinâmicas são testes de segurança ativos; só execute com autorização específica, alvo isolado e escopo definido.
- Se uma ferramenta não estiver disponível, informe a limitação. Não a instale nem altere o PATH sem autorização.

## Trabalho com agentes especializados

- O agente principal desta equipe é `tudo-aqui-orchestrator` (a conversa principal do Codex, não um subagente adicional): leia este arquivo, confira `git status`, delimite escopo e critérios de conclusão e escolha somente os especialistas necessários. Não convoque toda a equipe por padrão.
- Atribua um único responsável por escrita em cada tarefa. Os demais agentes devem investigar ou revisar sem editar; escrita paralela só é permitida em arquivos previamente separados e sem dependências concorrentes.
- Agentes compartilham o workspace e herdam as permissões da sessão principal. Suas instruções não isolam arquivos nem ampliam a autorização do usuário; aplique as mesmas regras de segurança, preservação e aprovação a todos.
- O agente principal integra e revisa todas as alterações, confirma os resultados observados das verificações e apresenta um único relatório final em português.

## Skills de engenharia do projeto

- Descubra e use as skills em `.agents/skills/` quando a tarefa corresponder à descrição de cada `SKILL.md`; elas complementam estas instruções e não concedem autorização adicional.
- Preserve as skills específicas existentes (`flutter-ui-builder`, `flutter-widget-tester`, `android-build-manager`, `firebase-emulator-manager` e `firebase-security-auditor`). Para planejamento, segurança mobile, privacidade, backend, QA amplo, refatoração, release ou performance, selecione a skill especializada mais próxima; combine skills somente quando necessário.
- Skills oficiais de plugins podem fornecer MCPs. Antes de usar uma ferramenta MCP, confira sua finalidade, escopo e se a operação pode acessar serviços hospedados; a presença da ferramenta não autoriza acesso a produção.
