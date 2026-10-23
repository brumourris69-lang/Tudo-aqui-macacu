# Auditoria visual e funcional da Home no MEmu

**Data:** 16/10/2026
**Escopo:** diagnóstico somente de leitura; sem alterações no aplicativo, Firebase, dados de teste ou serviços.

## Aplicativo e evidências

- MEmu já estava aberto, com um único dispositivo ADB visível (`127.0.0.1:21503`). O pacote em primeiro plano era `br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal`, versão `0.1.3-local`, atividade `MainActivity`.
- Dispositivo reportado pelo Android: `ASUS_AI2501_B`, Android 9, 720×1280 px, densidade 240 dpi.
- Auth, Firestore e Functions estavam em `127.0.0.1:9097`, `127.0.0.1:8087` e `127.0.0.1:5007`; a linha de comando do Emulator indicava `demo-universal-search` e `firebase.search-emulator.json`. As seis portas configuradas estavam vinculadas ao loopback. O helper validou a VPN local `tun0` antes da captura. Nenhum serviço foi iniciado ou encerrado.
- A captura foi obtida pelo helper Flutter de searchLocal, validada como PNG de 720×1280 e inspecionada visualmente. O app estava na Home antes de qualquer gesto.

Capturas novas, salvas fora do repositório:

- [Home inicial](C:/Users/tiago/AppData/Local/TudoAquiMacacu/visual-tests/20261016-122520-1a716b32/home.png)
- [Home após rolagem 1](C:/Users/tiago/AppData/Local/TudoAquiMacacu/visual-tests/20261016-122520-1a716b32/home-scroll-1.png)
- [Home após rolagem 2](C:/Users/tiago/AppData/Local/TudoAquiMacacu/visual-tests/20261016-122520-1a716b32/home-scroll-2.png)
- [Home após rolagem 3](C:/Users/tiago/AppData/Local/TudoAquiMacacu/visual-tests/20261016-122520-1a716b32/home-scroll-3.png)
- [Aba Explorar](C:/Users/tiago/AppData/Local/TudoAquiMacacu/visual-tests/20261016-122520-1a716b32/explorar-tab.png)
- [Retorno à Home](C:/Users/tiago/AppData/Local/TudoAquiMacacu/visual-tests/20261016-122520-1a716b32/home-return.png)
- [Home no fim da rolagem](C:/Users/tiago/AppData/Local/TudoAquiMacacu/visual-tests/20261016-122520-1a716b32/home-bottom.png)
- [Captura independente da QA](C:/Users/tiago/AppData/Local/TudoAquiMacacu/visual-tests/20261016-122518/home.png)
- [Relatório visual independente da QA](C:/Users/tiago/AppData/Local/TudoAquiMacacu/visual-tests/20261016-122518/report.md)

## Estado atual da Home

O `HomeView` apresenta marca, localização, clima, busca principal, categorias, banners/ofertas, destaques, cupons, vagas, notícias, agenda e Turismo. A configuração administrativa controla visibilidade, ordem, títulos e limites das seções. A navegação inferior contém Início, Explorar, Utilidades, Favoritos e Perfil.

A identidade azul, laranja e branca está consistente. O hero fotográfico, a busca branca e os cartões claros mantêm bom contraste na captura observada. O banner promocional é visualmente forte e os cartões de oferta, notícia, agenda e Turismo têm hierarquia clara.

## Problemas confirmados por evidência visual ou interação

1. **Localização repetida no hero.** “Cachoeiras de Macacu · RJ” aparece junto ao título e novamente no cartão de clima, consumindo espaço sem acrescentar informação.
2. **A faixa de categorias termina com um cartão parcial na borda direita.** A lista é horizontal e rolável; o corte aparenta ser a indicação de continuidade, mas não há outro indicador explícito de rolagem. Não foi constatado que uma categoria esteja inacessível.
3. **O topo ocupa grande parte da primeira tela.** Hero e banner são proeminentes; as categorias começam mais abaixo. É uma oportunidade de reduzir o caminho até as principais entradas, não um defeito funcional confirmado.
4. **Estados vazios estão presentes e são compreensíveis.** A seção de destaques informa que não há estabelecimentos em destaque; a agenda informa que não há evento publicado. Em uma captura inicial, a mensagem de destaques coincide parcialmente com a borda superior da barra inferior, mas a rolagem revela o conteúdo. Não foi confirmado corte permanente.
5. **Os dados visíveis são demonstrativos.** A Home exibe vagas e notícias identificadas como demonstração, coerentes com `searchLocal` e o projeto demo. Isso não foi tratado como conteúdo real da cidade.
6. **A navegação inferior foi testada.** Toquei em Explorar e retornei a Início. A aba abriu e a Home voltou na mesma posição de rolagem, confirmando a preservação desse estado nesta sessão.

