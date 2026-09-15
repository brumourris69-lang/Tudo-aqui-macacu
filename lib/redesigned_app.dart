
import 'dart:async';

import 'admin_audit.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

const sky = Color(0xFF007BFF);
const ocean = Color(0xFF0056D6);
const ink = Color(0xFF082B4C);
const orange = Color(0xFFFF7A00);
const yellow = Color(0xFFFF9A18);
const mist = Color(0xFFF1F5F9);
const soft = Color(0xFFF8FAFC);
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
          textTheme: GoogleFonts.poppinsTextTheme(),
          appBarTheme: const AppBarTheme(backgroundColor: soft, foregroundColor: ink, surfaceTintColor: Colors.transparent),
          filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: sky, foregroundColor: Colors.white, minimumSize: const Size(0, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
        ),
        home: const AuthGate(),
      );
}

const adminEmail = 'bru.mourris69@gmail.com';
const googleWebClientId = '801555679675-qvtghgv9sa65ipgls4usukru33uk3aec.apps.googleusercontent.com';

bool isAdminUser(User? user) => user?.email?.toLowerCase() == adminEmail;

Future<void> syncUserProfile(User user) async {
  try {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'displayName': user.displayName ?? '',
      'email': user.email ?? '',
      'photoUrl': user.photoURL ?? '',
      'role': isAdminUser(user) ? 'admin' : 'user',
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } on FirebaseException catch (error) {
    debugPrint('Perfil Firebase não sincronizado: ${error.code}');
  }
}

Future<void> recordMetric(String action, {String? target}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    await FirebaseFirestore.instance.collection('metrics').add({
      'action': action,
      'target': target ?? '',
      'userId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  } on FirebaseException catch (error) {
    debugPrint('Métrica não registrada: ${error.code}');
  }
}

bool isActiveContent(Map<String, dynamic> data) {
  final expiresAt = data['expiresAt'];
  if (expiresAt is! Timestamp) return true;
  return expiresAt.toDate().isAfter(DateTime.now());
}

class PushService {
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<String>? _tokenSubscription;

  static Future<void> activate(User user, BuildContext context) async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await messaging.getToken();
    if (token != null) await _saveToken(user.uid, token);
    await _tokenSubscription?.cancel();
    _tokenSubscription = messaging.onTokenRefresh.listen((token) => _saveToken(user.uid, token));
    await _foregroundSubscription?.cancel();
    _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${notification.title ?? 'Tudo Aqui Macacu'}: ${notification.body ?? ''}')));
      }
    });
  }

  static Future<void> _saveToken(String uid, String token) => FirebaseFirestore.instance.collection('users').doc(uid).collection('devices').doc(token).set({'token': token, 'updatedAt': FieldValue.serverTimestamp()});
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return CityShell(user: snapshot.data);
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
      debugPrint('Google login: abrindo seletor de conta');
      final account = await GoogleSignIn(serverClientId: googleWebClientId).signIn();
      if (account == null) { debugPrint('Google login: cancelado pelo usuário'); return; }
      final auth = await account.authentication;
      if (auth.idToken == null) throw StateError('Google não retornou o ID token');
      debugPrint('Google login: credencial recebida, iniciando sessão Firebase');
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      final result = await FirebaseAuth.instance.signInWithCredential(credential);
      debugPrint('Google login: sessão criada para ${result.user?.uid}');
      if (result.user != null) await syncUserProfile(result.user!);
    } on FirebaseAuthException catch (e) {
      debugPrint('Google login FirebaseAuthException: ${e.code} - ${e.message}');
      if (mounted) {
        setState(() => error = e.code == 'account-exists-with-different-credential'
            ? 'Esta conta já usa outra forma de acesso. Tente novamente com a mesma conta Google.'
            : 'Não foi possível concluir o login agora. Tente novamente.');
      }
    } catch (e) {
      debugPrint('Google login falhou: $e');
      final details = e.toString();
      if (mounted) {
        setState(() => error = details.contains('ApiException: 10') || details.contains('DEVELOPER_ERROR')
            ? 'Este APK ainda não foi reconhecido pelo Google. Instale a versão mais nova e tente novamente.'
            : 'Não foi possível entrar com o Google. Verifique sua conexão e tente novamente.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Brand(), const SizedBox(height: 34),
      const Icon(Icons.account_circle_rounded, color: sky, size: 82), const SizedBox(height: 18),
      Text('Personalize sua experiência', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8), const Text('Você pode explorar Macacu sem conta. Entre para salvar favoritos e receber novidades.', textAlign: TextAlign.center, style: TextStyle(color: muted)),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red))),
      const SizedBox(height: 22), App3DButton(onPressed: loading ? null : signIn, icon: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.login_rounded), label: 'Continuar com Google'),
    ]))),
  );
}

class CityShell extends StatefulWidget {
  const CityShell({super.key, required this.user});
  final User? user;
  @override
  State<CityShell> createState() => _CityShellState();
}

class _CityShellState extends State<CityShell> {
  int tab = 0;
  final saved = <String>{};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? favoritesSubscription;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    if (user != null) {
      unawaited(syncUserProfile(user));
      unawaited(PushService.activate(user, context));
      favoritesSubscription = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('favorites').snapshots().listen(
        (snapshot) {
          if (!mounted) return;
          setState(() { saved..clear()..addAll(snapshot.docs.map((doc) => (doc.data()['name'] ?? doc.id).toString())); });
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Favoritos Firebase indisponíveis: $error');
        },
      );
    }
  }

  void favorite(String name) {
    final user = widget.user;
    if (user == null) {
      setState(() => saved.contains(name) ? saved.remove(name) : saved.add(name));
      return;
    }
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('favorites').doc(name);
    if (saved.contains(name)) {
      unawaited(ref.delete().then((_) => recordMetric('favorite_remove', target: name)).catchError((_) => _showFavoriteError()));
    } else {
      unawaited(ref.set({'name': name, 'updatedAt': FieldValue.serverTimestamp()}).then((_) => recordMetric('favorite_add', target: name)).catchError((_) => _showFavoriteError()));
    }
  }

  void _showFavoriteError() {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível salvar agora. Tente novamente em instantes.')));
  }

  @override
  void dispose() {
    favoritesSubscription?.cancel();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final pages = [HomeView(saved: saved, favorite: favorite, showExplore: () => setState(() => tab = 1), user: widget.user), ExploreView(saved: saved, favorite: favorite), const OffersView(), SavedView(saved: saved, favorite: favorite), ProfileView(count: saved.length, user: widget.user)];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: tab, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        indicatorColor: mist,
        destinations: [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Explorar'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome_rounded), label: 'Destaques'),
          NavigationDestination(icon: Icon(Icons.favorite_border_rounded), selectedIcon: Icon(Icons.favorite_rounded), label: 'Favoritos'),
          const NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Perfil'),
        ],
      ),
    );
  }
}

