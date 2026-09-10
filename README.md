# Tudo Aqui Macacu — app mobile

Projeto Flutter preparado para Android e iPhone.

## Paleta visual

- Azul: `#00A9FF`
- Laranja: `#ED6A1F`
- Amarelo: `#FAB71D`

As três cores foram extraídas do arquivo de referência visual da marca.

## Interface modernizada

A experiência visual atual fica em `lib/redesigned_app.dart`, mantendo o aplicativo principal em `lib/main.dart`. Ela inclui a navegação por Início, Explorar, Ofertas, Favoritos e Perfil; catálogo por subcategorias; vitrines de negócios; vagas; notícias; agenda; turismo e direcionamentos externos configurados pelo administrador.

Os assets locais incluem um conjunto coerente de ícones 3D e uma imagem de natureza para a área de turismo. Os registros de empresas, ofertas, vagas, notícias e eventos continuam sendo demonstrativos até que você publique os conteúdos reais.

Após a instalação do Flutter, gere as pastas nativas e execute:

```powershell
flutter create --platforms=android,ios .
flutter run
```

Para criar um pacote Android:

```powershell
flutter build appbundle
```

Para criar a versão iOS, abra o projeto em um Mac com Xcode e execute:

```bash
flutter build ipa
```

Os registros exibidos no aplicativo são dados demonstrativos e não representam empresas reais.

## Catálogo por categoria

Cada categoria abre uma lista própria e permite filtrar os estabelecimentos por tipo. A estrutura inicial contempla alimentação, lojas, mercados, beleza, auto, saúde, hospedagem, serviços, turismo e casa & construção. Por exemplo, em **Onde comer?** há filtros para restaurantes, pizzarias, lanches, pastelarias, salgados, padarias, cafés, açaí, comida japonesa, bares e marmitas.

Quando você cadastrar um negócio, ele será associado à categoria e à subcategoria corretas, aparecendo somente para as pessoas que escolherem aquele filtro.

## Regra de publicação

Não existe painel, login ou formulário para empresários. Empresas, profissionais, promoções, vagas, notícias, eventos e informações turísticas são cadastrados, revisados e publicados exclusivamente pelo administrador.

Em cada perfil, o administrador configura os destinos externos: link do WhatsApp, link do Google Maps e link do cardápio digital. O aplicativo apenas direciona o público para esses canais.
