# Migração de conteúdo para o painel administrativo

## Auditoria inicial

| Conteúdo | Origem atual | Destino no Firebase | Já editável | Ação |
| --- | --- | --- | --- | --- |
| Anúncios do carrossel | Firestore `ads` | `ads` | Sim | Manter e ampliar campos de mídia/ordem |
| Estabelecimentos | Lista `businesses` no Dart | `establishments` | Parcial | Migrar exemplos e ligar Home, explorar, busca e favoritos |
| Categorias | Lista `catalog` no Dart | `categories` | Não | Criar administração e manter lista local como reserva na transição |
| Ofertas | Cards demonstrativos e `offers` | `offers` | Parcial | Ligar seção pública à coleção publicada |
| Eventos | Card demonstrativo e `events` | `events` | Parcial | Ligar agenda e destaque da Home |
| Turismo | Card demonstrativo | `establishments` com categoria Turismo | Parcial | Migrar pontos turísticos reais e usar a mesma ficha editável |
| Notícias, vagas e links | Conteúdo demonstrativo / coleções existentes | `news`, `jobs`, `links` | Parcial | Ligar listas públicas às coleções publicadas |
| Identidade e ilustrações | Assets locais | Assets locais | Não aplicável | Permanecem no aplicativo |

## Ordem segura

1. Criar e validar o modelo editável de estabelecimento no painel.
2. Migrar os exemplos para `establishments` sem remover a reserva local.
3. Fazer as telas públicas preferirem dados publicados do Firestore.
4. Só remover o conteúdo demonstrativo depois que a coleção estiver preenchida e validada.

## Dados que não devem voltar ao Dart

Nome, categoria, descrição, contatos, links, status de publicação, destaque e
ordem de estabelecimentos, promoções, eventos e turismo devem ser administrados
no Firebase. Assets locais ficam restritos à marca, ícones e placeholders.
# Home CMS — auditoria e migração

| Elemento | Origem atual | Destino | Fallback |
| --- | --- | --- | --- |
| Cabeçalho e busca | Flutter | `home_pages/published` | Design atual |
| Categorias | catálogo Flutter | `home_pages/published.sections.categories` | catálogo atual |
| Destaques | `establishments` | `home_pages/published.sections.highlights` | visível |
| Ofertas | Flutter / `offers` | `home_pages/published.sections.offers` | visível |
| Eventos e turismo | Flutter / módulos | `home_pages/published.sections` | visível |

As mudanças são feitas no documento `draft`; publicar cria uma cópia atômica em `published` e registra auditoria. Não há execução de código remoto.