class HomeView extends StatelessWidget {
  const HomeView({super.key, required this.saved, required this.favorite, required this.showExplore, required this.user});
  final Set<String> saved;
  final ValueChanged<String> favorite;
  final VoidCallback showExplore;
  final User? user;
  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection('home_pages').doc('published').snapshots(), builder: (context, snapshot) { final config=snapshot.data?.data() ?? const <String,dynamic>{}; final sections=Map<String,dynamic>.from(config['sections'] ?? const {}); final hero=(config['heroTitle'] ?? 'O que você procura hoje?').toString(); return CustomScrollView(slivers: [
        SliverToBoxAdapter(child: WelcomeHero(onSearch: () => showSearch(context: context, delegate: CitySearch()), user: user)),
        const SliverToBoxAdapter(child: AdCarousel()),
        if(sections['categories'] != false) SliverToBoxAdapter(child: SectionTitle(title: hero, action: 'Ver todas', onTap: showExplore)),
        if(sections['categories'] != false) SliverToBoxAdapter(child: SizedBox(height: 117, child: ListView.separated(padding: const EdgeInsets.symmetric(horizontal: 20), scrollDirection: Axis.horizontal, itemCount: homeCatalog.length, separatorBuilder: (_, _) => const SizedBox(width: 10), itemBuilder: (_, i) => CategoryTile(category: homeCatalog[i], onTap: () => openDirectory(context, homeCatalog[i]))))),
        if(sections['highlights'] != false) SliverToBoxAdapter(child: SectionTitle(title: 'Tá bombando em Macacu 🔥', action: 'Ver todos', onTap: showExplore)),
        if(sections['highlights'] != false) SliverToBoxAdapter(child: PublishedBusinessStrip(saved: saved, favorite: favorite)),
        SliverToBoxAdapter(child: SectionTitle(title: 'Ofertas em Macacu', action: 'Ver ofertas', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OffersView())))),
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: OfferBanner())),
        SliverToBoxAdapter(child: SectionTitle(title: 'Vantagens e avisos', action: 'Abrir', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ResourcesHub())))),
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: ResourcesPreview())),
        SliverToBoxAdapter(child: SectionTitle(title: 'Novos por aqui', action: 'Ver todas', onTap: () => openFeature(context, Feature.jobs))),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: jobs.take(2).map((job) => Padding(padding: const EdgeInsets.only(bottom: 10), child: JobCard(job: job))).toList()))),
        SliverToBoxAdapter(child: SectionTitle(title: 'O que tá rolando', action: 'Ver notícias', onTap: () => openFeature(context, Feature.news))),
        SliverToBoxAdapter(child: const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: LocalNewsCard())),
        SliverToBoxAdapter(child: SectionTitle(title: 'Agenda Macacu', action: 'Ver agenda', onTap: () => openFeature(context, Feature.events))),
        SliverToBoxAdapter(child: const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: EventCard())),
        SliverToBoxAdapter(child: SectionTitle(title: 'Descubra Macacu', action: 'Explorar agora', onTap: () => openFeature(context, Feature.tourism))),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 28), child: NatureBanner(onTap: () => openFeature(context, Feature.tourism)))),
      ]); });
}

class WelcomeHero extends StatelessWidget {
  const WelcomeHero({super.key, required this.onSearch, required this.user});
  final VoidCallback onSearch;
  final User? user;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 25),
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFEAF4FF), Color(0xFFF8FAFC)]), borderRadius: BorderRadius.vertical(bottom: Radius.circular(30))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Brand(), const Spacer(), CircleIcon(icon: Icons.notifications_none_rounded, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsView())))]),
          const SizedBox(height: 27),
          Text(user == null ? 'A cidade na sua mão.' : 'Olá, ${user!.displayName?.split(' ').first ?? 'Bruno'}! 👋', style: const TextStyle(color: ocean, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('O que você procura\nhoje?', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.03, letterSpacing: -1)),
          const SizedBox(height: 4),
          const Text('Cachoeiras de Macacu • RJ', style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 18),
          Material(color: Colors.white, borderRadius: BorderRadius.circular(16), child: InkWell(onTap: onSearch, borderRadius: BorderRadius.circular(16), child: const Padding(padding: EdgeInsets.symmetric(horizontal: 15, vertical: 16), child: Row(children: [Icon(Icons.search_rounded, color: ocean), SizedBox(width: 10), Expanded(child: Text('Encontre em Macacu...', style: TextStyle(color: muted))), Icon(Icons.tune_rounded, color: sky)])))),
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
      final remote = snapshot.data?.docs.map((d) => d.data()).where(isActiveContent).toList() ?? [];
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
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    ClipRRect(borderRadius: BorderRadius.circular(13), child: Image.asset('assets/images/tudo-aqui-macacu-icon-v1.png', width: 43, height: 43, fit: BoxFit.cover)),
    const SizedBox(width: 9),
    const Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text('Tudo Aqui Macacu', style: TextStyle(color: ink, fontWeight: FontWeight.w800, height: 1.05)), Text('A cidade na sua mão.', style: TextStyle(color: muted, fontSize: 9, fontWeight: FontWeight.w600))]),
  ]);
}

class App3DButton extends StatefulWidget {
  const App3DButton({super.key, required this.onPressed, required this.icon, required this.label});
  final VoidCallback? onPressed; final Widget icon; final String label;
  @override State<App3DButton> createState() => _App3DButtonState();
}
class _App3DButtonState extends State<App3DButton> {
  bool pressed = false;
  @override Widget build(BuildContext context) => GestureDetector(
    onTapDown: widget.onPressed == null ? null : (_) => setState(() => pressed = true),
    onTapCancel: () => setState(() => pressed = false),
    onTapUp: widget.onPressed == null ? null : (_) { setState(() => pressed = false); widget.onPressed!(); },
    child: AnimatedContainer(duration: const Duration(milliseconds: 120), transform: Matrix4.translationValues(0, pressed ? 3 : 0, 0), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF9A18), Color(0xFFFF5A00)]), borderRadius: BorderRadius.circular(14), boxShadow: pressed ? null : const [BoxShadow(color: Color(0x44082B4C), offset: Offset(0, 3), blurRadius: 0)]), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13), child: Row(mainAxisSize: MainAxisSize.min, children: [widget.icon, const SizedBox(width: 9), Text(widget.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))])),
  );
}

