import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

const sky = Color(0xFF00A9FF);
const ocean = Color(0xFF007ABF);
const ink = Color(0xFF101820);
const orange = Color(0xFFED6A1F);
const yellow = Color(0xFFFAB71D);
const mist = Color(0xFFEAF8FF);
const soft = Color(0xFFF7FBFD);
const muted = Color(0xFF647784);

class RedesignedApp extends StatelessWidget {
  const RedesignedApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Tudo Aqui Macacu',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: soft,
          colorScheme: ColorScheme.fromSeed(seedColor: sky, primary: sky, secondary: orange, surface: Colors.white),
          appBarTheme: const AppBarTheme(backgroundColor: soft, foregroundColor: ink, surfaceTintColor: Colors.transparent),
          filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: sky, foregroundColor: Colors.white, minimumSize: const Size(0, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
        ),
        home: const AuthGate(),
      );
}

const adminEmail = 'bru.mourris69@gmail.com';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final user = snapshot.data;
          return user == null ? const GoogleLoginView() : CityShell(user: user);
        },
      );
}

class GoogleLoginView extends StatefulWidget {
  const GoogleLoginView({super.key});
  @override
  State<GoogleLoginView> createState() => _GoogleLoginViewState();
}

class _GoogleLoginViewState extends State<GoogleLoginView> {
  bool loading = false;
  String? error;
  Future<void> signIn() async {
    setState(() { loading = true; error = null; });
    try {
      final account = await GoogleSignIn().signIn();
      if (account == null) return;
      final auth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      if (mounted) setState(() => error = 'Não foi possível entrar com o Google. Tente novamente.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Brand(), const SizedBox(height: 34),
      const Icon(Icons.account_circle_rounded, color: sky, size: 82), const SizedBox(height: 18),
      Text('Entre para usar o app', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8), const Text('O acesso é feito somente com sua conta Google.', textAlign: TextAlign.center, style: TextStyle(color: muted)),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red))),
      const SizedBox(height: 22), FilledButton.icon(onPressed: loading ? null : signIn, icon: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.login_rounded), label: const Text('Continuar com Google')),
    ]))),
  );
}

class CityShell extends StatefulWidget {
  const CityShell({super.key, required this.user});
  final User user;
  @override
  State<CityShell> createState() => _CityShellState();
}

class _CityShellState extends State<CityShell> {
  int tab = 0;
  final saved = <String>{};
  void favorite(String name) => setState(() => saved.contains(name) ? saved.remove(name) : saved.add(name));
  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.user.email?.toLowerCase() == adminEmail;
    final pages = [HomeView(saved: saved, favorite: favorite, showExplore: () => setState(() => tab = 1)), ExploreView(saved: saved, favorite: favorite), const OffersView(), SavedView(saved: saved, favorite: favorite), ProfileView(count: saved.length, user: widget.user), const ContactView(), if (isAdmin) const AdminView()];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: tab, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        indicatorColor: mist,
        destinations: [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Explorar'),
          NavigationDestination(icon: Icon(Icons.local_offer_outlined), selectedIcon: Icon(Icons.local_offer_rounded), label: 'Ofertas'),
          NavigationDestination(icon: Icon(Icons.favorite_border_rounded), selectedIcon: Icon(Icons.favorite_rounded), label: 'Favoritos'),
          const NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Perfil'),
          const NavigationDestination(icon: Icon(Icons.mail_outline_rounded), selectedIcon: Icon(Icons.mail_rounded), label: 'Contato'),
          if (isAdmin) const NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined), selectedIcon: Icon(Icons.admin_panel_settings_rounded), label: 'Admin'),
        ],
      ),
    );
  }
}

class HomeView extends StatelessWidget {
  const HomeView({super.key, required this.saved, required this.favorite, required this.showExplore});
  final Set<String> saved;
  final ValueChanged<String> favorite;
  final VoidCallback showExplore;
  @override
  Widget build(BuildContext context) => CustomScrollView(slivers: [
        SliverToBoxAdapter(child: WelcomeHero(onSearch: () => showSearch(context: context, delegate: CitySearch()))),
        const SliverToBoxAdapter(child: AdCarousel()),
        SliverToBoxAdapter(child: SectionTitle(title: 'Explore por categoria', action: 'Ver todas', onTap: showExplore)),
        SliverToBoxAdapter(child: SizedBox(height: 117, child: ListView.separated(padding: const EdgeInsets.symmetric(horizontal: 20), scrollDirection: Axis.horizontal, itemCount: homeCatalog.length, separatorBuilder: (_, _) => const SizedBox(width: 10), itemBuilder: (_, i) => CategoryTile(category: homeCatalog[i], onTap: () => openDirectory(context, homeCatalog[i]))))),
        SliverToBoxAdapter(child: SectionTitle(title: 'Destaques em Macacu', action: 'Ver todos', onTap: showExplore)),
        SliverToBoxAdapter(child: SizedBox(height: 230, child: ListView.separated(padding: const EdgeInsets.symmetric(horizontal: 20), scrollDirection: Axis.horizontal, itemCount: featured.length, separatorBuilder: (_, _) => const SizedBox(width: 12), itemBuilder: (_, i) => SizedBox(width: 292, child: BusinessCard(business: featured[i], saved: saved.contains(featured[i].name), onFavorite: () => favorite(featured[i].name), compact: true))))),
        SliverToBoxAdapter(child: SectionTitle(title: 'Ofertas perto de você', action: 'Ver ofertas', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OffersView())))),
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: OfferBanner())),
        SliverToBoxAdapter(child: SectionTitle(title: 'Vagas recentes', action: 'Ver todas as vagas', onTap: () => openFeature(context, Feature.jobs))),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: jobs.take(2).map((job) => Padding(padding: const EdgeInsets.only(bottom: 10), child: JobCard(job: job))).toList()))),
        SliverToBoxAdapter(child: SectionTitle(title: 'O que está acontecendo', action: 'Ver notícias', onTap: () => openFeature(context, Feature.news))),
        SliverToBoxAdapter(child: const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: LocalNewsCard())),
        SliverToBoxAdapter(child: SectionTitle(title: 'Agenda Macacu', action: 'Ver agenda', onTap: () => openFeature(context, Feature.events))),
        SliverToBoxAdapter(child: const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: EventCard())),
        SliverToBoxAdapter(child: SectionTitle(title: 'Explore Macacu', action: 'Conhecer', onTap: () => openFeature(context, Feature.tourism))),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 28), child: NatureBanner(onTap: () => openFeature(context, Feature.tourism)))),
      ]);
}

