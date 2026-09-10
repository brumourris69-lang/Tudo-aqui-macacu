import 'package:flutter/material.dart';
import 'redesigned_app.dart';

void main() => runApp(const RedesignedApp());

/*
  Rascunho anterior preservado apenas para referência. A versão ativa do
  aplicativo está em redesigned_app.dart.

const _green = Color(0xFF00A9FF);
const _deepGreen = Color(0xFF101820);
const _orange = Color(0xFFED6A1F);
const _yellow = Color(0xFFFAB71D);
const _cream = Color(0xFFFFFFFF);

class TudoAquiApp extends StatelessWidget {
  const TudoAquiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tudo Aqui Macacu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _cream,
      colorScheme: ColorScheme.fromSeed(seedColor: _green, brightness: Brightness.light, secondary: _orange),
        appBarTheme: const AppBarTheme(backgroundColor: _cream, foregroundColor: _deepGreen, elevation: 0),
        textTheme: Theme.of(context).textTheme.apply(bodyColor: _deepGreen, displayColor: _deepGreen),
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final Set<String> _favorites = {};

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(favorites: _favorites, onFavorite: _toggleFavorite),
      ExplorePage(favorites: _favorites, onFavorite: _toggleFavorite),
      const JobsPage(),
      ProfilePage(favoriteCount: _favorites.length),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: 'Explorar'),
          NavigationDestination(icon: Icon(Icons.work_outline), selectedIcon: Icon(Icons.work), label: 'Vagas'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Conta'),
        ],
      ),
    );
  }

  void _toggleFavorite(String name) => setState(() {
        _favorites.contains(name) ? _favorites.remove(name) : _favorites.add(name);
      });
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.favorites, required this.onFavorite});

  final Set<String> favorites;
  final ValueChanged<String> onFavorite;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _HomeHeader(onSearch: () => _openSearch(context))),
        SliverToBoxAdapter(child: SectionTitle(title: 'Explore por categoria', action: 'Ver todas', onAction: () {})),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          sliver: SliverToBoxAdapter(
            child: SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: demoCategories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, index) => CategoryTile(category: demoCategories[index], onTap: () => _openCategory(context, demoCategories[index])),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(child: SectionTitle(title: 'Destaques da cidade', action: 'Ver guia', onAction: () {})),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
          sliver: SliverList.separated(
            itemCount: demoBusinesses.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, index) => BusinessCard(
              business: demoBusinesses[index],
              isFavorite: favorites.contains(demoBusinesses[index].name),
              onFavorite: () => onFavorite(demoBusinesses[index].name),
            ),
          ),
        ),
        SliverToBoxAdapter(child: _OfferBanner()),
        SliverToBoxAdapter(child: SectionTitle(title: 'Vagas recentes', action: 'Ver todas', onAction: () {})),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          sliver: SliverList.separated(
            itemCount: demoJobs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) => JobTile(job: demoJobs[index]),
          ),
        ),
        SliverToBoxAdapter(child: _TourismBanner()),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  void _openSearch(BuildContext context) {
    showSearch(context: context, delegate: MacacuSearchDelegate());
  }

  void _openCategory(BuildContext context, Category category) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CategoryDirectoryPage(category: category)));
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onSearch});
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEAF8FF),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [BrandMark(), Spacer(), Icon(Icons.notifications_none_outlined), SizedBox(width: 18), CircleAvatar(radius: 17, backgroundColor: _yellow, child: Text('M', style: TextStyle(color: _deepGreen) ))]),
        const SizedBox(height: 34),
        const Text('BEM-VINDO À SUA CIDADE', style: TextStyle(color: _orange, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 1.4)),
        const SizedBox(height: 9),
        Text('Tudo que Macacu\ntem de bom, perto\nde você.', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700, height: .98, letterSpacing: -1.4)),
        const SizedBox(height: 14),
        const Text('Comércios, profissionais, oportunidades e experiências locais em um só lugar.', style: TextStyle(color: Color(0xFF52615D), height: 1.4)),
        const SizedBox(height: 23),
        InkWell(
          onTap: onSearch,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: const Row(children: [Icon(Icons.search, color: Color(0xFF65716D)), SizedBox(width: 10), Expanded(child: Text('O que você está procurando?', style: TextStyle(color: Color(0xFF65716D)))), Icon(Icons.arrow_forward, color: _green)]),
          ),
        ),
      ]),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});
  @override
  Widget build(BuildContext context) => const Row(mainAxisSize: MainAxisSize.min, children: [
        DecoratedBox(decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.all(Radius.circular(11))), child: SizedBox(width: 35, height: 35, child: Icon(Icons.water, color: Colors.white, size: 21))),
        SizedBox(width: 8),
        Text('Tudo Aqui\nMacacu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.0)),
      ]);
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, required this.action, required this.onAction});
  final String title;
  final String action;
  final VoidCallback onAction;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 14, 15),
        child: Row(children: [Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.7))), TextButton(onPressed: onAction, child: Text('$action  →'))]),
      );
}

class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.category, required this.onTap});
  final Category category;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 84,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                DecoratedBox(decoration: const BoxDecoration(color: Color(0xFFE5F6FF), shape: BoxShape.circle), child: SizedBox(width: 38, height: 38, child: Icon(category.icon, color: _green, size: 20))),
                const SizedBox(height: 7),
                Text(category.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      );
}

class BusinessCard extends StatelessWidget {
  const BusinessCard({super.key, required this.business, required this.isFavorite, required this.onFavorite});
  final Business business;
  final bool isFavorite;
  final VoidCallback onFavorite;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showModalBottomSheet(context: context, showDragHandle: true, builder: (_) => BusinessSheet(business: business)),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(children: [
              DecoratedBox(decoration: BoxDecoration(color: business.color, borderRadius: BorderRadius.circular(13)), child: SizedBox(width: 58, height: 58, child: Icon(business.icon, color: Colors.white, size: 28))),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${business.subcategory.toUpperCase()} · DEMONSTRAÇÃO', style: const TextStyle(color: _orange, fontSize: 9, letterSpacing: .6, fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(business.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)), const SizedBox(height: 3), Text(business.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF65716D), fontSize: 12))])),
              IconButton(onPressed: onFavorite, icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border, color: isFavorite ? _orange : _green)),
            ]),
          ),
        ),
      );
}

class _OfferBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('OFERTAS DE HOJE', style: TextStyle(color: _yellow, fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 1.2)), SizedBox(height: 8), Text('Economize no comércio local.', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, height: 1.02)), SizedBox(height: 8), Text('Promoções cadastradas por empresas participantes.', style: TextStyle(color: Color(0xFFDDF4FF), fontSize: 12))])),
          const SizedBox(width: 13),
          const DecoratedBox(decoration: BoxDecoration(color: _orange, shape: BoxShape.circle), child: SizedBox(width: 70, height: 70, child: Center(child: Text('OFERTAS', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)))))
        ]),
      );
}

class _TourismBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFEAF8FF),
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('CONHEÇA MACACU', style: TextStyle(color: _orange, fontSize: 10, letterSpacing: 1.3, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Onde a natureza\nte recebe.', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 31, height: .98, letterSpacing: -1)),
          const SizedBox(height: 8),
          const Text('Cachoeiras, trilhas, sabores e experiências para descobrir no seu ritmo.', style: TextStyle(color: Color(0xFF52615D))),
          const SizedBox(height: 18),
          FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.map_outlined), label: const Text('Planejar meu passeio')),
        ]),
      );
}

class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key, required this.favorites, required this.onFavorite});
  final Set<String> favorites;
  final ValueChanged<String> onFavorite;
  @override
  Widget build(BuildContext context) => CustomScrollView(slivers: [
        const SliverAppBar(pinned: true, title: BrandMark()),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 22, 20, 10), child: Text('Encontre o que precisa', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate((_, index) => CategoryTile(category: demoCategories[index], onTap: () => _openCategory(context, demoCategories[index])), childCount: demoCategories.length),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: .86),
          ),
        ),
        SliverToBoxAdapter(child: SectionTitle(title: 'Comércios', action: 'Filtros', onAction: () {})),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          sliver: SliverList.separated(itemCount: demoBusinesses.length, separatorBuilder: (_, __) => const SizedBox(height: 12), itemBuilder: (_, index) => BusinessCard(business: demoBusinesses[index], isFavorite: favorites.contains(demoBusinesses[index].name), onFavorite: () => onFavorite(demoBusinesses[index].name))),
        ),
      ]);

  void _openCategory(BuildContext context, Category category) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CategoryDirectoryPage(category: category)));
  }
}

class CategoryDirectoryPage extends StatefulWidget {
  const CategoryDirectoryPage({super.key, required this.category});
  final Category category;

  @override
  State<CategoryDirectoryPage> createState() => _CategoryDirectoryPageState();
}

class _CategoryDirectoryPageState extends State<CategoryDirectoryPage> {
  String selectedType = 'Todos';
  final Set<String> favorites = {};

  @override
  Widget build(BuildContext context) {
    final businessesInCategory = allBusinesses.where((business) => business.category == widget.category.name).toList();
    final visible = selectedType == 'Todos' ? businessesInCategory : businessesInCategory.where((business) => business.subcategory == selectedType).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.name)),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 28), children: [
        Text('Escolha um tipo e encontre estabelecimentos em ${widget.category.name.toLowerCase()}.', style: const TextStyle(color: Color(0xFF52615D))),
        const SizedBox(height: 18),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: ['Todos', ...widget.category.subcategories].map((type) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(type), selected: selectedType == type, onSelected: (_) => setState(() => selectedType = type)))).toList()),
        ),
        const SizedBox(height: 16),
        Text('${visible.length} opção(ões) em ${selectedType.toLowerCase()}', style: const TextStyle(fontSize: 12, color: _orange, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (visible.isEmpty)
          const _DirectoryEmptyState()
        else
          ...visible.map((business) => Padding(padding: const EdgeInsets.only(bottom: 12), child: BusinessCard(business: business, isFavorite: favorites.contains(business.name), onFavorite: () => setState(() => favorites.contains(business.name) ? favorites.remove(business.name) : favorites.add(business.name))))),
        const Padding(padding: EdgeInsets.only(top: 8), child: Text('Estabelecimentos exibidos como demonstração. Você incluirá os negócios reais pelo painel administrativo.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Color(0xFF65716D)))),
      ]),
    );
  }
}

class _DirectoryEmptyState extends StatelessWidget {
  const _DirectoryEmptyState();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 28, horizontal: 18),
        child: Column(children: [
          Icon(Icons.storefront_outlined, color: _green, size: 36),
          SizedBox(height: 10),
          Text('Em breve, novos estabelecimentos aparecerão aqui.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text('Você controla os cadastros e decide o que entra na vitrine.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF65716D))),
        ]),
      );
}

class JobsPage extends StatefulWidget {
  const JobsPage({super.key});
  @override
  State<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends State<JobsPage> {
  String selected = 'Todas';
  @override
  Widget build(BuildContext context) {
    final visible = selected == 'Todas' ? demoJobs : demoJobs.where((job) => job.area == selected).toList();
    return CustomScrollView(slivers: [
      const SliverAppBar(pinned: true, title: BrandMark()),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 22, 20, 6), child: Text('Vagas de emprego', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
      const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('Oportunidades publicadas por empresas locais.'))),
      SliverToBoxAdapter(child: SizedBox(height: 64, child: ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 8), scrollDirection: Axis.horizontal, children: ['Todas', 'Comércio', 'Serviços', 'Restaurante'].map((item) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(item), selected: selected == item, onSelected: (_) => setState(() => selected = item))).toList()))),
      SliverPadding(padding: const EdgeInsets.all(20), sliver: SliverList.separated(itemCount: visible.length, separatorBuilder: (_, __) => const SizedBox(height: 12), itemBuilder: (_, index) => JobTile(job: visible[index]))),
    ]);
}

class JobTile extends StatelessWidget {
  const JobTile({super.key, required this.job});
  final Job job;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showModalBottomSheet(context: context, showDragHandle: true, builder: (_) => Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 32), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(job.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 8), Text('${job.area} · ${job.type}'), const SizedBox(height: 10), const Text('Vaga de demonstração. No lançamento, a candidatura seguirá pelo contato ou formulário definido pela empresa.'), const SizedBox(height: 20), SizedBox(width: double.infinity, child: FilledButton(onPressed: () {}, child: const Text('Candidatar-se')))]))),
          child: Padding(padding: const EdgeInsets.all(15), child: Row(children: [const DecoratedBox(decoration: BoxDecoration(color: Color(0xFFE5F6FF), shape: BoxShape.circle), child: SizedBox(width: 45, height: 45, child: Icon(Icons.work_outline, color: _green))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(job.when, style: const TextStyle(color: _orange, fontSize: 10, fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text(job.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)), Text('${job.area} · ${job.type}', style: const TextStyle(fontSize: 12, color: Color(0xFF65716D)))])), const Icon(Icons.chevron_right, color: _green)])),
        ),
      );
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.favoriteCount});
  final int favoriteCount;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
        const SizedBox(height: 12),
        const Row(children: [CircleAvatar(radius: 28, backgroundColor: _yellow, child: Icon(Icons.person_outline, color: _deepGreen)), SizedBox(width: 13), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Sua conta', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)), Text('Entre para salvar seus favoritos')])]),
        const SizedBox(height: 25),
        _ProfileCard(icon: Icons.favorite_border, title: 'Itens salvos', subtitle: '$favoriteCount favorito(s) neste aparelho'),
        _ProfileCard(icon: Icons.notifications_none, title: 'Notificações', subtitle: 'Promoções, vagas e novidades'),
        const SizedBox(height: 26),
        const Text('Feito para quem vive Macacu', textAlign: TextAlign.center, style: TextStyle(color: _green, fontWeight: FontWeight.w600)),
      ]);
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.icon, required this.title, required this.subtitle, this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(child: ListTile(onTap: onTap, leading: Icon(icon, color: _green), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right)));
}

class BusinessSheet extends StatelessWidget {
  const BusinessSheet({super.key, required this.business});
  final Business business;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(business.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text('${business.category} · ${business.subcategory} · PERFIL DEMONSTRATIVO', style: const TextStyle(fontSize: 11, color: _orange, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          Text(business.description),
          const SizedBox(height: 12),
          const Text('Os links de contato, rota e cardápio são cadastrados e atualizados exclusivamente pelo administrador.'),
          const SizedBox(height: 22),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => _launchDestination(context, business.whatsappUrl, 'WhatsApp', LaunchMode.externalApplication), icon: const Icon(Icons.chat_outlined), label: const Text('Falar no WhatsApp'))),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _launchDestination(context, business.mapsUrl, 'Google Maps', LaunchMode.externalApplication), icon: const Icon(Icons.directions_outlined), label: const Text('Como chegar'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: () => _launchDestination(context, business.menuUrl, 'Cardápio digital', LaunchMode.inAppBrowserView), icon: const Icon(Icons.menu_book_outlined), label: const Text('Cardápio'))),
          ]),
        ]),
      );
}

Future<void> _launchDestination(BuildContext context, String url, String label, LaunchMode mode) async {
  final target = Uri.tryParse(url);
  if (target == null || url.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label será disponibilizado quando você cadastrar o estabelecimento.')));
    return;
  }
  if (!await launchUrl(target, mode: mode)) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível abrir $label.')));
  }
}

class MacacuSearchDelegate extends SearchDelegate<void> {
  @override
  List<Widget>? buildActions(BuildContext context) => [IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear))];
  @override
  Widget? buildLeading(BuildContext context) => IconButton(onPressed: () => close(context, null), icon: const Icon(Icons.arrow_back));
  @override
  Widget buildResults(BuildContext context) => _results();
  @override
  Widget buildSuggestions(BuildContext context) => _results();
  Widget _results() {
    final text = query.toLowerCase().trim();
    final results = [...allBusinesses.map((item) => item.name), 'João — Mecânico', 'Roteiro: Cachoeiras e trilhas', 'Vaga: Atendente de loja'].where((item) => text.isEmpty || item.toLowerCase().contains(text)).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [if (text.isEmpty) const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Busque comércios, profissionais, vagas, eventos ou pontos turísticos.')), ...results.map((result) => Card(child: ListTile(leading: const Icon(Icons.search, color: _green), title: Text(result), subtitle: const Text('Resultado de demonstração'), onTap: () {}))), if (results.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(28), child: Text('Nenhum resultado encontrado.')))]);
  }
}

class Category {
  const Category(this.name, this.icon, {required this.subcategories});
  final String name;
  final IconData icon;
  final List<String> subcategories;
}

class Business {
  const Business(this.name, this.category, this.description, this.icon, this.color, {this.subcategory = '', this.whatsappUrl = '', this.mapsUrl = '', this.menuUrl = ''});
  final String name;
  final String category;
  final String description;
  final IconData icon;
  final Color color;
  final String subcategory;
  final String whatsappUrl;
  final String mapsUrl;
  final String menuUrl;
}

class Job {
  const Job(this.title, this.area, this.type, this.when);
  final String title;
  final String area;
  final String type;
  final String when;
}

const demoCategories = [
  Category('Onde comer?', Icons.restaurant_outlined, subcategories: ['Restaurantes', 'Pizzarias', 'Hambúrgueres e lanches', 'Pastelarias', 'Salgados', 'Padarias e confeitarias', 'Cafés e docerias', 'Açaí e sorvetes', 'Comida japonesa', 'Bares e petiscos', 'Marmitas e delivery']),
  Category('Lojas', Icons.shopping_bag_outlined, subcategories: ['Moda e acessórios', 'Calçados', 'Infantil', 'Casa e decoração', 'Celulares e eletrônicos', 'Presentes', 'Papelaria e livros', 'Variedades']),
  Category('Mercados', Icons.shopping_cart_outlined, subcategories: ['Supermercados', 'Mercearias', 'Hortifruti', 'Açougues', 'Bebidas', 'Produtos naturais']),
  Category('Beleza', Icons.content_cut, subcategories: ['Cabeleireiros e salões', 'Barbearias', 'Manicure e unhas', 'Estética', 'Maquiagem', 'Massagem e bem-estar']),
  Category('Auto', Icons.directions_car_outlined, subcategories: ['Oficinas', 'Autopeças', 'Pneus', 'Lava jatos', 'Motos', 'Autoelétrica', 'Combustíveis']),
  Category('Saúde', Icons.local_hospital_outlined, subcategories: ['Farmácias', 'Clínicas', 'Dentistas', 'Laboratórios', 'Psicologia', 'Fisioterapia']),
  Category('Hospedagem', Icons.bed_outlined, subcategories: ['Hotéis e pousadas', 'Sítios e chalés', 'Camping', 'Locais para eventos']),
  Category('Serviços', Icons.handyman_outlined, subcategories: ['Construção e reformas', 'Eletricista', 'Encanador', 'Informática', 'Fotografia', 'Contabilidade', 'Limpeza', 'Segurança']),
  Category('Turismo', Icons.park_outlined, subcategories: ['Cachoeiras', 'Trilhas', 'Pontos turísticos', 'Guias e passeios', 'Artesanato local', 'Feiras']),
  Category('Casa e construção', Icons.home_work_outlined, subcategories: ['Materiais de construção', 'Móveis', 'Decoração', 'Ferragens', 'Vidraçaria', 'Marcenaria']),
];
const demoBusinesses = [
  Business('Café da Serra', 'Onde comer?', 'Sabores acolhedores no coração da cidade.', Icons.local_cafe_outlined, _orange, subcategory: 'Cafés e docerias'),
  Business('Estúdio Raiz', 'Beleza', 'Cuidado, beleza e autoestima para você.', Icons.spa_outlined, _yellow, subcategory: 'Cabeleireiros e salões'),
  Business('Mercado do Vale', 'Mercados', 'Variedade e praticidade para o seu dia.', Icons.storefront_outlined, _green, subcategory: 'Supermercados'),
  Business('Loja demonstração', 'Lojas', 'Moda, presentes e opções para a cidade.', Icons.shopping_bag_outlined, _orange, subcategory: 'Moda e acessórios'),
  Business('Auto Centro demonstração', 'Auto', 'Cuidados para carro e moto.', Icons.car_repair_outlined, _green, subcategory: 'Oficinas'),
  Business('Clínica demonstração', 'Saúde', 'Atendimento e cuidado para a comunidade.', Icons.medical_services_outlined, _yellow, subcategory: 'Clínicas'),
  Business('Pousada demonstração', 'Hospedagem', 'Uma estadia para descobrir Macacu.', Icons.cottage_outlined, _orange, subcategory: 'Hotéis e pousadas'),
  Business('Serviços demonstração', 'Serviços', 'Profissionais para o que você precisar.', Icons.handyman_outlined, _green, subcategory: 'Construção e reformas'),
  Business('Roteiro demonstração', 'Turismo', 'Experiências e paisagens para conhecer.', Icons.hiking_outlined, _yellow, subcategory: 'Cachoeiras'),
  Business('Casa & Construção demonstração', 'Casa e construção', 'Soluções para sua casa e obra.', Icons.home_work_outlined, _orange, subcategory: 'Materiais de construção'),
];
const foodBusinesses = [
  Business('Restaurante demonstração', 'Onde comer?', 'Pratos para almoçar ou jantar.', Icons.restaurant_outlined, _green, subcategory: 'Restaurantes'),
  Business('Pizzaria Sabor Local', 'Onde comer?', 'Pizzas artesanais para pedir ou retirar.', Icons.local_pizza_outlined, _orange, subcategory: 'Pizzarias'),
  Business('Pastel do Vale', 'Onde comer?', 'Pastéis preparados na hora.', Icons.bakery_dining_outlined, _yellow, subcategory: 'Pastelarias'),
  Business('Salgados da Praça', 'Onde comer?', 'Salgados e lanches rápidos.', Icons.breakfast_dining_outlined, _green, subcategory: 'Salgados'),
  Business('Hambúrguer da Serra', 'Onde comer?', 'Hambúrgueres, porções e bebidas.', Icons.lunch_dining_outlined, _orange, subcategory: 'Hambúrgueres e lanches'),
  Business('Padaria demonstração', 'Onde comer?', 'Pães, bolos e opções para o café.', Icons.breakfast_dining_outlined, _yellow, subcategory: 'Padarias e confeitarias'),
  Business('Açaí demonstração', 'Onde comer?', 'Açaí, sorvetes e sobremesas.', Icons.icecream_outlined, _green, subcategory: 'Açaí e sorvetes'),
  Business('Japonês demonstração', 'Onde comer?', 'Sabores orientais para experimentar.', Icons.ramen_dining_outlined, _orange, subcategory: 'Comida japonesa'),
  Business('Bar demonstração', 'Onde comer?', 'Petiscos, bebidas e encontros.', Icons.sports_bar_outlined, _yellow, subcategory: 'Bares e petiscos'),
  Business('Marmitas demonstração', 'Onde comer?', 'Refeições práticas para seu dia.', Icons.delivery_dining_outlined, _green, subcategory: 'Marmitas e delivery'),
];
const allBusinesses = [...demoBusinesses, ...foodBusinesses];
const demoJobs = [
  Job('Atendente de loja', 'Comércio', 'Tempo integral', 'HOJE'), Job('Auxiliar administrativo', 'Serviços', 'CLT', 'ONTEM'), Job('Cozinheiro(a)', 'Restaurante', 'CLT', 'HÁ 2 DIAS'),
];
*/