class CircleIcon extends StatelessWidget {
  const CircleIcon({super.key, required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(color: Colors.white, shape: const CircleBorder(), child: InkWell(onTap: onTap, customBorder: const CircleBorder(), child: SizedBox(width: 40, height: 40, child: Icon(icon, color: ink))));
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
  Widget build(BuildContext context) => SizedBox(width: grid ? null : 92, child: Material(color: Colors.white, borderRadius: BorderRadius.circular(18), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Padding(padding: const EdgeInsets.all(9), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Sprite(index: category.artwork, size: grid ? 83 : 49), const SizedBox(height: 6), Text(category.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1.1))])))));
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
          onTap: () { unawaited(recordMetric('business_open', target: business.name)); Navigator.of(context).push(MaterialPageRoute(builder: (_) => BusinessProfile(business: business, saved: saved, onFavorite: onFavorite))); },
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
  Widget build(BuildContext context) => Scaffold(body: CustomScrollView(slivers: [const SliverAppBar(pinned: true, title: Brand()), SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 4), child: Text('Encontre tudo em um só lugar', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),), const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('Compre de quem é daqui. Escolha uma categoria para começar.', style: TextStyle(color: muted))),), SliverPadding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 26), sliver: SliverGrid(delegate: SliverChildBuilderDelegate((_, i) => CategoryTile(category: catalog[i], grid: true, onTap: () => openDirectory(context, catalog[i])), childCount: catalog.length), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: .82, crossAxisSpacing: 10, mainAxisSpacing: 10))), SliverToBoxAdapter(child: SectionTitle(title: 'Negócios em destaque', action: 'Ver todos', onTap: () {})), SliverToBoxAdapter(child: PublishedBusinessList(saved: saved, favorite: favorite))]));
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
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: publishedBusinessesStream(),
    builder: (context, snapshot) {
      final remote = snapshot.data?.docs.map(Business.fromFirestore).where((item) => item.category == widget.category.name).toList() ?? const <Business>[];
      final inCategory = remote.isEmpty ? businesses.where((item) => item.category == widget.category.name).toList() : remote;
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
    },
  );
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
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: publishedBusinessesStream(), builder: (context, snapshot) { final remote = snapshot.data?.docs.map(Business.fromFirestore).toList() ?? const <Business>[]; final source = remote.isEmpty ? businesses : remote; final items = source.where((item) => saved.contains(item.name)).toList(); return Scaffold(body: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 28), children: [const Brand(), const SizedBox(height: 25), Text('Seus favoritos', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 5), const Text('Guarde os negócios que quer consultar depois.', style: TextStyle(color: muted)), const SizedBox(height: 20), if (items.isEmpty) const EmptyDirectory() else ...items.map((item) => Padding(padding: const EdgeInsets.only(bottom: 12), child: BusinessCard(business: item, saved: true, onFavorite: () => favorite(item.name))))])); });
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
  final User? user;
  @override
  Widget build(BuildContext context) {
    final isAdmin = isAdminUser(user);
    if (user == null) return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [const Brand(), const SizedBox(height: 28), const Icon(Icons.favorite_outline_rounded, color: orange, size: 54), const SizedBox(height: 12), Text('Entre para personalizar', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 7), const Text('Salve seus lugares e receba novidades de Macacu.', textAlign: TextAlign.center, style: TextStyle(color: muted)), const SizedBox(height: 18), FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GoogleLoginView())), icon: const Icon(Icons.login_rounded), label: const Text('Continuar com Google'))]))));
    return Scaffold(body: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 28), children: [
      const Brand(), const SizedBox(height: 27),
      Row(children: [CircleAvatar(radius: 31, backgroundColor: yellow, backgroundImage: user!.photoURL == null ? null : NetworkImage(user!.photoURL!), child: user!.photoURL == null ? const Icon(Icons.person_outline_rounded, color: ink, size: 31) : null), const SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(user!.displayName ?? 'Sua área', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)), Text(user!.email ?? '', style: const TextStyle(color: muted))]))]),
      const SizedBox(height: 26),
      MenuRow(icon: Icons.favorite_outline_rounded, title: 'Itens salvos', text: '$count favorito(s) na sua conta'),
      MenuRow(icon: Icons.notifications_none_rounded, title: 'Notificações', text: 'Ofertas, vagas e novidades de Macacu', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsView()))),
      MenuRow(icon: Icons.mail_outline_rounded, title: 'Fale com a gente', text: 'Sugestões e divulgação', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactView()))),
      if (isAdmin) MenuRow(icon: Icons.admin_panel_settings_outlined, title: 'Administração', text: 'Gerencie todo o aplicativo', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminView()))),
      MenuRow(icon: Icons.logout_rounded, title: 'Sair da conta', text: 'Entrar com outra conta Google', onTap: () => FirebaseAuth.instance.signOut()),
      const SizedBox(height: 24),
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: mist, borderRadius: BorderRadius.circular(20)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Nossa cidade. Mais perto de você.', style: TextStyle(fontWeight: FontWeight.w800)), SizedBox(height: 5), Text('Tudo de Macacu em um só lugar.', style: TextStyle(color: muted, fontSize: 12))])),
    ]));
  }
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
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Administração')), body: ListView(padding: const EdgeInsets.all(20), children: [
    Text('Controle do aplicativo', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
    const SizedBox(height: 6), const Text('Publique, revise e acompanhe tudo por aqui.', style: TextStyle(color: muted)), const SizedBox(height: 22),
    ListTile(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HomeEditor())), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), tileColor: const Color(0xFFEAF4FF), leading: const Icon(Icons.home_work_outlined, color: ocean), title: const Text('Home Page', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: const Text('Editar rascunho e publicar a página inicial'), trailing: const Icon(Icons.chevron_right_rounded, color: sky)),
    const SizedBox(height: 10),
    ListTile(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InitialContentImporter())), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), tileColor: const Color(0xFFFFF0D8), leading: const Icon(Icons.file_download_outlined, color: orange), title: const Text('Importar conteúdo inicial', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: const Text('Leva os exemplos do app para a área editável'), trailing: const Icon(Icons.chevron_right_rounded, color: sky)),
    const SizedBox(height: 10),
    ...const [('establishments', 'Estabelecimentos', Icons.storefront_outlined), ('ads', 'Anúncios do carrossel', Icons.campaign_outlined), ('offers', 'Ofertas', Icons.local_offer_outlined), ('coupons', 'Cupons exclusivos', Icons.confirmation_number_outlined), ('alerts', 'Avisos importantes', Icons.warning_amber_rounded), ('routes', 'Roteiros turísticos', Icons.route_outlined), ('polls', 'Enquetes da cidade', Icons.poll_outlined), ('jobs', 'Vagas', Icons.work_outline_rounded), ('news', 'Notícias', Icons.newspaper_rounded), ('events', 'Eventos', Icons.event_note_outlined), ('links', 'Links e botões', Icons.link_rounded)].map((item) => Padding(padding: const EdgeInsets.only(bottom: 10), child: ListTile(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ContentManager(collection: item.$1, title: item.$2))), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), tileColor: Colors.white, leading: Icon(item.$3, color: ocean), title: Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w800)), trailing: const Icon(Icons.chevron_right_rounded, color: sky)))),
    ListTile(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationComposer())), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), tileColor: Colors.white, leading: const Icon(Icons.notifications_active_outlined, color: ocean), title: const Text('Enviar notificação', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: const Text('Crie um aviso específico para o aplicativo'), trailing: const Icon(Icons.chevron_right_rounded, color: sky)),
    ListTile(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminMetricsView())), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), tileColor: mist, leading: const Icon(Icons.bar_chart_rounded, color: ocean), title: const Text('Métricas de anúncios', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: const Text('Visível somente para você'), trailing: const Icon(Icons.chevron_right_rounded, color: sky)),
    const SizedBox(height: 10), ListTile(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAuditView())), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), tileColor: mist, leading: const Icon(Icons.history_rounded, color: ocean), title: const Text('Histórico administrativo', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: const Text('Registros das alterações feitas no app'), trailing: const Icon(Icons.chevron_right_rounded, color: sky)),
    const SizedBox(height: 10), ListTile(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReviewManager())), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), tileColor: mist, leading: const Icon(Icons.rate_review_outlined, color: ocean), title: const Text('Avaliações e correções', style: TextStyle(fontWeight: FontWeight.w800)), trailing: const Icon(Icons.chevron_right_rounded, color: sky)),
    const SizedBox(height: 10), ListTile(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactInbox())), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), tileColor: mist, leading: const Icon(Icons.mail_rounded, color: ocean), title: const Text('Mensagens recebidas', style: TextStyle(fontWeight: FontWeight.w800)), trailing: const Icon(Icons.chevron_right_rounded, color: sky)),
  ]));
}