class WelcomeHero extends StatelessWidget {
  const WelcomeHero({super.key, required this.onSearch});
  final VoidCallback onSearch;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 25),
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFE2F7FF), Color(0xFFF9FCFE)]), borderRadius: BorderRadius.vertical(bottom: Radius.circular(30))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Brand(), Spacer(), CircleIcon(icon: Icons.notifications_none_rounded)]),
          const SizedBox(height: 27),
          const Text('Olá! 👋', style: TextStyle(color: ocean, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('O que você procura\nem Macacu hoje?', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.03, letterSpacing: -1)),
          const SizedBox(height: 18),
          Material(color: Colors.white, borderRadius: BorderRadius.circular(16), child: InkWell(onTap: onSearch, borderRadius: BorderRadius.circular(16), child: const Padding(padding: EdgeInsets.symmetric(horizontal: 15, vertical: 16), child: Row(children: [Icon(Icons.search_rounded, color: ocean), SizedBox(width: 10), Expanded(child: Text('Buscar lojas, serviços, profissionais...', style: TextStyle(color: muted))), Icon(Icons.tune_rounded, color: sky)])))),
        ]),
      );
}

class AdCarousel extends StatefulWidget {
  const AdCarousel({super.key});
  @override State<AdCarousel> createState() => _AdCarouselState();
}

class _AdCarouselState extends State<AdCarousel> {
  final controller = PageController(viewportFraction: .9);
  int page = 0;
  final fallbackAds = const ['Anuncie aqui', 'Destaque sua empresa', 'Oferta da semana', 'Conheça Macacu', 'Comércio local', 'Serviços em destaque', 'Gastronomia', 'Turismo', 'Eventos', 'Sua marca aqui'];
  @override void initState() { super.initState(); Future.doWhile(() async { await Future.delayed(const Duration(seconds: 4)); if (!mounted) return false; final count = controller.positions.isEmpty ? fallbackAds.length : (controller.page == null ? fallbackAds.length : fallbackAds.length); page = (page + 1) % count; controller.animateToPage(page, duration: const Duration(milliseconds: 450), curve: Curves.easeOut); return true; }); }
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('ads').where('published', isEqualTo: true).snapshots(),
    builder: (context, snapshot) {
      final remote = snapshot.data?.docs.map((d) => d.data()).toList() ?? [];
      final ads = remote.isEmpty ? fallbackAds.map((title) => <String, dynamic>{'title': title, 'description': '', 'link': ''}).toList() : remote;
      return SizedBox(
        height: 174,
        child: PageView.builder(
          controller: controller,
          itemCount: ads.length,
          itemBuilder: (_, i) {
            final ad = ads[i];
            final title = (ad['title'] ?? '').toString();
            final description = (ad['description'] ?? '').toString();
            final link = (ad['link'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 4, 0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: link.isEmpty ? null : () => openUrl(context, link, title),
                  borderRadius: BorderRadius.circular(22),
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [ocean, sky]), borderRadius: BorderRadius.circular(22)),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('ESPAÇO PUBLICITÁRIO', style: TextStyle(color: yellow, fontWeight: FontWeight.w800, fontSize: 10)),
                        const Spacer(),
                        Text(title, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(description.isEmpty ? 'Toque para saber mais' : description, style: const TextStyle(color: Color(0xFFDDF4FF))),
                      ]),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
  @override void dispose() { controller.dispose(); super.dispose(); }
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => const Row(mainAxisSize: MainAxisSize.min, children: [DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [sky, ocean]), borderRadius: BorderRadius.all(Radius.circular(12))), child: SizedBox(width: 39, height: 39, child: Icon(Icons.water_rounded, color: Colors.white))), SizedBox(width: 9), Text('Tudo Aqui\nMacacu', style: TextStyle(fontWeight: FontWeight.w800, height: 1.05))]);
}

class CircleIcon extends StatelessWidget {
  const CircleIcon({super.key, required this.icon});
  final IconData icon;
  @override
  Widget build(BuildContext context) => DecoratedBox(decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: SizedBox(width: 40, height: 40, child: Icon(icon, color: ink)));
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, required this.action, required this.onTap});
  final String title;
  final String action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(20, 27, 14, 13), child: Row(children: [Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.5))), TextButton(onPressed: onTap, child: Text('$action  ›'))]));
}

class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.category, required this.onTap, this.grid = false});
  final Category category;
  final VoidCallback onTap;
  final bool grid;
  @override
  Widget build(BuildContext context) => SizedBox(width: grid ? null : 92, child: Material(color: Colors.white, borderRadius: BorderRadius.circular(18), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Padding(padding: const EdgeInsets.all(9), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Sprite(index: category.artwork, size: grid ? 55 : 49), const SizedBox(height: 6), Text(category.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1.1))])))));
}

class Sprite extends StatelessWidget {
  const Sprite({super.key, required this.index, this.size = 56});
  final int index;
  final double size;
  @override
  Widget build(BuildContext context) {
    final col = index % 6;
    final row = index ~/ 6;
    return SizedBox(width: size, height: size, child: ClipRRect(borderRadius: BorderRadius.circular(size * .23), child: OverflowBox(alignment: Alignment.topLeft, minWidth: size * 6, maxWidth: size * 6, minHeight: size * 3, maxHeight: size * 3, child: Transform.translate(offset: Offset(-col * size, -row * size), child: Image.asset('assets/images/category-icons-3d.png', width: size * 6, height: size * 3, fit: BoxFit.fill)))));
  }
}

