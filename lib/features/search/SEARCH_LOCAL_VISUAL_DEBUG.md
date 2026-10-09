# Etapa 4H — visualização e Hot Reload recuperados

## Resultado observado

O Flutter renderiza normalmente: capturas do próprio engine mostram a tela atual
com a VPN ativa. A janela Windows do MEmu apresentou imagens válidas inicialmente,
mas sua captura via Windows.Graphics.Capture ficou depois incompleta/transparente
ou desatualizada. O screencap ADB gera PNG preto (720×1280) tanto na busca quanto
no launcher Android. A captura nativa MEmuManage mostra o console de boot Linux,
não a superfície Android, e também não serve para revisar a interface.

Não há FLAG_SECURE na janela do aplicativo nem configuração correspondente no
código Android. SurfaceFlinger registra buffers e quadros da SurfaceView Flutter.
O defeito foi localizado no caminho de captura/composição desta instalação MEmu;
a causa interna específica de driver/compositor não foi isolada. Não é ausência
de renderização Flutter. Não se desligou a VPN para atribuir causalidade nem se
alterou a aceleração gráfica global. FLAG_SECURE em DisplayInfo descreve uma
capacidade do display, não prova proteção de captura da janela.

A alternativa validada é tools/capture-search-local.ps1: chama _flutter.screenshot
no VM Service autenticado do processo debug local. A PNG contém o quadro real
renderizado pelo Flutter, sem moldura MEmu, teclado ou outras superfícies nativas.
O script verifica PID/pacote, VPN, URI autenticada e bind loopback; remove seu
encaminhamento temporário ao terminar. Não modifica a arte, a interface ou a VPN.

```powershell
.\tools\capture-search-local.ps1 -Out C:\caminho-local\busca.png
```

## Depuração

O processo local PID 16451 escutava VM Service em 127.0.0.1:41335. Sem a chave
da URI, getVM respondeu 403: a autenticação de depuração permaneceu habilitada.
Descoberta automática não tinha anúncio/log utilizável; as tentativas anteriores
de iniciar Flutter junto da VPN sofreram perda do ADB/reverse durante a mudança
de rede do MEmu. Não é necessário liberar internet ou alterar rotas da VPN:
após estabilização, o VM Service já é acessível via loopback/adb forward.