class AdminAuditView extends StatelessWidget {
  const AdminAuditView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Histórico administrativo')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('admin_audit_logs').orderBy('createdAt', descending: true).limit(100).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Center(child: Padding(padding: EdgeInsets.all(28), child: Text('Não foi possível carregar o histórico. Tente novamente quando houver conexão.')));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final logs = snapshot.data!.docs;
            if (logs.isEmpty) return const Center(child: Text('As próximas alterações administrativas aparecerão aqui.'));
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: logs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final item = logs[index].data();
                final timestamp = item['createdAt'] as Timestamp?;
                final when = timestamp == null ? 'Sincronizando horário...' : '${timestamp.toDate().day.toString().padLeft(2, '0')}/${timestamp.toDate().month.toString().padLeft(2, '0')} às ${timestamp.toDate().hour.toString().padLeft(2, '0')}:${timestamp.toDate().minute.toString().padLeft(2, '0')}';
                return ListTile(
                  tileColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  leading: const Icon(Icons.history_rounded, color: ocean),
                  title: Text('${item['action'] ?? 'alteração'} · ${item['label'] ?? item['collection'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('$when\n${item['collection'] ?? ''}'),
                  isThreeLine: true,
                );
              },
            );
          },
        ),
      );
}

class InitialContentImporter extends StatefulWidget {
  const InitialContentImporter({super.key});

  @override
  State<InitialContentImporter> createState() => _InitialContentImporterState();
}

class _InitialContentImporterState extends State<InitialContentImporter> {
  bool importing = false;

  Future<void> importExamples() async {
    if (!isAdminUser(FirebaseAuth.instance.currentUser)) return;
    setState(() => importing = true);
    try {
      final collection = FirebaseFirestore.instance.collection('establishments');
      final existing = await collection.get();
      final ids = existing.docs.map((document) => document.id).toSet();
      final batch = FirebaseFirestore.instance.batch();
      var added = 0;
      for (var index = 0; index < businesses.length; index++) {
        final business = businesses[index];
        final id = 'modelo-${index + 1}';
        if (ids.contains(id)) continue;
        batch.set(collection.doc(id), {
          'name': business.name,
          'title': business.name,
          'category': business.category,
          'subcategory': business.subcategory,
          'description': business.description,
          'location': business.location,
          'artwork': business.artwork,
          'featured': business.featured,
          'open': business.open,
          'whatsapp': business.whatsapp,
          'phone': business.phone,
          'instagram': business.instagram,
          'maps': business.maps,
          'published': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'initial_template',
        });
        added++;
      }
      if (added > 0) await batch.commit();
      await recordAdminAudit(action: 'import_initial_content', collection: 'establishments', documentId: 'initial-template', label: '$added estabelecimento(s) importado(s)');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(added == 0 ? 'Os exemplos já estão na área administrável.' : '$added exemplo(s) foram importados. Agora você pode editar ou apagar cada um.')));
    } on FirebaseException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível importar agora. Verifique sua conexão e tente novamente.')));
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Importar conteúdo inicial')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Transformar exemplos em conteúdo editável', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            const Text('Isso copia os estabelecimentos demonstrativos para o Firebase uma única vez. Os que já existem não são substituídos. Depois, você controla publicação, destaque, contatos e descrição pela aba Estabelecimentos.'),
            const Spacer(),
            FilledButton.icon(onPressed: importing ? null : importExamples, icon: const Icon(Icons.file_download_outlined), label: Text(importing ? 'Importando...' : 'Importar exemplos')),
          ]),
        ),
      );
}

class HomeEditor extends StatefulWidget { const HomeEditor({super.key}); @override State<HomeEditor> createState() => _HomeEditorState(); }
class _HomeEditorState extends State<HomeEditor> {
  final title = TextEditingController(); final search = TextEditingController(); bool categories = true, highlights = true, offers = true, events = true, tourism = true, saving = false;
  @override void dispose() { title.dispose(); search.dispose(); super.dispose(); }
  Future<void> load() async { final d = (await FirebaseFirestore.instance.collection('home_pages').doc('draft').get()).data() ?? {}; title.text = (d['heroTitle'] ?? 'O que você procura hoje?').toString(); search.text = (d['searchPlaceholder'] ?? 'Encontre em Macacu...').toString(); final s = Map<String,dynamic>.from(d['sections'] ?? {}); setState(() { categories=s['categories'] ?? true; highlights=s['highlights'] ?? true; offers=s['offers'] ?? true; events=s['events'] ?? true; tourism=s['tourism'] ?? true; }); }
  Future<void> save(bool publish) async { setState(() => saving=true); final data={'heroTitle':title.text.trim(),'searchPlaceholder':search.text.trim(),'sections':{'categories':categories,'highlights':highlights,'offers':offers,'events':events,'tourism':tourism},'updatedAt':FieldValue.serverTimestamp()}; final db=FirebaseFirestore.instance; await db.collection('home_pages').doc('draft').set(data,SetOptions(merge:true)); if(publish) { await db.collection('home_pages').doc('published').set({...data,'publishedAt':FieldValue.serverTimestamp(),'version':FieldValue.increment(1)},SetOptions(merge:true)); await recordAdminAudit(action:'publish_home',collection:'home_pages',documentId:'published',label:'Home publicada'); } if(mounted){setState(()=>saving=false);ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(publish?'Home publicada.':'Rascunho salvo.')));} }
  @override void initState(){super.initState();load();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Editor da Home')),body:ListView(padding:const EdgeInsets.all(20),children:[const Text('Rascunho e publicação',style:TextStyle(fontWeight:FontWeight.w800,fontSize:20)),const SizedBox(height:12),TextField(controller:title,decoration:const InputDecoration(labelText:'Frase principal',border:OutlineInputBorder())),const SizedBox(height:12),TextField(controller:search,decoration:const InputDecoration(labelText:'Busca',border:OutlineInputBorder())),const SizedBox(height:12),...<String,bool>{'Categorias':categories,'Destaques':highlights,'Ofertas':offers,'Eventos':events,'Turismo':tourism}.entries.map((e)=>SwitchListTile(title:Text(e.key),value:e.value,onChanged:(v)=>setState((){if(e.key=='Categorias')categories=v;if(e.key=='Destaques')highlights=v;if(e.key=='Ofertas')offers=v;if(e.key=='Eventos')events=v;if(e.key=='Turismo')tourism=v;})),const SizedBox(height:16),FilledButton(onPressed:saving?null:()=>save(false),child:const Text('Salvar rascunho')),const SizedBox(height:10),FilledButton.tonal(onPressed:saving?null:()=>save(true),child:const Text('Publicar alterações'))])); }

class ContentManager extends StatelessWidget { const ContentManager({super.key, required this.collection, required this.title}); final String collection, title;
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), floatingActionButton: FloatingActionButton.extended(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ContentEditor(collection: collection))), icon: const Icon(Icons.add_rounded), label: const Text('Adicionar')), body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection(collection).orderBy('updatedAt', descending: true).snapshots(), builder: (context, snap) { if (snap.hasError) return const Center(child: Text('Não foi possível carregar os itens.')); if (!snap.hasData) return const Center(child: CircularProgressIndicator()); final docs = snap.data!.docs; if (docs.isEmpty) return const Center(child: Text('Ainda não há itens. Use Adicionar para publicar.')); return ListView.separated(padding: const EdgeInsets.all(16), itemCount: docs.length, separatorBuilder: (_, _) => const SizedBox(height: 8), itemBuilder: (_, i) { final d = docs[i]; final data = d.data(); return ListTile(tileColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), title: Text((data['title'] ?? data['name'] ?? 'Sem título').toString(), style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(data['published'] == false ? 'Rascunho' : 'Publicado'), trailing: const Icon(Icons.edit_rounded), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ContentEditor(collection: collection, doc: d)))); }); })); }