class BusinessCard extends StatelessWidget {
  const BusinessCard({super.key, required this.business, required this.saved, required this.onFavorite, this.compact = false});
  final Business business;
  final bool saved;
  final VoidCallback onFavorite;
  final bool compact;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BusinessProfile(business: business, saved: saved, onFavorite: onFavorite))),
          child: Padding(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 61, height: 61, decoration: BoxDecoration(color: mist, borderRadius: BorderRadius.circular(17)), child: Center(child: Sprite(index: business.artwork, size: 54))),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [if (business.featured) const MiniLabel(text: 'DESTAQUE', color: orange), const Spacer(), IconButton(visualDensity: VisualDensity.compact, onPressed: onFavorite, icon: Icon(saved ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: saved ? orange : sky))]), Text(business.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), const SizedBox(height: 2), Text(business.subcategory, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted, fontSize: 12))]))
            ]),
            const SizedBox(height: 9),
            Text(business.description, maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 8),
            Row(children: [const Icon(Icons.location_on_outlined, size: 15, color: ocean), const SizedBox(width: 3), Expanded(child: Text(business.location, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted, fontSize: 11))), if (business.open) const MiniLabel(text: 'ABERTO', color: Color(0xFF1E9662))]),
            if (!compact) ...[const SizedBox(height: 12), Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () => openUrl(context, business.whatsapp, 'WhatsApp'), icon: const Icon(Icons.chat_outlined, size: 17), label: const Text('WhatsApp'))), const SizedBox(width: 9), Expanded(child: FilledButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BusinessProfile(business: business, saved: saved, onFavorite: onFavorite))), child: const Text('Ver negócio')))])],
          ])),
        ),
      );
}

class MiniLabel extends StatelessWidget {
  const MiniLabel({super.key, required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => DecoratedBox(decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: .4))));
}

class OfferBanner extends StatelessWidget {
  const OfferBanner({super.key});
  @override
  Widget build(BuildContext context) => DecoratedBox(decoration: BoxDecoration(gradient: const LinearGradient(colors: [ocean, sky]), borderRadius: BorderRadius.circular(22)), child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('OFERTA EM DESTAQUE', style: TextStyle(color: yellow, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)), SizedBox(height: 7), Text('Condições especiais para a cidade.', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, height: 1.05)), SizedBox(height: 7), Text('Confira os detalhes no negócio participante.', style: TextStyle(color: Color(0xFFDDF4FF), fontSize: 12))])), const Sprite(index: 16, size: 72)])));
}

class JobCard extends StatelessWidget {
  const JobCard({super.key, required this.job});
  final Job job;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: () => openFeature(context, Feature.jobs),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(children: [
              Container(width: 47, height: 47, decoration: BoxDecoration(color: mist, borderRadius: BorderRadius.circular(14)), child: const Center(child: Sprite(index: 4, size: 41))),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(job.title, style: const TextStyle(fontWeight: FontWeight.w800)), Text('${job.company} · ${job.type}', style: const TextStyle(color: muted, fontSize: 12)), Text(job.when, style: const TextStyle(color: orange, fontSize: 10, fontWeight: FontWeight.w800))])),
              const Icon(Icons.chevron_right_rounded, color: sky),
            ]),
          ),
        ),
      );
}

class LocalNewsCard extends StatelessWidget {
  const LocalNewsCard({super.key});
  @override
  Widget build(BuildContext context) => Material(color: Colors.white, borderRadius: BorderRadius.circular(20), child: InkWell(onTap: () => openFeature(context, Feature.news), borderRadius: BorderRadius.circular(20), child: const Padding(padding: EdgeInsets.all(14), child: Row(children: [DecoratedBox(decoration: BoxDecoration(color: mist, borderRadius: BorderRadius.all(Radius.circular(16))), child: SizedBox(width: 70, height: 70, child: Center(child: Sprite(index: 6, size: 62)))), SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('NOTÍCIA LOCAL', style: TextStyle(color: orange, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .6)), SizedBox(height: 4), Text('Acontecendo em Macacu', style: TextStyle(fontWeight: FontWeight.w800)), SizedBox(height: 4), Text('Conteúdo com fonte parceira identificada.', style: TextStyle(color: muted, fontSize: 12)), SizedBox(height: 5), Text('Fonte demonstrativa · Hoje', style: TextStyle(color: ocean, fontSize: 11, fontWeight: FontWeight.w700))]))]))));
}

class EventCard extends StatelessWidget {
  const EventCard({super.key});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => openFeature(context, Feature.events),
          borderRadius: BorderRadius.circular(20),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Row(children: [
              DecoratedBox(decoration: BoxDecoration(color: Color(0x33FAB71D), borderRadius: BorderRadius.all(Radius.circular(14))), child: SizedBox(width: 54, height: 54, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('18', style: TextStyle(color: orange, fontSize: 21, fontWeight: FontWeight.w800)), Text('SET', style: TextStyle(color: ink, fontSize: 10, fontWeight: FontWeight.w800))]))),
              SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Evento demonstrativo da cidade', style: TextStyle(fontWeight: FontWeight.w800)), SizedBox(height: 3), Text('Centro · Cachoeiras de Macacu', style: TextStyle(color: muted, fontSize: 12))])),
              Icon(Icons.calendar_month_outlined, color: sky),
            ]),
          ),
        ),
      );
}

class NatureBanner extends StatelessWidget {
  const NatureBanner({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(borderRadius: BorderRadius.circular(23), clipBehavior: Clip.antiAlias, child: InkWell(onTap: onTap, child: SizedBox(height: 190, child: Stack(fit: StackFit.expand, children: [Image.asset('assets/images/macacu-waterfall-hero.png', fit: BoxFit.cover), const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xB3101820), Color(0x00101820)], begin: Alignment.bottomLeft, end: Alignment.topRight))), const Positioned(left: 18, right: 18, bottom: 17, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('EXPLORE MACACU', style: TextStyle(color: yellow, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)), SizedBox(height: 5), Text('Cachoeiras, trilhas e descobertas.', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.05)), SizedBox(height: 5), Text('Conheça nossa cidade no seu ritmo.', style: TextStyle(color: Color(0xFFE1F5FF), fontSize: 12))]))]))));
}