## Problemas funcionais confirmados

- Nenhuma falha de toque ou navegação foi reproduzida nesta inspeção.
- Busca, categorias, links “Ver todos”, perfil, notificações e cartões de seção não foram acionados; seu funcionamento permanece **não verificado em dispositivo**.
- A captura não prova por si só que uma consulta foi atendida naquele instante. A tela contém conteúdo demonstrativo e os Emulators locais estavam disponíveis, mas nenhum teste de rede foi provocado.

## Sinais não confirmados

A QA consultou uma janela limitada de logs do processo do aplicativo. Nela havia avisos relacionados a provider do App Check, `RESOURCE_EXHAUSTED` do Firestore, EGL e tentativas de autenticação com usuário inexistente. Não se confirmou se esses registros eram atuais, se ocorreram durante a captura ou se causam algum problema visível. Não foram reproduzidos nem tratados como falha da Home. O cartão “Previsão indisponível no momento” também é apenas o estado observado e não comprova falha do backend.

## Diagnóstico do código e testes existentes

- `lib/redesigned_app.dart` concentra `CityShell`, `HomeView`, composição das seções, `WelcomeHero`, `SectionTitle` e `CategoryTile`. `CityShell` usa `IndexedStack`; a configuração e a maior parte da lógica visual estão no mesmo arquivo.
- `lib/features/home/models/home_page_config.dart` normaliza ordem, visibilidade, títulos e limites.
- `lib/features/home/widgets/home_weather_chip.dart` contém o cartão de clima; `home_tourism_carousel.dart` contém a faixa de Turismo; `lib/core/theme/app_colors.dart` define a paleta.
- `test/home_navigation_test.dart`, `home_page_config_test.dart`, `home_loading_retry_test.dart`, `home_content_retry_test.dart` e testes de Turismo cobrem partes da configuração, navegação, retry e componentes.
- Lacuna de cobertura: o teste responsivo em `home_navigation_test.dart` verifica `HomeCategoryGrid`, enquanto a seção real da Home monta uma `ListView` horizontal de `CategoryTile`. Assim, o teste existente não demonstra o comportamento da faixa real da Home em telas estreitas ou com texto ampliado.
- O atalho de notificações usa `CircleIcon` com tamanho padrão de 37 dp sem tooltip explícito; o atalho de perfil tem tooltip e 48 dp. Isso é uma lacuna de acessibilidade indicada pelo código, não um toque que tenha falhado.

Os testes não foram executados nesta tarefa.

## Cinco melhorias de maior impacto

1. **Adaptar os atalhos de categoria.** Manter ordem e destinos configuráveis, tornar a continuidade da faixa evidente ou usar uma composição responsiva; criar teste para a seção real da Home, inclusive com fonte ampliada.
2. **Enxugar e adaptar o hero.** Evitar repetição da localização, reorganizar clima e título em larguras menores e revisar a apresentação quando o clima estiver indisponível.
3. **Reduzir o caminho até as ações principais.** Avaliar uma versão mais compacta do hero e do banner, sem retirar controles administrativos de ordem, visibilidade e limites.
4. **Refinar estados vazios.** Manter mensagens claras, ajustar sua densidade vertical e garantir que a ação de seção continue evidente quando não houver conteúdo.
5. **Fortalecer acessibilidade dos controles.** Dar rótulos semânticos explícitos e revisar alvos de toque de notificações e outros atalhos; validar tamanhos de texto e contraste sobre as imagens configuradas.

## Plano de implementação em etapas pequenas

1. Acrescentar testes da composição real de `HomeView` em larguras estreitas e com escala de texto ampliada, sem alterar a ordem ou os limites administrativos.
2. Ajustar somente a faixa de categorias e inspecioná-la novamente no MEmu.
3. Refinar o hero de forma responsiva e revisar estados de clima disponível/indisponível.
4. Ajustar a apresentação dos estados vazios e a densidade do banner, um componente por vez.
5. Validar semântica, navegação, configuração administrativa e retorno de aba; executar testes Flutter direcionados antes de aprovar o conjunto.

## Riscos de regressão

`redesigned_app.dart` também contém navegação e componentes usados por outras áreas. Mudanças no shell podem afetar retenção de estado; mudanças na faixa de categorias podem alterar atalhos; mudanças em `HomePageConfig` podem afetar publicação administrativa e limites. A implementação deve manter um único responsável por escrita e verificar cada etapa separadamente.

## Alterações nesta auditoria

Nenhum código Flutter ou serviço foi alterado. Foi criado apenas este relatório no repositório; as capturas ficam no diretório local de QA fora do Git. Não foram executados testes, build ou ações Firebase. O MEmu e os Emulators preexistentes permaneceram ativos.