class ContentEditor extends StatefulWidget { const ContentEditor({super.key, required this.collection, this.doc}); final String collection; final DocumentSnapshot<Map<String, dynamic>>? doc; @override State<ContentEditor> createState() => _ContentEditorState(); }
class _ContentEditorState extends State<ContentEditor> {
  late final TextEditingController title;
  late final TextEditingController description;
  late final TextEditingController link;
  late final TextEditingController icon;
  late final TextEditingController expires;
  late final TextEditingController category;
  late final TextEditingController subcategory;
  late final TextEditingController location;
  late final TextEditingController whatsapp;
  late final TextEditingController phone;
  late final TextEditingController instagram;
  late final TextEditingController maps;
  bool featured = false;
  bool published = true;
  bool saving = false;
  @override void initState() { super.initState(); final d = widget.doc?.data() ?? {}; title = TextEditingController(text: (d['title'] ?? d['name'] ?? '').toString()); description = TextEditingController(text: (d['description'] ?? '').toString()); link = TextEditingController(text: (d['link'] ?? d['url'] ?? '').toString()); icon = TextEditingController(text: (d['artwork'] ?? '0').toString()); category = TextEditingController(text: (d['category'] ?? '').toString()); subcategory = TextEditingController(text: (d['subcategory'] ?? '').toString()); location = TextEditingController(text: (d['location'] ?? d['address'] ?? '').toString()); whatsapp = TextEditingController(text: (d['whatsapp'] ?? '').toString()); phone = TextEditingController(text: (d['phone'] ?? '').toString()); instagram = TextEditingController(text: (d['instagram'] ?? '').toString()); maps = TextEditingController(text: (d['maps'] ?? d['mapsUrl'] ?? '').toString()); final expiry = d['expiresAt']; expires = TextEditingController(text: expiry is Timestamp ? '${expiry.toDate().year}-${expiry.toDate().month.toString().padLeft(2, '0')}-${expiry.toDate().day.toString().padLeft(2, '0')}' : ''); published = d['published'] as bool? ?? true; featured = d['featured'] as bool? ?? false; }
  @override void dispose() { title.dispose(); description.dispose(); link.dispose(); icon.dispose(); expires.dispose(); category.dispose(); subcategory.dispose(); location.dispose(); whatsapp.dispose(); phone.dispose(); instagram.dispose(); maps.dispose(); super.dispose(); }
  Future<void> save() async {
    if (title.text.trim().isEmpty) return;
    setState(() => saving = true);
    try {
      final expiry = DateTime.tryParse(expires.text.trim());
      final data = {
        'title': title.text.trim(),
        'description': description.text.trim(),
        'link': link.text.trim(),
        'artwork': int.tryParse(icon.text.trim()) ?? 0,
        if (widget.collection == 'establishments') ...{'name': title.text.trim(), 'category': category.text.trim(), 'subcategory': subcategory.text.trim(), 'location': location.text.trim(), 'whatsapp': whatsapp.text.trim(), 'phone': phone.text.trim(), 'instagram': instagram.text.trim(), 'maps': maps.text.trim(), 'featured': featured},
        'published': published,
        'updatedAt': FieldValue.serverTimestamp(),
        if (expiry != null) 'expiresAt': Timestamp.fromDate(DateTime(expiry.year, expiry.month, expiry.day, 23, 59, 59)),
      };
      final reference = widget.doc == null
          ? await FirebaseFirestore.instance.collection(widget.collection).add(data)
          : widget.doc!.reference;
      if (widget.doc != null) await reference.set(data, SetOptions(merge: true));
      await recordAdminAudit(
        action: widget.doc == null ? 'create' : 'update',
        collection: widget.collection,
        documentId: reference.id,
        label: title.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } on FirebaseException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível salvar agora. Verifique a internet e tente novamente.')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
  Future<void> remove() async {
    final document = widget.doc;
    if (document == null) return;
    try {
      await document.reference.delete();
      await recordAdminAudit(action: 'delete', collection: widget.collection, documentId: document.id, label: title.text.trim());
      if (mounted) Navigator.pop(context);
    } on FirebaseException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível excluir agora. Tente novamente.')));
    }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.doc == null ? 'Adicionar' : 'Editar')), body: ListView(padding: const EdgeInsets.all(20), children: [TextField(controller: title, decoration: const InputDecoration(labelText: 'Título ou nome', border: OutlineInputBorder())), const SizedBox(height: 14), if (widget.collection == 'establishments') ...[TextField(controller: category, decoration: const InputDecoration(labelText: 'Categoria', border: OutlineInputBorder())), const SizedBox(height: 14), TextField(controller: subcategory, decoration: const InputDecoration(labelText: 'Subcategoria', border: OutlineInputBorder())), const SizedBox(height: 14)], TextField(controller: description, maxLines: 5, decoration: const InputDecoration(labelText: 'Descrição', border: OutlineInputBorder())), const SizedBox(height: 14), if (widget.collection == 'establishments') ...[TextField(controller: location, decoration: const InputDecoration(labelText: 'Endereço ou localização', border: OutlineInputBorder())), const SizedBox(height: 14), TextField(controller: whatsapp, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'WhatsApp (link wa.me)', border: OutlineInputBorder())), const SizedBox(height: 14), TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefone (tel:)', border: OutlineInputBorder())), const SizedBox(height: 14), TextField(controller: instagram, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Instagram (URL)', border: OutlineInputBorder())), const SizedBox(height: 14), TextField(controller: maps, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Link do Google Maps', border: OutlineInputBorder())), const SizedBox(height: 14)], TextField(controller: link, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Link do botão (opcional)', border: OutlineInputBorder())), const SizedBox(height: 14), TextField(controller: icon, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Ícone (número de 0 a 17)', helperText: 'Escolha o ícone que aparecerá no aplicativo', border: OutlineInputBorder())), const SizedBox(height: 14), if (widget.collection == 'ads' || widget.collection == 'offers') TextField(controller: expires, keyboardType: TextInputType.datetime, decoration: const InputDecoration(labelText: 'Encerrar em (AAAA-MM-DD)', helperText: 'Deixe vazio para não expirar', border: OutlineInputBorder())), if (widget.collection == 'establishments') SwitchListTile(value: featured, onChanged: (v) => setState(() => featured = v), title: const Text('Destaque na Home'), contentPadding: EdgeInsets.zero), SwitchListTile(value: published, onChanged: (v) => setState(() => published = v), title: const Text('Publicado'), subtitle: const Text('Desative para manter como rascunho'), contentPadding: EdgeInsets.zero), const SizedBox(height: 10), FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'Salvando...' : 'Salvar alterações')), if (widget.doc != null) TextButton.icon(onPressed: remove, icon: const Icon(Icons.delete_outline, color: Colors.red), label: const Text('Excluir item', style: TextStyle(color: Colors.red))) ]));
}