class ExploreView extends StatelessWidget {
  const ExploreView({super.key, required this.saved, required this.favorite});
  final Set<String> saved;
  final ValueChanged<String> favorite;
  @override
  Widget build(BuildContext context) => Scaffold(body: CustomScrollView(slivers: [const SliverAppBar(pinned: true, title: Brand()), SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 4), child: Text('Encontre tudo em um só lugar', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),), const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('Compre de quem é daqui. Escolha uma categoria para começar.', style: TextStyle(color: muted))),), SliverPadding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 26), sliver: SliverGrid(delegate: SliverChildBuilderDelegate((_, i) => CategoryTile(category: catalog[i], grid: true, onTap: () => openDirectory(context, catalog[i])), childCount: catalog.length), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: .92, crossAxisSpacing: 10, mainAxisSpacing: 10))), SliverToBoxAdapter(child: SectionTitle(title: 'Negócios em destaque', action: 'Ver todos', onTap: () {})), SliverPadding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 30), sliver: SliverList(delegate: SliverChildBuilderDelegate((_, i) => Padding(padding: const EdgeInsets.only(bottom: 12), child: BusinessCard(business: featured[i], saved: saved.contains(featured[i].name), onFavorite: () => favorite(featured[i].name))), childCount: featured.length)))]));
}

void openDirectory(BuildContext context, Category category) {
  if (category.name == 'Serviços úteis') {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PublicServicesView()));
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => DirectoryView(category: category)));
}

class DirectoryView extends StatefulWidget {
  const DirectoryView({super.key, required this.category});
  final Category category;
  @override
  State<DirectoryView> createState() => _DirectoryViewState();
}

class _DirectoryViewState extends State<DirectoryView> {
  String type = 'Todos';
  final localSaved = <String>{};
  @override
  Widget build(BuildContext context) {
    final inCategory = businesses.where((item) => item.category == widget.category.name).toList();
    final visible = type == 'Todos' ? inCategory : inCategory.where((item) => item.subcategory == type).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 5, 20, 30),
        children: [
          Row(
            children: [
              Sprite(index: widget.category.artwork, size: 68),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.category.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    const Text('Escolha um tipo para encontrar o que precisa.', style: TextStyle(color: muted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(spacing: 8, runSpacing: 8, children: ['Todos', ...widget.category.types].map((item) => ChoiceChip(label: Text(item), selected: type == item, onSelected: (_) => setState(() => type = item))).toList()),
          const SizedBox(height: 18),
          Text('${visible.length} resultados', style: const TextStyle(color: orange, fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (visible.isEmpty)
            const EmptyDirectory()
          else
            ...visible.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: BusinessCard(
                  business: item,
                  saved: localSaved.contains(item.name),
                  onFavorite: () => setState(
                    () => localSaved.contains(item.name)
                        ? localSaved.remove(item.name)
                        : localSaved.add(item.name),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          const Text('Dados demonstrativos. Você cadastra e aprova cada negócio antes de ele aparecer para o público.', textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 11)),
        ],
      ),
    );
  }
}

class EmptyDirectory extends StatelessWidget {
  const EmptyDirectory({super.key});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: mist, borderRadius: BorderRadius.circular(20)), child: const Column(children: [Icon(Icons.storefront_outlined, color: sky, size: 38), SizedBox(height: 10), Text('Em breve, novos estabelecimentos aparecerão aqui.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800)), SizedBox(height: 5), Text('Você decide o que entra na vitrine.', textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12))]));
}

class PublicServicesView extends StatefulWidget {
  const PublicServicesView({super.key});

  @override
  State<PublicServicesView> createState() => _PublicServicesViewState();
}

class _PublicServicesViewState extends State<PublicServicesView> {
  bool payments = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Serviços úteis')),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 6, 20, 30), children: [
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [ocean, sky]), borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              const Sprite(index: 17, size: 66),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(payments ? 'Contas essenciais' : 'Serviços públicos', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)), const SizedBox(height: 5), Text(payments ? 'Acesse os canais oficiais para consultar ou pagar.' : 'Informações rápidas que ajudam no dia a dia.', style: const TextStyle(color: Color(0xFFDDF4FF), fontSize: 12))])),
            ]),
          ),
          const SizedBox(height: 18),
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, icon: Icon(Icons.public_outlined), label: Text('Utilidades')), ButtonSegment(value: true, icon: Icon(Icons.receipt_long_outlined), label: Text('Pagar contas'))],
            selected: {payments},
            onSelectionChanged: (value) => setState(() => payments = value.first),
          ),
          const SizedBox(height: 20),
          if (payments) ...const [_SafetyNotice(), SizedBox(height: 13)],
          if (payments) ...[
            BillTile(icon: Icons.bolt_rounded, title: 'Energia elétrica', subtitle: 'Consultar fatura ou acessar pagamento oficial.', color: yellow),
            BillTile(icon: Icons.water_drop_rounded, title: 'Água', subtitle: 'Consultar consumo, segunda via ou pagamento oficial.', color: sky),
            BillTile(icon: Icons.wifi_rounded, title: 'Internet', subtitle: 'Acessar o canal oficial do seu provedor.', color: orange),
          ] else ...[
            const UtilityTile(icon: Icons.local_hospital_outlined, title: 'Saúde e emergências', subtitle: 'Contatos e orientações publicadas pelo administrador.'),
            const UtilityTile(icon: Icons.account_balance_outlined, title: 'Prefeitura e serviços municipais', subtitle: 'Links e informações oficiais da cidade.'),
            const UtilityTile(icon: Icons.warning_amber_rounded, title: 'Defesa Civil', subtitle: 'Avisos importantes e canais de atendimento.'),
            const UtilityTile(icon: Icons.directions_bus_outlined, title: 'Transporte e mobilidade', subtitle: 'Informações úteis para circular pela cidade.'),
          ],
          const SizedBox(height: 12),
          const Text('Os links e contatos desta área são inseridos e revisados exclusivamente pelo administrador.', textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 11)),
        ]),
      );
}

class _SafetyNotice extends StatelessWidget {
  const _SafetyNotice();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: mist, borderRadius: BorderRadius.circular(17)),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.verified_user_outlined, color: ocean), SizedBox(width: 10), Expanded(child: Text('Para sua segurança, o Tudo Aqui Macacu apenas direciona você ao canal oficial. Nenhum dado de cartão, senha ou pagamento é coletado no aplicativo.', style: TextStyle(color: muted, fontSize: 12, height: 1.35)))]),
      );
}

