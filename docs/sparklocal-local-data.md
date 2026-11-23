# Dados locais do SparkLocal

O APK contém o código e os recursos de imagem empacotados, como o roteiro de
coleta. Banners, estabelecimentos e outros conteúdos publicados durante os
testes ficam no Firestore Emulator; eles não são gravados dentro do APK.

O inicializador `tools/start-spark-local-emulators.ps1` agora:

1. Confere o projeto `demo-universal-search`, Auth/Firestore em loopback e as
   Rules locais `firestore.beta.rules`.
2. Importa o snapshot visual sintético validado mais recente, ou a sessão SparkLocal
   mais recente que tenha sido exportada e validada.
3. Exporta cada encerramento para uma pasta nova em
   `%LOCALAPPDATA%\TudoAquiMacacu\emulator-snapshots\sparklocal-session-*`.
   Snapshots anteriores nunca são sobrescritos.

Para encerrar uma sessão, interrompa o comando no terminal com `Ctrl+C` e espere
ele informar que os dados foram salvos. Evite fechar o terminal à força; uma
interrupção brusca pode impedir o último export. Os snapshots ficam fora do Git e
continuam exclusivamente locais: nenhum dado é enviado ao Firebase hospedado.

O Emulator que já estava ativo importou uma sessão anterior de 12/11. Seu estado
ao vivo foi exportado para uma pasta `sparklocal-session-*` nova e validada, sem
reiniciar nem substituir o processo ativo. O próximo início pelo script acima
carregará essa cópia atual recuperável; se ainda não existir uma sessão exportada,
ele usa o snapshot visual sintético de 16/11. Enquanto o processo atual mantiver
as portas 9097/8087 ocupadas, o script recusa iniciar outra instância.