class ContactInbox extends StatelessWidget { const ContactInbox({super.key}); @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Mensagens recebidas')), body: StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream: FirebaseFirestore.instance.collection('contact_messages').orderBy('createdAt', descending:true).snapshots(), builder: (context,s) { if (!s.hasData) return const Center(child:CircularProgressIndicator()); final docs=s.data!.docs; if(docs.isEmpty) return const Center(child:Text('Nenhuma mensagem ainda.')); return ListView.builder(itemCount:docs.length,itemBuilder:(_,i){final d=docs[i].data(); return ListTile(title:Text((d['name']??'Visitante').toString()),subtitle:Text('${d['message']??''}\n${d['contact']??d['email']??''}'),isThreeLine:true);}); })); }

class ResourcesPreview extends StatelessWidget { const ResourcesPreview({super.key}); @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: mist, borderRadius: BorderRadius.circular(20)), child: const Row(children: [Icon(Icons.local_activity_outlined, color: orange, size: 34), SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Cupons, alertas e agenda', style: TextStyle(fontWeight: FontWeight.w800)), SizedBox(height: 3), Text('Benefícios e informações locais reunidos para você.', style: TextStyle(color: muted, fontSize: 12))]))])); }

class ResourcesHub extends StatelessWidget { const ResourcesHub({super.key}); @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Mais Macacu')), body: ListView(padding: const EdgeInsets.all(20), children: [Text('Vantagens e informações locais', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 8), const Text('Tudo organizado para você aproveitar mais a cidade.', style: TextStyle(color: muted)), const SizedBox(height: 20), ...const [(Icons.confirmation_number_outlined, 'Cupons exclusivos', 'Descontos e benefícios locais'), (Icons.warning_amber_rounded, 'Avisos importantes', 'Informações que pedem atenção'), (Icons.event_available_outlined, 'Agenda com lembrete', 'Eventos para salvar e acompanhar'), (Icons.route_outlined, 'Roteiros turísticos', 'Ideias para descobrir Macacu'), (Icons.poll_outlined, 'Enquetes da cidade', 'Dê sua opinião'), (Icons.store_mall_directory_outlined, 'Indique uma empresa', 'Envie dados para revisão')].map((item) => Padding(padding: const EdgeInsets.only(bottom: 10), child: ListTile(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), tileColor: Colors.white, leading: Icon(item.$1, color: ocean), title: Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(item.$3), trailing: const Icon(Icons.chevron_right_rounded, color: sky), onTap: () { final page = item.$2 == 'Cupons exclusivos' ? const CouponsView() : item.$2 == 'Avisos importantes' ? const LocalAlertsView() : item.$2 == 'Agenda com lembrete' ? const EventsReminderView() : item.$2 == 'Roteiros turísticos' ? const TouristRoutesView() : item.$2 == 'Enquetes da cidade' ? const PollsView() : const BusinessProposalView(); Navigator.push(context, MaterialPageRoute(builder: (_) => page)); }))) ])); }

class FirestoreContentList extends StatelessWidget { const FirestoreContentList({super.key, required this.collection, required this.empty, this.actionLabel = 'Abrir'}); final String collection, empty, actionLabel; @override Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection(collection).where('published', isEqualTo: true).snapshots(), builder: (context, s) { final data = (s.data?.docs.map((d) => d.data()).where(isActiveContent).toList() ?? []); if (data.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(28), child: Text(empty, textAlign: TextAlign.center))); return ListView.separated(padding: const EdgeInsets.all(20), itemCount: data.length, separatorBuilder: (_, _) => const SizedBox(height: 10), itemBuilder: (_, i) { final item = data[i]; return ListTile(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), tileColor: Colors.white, leading: const Icon(Icons.local_activity_outlined, color: orange), title: Text((item['title'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text((item['description'] ?? '').toString()), trailing: TextButton(onPressed: () => openUrl(context, (item['link'] ?? '').toString(), actionLabel), child: Text(actionLabel))); }); }); }
class CouponsView extends StatelessWidget { const CouponsView({super.key}); @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Cupons exclusivos')), body: const FirestoreContentList(collection: 'coupons', empty: 'Novos cupons aparecerão aqui.', actionLabel: 'Usar')); }
class LocalAlertsView extends StatelessWidget { const LocalAlertsView({super.key}); @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Avisos importantes')), body: const FirestoreContentList(collection: 'alerts', empty: 'Não há avisos importantes no momento.', actionLabel: 'Ver')); }
class TouristRoutesView extends StatelessWidget { const TouristRoutesView({super.key}); @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Roteiros turísticos')), body: const FirestoreContentList(collection: 'routes', empty: 'Em breve você verá roteiros para explorar Macacu.', actionLabel: 'Ver roteiro')); }
class EventsReminderView extends StatelessWidget { const EventsReminderView({super.key}); @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Agenda com lembrete')), body: const FirestoreContentList(collection: 'events', empty: 'Nenhum evento publicado no momento.', actionLabel: 'Lembrar')); }

class PollsView extends StatelessWidget {
  const PollsView({super.key});
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Enquetes da cidade')), body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection('polls').where('published', isEqualTo: true).snapshots(), builder: (context, s) {
    final docs = s.data?.docs ?? [];
    if (docs.isEmpty) return const Center(child: Text('Em breve teremos enquetes para a cidade.'));
    return ListView(padding: const EdgeInsets.all(20), children: docs.map((d) {
      final data = d.data();
      final options = List<String>.from(data['options'] ?? []);
      return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text((data['title'] ?? 'Enquete').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        ...options.map((option) => OutlinedButton(onPressed: FirebaseAuth.instance.currentUser == null ? null : () => d.reference.collection('votes').doc(FirebaseAuth.instance.currentUser!.uid).set({'option': option, 'updatedAt': FieldValue.serverTimestamp()}), child: Align(alignment: Alignment.centerLeft, child: Text(option)))),
      ])));
    }).toList());
  }));
}

class BusinessProposalView extends StatefulWidget { const BusinessProposalView({super.key}); @override State<BusinessProposalView> createState() => _BusinessProposalViewState(); }
class _BusinessProposalViewState extends State<BusinessProposalView> { final name = TextEditingController(); final contact = TextEditingController(); final details = TextEditingController(); bool sending = false; @override void dispose() { name.dispose(); contact.dispose(); details.dispose(); super.dispose(); } Future<void> send() async { if (name.text.trim().isEmpty || details.text.trim().isEmpty) return; setState(() => sending = true); try { await FirebaseFirestore.instance.collection('business_proposals').add({'name': name.text.trim(), 'contact': contact.text.trim(), 'details': details.text.trim(), 'status': 'pending', 'createdAt': FieldValue.serverTimestamp()}); if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recebido. Você fará a revisão antes de publicar.'))); Navigator.pop(context); } } finally { if (mounted) setState(() => sending = false); } } @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Indique uma empresa')), body: ListView(padding: const EdgeInsets.all(20), children: [const Text('Envie os dados. A publicação depende da aprovação do administrador.', style: TextStyle(color: muted)), const SizedBox(height: 18), TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome da empresa', border: OutlineInputBorder())), const SizedBox(height: 12), TextField(controller: contact, decoration: const InputDecoration(labelText: 'WhatsApp ou contato', border: OutlineInputBorder())), const SizedBox(height: 12), TextField(controller: details, maxLines: 5, decoration: const InputDecoration(labelText: 'Descrição e informações', border: OutlineInputBorder())), const SizedBox(height: 16), FilledButton(onPressed: sending ? null : send, child: Text(sending ? 'Enviando...' : 'Enviar para aprovação'))])); }

class NotificationsView extends StatelessWidget {
  const NotificationsView({super.key});
  @override Widget build(BuildContext context) { final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase() ?? ''; return Scaffold(appBar: AppBar(title: const Text('Notificações')), body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection('notifications').where('published', isEqualTo: true).snapshots(), builder: (context, snapshot) { final items = (snapshot.data?.docs.map((d) => d.data()).where((item) => isActiveContent(item) && ((item['targetEmail'] ?? '').toString().isEmpty || (item['targetEmail'] ?? '').toString().toLowerCase() == email)).toList() ?? [])..sort((a, b) => ((b['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((a['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)); if (items.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(28), child: Text('Você está em dia. As novidades de Macacu aparecerão aqui.', textAlign: TextAlign.center))); return ListView.separated(padding: const EdgeInsets.all(20), itemCount: items.length, separatorBuilder: (_, _) => const SizedBox(height: 10), itemBuilder: (_, i) { final item = items[i]; return ListTile(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), tileColor: Colors.white, leading: const CircleIcon(icon: Icons.notifications_active_rounded), title: Text((item['title'] ?? 'Novidade em Macacu').toString(), style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text((item['description'] ?? '').toString()), onTap: () { unawaited(recordMetric('notification_open', target: (item['title'] ?? '').toString())); openUrl(context, (item['link'] ?? '').toString(), 'notificação'); }); }); })); }
}

class NotificationComposer extends StatefulWidget {
  const NotificationComposer({super.key});
  @override State<NotificationComposer> createState() => _NotificationComposerState();
}

class _NotificationComposerState extends State<NotificationComposer> {
  final title = TextEditingController();
  final message = TextEditingController();
  final link = TextEditingController();
  final recipient = TextEditingController();
  bool sendToAll = true;
  bool sending = false;
  @override void dispose() { title.dispose(); message.dispose(); link.dispose(); recipient.dispose(); super.dispose(); }

  Future<void> send() async {
    if (title.text.trim().isEmpty || message.text.trim().isEmpty || (!sendToAll && recipient.text.trim().isEmpty)) return;
    setState(() => sending = true);
    final targetEmail = sendToAll ? '' : recipient.text.trim().toLowerCase();
    final payload = {'title': title.text.trim(), 'description': message.text.trim(), 'link': link.text.trim(), 'targetEmail': targetEmail, 'published': true, 'updatedAt': FieldValue.serverTimestamp()};
    try {
      final notification = await FirebaseFirestore.instance.collection('notifications').add(payload);
      await FirebaseFirestore.instance.collection('push_queue').add({...payload, 'status': 'queued', 'createdAt': FieldValue.serverTimestamp()});
      await recordAdminAudit(action: 'send_notification', collection: 'notifications', documentId: notification.id, label: title.text.trim());
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notificação preparada para envio.'))); Navigator.pop(context); }
    } on FirebaseException catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível preparar a notificação.')));
    } finally { if (mounted) setState(() => sending = false); }
  }

  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Enviar notificação')), body: ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Aparece dentro do app e, com o push ativado, como alerta no celular.', style: TextStyle(color: muted)), const SizedBox(height: 20),
    TextField(controller: title, decoration: const InputDecoration(labelText: 'Título', border: OutlineInputBorder())), const SizedBox(height: 14),
    TextField(controller: message, maxLines: 4, decoration: const InputDecoration(labelText: 'Mensagem', border: OutlineInputBorder())), const SizedBox(height: 14),
    TextField(controller: link, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Link ao tocar (opcional)', border: OutlineInputBorder())), const SizedBox(height: 16),
    SwitchListTile(value: sendToAll, onChanged: (value) => setState(() => sendToAll = value), title: const Text('Enviar para todos'), subtitle: Text(sendToAll ? 'Todos os usuários que permitiram notificações.' : 'Enviar somente para uma conta específica.'), contentPadding: EdgeInsets.zero),
    if (!sendToAll) TextField(controller: recipient, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail da conta', border: OutlineInputBorder())),
    const SizedBox(height: 18), FilledButton.icon(onPressed: sending ? null : send, icon: const Icon(Icons.send_rounded), label: Text(sending ? 'Preparando...' : 'Disparar notificação')),
  ]));
}

class ReviewForm extends StatefulWidget { const ReviewForm({super.key, required this.business}); final Business business; @override State<ReviewForm> createState() => _ReviewFormState(); }
class _ReviewFormState extends State<ReviewForm> { final message = TextEditingController(); int stars = 5; bool sending = false; @override void dispose() { message.dispose(); super.dispose(); } Future<void> send() async { final user = FirebaseAuth.instance.currentUser; if (user == null) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entre com Google para enviar uma avaliação.'))); return; } if (message.text.trim().isEmpty) return; setState(() => sending = true); try { await FirebaseFirestore.instance.collection('reviews').add({'business': widget.business.name, 'message': message.text.trim(), 'stars': stars, 'userId': user.uid, 'status': 'pending', 'createdAt': FieldValue.serverTimestamp()}); if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recebido. O administrador vai revisar antes de publicar.'))); Navigator.pop(context); } } finally { if (mounted) setState(() => sending = false); } } @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Avaliar estabelecimento')), body: ListView(padding: const EdgeInsets.all(20), children: [Text(widget.business.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 8), const Text('Sua avaliação é revisada pelo administrador antes de aparecer.', style: TextStyle(color: muted)), const SizedBox(height: 20), Wrap(children: List.generate(5, (i) => IconButton(onPressed: () => setState(() => stars = i + 1), icon: Icon(i < stars ? Icons.star_rounded : Icons.star_outline_rounded, color: yellow, size: 32)))), TextField(controller: message, maxLines: 5, decoration: const InputDecoration(labelText: 'Avaliação ou correção', border: OutlineInputBorder())), const SizedBox(height: 16), FilledButton(onPressed: sending ? null : send, child: Text(sending ? 'Enviando...' : 'Enviar para revisão'))])); }