class BillTile extends StatelessWidget {
  const BillTile({super.key, required this.icon, required this.title, required this.subtitle, required this.color});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(width: 52, height: 52, decoration: BoxDecoration(color: color.withValues(alpha: .18), borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: color == yellow ? orange : color)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: muted, fontSize: 12, height: 1.25))])),
              IconButton(onPressed: () => openUrl(context, '', 'canal de $title'), icon: const Icon(Icons.open_in_new_rounded, color: sky), tooltip: 'Acessar canal oficial'),
            ]),
          ),
        ),
      );
}

class UtilityTile extends StatelessWidget {
  const UtilityTile({super.key, required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Material(color: Colors.white, borderRadius: BorderRadius.circular(20), child: ListTile(leading: Container(width: 47, height: 47, decoration: BoxDecoration(color: mist, borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: ocean)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right_rounded, color: sky))),
      );
}

class BusinessProfile extends StatelessWidget {
  const BusinessProfile({super.key, required this.business, required this.saved, required this.onFavorite});
  final Business business;
  final bool saved;
  final VoidCallback onFavorite;
  @override
  Widget build(BuildContext context) => Scaffold(body: CustomScrollView(slivers: [SliverAppBar(expandedHeight: 220, pinned: true, actions: [IconButton(onPressed: onFavorite, icon: Icon(saved ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: saved ? orange : Colors.white))], flexibleSpace: FlexibleSpaceBar(background: Stack(fit: StackFit.expand, children: [if (business.category == 'Turismo') Image.asset('assets/images/macacu-waterfall-hero.png', fit: BoxFit.cover) else Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [ocean, sky]))), Positioned(right: 25, bottom: 23, child: Sprite(index: business.artwork, size: 143)), const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0x66101820), Color(0x00101820)], begin: Alignment.topCenter, end: Alignment.center)))]))), SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 30), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Transform.translate(offset: const Offset(0, -35), child: Container(width: 76, height: 76, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: const [BoxShadow(color: Color(0x22101820), blurRadius: 16, offset: Offset(0, 7))]), child: Center(child: Sprite(index: business.artwork, size: 67)))), Transform.translate(offset: const Offset(0, -18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(business.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text('${business.category} · ${business.subcategory}', style: const TextStyle(color: ocean, fontWeight: FontWeight.w700, fontSize: 12)), const SizedBox(height: 7), Row(children: [const Icon(Icons.location_on_outlined, size: 16, color: muted), const SizedBox(width: 3), Expanded(child: Text(business.location, style: const TextStyle(color: muted, fontSize: 12))), if (business.open) const MiniLabel(text: 'ABERTO AGORA', color: Color(0xFF1E9662))])])), Wrap(spacing: 8, runSpacing: 8, children: [FilledButton.icon(onPressed: () => openUrl(context, business.whatsapp, 'WhatsApp'), icon: const Icon(Icons.chat_outlined), label: const Text('WhatsApp')), OutlinedButton.icon(onPressed: () => openUrl(context, business.phone, 'Ligação'), icon: const Icon(Icons.call_outlined), label: const Text('Ligar')), OutlinedButton.icon(onPressed: () => openUrl(context, business.instagram, 'Instagram'), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Instagram')), OutlinedButton.icon(onPressed: () => openUrl(context, business.maps, 'Google Maps'), icon: const Icon(Icons.directions_outlined), label: const Text('Como chegar'))]), const SizedBox(height: 24), const InfoBlock(title: 'Sobre', text: 'Esta é uma vitrine demonstrativa. No lançamento, você adicionará a apresentação, os contatos e as informações revisadas de cada estabelecimento.'), const InfoBlock(title: 'Produtos e serviços', text: 'Itens, serviços e diferenciais podem ser organizados aqui para facilitar a escolha do público.'), const InfoBlock(title: 'Fotos e promoções', text: 'As fotos e promoções aprovadas por você ficam reunidas nesta área.'), const InfoBlock(title: 'Horários e contato', text: 'O administrador atualiza horários, endereço, redes sociais e todos os canais externos.')])))]));
}

class InfoBlock extends StatelessWidget {
  const InfoBlock({super.key, required this.title, required this.text});
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 19), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)), const SizedBox(height: 6), Text(text, style: const TextStyle(color: muted, height: 1.45))]));
}

