# Links internos de conteúdo

O app reconhece o contrato local `tudoaqui://content/<tipo>/<id>` para
`establishment`, `tourism` e `event`. O ID é o identificador estável do
documento. O Android encaminha intents frios e quentes por um canal nativo;
o parser Dart valida esquema, host, tipo, ID, query e fragmento antes de
navegar. A fila conserva links até a shell estar pronta, processa destinos
diferentes em ordem e elimina duplicatas enquanto o destino está ativo ou
aguardando.

O contrato serve para testes e encaminhamento entre telas instaladas. Não é
uma URL pública e não deve ser divulgado em compartilhamentos. Estabelecimentos,
turismo e eventos são resolvidos somente pelo serviço público allowlisted já
existente. Uma resposta indisponível não revela rascunhos, conteúdo inativo ou
documentos removidos. O compartilhamento continua em texto sem URL.

Para ativar links públicos no futuro será necessário aprovar um domínio real,
publicar nele a associação Android (`assetlinks.json`), verificar o certificado
de assinatura e definir a rota web/de fallback. Esta implementação não declara
nem configura esse domínio.