class ReviewManager extends StatelessWidget { const ReviewManager({super.key}); @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Avaliações e correções')), body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection('reviews').orderBy('createdAt', descending: true).snapshots(), builder: (context, s) { if (!s.hasData) return const Center(child: CircularProgressIndicator()); final docs = s.data!.docs; if (docs.isEmpty) return const Center(child: Text('Nenhuma avaliação pendente.')); return ListView.separated(padding: const EdgeInsets.all(16), itemCount: docs.length, separatorBuilder: (_, _) => const SizedBox(height: 10), itemBuilder: (_, i) { final d = docs[i]; final item = d.data(); return ListTile(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), tileColor: Colors.white, title: Text((item['business'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${item['stars'] ?? 0} estrelas · ${item['message'] ?? ''}'), trailing: PopupMenuButton<String>(onSelected: (value) => d.reference.update({'status': value}), itemBuilder: (_) => const [PopupMenuItem(value: 'approved', child: Text('Aprovar')), PopupMenuItem(value: 'rejected', child: Text('Recusar'))])); }); })); }

class AdminMetricsView extends StatelessWidget { const AdminMetricsView({super.key}); @override Widget build(BuildContext context) { if (!isAdminUser(FirebaseAuth.instance.currentUser)) return const Scaffold(body: Center(child: Text('Acesso restrito ao administrador.'))); return Scaffold(appBar: AppBar(title: const Text('Métricas de anúncios')), body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection('metrics').orderBy('createdAt', descending: true).limit(100).snapshots(), builder: (context, s) { if (s.hasError) return const Center(child: Text('Não foi possível carregar as métricas. Tente novamente.')); final docs = s.data?.docs ?? []; final opens = docs.where((d) => d.data()['action'] == 'business_open').length; final clicks = docs.where((d) => d.data()['action'] == 'external_click').length; final favorites = docs.where((d) => d.data()['action'] == 'favorite_add').length; final notifications = docs.where((d) => d.data()['action'] == 'notification_open').length; return ListView(padding: const EdgeInsets.all(20), children: [Text('Desempenho recente', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 6), const Text('Dados visíveis somente na sua conta administrativa.', style: TextStyle(color: muted)), const SizedBox(height: 20), Wrap(spacing: 10, runSpacing: 10, children: [MetricTile(label: 'Perfis abertos', value: opens.toString(), icon: Icons.storefront_outlined), MetricTile(label: 'Cliques externos', value: clicks.toString(), icon: Icons.ads_click_outlined), MetricTile(label: 'Favoritos', value: favorites.toString(), icon: Icons.favorite_outline_rounded), MetricTile(label: 'Notificações', value: notifications.toString(), icon: Icons.notifications_outlined)]), const SizedBox(height: 22), const Text('Últimas interações', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 8), ...docs.take(20).map((d) => ListTile(title: Text((d.data()['target'] ?? d.data()['action'] ?? '').toString()), subtitle: Text((d.data()['action'] ?? '').toString()), leading: const Icon(Icons.insights_rounded, color: ocean)))]); })); } }
class MetricTile extends StatelessWidget { const MetricTile({super.key, required this.label, required this.value, required this.icon}); final String label, value; final IconData icon; @override Widget build(BuildContext context) => SizedBox(width: 160, child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: ocean), const SizedBox(height: 16), Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), Text(label, style: const TextStyle(color: muted, fontSize: 12))]))); }

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
  @override String get searchFieldLabel => 'Empresa, serviço, bairro ou categoria';
  @override List<Widget>? buildActions(BuildContext context) => [IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear_rounded))];
  @override Widget? buildLeading(BuildContext context) => IconButton(onPressed: () => close(context, null), icon: const Icon(Icons.arrow_back_rounded));
  @override Widget buildResults(BuildContext context) => results();
  @override Widget buildSuggestions(BuildContext context) => results();
  Widget results() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: publishedBusinessesStream(), builder: (context, snapshot) { final source = snapshot.data?.docs.map(Business.fromFirestore).toList() ?? const <Business>[]; final all = source.isEmpty ? businesses : source; final term = query.toLowerCase().trim(); final found = all.where((b) => term.isEmpty || '${b.name} ${b.category} ${b.subcategory} ${b.location} ${b.description}'.toLowerCase().contains(term)).toList(); return ListView(padding: const EdgeInsets.all(20), children: [if (query.isEmpty) const Text('Busque por empresa, serviço, bairro, turismo ou categoria.', style: TextStyle(color: muted)), if (query.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text('${found.length} resultado(s) para “$query”', style: const TextStyle(color: orange, fontWeight: FontWeight.w800))), const SizedBox(height: 12), if (found.isEmpty) const EmptyDirectory() else ...found.map((b) => Padding(padding: const EdgeInsets.only(bottom: 12), child: BusinessCard(business: b, saved: false, onFavorite: () {})))]); });
}