class OffersView extends StatelessWidget {
  const OffersView({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            const Brand(),
            const SizedBox(height: 25),
            Text('Ofertas perto de você', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            const Text('Promoções escolhidas para movimentar o comércio local.', style: TextStyle(color: muted)),
            const SizedBox(height: 20),
            ...['Oferta especial da semana', 'Condição para clientes locais', 'Experiência em destaque'].map(
              (text) => Padding(
                padding: const EdgeInsets.only(bottom: 13),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(color: mist, borderRadius: BorderRadius.circular(18)),
                          child: const Center(child: Sprite(index: 16, size: 61)),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const MiniLabel(text: 'OFERTA', color: orange),
                              const SizedBox(height: 6),
                              Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 3),
                              const Text('Negócio demonstrativo', style: TextStyle(color: muted, fontSize: 12)),
                              const SizedBox(height: 5),
                              const Text('Confira os detalhes pelo WhatsApp', style: TextStyle(color: ocean, fontWeight: FontWeight.w700, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class SavedView extends StatelessWidget {
  const SavedView({super.key, required this.saved, required this.favorite});
  final Set<String> saved;
  final ValueChanged<String> favorite;
  @override
  Widget build(BuildContext context) { final items = businesses.where((item) => saved.contains(item.name)).toList(); return Scaffold(body: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 28), children: [const Brand(), const SizedBox(height: 25), Text('Seus favoritos', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 5), const Text('Guarde os negócios que quer consultar depois.', style: TextStyle(color: muted)), const SizedBox(height: 20), if (items.isEmpty) const EmptyDirectory() else ...items.map((item) => Padding(padding: const EdgeInsets.only(bottom: 12), child: BusinessCard(business: item, saved: true, onFavorite: () => favorite(item.name))))])); }
}

class ContactView extends StatefulWidget {
  const ContactView({super.key});
  @override State<ContactView> createState() => _ContactViewState();
}
class _ContactViewState extends State<ContactView> {
  final name = TextEditingController(); final contact = TextEditingController(); final message = TextEditingController(); bool sending = false;
  @override void dispose() { name.dispose(); contact.dispose(); message.dispose(); super.dispose(); }
  Future<void> send() async {
    if (message.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      await FirebaseFirestore.instance.collection('contact_messages').add({'name': name.text.trim(), 'contact': contact.text.trim(), 'message': message.text.trim(), 'email': user.email, 'createdAt': FieldValue.serverTimestamp(), 'read': false});
      name.clear(); contact.clear(); message.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mensagem enviada. Obrigado pelo contato!')));
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível enviar agora. Tente novamente.'))); }
    if (mounted) setState(() => sending = false);
  }
  @override Widget build(BuildContext context) => Scaffold(body: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 28), children: [const Brand(), const SizedBox(height: 26), Text('Fale com a gente', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 6), const Text('Envie sugestões, dúvidas ou solicite a divulgação do seu negócio.', style: TextStyle(color: muted)), const SizedBox(height: 24), TextField(controller: name, decoration: const InputDecoration(labelText: 'Seu nome', border: OutlineInputBorder())), const SizedBox(height: 12), TextField(controller: contact, decoration: const InputDecoration(labelText: 'Seu contato', border: OutlineInputBorder())), const SizedBox(height: 12), TextField(controller: message, maxLines: 5, decoration: const InputDecoration(labelText: 'Mensagem', alignLabelWithHint: true, border: OutlineInputBorder())), const SizedBox(height: 16), FilledButton.icon(onPressed: sending ? null : send, icon: const Icon(Icons.send_rounded), label: Text(sending ? 'Enviando...' : 'Enviar mensagem'))]));
}

class ProfileView extends StatelessWidget {
  const ProfileView({super.key, required this.count, required this.user});
  final int count;
  final User user;
  @override
  Widget build(BuildContext context) => Scaffold(body: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 28), children: [const Brand(), const SizedBox(height: 27), Row(children: [CircleAvatar(radius: 31, backgroundColor: yellow, backgroundImage: user.photoURL == null ? null : NetworkImage(user.photoURL!), child: user.photoURL == null ? const Icon(Icons.person_outline_rounded, color: ink, size: 31) : null), const SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(user.displayName ?? 'Sua área', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)), Text(user.email ?? 'Preferências e itens salvos', style: const TextStyle(color: muted))]))]), const SizedBox(height: 26), MenuRow(icon: Icons.favorite_outline_rounded, title: 'Itens salvos', text: '$count favorito(s) neste aparelho'), const MenuRow(icon: Icons.notifications_none_rounded, title: 'Notificações', text: 'Ofertas, vagas e novidades de Macacu'), const MenuRow(icon: Icons.location_on_outlined, title: 'Localização', text: 'Encontre opções perto de você'), MenuRow(icon: Icons.logout_rounded, title: 'Sair da conta', text: 'Entrar com outra conta Google', onTap: () => FirebaseAuth.instance.signOut()), const SizedBox(height: 24), Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: mist, borderRadius: BorderRadius.circular(20)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Feito para quem vive Macacu', style: TextStyle(fontWeight: FontWeight.w800)), SizedBox(height: 5), Text('Informações publicadas e revisadas pelo administrador do aplicativo.', style: TextStyle(color: muted, fontSize: 12))]))]));
}

class MenuRow extends StatelessWidget {
  const MenuRow({super.key, required this.icon, required this.title, required this.text, this.onTap});
  final IconData icon;
  final String title;
  final String text;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Material(color: Colors.white, borderRadius: BorderRadius.circular(18), child: ListTile(onTap: onTap, leading: Icon(icon, color: ocean), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(text), trailing: const Icon(Icons.chevron_right_rounded, color: sky))));
}

class AdminView extends StatelessWidget {
  const AdminView({super.key});
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Administração')), body: ListView(padding: const EdgeInsets.all(20), children: [Text('Gerenciar conteúdo', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 6), const Text('Tudo o que for publicado aqui fica disponível para os usuários conectados.', style: TextStyle(color: muted)), const SizedBox(height: 22), ...const [('establishments', 'Estabelecimentos', Icons.storefront_outlined), ('ads', 'Anúncios do carrossel', Icons.campaign_outlined), ('offers', 'Ofertas', Icons.local_offer_outlined), ('jobs', 'Vagas', Icons.work_outline_rounded), ('news', 'Notícias', Icons.newspaper_rounded), ('events', 'Eventos', Icons.event_note_outlined), ('links', 'Links e botões', Icons.link_rounded)].map((item) => Padding(padding: const EdgeInsets.only(bottom: 10), child: ListTile(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ContentManager(collection: item.$1, title: item.$2))), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), tileColor: Colors.white, leading: Icon(item.$3, color: ocean), title: Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w800)), trailing: const Icon(Icons.chevron_right_rounded, color: sky)))), ListTile(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactInbox())), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), tileColor: mist, leading: const Icon(Icons.mail_rounded, color: ocean), title: const Text('Mensagens recebidas', style: TextStyle(fontWeight: FontWeight.w800)), trailing: const Icon(Icons.chevron_right_rounded, color: sky))]));
}

class ContentManager extends StatelessWidget { const ContentManager({super.key, required this.collection, required this.title}); final String collection, title;
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), floatingActionButton: FloatingActionButton.extended(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ContentEditor(collection: collection))), icon: const Icon(Icons.add_rounded), label: const Text('Adicionar')), body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection(collection).orderBy('updatedAt', descending: true).snapshots(), builder: (context, snap) { if (snap.hasError) return const Center(child: Text('Não foi possível carregar os itens.')); if (!snap.hasData) return const Center(child: CircularProgressIndicator()); final docs = snap.data!.docs; if (docs.isEmpty) return const Center(child: Text('Ainda não há itens. Use Adicionar para publicar.')); return ListView.separated(padding: const EdgeInsets.all(16), itemCount: docs.length, separatorBuilder: (_, _) => const SizedBox(height: 8), itemBuilder: (_, i) { final d = docs[i]; final data = d.data(); return ListTile(tileColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), title: Text((data['title'] ?? data['name'] ?? 'Sem título').toString(), style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(data['published'] == false ? 'Rascunho' : 'Publicado'), trailing: const Icon(Icons.edit_rounded), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ContentEditor(collection: collection, doc: d)))); }); })); }

