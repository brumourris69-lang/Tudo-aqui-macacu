# Base de estabelecimentos — etapa 3

Esta base apenas transforma mapas fornecidos em resultados públicos. Não faz
consultas, não usa dados locais demonstrativos e não conecta a interface.
BusinessSearchAdapter reutiliza Business.fromData com campos de exibição
selecionados; não guarda o documento completo nem dados de contato.

## Contrato de elegibilidade

published precisa ser o booleano true. active ausente não restringe o registro;
se presente precisa ser booleano e true. expiresAt ausente não restringe; se
presente precisa ser Timestamp posterior ao instante now fornecido pelo chamador.
Valores nulos/malformados e publicação ausente ficam pending. open não interfere.
ID vazio ou nome/título ausente não produz resultado.

Isso é uma política local para a futura busca, não uma alteração de Security
Rules nem uma garantia sobre documentos já acessíveis em produção.

## Filtros

Todos aceita qualquer categoria de estabelecimento elegível.
Comércios inclui Comércio, Onde comer?, Saúde, Imóveis, Veículos, Pets, Beleza,
Academias, Educação, Hospedagem e Tecnologia.
Serviços inclui Serviços e Profissionais.
Categorias mistas seguem a categoria principal existente. Não há inferência
por subcategoria: assistência técnica em Tecnologia permanece em Comércios.
Empregos, Turismo, Notícias, Eventos, Promoções, Serviços úteis, categorias
desconhecidas e categoria ausente ficam somente em Todos nesta etapa.
Os testes conferem os nomes mapeados contra o catálogo real do app.

## Pendências antes da integração

- Confirmar a semântica de active nos documentos reais, as regras implantadas
  e eventuais expiresAt legados/nulos; não converter valores silenciosamente.
- Validar o agrupamento das categorias mistas com o produto. Não deduzir
  comércio/serviço por palavras ambíguas de subcategorias.
- Confirmar que imageUrl/logoUrl apontam para imagens publicáveis. Validar uma
  URL HTTP(S) não prova que seu conteúdo está autorizado para publicação.
- Normalizar consulta e corpus com a mesma função. A função cobre caracteres
  latinos comuns/português e marcas combinantes; não é transliteração universal,
  mecanismo de busca, geração de prefixos ou índice.
- Na integração futura, resolver o documento por coleção/ID, revalidar sua
  disponibilidade e reutilizar BusinessProfile e o fluxo atual de favoritos.
  O destino é apenas metadado; não há nova rota, callback ou página duplicada.
- BusinessRepository atualmente só filtra published. Não usar Business.open
  nem um Business isolado como prova da elegibilidade completa.