Future<void> openUrl(BuildContext context, String url, String label) async { final target = Uri.tryParse(url); if (target == null || url.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label será disponibilizado quando você cadastrar o estabelecimento.'))); return; } unawaited(recordMetric('external_click', target: label)); if (!await launchUrl(target, mode: LaunchMode.externalApplication) && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível abrir $label.'))); }

class Category { const Category(this.name, this.artwork, this.types); final String name; final int artwork; final List<String> types; }
class Business {
  const Business(this.name, this.category, this.subcategory, this.description, this.location, this.artwork, {this.id = '', this.featured = false, this.open = true, this.whatsapp = '', this.phone = '', this.instagram = '', this.maps = ''});
  factory Business.fromFirestore(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data() ?? const <String, dynamic>{};
    return Business(
      (data['name'] ?? data['title'] ?? 'Estabelecimento').toString(),
      (data['category'] ?? 'Comércio').toString(),
      (data['subcategory'] ?? '').toString(),
      (data['shortDescription'] ?? data['description'] ?? '').toString(),
      (data['location'] ?? data['address'] ?? 'Cachoeiras de Macacu').toString(),
      (data['artwork'] as num?)?.toInt() ?? 0,
      id: document.id,
      featured: data['featured'] == true,
      open: data['open'] != false,
      whatsapp: (data['whatsapp'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      instagram: (data['instagram'] ?? '').toString(),
      maps: (data['maps'] ?? data['mapsUrl'] ?? '').toString(),
    );
  }
  final String id, name, category, subcategory, description, location, whatsapp, phone, instagram, maps;
  final int artwork;
  final bool featured, open;
}

Stream<QuerySnapshot<Map<String, dynamic>>> publishedBusinessesStream() => FirebaseFirestore.instance.collection('establishments').where('published', isEqualTo: true).snapshots();

class PublishedBusinessStrip extends StatelessWidget {
  const PublishedBusinessStrip({super.key, required this.saved, required this.favorite});
  final Set<String> saved;
  final ValueChanged<String> favorite;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: publishedBusinessesStream(),
        builder: (context, snapshot) {
          final remote = snapshot.data?.docs.map(Business.fromFirestore).where((business) => business.featured).toList() ?? const <Business>[];
          final items = remote.isEmpty ? featured : remote;
          return SizedBox(height: 230, child: ListView.separated(padding: const EdgeInsets.symmetric(horizontal: 20), scrollDirection: Axis.horizontal, itemCount: items.length, separatorBuilder: (_, _) => const SizedBox(width: 12), itemBuilder: (_, index) => SizedBox(width: 292, child: BusinessCard(business: items[index], saved: saved.contains(items[index].name), onFavorite: () => favorite(items[index].name), compact: true))));
        },
      );
}

class PublishedBusinessList extends StatelessWidget {
  const PublishedBusinessList({super.key, required this.saved, required this.favorite});
  final Set<String> saved;
  final ValueChanged<String> favorite;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: publishedBusinessesStream(),
        builder: (context, snapshot) {
          final remote = snapshot.data?.docs.map(Business.fromFirestore).where((business) => business.featured).toList() ?? const <Business>[];
          final items = remote.isEmpty ? featured : remote;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
            child: Column(children: items.map((business) => Padding(padding: const EdgeInsets.only(bottom: 12), child: BusinessCard(business: business, saved: saved.contains(business.name), onFavorite: () => favorite(business.name)))).toList()),
          );
        },
      );
}
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