class ContentEditor extends StatefulWidget { const ContentEditor({super.key, required this.collection, this.doc}); final String collection; final DocumentSnapshot<Map<String, dynamic>>? doc; @override State<ContentEditor> createState() => _ContentEditorState(); }
class _ContentEditorState extends State<ContentEditor> { late final TextEditingController title; late final TextEditingController description; late final TextEditingController link; bool published = true; bool saving = false;
  @override void initState() { super.initState(); final d = widget.doc?.data() ?? {}; title = TextEditingController(text: (d['title'] ?? d['name'] ?? '').toString()); description = TextEditingController(text: (d['description'] ?? '').toString()); link = TextEditingController(text: (d['link'] ?? d['url'] ?? '').toString()); published = d['published'] as bool? ?? true; }
  @override void dispose() { title.dispose(); description.dispose(); link.dispose(); super.dispose(); }
  Future<void> save() async { if (title.text.trim().isEmpty) return; setState(() => saving = true); final data = {'title': title.text.trim(), 'description': description.text.trim(), 'link': link.text.trim(), 'published': published, 'updatedAt': FieldValue.serverTimestamp()}; if (widget.doc == null) { await FirebaseFirestore.instance.collection(widget.collection).add(data); } else { await widget.doc!.reference.set(data, SetOptions(merge: true)); } if (mounted) Navigator.pop(context); }
  Future<void> remove() async { await widget.doc?.reference.delete(); if (mounted) Navigator.pop(context); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.doc == null ? 'Adicionar' : 'Editar')), body: ListView(padding: const EdgeInsets.all(20), children: [TextField(controller: title, decoration: const InputDecoration(labelText: 'Título ou nome', border: OutlineInputBorder())), const SizedBox(height: 14), TextField(controller: description, maxLines: 5, decoration: const InputDecoration(labelText: 'Descrição', border: OutlineInputBorder())), const SizedBox(height: 14), TextField(controller: link, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Link do botão (opcional)', border: OutlineInputBorder())), SwitchListTile(value: published, onChanged: (v) => setState(() => published = v), title: const Text('Publicado'), subtitle: const Text('Desative para manter como rascunho'), contentPadding: EdgeInsets.zero), const SizedBox(height: 10), FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'Salvando...' : 'Salvar alterações')), if (widget.doc != null) TextButton.icon(onPressed: remove, icon: const Icon(Icons.delete_outline, color: Colors.red), label: const Text('Excluir item', style: TextStyle(color: Colors.red))) ])); }

class ContactInbox extends StatelessWidget { const ContactInbox({super.key}); @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Mensagens recebidas')), body: StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream: FirebaseFirestore.instance.collection('contact_messages').orderBy('createdAt', descending:true).snapshots(), builder: (context,s) { if (!s.hasData) return const Center(child:CircularProgressIndicator()); final docs=s.data!.docs; if(docs.isEmpty) return const Center(child:Text('Nenhuma mensagem ainda.')); return ListView.builder(itemCount:docs.length,itemBuilder:(_,i){final d=docs[i].data(); return ListTile(title:Text((d['name']??'Visitante').toString()),subtitle:Text('${d['message']??''}\n${d['contact']??d['email']??''}'),isThreeLine:true);}); })); }

enum Feature { jobs, news, events, tourism }
void openFeature(BuildContext context, Feature feature) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FeatureView(feature: feature)));

class FeatureView extends StatelessWidget {
  const FeatureView({super.key, required this.feature});
  final Feature feature;
  @override
  Widget build(BuildContext context) {
    final tourism = feature == Feature.tourism;
    final title = tourism ? 'Explore Macacu' : feature == Feature.jobs ? 'Vagas em Macacu' : feature == Feature.news ? 'Notícias de Macacu' : 'Agenda Macacu';
    final sprite = tourism ? 5 : feature == Feature.jobs ? 4 : feature == Feature.news ? 6 : 7;
    final subtitle = tourism ? 'Natureza, sabores e experiências para montar o seu roteiro.' : feature == Feature.jobs ? 'Oportunidades locais publicadas e revisadas para a cidade.' : feature == Feature.news ? 'Conteúdos locais sempre com a fonte responsável identificada.' : 'Eventos e encontros que movimentam a cidade.';
    return Scaffold(appBar: AppBar(title: Text(title)), body: ListView(padding: const EdgeInsets.fromLTRB(20, 6, 20, 28), children: [if (tourism) NatureBanner(onTap: () {}), if (tourism) const SizedBox(height: 22), Row(children: [Sprite(index: sprite, size: 68), const SizedBox(width: 12), Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)))]), const SizedBox(height: 6), Text(subtitle, style: const TextStyle(color: muted)), const SizedBox(height: 18), if (feature == Feature.jobs) ...jobs.map((job) => Padding(padding: const EdgeInsets.only(bottom: 12), child: JobCard(job: job))) else ...List.generate(3, (i) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Material(color: Colors.white, borderRadius: BorderRadius.circular(20), child: Padding(padding: const EdgeInsets.all(15), child: Row(children: [Sprite(index: sprite, size: 58), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tourism ? 'Experiência demonstrativa' : feature == Feature.news ? 'Conteúdo demonstrativo local' : 'Evento demonstrativo', style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text('Informações que você aprovará antes de publicar no aplicativo.', style: const TextStyle(color: muted, fontSize: 12)), const SizedBox(height: 6), Text(tourism ? 'Ver roteiro' : feature == Feature.news ? 'Fonte demonstrativa · Hoje' : 'Centro · Macacu', style: const TextStyle(color: ocean, fontWeight: FontWeight.w700, fontSize: 11))]))]))))) ]));
  }
}

class CitySearch extends SearchDelegate<void> {
  @override List<Widget>? buildActions(BuildContext context) => [IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear_rounded))];
  @override Widget? buildLeading(BuildContext context) => IconButton(onPressed: () => close(context, null), icon: const Icon(Icons.arrow_back_rounded));
  @override Widget buildResults(BuildContext context) => results();
  @override Widget buildSuggestions(BuildContext context) => results();
  Widget results() { final found = businesses.where((b) => query.isEmpty || b.name.toLowerCase().contains(query.toLowerCase()) || b.subcategory.toLowerCase().contains(query.toLowerCase())).toList(); return ListView(padding: const EdgeInsets.all(20), children: [if (query.isEmpty) const Text('Busque comércios, serviços, profissionais e turismo.', style: TextStyle(color: muted)), const SizedBox(height: 12), if (found.isEmpty) const EmptyDirectory() else ...found.map((b) => Padding(padding: const EdgeInsets.only(bottom: 12), child: BusinessCard(business: b, saved: false, onFavorite: () {})))]); }
}