`read-search-local-vm-uri.py` consulta somente o processo do pacote debug local,
com VPN existente. Lê FlutterJNI.vmServiceUri por comandos JDWP de leitura;
não invoca métodos, suspende threads, redefine classes ou remove autenticação.
Esse campo é documentado no [código oficial FlutterJNI](https://github.com/flutter/engine/blob/main/shell/platform/android/io/flutter/embedding/engine/FlutterJNI.java).
Comandos usados seguem o [protocolo JDWP oficial](https://docs.oracle.com/en/java/javase/21/docs/specs/jdwp/jdwp-protocol.html).
Não copiar a URI autenticada para logs públicos.

`attach-search-local.ps1` verifica APK debug, serviços locais, pacote/PID do VM
e bind do encaminhamento em 127.0.0.1. Conecta-se ao processo existente, sem
reiniciar o aplicativo ou interromper sua VPN. O servidor auxiliar DDS encontrou
colisão de porta nesta máquina; `--no-dds` usa diretamente o VM Service com sua
autenticação preservada. Auth/App Check/regras da busca não foram alterados.

Flutter attach não fornece --flavor. Para preservar FLUTTER_APP_FLAVOR e os
assets Poppins exclusivos do APK local, o script cria um projeto de depuração
descartável em `pr/work/search-local-debug-session`, com default-flavor searchLocal,
configuração de pacotes absoluta e junctions para lib/assets/android. Entry point
continua o main.dart original. O pubspec da aplicação e a versão normal permanecem
intactos. Esse projeto não é destinado a builds, commit ou distribuição.

Exemplo, a partir de app:

```powershell
.\tools\attach-search-local.ps1
```

Em execução: r = Hot Reload; d = desconectar preservando o app/VPN.
Não usar q para uma simples desconexão, pois o comando encerra o aplicativo.
A sessão desta etapa foi deixada conectada para os próximos reloads.

## Testes e integridade

- Reload sem mudança: 981 ms.
- Comentário temporário na página de busca: recarga de 11 bibliotecas em 3,340 s.
- Comentário removido e fonte restaurada: recarga de 1 biblioteca em 3,143 s.
- Nova recarga posterior: sucesso, 3,469 s. Estado da busca preservado.
- PID 16451 e tun0 mantidos; nenhuma reinstalação, reinício ou VPN desligada.
- Auth 9097, Firestore 8087, Functions 5007 e VM forward somente em loopback.
- Probes run-as UID 10073 para TEST-NET IPv4 192.0.2.1 e IPv6 2001:db8::1:
  timeout/bloqueio. Rotas sink/DNS externo permanecem idênticos à etapa 4F.2.
- Proxy temporário HTTP em 127.0.0.1:5017, apenas para a callable demo, atrasou
  cinco segundos a resposta para capturar carregamento. Mantinha os headers de
  Auth/App Check, sem registrar tokens. Foi encerrado; reverse 5007 restaurado.
- Erro visual testado removendo apenas reverse 5007; conexão local restaurada,
  Tentar novamente recuperou Barbearia Modelo e Eletricista Modelo.
- Flutter Analyze: nenhuma ocorrência.
- 12 testes Flutter relevantes passaram (busca UI/transport/navegação/isolamento).
- APK de teste inspecionado novamente: debug local, sem Firebase/FCM nativos
  de produção. Nenhum arquivo de interface/design foi modificado nesta etapa.

## Capturas para revisão

Capturas diretas do engine Flutter, preservadas sem edição em
`C:/Users/tiago/Documents/Codex/2026-09-11/pr/work/search4h-captures/`:

- [Home e barra de pesquisa](/C:/Users/tiago/Documents/Codex/2026-09-11/pr/work/search4h-captures/24-home-vm.png)
- [Campo de busca e filtros](/C:/Users/tiago/Documents/Codex/2026-09-11/pr/work/search4h-captures/21-campo-filtros-vm.png)
- [Resultado Eletrônica Vieira](/C:/Users/tiago/Documents/Codex/2026-09-11/pr/work/search4h-captures/22-resultados-vm.png)
- [BusinessProfile existente](/C:/Users/tiago/Documents/Codex/2026-09-11/pr/work/search4h-captures/23-perfil-vm.png)
- [Estado vazio](/C:/Users/tiago/Documents/Codex/2026-09-11/pr/work/search4h-captures/25-vazio-vm.png)
- [Filtros horizontais adicionais](/C:/Users/tiago/Documents/Codex/2026-09-11/pr/work/search4h-captures/26-filtros-vm.png)
- [Carregamento](/C:/Users/tiago/Documents/Codex/2026-09-11/pr/work/search4h-captures/27-carregando-vm.png)
- [Erro de conexão local](/C:/Users/tiago/Documents/Codex/2026-09-11/pr/work/search4h-captures/28-erro-vm.png)
- [Recuperação após Tentar novamente](/C:/Users/tiago/Documents/Codex/2026-09-11/pr/work/search4h-captures/29-recuperacao-vm.png)

Todos esses estados foram inspecionados nas capturas reais do processo searchLocal
em execução no MEmu. Campo/resultados legíveis, filtros roláveis, estados distintos
e perfil com dados explicitamente fictícios. Nenhum ajuste de design foi feito.
A aprovação estética continua sendo do usuário. Capturas Windows anteriores foram
mantidas apenas como diagnóstico; não são a fonte principal de revisão.

## Arquivos desta etapa e limitações

Criados somente:

- tools/read-search-local-vm-uri.py
- tools/attach-search-local.ps1
- tools/capture-search-local.ps1
- lib/features/search/SEARCH_LOCAL_VISUAL_DEBUG.md

Artefatos locais em work: projeto de depuração, PNGs, logs transitórios de
tentativas. Não houve build APK nesta etapa, alteração de Android/Flutter UI,
regras, backend, Admin, produção, commit, push ou deploy.

Limitações: screencap ADB permanece preto e captura da janela MEmu é instável; JDWP depende do campo nativo do SDK
atual e de pacote debuggable. Portas/URI mudam se o processo reiniciar; executar
novamente o script somente quando precisar reconectar. Atualizações nativas ainda
exigem APK debug local; Hot Reload cobre alterações Dart compatíveis. A atestação
App Check real continua fora do escopo local, conforme documentação 4G.