Future<void> openUrl(BuildContext context, String url, String label) async { final target = Uri.tryParse(url); if (target == null || url.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label será disponibilizado quando você cadastrar o estabelecimento.'))); return; } if (!await launchUrl(target, mode: LaunchMode.externalApplication) && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível abrir $label.'))); }

class Category { const Category(this.name, this.artwork, this.types); final String name; final int artwork; final List<String> types; }
class Business { const Business(this.name, this.category, this.subcategory, this.description, this.location, this.artwork, {this.featured = false, this.open = true, this.whatsapp = '', this.phone = '', this.instagram = '', this.maps = ''}); final String name, category, subcategory, description, location, whatsapp, phone, instagram, maps; final int artwork; final bool featured, open; }
class Job { const Job(this.title, this.company, this.area, this.type, this.when); final String title, company, area, type, when; }

const catalog = [
  Category('Comércio', 0, ['Moda e acessórios', 'Calçados', 'Infantil', 'Casa e decoração', 'Eletrônicos', 'Presentes', 'Papelaria']),
  Category('Onde comer?', 1, ['Restaurantes', 'Pizzarias', 'Hambúrgueres e lanches', 'Pastelarias', 'Salgados', 'Padarias e confeitarias', 'Cafés e docerias', 'Açaí e sorvetes', 'Comida japonesa', 'Bares e petiscos', 'Marmitas e delivery']),
  Category('Serviços', 2, ['Construção e reformas', 'Eletricista', 'Encanador', 'Informática', 'Fotografia', 'Contabilidade', 'Limpeza']),
  Category('Profissionais', 3, ['Autônomos', 'Manutenção', 'Consultoria', 'Cuidados pessoais']),
  Category('Empregos', 4, ['Comércio', 'Serviços', 'Gastronomia', 'Administrativo']),
  Category('Turismo', 5, ['Cachoeiras', 'Trilhas', 'Pontos turísticos', 'Guias e passeios', 'Artesanato local']),
  Category('Notícias', 6, ['Cidade', 'Comunidade', 'Cultura', 'Esporte']), Category('Eventos', 7, ['Shows', 'Feiras', 'Cultura', 'Família']),
  Category('Saúde', 8, ['Farmácias', 'Clínicas', 'Dentistas', 'Laboratórios', 'Psicologia']), Category('Imóveis', 9, ['Aluguel', 'Compra e venda', 'Temporada']),
  Category('Veículos', 10, ['Oficinas', 'Autopeças', 'Pneus', 'Lava jatos', 'Motos']), Category('Pets', 11, ['Pet shops', 'Veterinários', 'Banho e tosa']),
  Category('Beleza', 12, ['Cabeleireiros e salões', 'Barbearias', 'Manicure e unhas', 'Estética']), Category('Academias', 13, ['Academias', 'Personal trainer', 'Pilates']),
  Category('Educação', 14, ['Escolas', 'Cursos', 'Reforço escolar']), Category('Hospedagem', 15, ['Hotéis e pousadas', 'Sítios e chalés', 'Camping']),
  Category('Promoções', 16, ['Ofertas do dia', 'Cupons', 'Lançamentos']), Category('Serviços úteis', 17, ['Contas essenciais', 'Utilidade pública', 'Emergências', 'Informações locais']),
];

final homeCatalog = [...catalog.take(8), catalog.last];

const businesses = [
  Business('Café da Serra', 'Onde comer?', 'Cafés e docerias', 'Sabores acolhedores no coração da cidade.', 'Centro · Cachoeiras de Macacu', 1, featured: true),
  Business('Pizzaria Sabor Local', 'Onde comer?', 'Pizzarias', 'Pizzas artesanais para pedir ou retirar.', 'Centro · Cachoeiras de Macacu', 1, featured: true),
  Business('Hambúrguer da Serra', 'Onde comer?', 'Hambúrgueres e lanches', 'Lanches, porções e bebidas.', 'Centro · Cachoeiras de Macacu', 1),
  Business('Pastel do Vale', 'Onde comer?', 'Pastelarias', 'Pastéis preparados na hora.', 'Centro · Cachoeiras de Macacu', 1),
  Business('Loja demonstração', 'Comércio', 'Moda e acessórios', 'Moda, presentes e opções para a cidade.', 'Centro · Cachoeiras de Macacu', 0, featured: true),
  Business('Estúdio Raiz', 'Beleza', 'Cabeleireiros e salões', 'Cuidado, beleza e autoestima para você.', 'Centro · Cachoeiras de Macacu', 12, featured: true),
  Business('Auto Centro demonstração', 'Veículos', 'Oficinas', 'Cuidados para carro e moto.', 'Bairro demonstração · Macacu', 10),
  Business('Clínica demonstração', 'Saúde', 'Clínicas', 'Atendimento e cuidado para a comunidade.', 'Centro · Cachoeiras de Macacu', 8),
  Business('Pousada demonstração', 'Hospedagem', 'Hotéis e pousadas', 'Uma estadia para descobrir Macacu.', 'Região turística · Macacu', 15),
  Business('Serviços demonstração', 'Serviços', 'Construção e reformas', 'Profissionais para o que você precisar.', 'Atende Cachoeiras de Macacu', 2),
  Business('João demonstração', 'Profissionais', 'Manutenção', 'Profissional local para serviços do dia a dia.', 'Atende Cachoeiras de Macacu', 3),
  Business('Roteiro demonstração', 'Turismo', 'Cachoeiras', 'Experiências e paisagens para conhecer.', 'Cachoeiras de Macacu', 5),
];
final featured = businesses.where((item) => item.featured).toList();
const jobs = [Job('Auxiliar administrativo', 'Empresa demonstração', 'Serviços', 'CLT', 'HOJE'), Job('Atendente de loja', 'Comércio demonstração', 'Comércio', 'Tempo integral', 'HOJE'), Job('Cozinheiro(a)', 'Gastronomia demonstração', 'Gastronomia', 'CLT', 'HÁ 2 DIAS')];
