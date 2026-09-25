import 'dart:async';

import 'admin_audit.dart';
import 'core/config/firestore_collections.dart';
import 'core/media/media_url_service.dart';
import 'core/services/external_link_service.dart';
import 'core/services/metrics_service.dart';
import 'core/theme/app_colors.dart';
import 'core/widgets/mini_label.dart';
import 'core/widgets/sprite.dart';
import 'features/businesses/models/business.dart';
import 'features/businesses/repositories/business_repository.dart';
import 'features/businesses/services/business_actions.dart';
import 'features/businesses/widgets/business_avatar.dart';
import 'features/businesses/widgets/business_card.dart';
import 'features/businesses/widgets/business_hero_media.dart';
import 'features/businesses/widgets/business_info_block.dart';
import 'features/businesses/widgets/published_business_list.dart';
import 'features/businesses/widgets/published_business_strip.dart';
import 'features/utilities/models/utility_item.dart';
import 'features/tourism/models/tourist_spot.dart';
import 'features/home/models/home_page_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_fonts/google_fonts.dart';

const sky = AppColors.sky;
const ocean = AppColors.ocean;
const ink = AppColors.ink;
const orange = AppColors.orange;
const yellow = AppColors.yellow;
const mist = AppColors.mist;
const soft = AppColors.soft;
const muted = AppColors.muted;
const loginSuccessBackgroundAsset =
    'assets/images/login-success-tudo-aqui-macacu.png';
const splashBackgroundAsset = 'assets/images/splash-tudo-aqui-macacu.png';

final businessRepository = BusinessRepository();

class RedesignedApp extends StatelessWidget {
  const RedesignedApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tudo Aqui Macacu',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: soft,
      colorScheme: ColorScheme.fromSeed(
        seedColor: sky,
        primary: sky,
        secondary: orange,
        surface: Colors.white,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(),
      appBarTheme: const AppBarTheme(
        backgroundColor: soft,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: sky,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
    ),
    home: const AppStartupGate(),
  );
}

const adminEmail = 'bru.mourris69@gmail.com';
const googleWebClientId =
    '801555679675-qvtghgv9sa65ipgls4usukru33uk3aec.apps.googleusercontent.com';

bool isAdminUser(User? user) => user?.email?.toLowerCase() == adminEmail;

Future<void> syncUserProfile(User user) async {
  try {
    final ref = FirebaseFirestore.instance
        .collection(FirestoreCollections.users)
        .doc(user.uid);
    final snapshot = await ref.get();
    await ref.set({
      'displayName': user.displayName ?? '',
      'email': user.email ?? '',
      'photoUrl': user.photoURL ?? '',
      'role': isAdminUser(user) ? 'admin' : 'user',
      'updatedAt': FieldValue.serverTimestamp(),
      if (!snapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } on FirebaseException catch (error) {
    debugPrint('Perfil Firebase não sincronizado: ${error.code}');
  }
}

bool isActiveContent(Map<String, dynamic> data) {
  final expiresAt = data['expiresAt'];
  if (expiresAt is! Timestamp) return true;
  return expiresAt.toDate().isAfter(DateTime.now());
}

List<String> contentImageUrls(Map<String, dynamic> data) {
  final gallery = ((data['galleryUrls'] as List?) ?? const [])
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .map(cloudinaryOptimizedImageUrl)
      .toList();
  final cover = cloudinaryOptimizedImageUrl(
    (data['imageUrl'] ?? '').toString(),
  );
  if (cover.isNotEmpty) {
    gallery.remove(cover);
    gallery.insert(0, cover);
  }
  return gallery;
}

String localContentMeta(Map<String, dynamic> data) {
  final parts = [
    (data['eventDate'] ?? data['date'] ?? '').toString(),
    (data['location'] ?? data['address'] ?? '').toString(),
    (data['contact'] ?? '').toString(),
  ].map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
  return parts.join(' · ');
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
    _tokenSubscription = messaging.onTokenRefresh.listen(
      (token) => _saveToken(user.uid, token),
    );
    await _foregroundSubscription?.cancel();
    _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${notification.title ?? 'Tudo Aqui Macacu'}: ${notification.body ?? ''}',
            ),
          ),
        );
      }
    });
  }

  static Future<void> deactivate(User user) async {
    final messaging = FirebaseMessaging.instance;
    await _foregroundSubscription?.cancel();
    await _tokenSubscription?.cancel();
    _foregroundSubscription = null;
    _tokenSubscription = null;
    try {
      final token = await messaging.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection(FirestoreCollections.users)
            .doc(user.uid)
            .collection(FirestoreCollections.devices)
            .doc(token)
            .delete();
      }
    } on FirebaseException catch (error) {
      debugPrint('Token FCM não removido: ${error.code}');
    }
    try {
      await messaging.deleteToken();
    } catch (error) {
      debugPrint('Token FCM local não apagado: $error');
    }
  }

  static Future<void> _saveToken(String uid, String token) => FirebaseFirestore
      .instance
      .collection(FirestoreCollections.users)
      .doc(uid)
      .collection(FirestoreCollections.devices)
      .doc(token)
      .set({
        'token': token,
        'platform': 'android',
        'active': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}

class AppStartupGate extends StatefulWidget {
  const AppStartupGate({super.key});

  @override
  State<AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends State<AppStartupGate> {
  double progress = 0;
  bool ready = false;
  Object? startupError;
  int startupAttempts = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start({bool manual = false}) async {
    if (manual) startupAttempts = 0;
    if (!mounted) return;
    setState(() {
      ready = false;
      startupError = null;
      progress = 0;
    });
    try {
      _setProgress(.08);
      await precacheImage(const AssetImage(splashBackgroundAsset), context);
      _setProgress(.22);

      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _setProgress(.58);

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        unawaited(syncUserProfile(user));
      }
      _setProgress(.74);

      await _warmEssentialConfig();
      _setProgress(1);

      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (!mounted) return;
      setState(() => ready = true);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'Tudo Aqui Macacu startup',
        ),
      );
      if (!mounted) return;
      startupAttempts += 1;
      if (startupAttempts < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
        if (mounted) unawaited(_start());
        return;
      }
      if (Firebase.apps.isNotEmpty) {
        setState(() => ready = true);
        return;
      }
      setState(() => startupError = error);
    }
  }

  void _setProgress(double value) {
    if (!mounted) return;
    setState(() => progress = value.clamp(0, 1));
  }

  Future<void> _warmEssentialConfig() async {
    try {
      await FirebaseFirestore.instance
          .collection(FirestoreCollections.homePages)
          .doc('published')
          .get()
          .timeout(const Duration(seconds: 2));
    } catch (error) {
      debugPrint('Configuração inicial não pré-carregada: $error');
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 420),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    child: ready
        ? const AuthGate(key: ValueKey('auth-gate'))
        : SplashLoadingScreen(
            key: const ValueKey('splash-loading'),
            progress: progress,
            error: startupError,
            onRetry: () => _start(manual: true),
          ),
  );
}

class SplashLoadingScreen extends StatelessWidget {
  const SplashLoadingScreen({
    super.key,
    required this.progress,
    required this.error,
    required this.onRetry,
  });

  final double progress;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(splashBackgroundAsset, fit: BoxFit.cover),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 34),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (error != null) ...[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .92),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Não foi possível iniciar agora.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: onRetry,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Tentar novamente'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  SplashProgressBar(value: progress),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class SplashProgressBar extends StatelessWidget {
  const SplashProgressBar({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.clamp(180.0, 420.0);
      return Center(
        child: SizedBox(
          width: width,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0, 1)),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            builder: (context, animatedValue, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 8,
                    color: Colors.white.withValues(alpha: .30),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: animatedValue,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [sky, orange],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${(animatedValue * 100).round().clamp(0, 100)}%',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .86),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
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
      final user = snapshot.data;
      return CityShell(key: ValueKey(user?.uid ?? 'guest'), user: user);
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
  bool success = false;
  String? error;
  Future<void> signIn() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final account = await GoogleSignIn(
        serverClientId: googleWebClientId,
      ).signIn();
      if (account == null) {
        return;
      }
      final auth = await account.authentication;
      if (auth.idToken == null) {
        throw StateError('Google não retornou o ID token');
      }
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      final result = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      if (result.user != null) await syncUserProfile(result.user!);
      if (!mounted) return;
      setState(() {
        success = true;
        loading = false;
      });
      await Future<void>.delayed(const Duration(milliseconds: 850));
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      debugPrint(
        'Google login FirebaseAuthException: ${e.code} - ${e.message}',
      );
      if (mounted) {
        setState(
          () => error = e.code == 'account-exists-with-different-credential'
              ? 'Esta conta já usa outra forma de acesso. Tente novamente com a mesma conta Google.'
              : 'Não foi possível concluir o login agora. Tente novamente.',
        );
      }
    } catch (e) {
      debugPrint('Google login falhou: $e');
      final details = e.toString();
      if (mounted) {
        setState(
          () => error =
              details.contains('ApiException: 10') ||
                  details.contains('DEVELOPER_ERROR')
              ? 'Este APK ainda não foi reconhecido pelo Google. Instale a versão mais nova e tente novamente.'
              : 'Não foi possível entrar com o Google. Verifique sua conexão e tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => success
      ? const LoginSuccessView()
      : Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Brand(),
                  const SizedBox(height: 34),
                  const Icon(
                    Icons.account_circle_rounded,
                    color: sky,
                    size: 82,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Personalize sua experiência',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Você pode explorar Macacu sem conta. Entre para salvar favoritos e receber novidades.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 22),
                  App3DButton(
                    onPressed: loading ? null : signIn,
                    icon: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.login_rounded),
                    label: 'Continuar com Google',
                  ),
                ],
              ),
            ),
          ),
        );
}

class LoginSuccessView extends StatelessWidget {
  const LoginSuccessView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TweenAnimationBuilder<double>(
      tween: Tween(begin: .96, end: 1),
      duration: const Duration(milliseconds: 560),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) => Opacity(
        opacity: ((scale - .96) / .04).clamp(0, 1),
        child: Transform.scale(scale: scale, child: child),
      ),
      child: Image.asset(loginSuccessBackgroundAsset, fit: BoxFit.cover),
    ),
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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  favoritesSubscription;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    if (user != null) {
      unawaited(syncUserProfile(user));
      unawaited(PushService.activate(user, context));
      favoritesSubscription = FirebaseFirestore.instance
          .collection(FirestoreCollections.users)
          .doc(user.uid)
          .collection(FirestoreCollections.favorites)
          .snapshots()
          .listen(
            (snapshot) {
              if (!mounted) return;
              setState(() {
                saved
                  ..clear()
                  ..addAll(snapshot.docs.map((doc) => doc.id));
                for (final doc in snapshot.docs) {
                  final legacyName = (doc.data()['name'] ?? '').toString();
                  if (legacyName.isNotEmpty) saved.add(legacyName);
                }
              });
            },
            onError: (Object error, StackTrace stackTrace) {
              debugPrint('Favoritos Firebase indisponíveis: $error');
            },
          );
    }
  }

  void favorite(Business business) {
    final user = widget.user;
    final key = business.favoriteKey;
    final legacyKey = business.name;
    final currentlySaved = saved.contains(key) || saved.contains(legacyKey);
    if (user == null) {
      setState(() {
        if (currentlySaved) {
          saved
            ..remove(key)
            ..remove(legacyKey);
        } else {
          saved.add(key);
        }
      });
      return;
    }
    final ref = FirebaseFirestore.instance
        .collection(FirestoreCollections.users)
        .doc(user.uid)
        .collection(FirestoreCollections.favorites)
        .doc(key);
    final legacyRef = FirebaseFirestore.instance
        .collection(FirestoreCollections.users)
        .doc(user.uid)
        .collection(FirestoreCollections.favorites)
        .doc(legacyKey);
    if (currentlySaved) {
      unawaited(
        Future.wait([ref.delete(), if (legacyKey != key) legacyRef.delete()])
            .then(
              (_) => recordMetric(
                'favorite_remove',
                target: key,
                targetType: 'business',
              ),
            )
            .catchError((_) => _showFavoriteError()),
      );
    } else {
      unawaited(
        ref
            .set({
              'id': key,
              'name': business.name,
              'updatedAt': FieldValue.serverTimestamp(),
            })
            .then(
              (_) => recordMetric(
                'favorite_add',
                target: key,
                targetType: 'business',
              ),
            )
            .catchError((_) => _showFavoriteError()),
      );
    }
  }

  void _showFavoriteError() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível salvar agora. Tente novamente em instantes.',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    favoritesSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeView(
        saved: saved,
        favorite: favorite,
        showExplore: () => setState(() => tab = 1),
        user: widget.user,
      ),
      ExploreView(saved: saved, favorite: favorite),
      const PublicServicesView(),
      SavedView(saved: saved, favorite: favorite),
      ProfileView(count: saved.length, user: widget.user),
    ];
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: tab, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        indicatorColor: mist,
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Explorar',
          ),
          NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public_rounded),
            label: 'Utilidades',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: 'Favoritos',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

String _homeSectionName(String key) =>
    const {
      'banner': 'Banners',
      'categories': 'Categorias',
      'highlights': 'Destaques',
      'offers': 'Ofertas',
      'resources': 'Utilidades',
      'jobs': 'Empregos',
      'events': 'Eventos e notícias',
      'eventsAgenda': 'Agenda',
      'tourism': 'Turismo',
    }[key] ??
    key;

class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
    required this.saved,
    required this.favorite,
    required this.showExplore,
    required this.user,
  });
  final Set<String> saved;
  final ValueChanged<Business> favorite;
  final VoidCallback showExplore;
  final User? user;
  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  bool editMode = false;

  Future<void> _refresh() => FirebaseFirestore.instance
      .collection(FirestoreCollections.homePages)
      .doc('published')
      .get(const GetOptions(source: Source.server))
      .then((_) {});

  bool get _isAdmin => isAdminUser(widget.user);

  Future<void> _saveHomeQuick(
    Map<String, dynamic> data, {
    required String label,
    required bool publish,
  }) async {
    if (!_isAdmin) return;
    final db = FirebaseFirestore.instance;
    final payload = {...data, 'updatedAt': FieldValue.serverTimestamp()};
    await db
        .collection(FirestoreCollections.homePages)
        .doc('draft')
        .set(payload, SetOptions(merge: true));
    if (publish) {
      await db.collection(FirestoreCollections.homePages).doc('published').set({
        ...payload,
        'publishedAt': FieldValue.serverTimestamp(),
        'version': FieldValue.increment(1),
      }, SetOptions(merge: true));
    }
    await recordAdminAudit(
      action: publish ? 'visual_publish_home' : 'visual_save_home_draft',
      collection: 'home_pages',
      documentId: publish ? 'published' : 'draft',
      label: label,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          publish
              ? 'Alteração publicada na Home.'
              : 'Rascunho salvo. Revise antes de publicar.',
        ),
      ),
    );
  }

  Future<void> _editHero(HomePageConfig page) async {
    final data = _editableHomeData(page);
    final title = TextEditingController(text: page.heroTitle);
    final search = TextEditingController(text: page.searchPlaceholder);
    final greeting = TextEditingController(text: page.greeting);
    final location = TextEditingController(text: page.location);
    await _showHomeQuickSheet(
      title: 'Editar topo da Home',
      children: [
        TextField(
          controller: title,
          decoration: _quickField('Título principal'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: search,
          decoration: _quickField('Texto da busca'),
        ),
        const SizedBox(height: 12),
        TextField(controller: greeting, decoration: _quickField('Saudação')),
        const SizedBox(height: 12),
        TextField(controller: location, decoration: _quickField('Localização')),
      ],
      onSaveDraft: () {
        data['heroTitle'] = title.text.trim();
        data['searchPlaceholder'] = search.text.trim();
        data['visual'] = {
          ...Map<String, dynamic>.from(data['visual'] as Map),
          'greeting': greeting.text.trim(),
          'location': location.text.trim(),
        };
        return _saveHomeQuick(
          data,
          label: 'Topo da Home editado',
          publish: false,
        );
      },
      onPublish: () {
        data['heroTitle'] = title.text.trim();
        data['searchPlaceholder'] = search.text.trim();
        data['visual'] = {
          ...Map<String, dynamic>.from(data['visual'] as Map),
          'greeting': greeting.text.trim(),
          'location': location.text.trim(),
        };
        return _saveHomeQuick(
          data,
          label: 'Topo da Home publicado',
          publish: true,
        );
      },
    );
    title.dispose();
    search.dispose();
    greeting.dispose();
    location.dispose();
  }

  Future<void> _editVisual(HomePageConfig page) async {
    final data = _editableHomeData(page);
    final logo = TextEditingController(text: page.logoUrl);
    final image = TextEditingController(text: page.backgroundImageUrl);
    final start = TextEditingController(text: page.backgroundStart);
    final end = TextEditingController(text: page.backgroundEnd);
    var type = page.backgroundType;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              18,
              18,
              MediaQuery.of(context).viewInsets.bottom + 18,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _quickSheetHeader('Identidade visual'),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: _quickField('Tipo de fundo'),
                    items: const [
                      DropdownMenuItem(
                        value: 'gradient',
                        child: Text('Gradiente'),
                      ),
                      DropdownMenuItem(
                        value: 'color',
                        child: Text('Cor sólida'),
                      ),
                      DropdownMenuItem(value: 'image', child: Text('Imagem')),
                    ],
                    onChanged: (value) =>
                        setSheetState(() => type = value ?? 'gradient'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: logo,
                    decoration: _quickField('Logo URL'),
                  ),
                  const SizedBox(height: 12),
                  const CloudinaryUploadHelper(
                    description:
                        'Suba o logo no Cloudinary e cole aqui a URL para atualizar a identidade visual.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: start,
                    decoration: _quickField('Cor inicial'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: end,
                    decoration: _quickField('Cor final'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: image,
                    keyboardType: TextInputType.url,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: _quickField('Imagem de fundo URL Cloudinary'),
                  ),
                  const SizedBox(height: 12),
                  const CloudinaryUploadHelper(
                    description:
                        'Suba a imagem no Cloudinary e cole aqui a URL para trocar o fundo da Home.',
                  ),
                  const SizedBox(height: 12),
                  HomeImagePreview(
                    url: image.text.trim(),
                    onRemove: () {
                      image.clear();
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 18),
                  _quickSaveButtons(
                    onDraft: () {
                      data['visual'] = {
                        ...Map<String, dynamic>.from(data['visual'] as Map),
                        'logoUrl': logo.text.trim(),
                        'backgroundType': type,
                        'backgroundStart': start.text.trim(),
                        'backgroundEnd': end.text.trim(),
                        'backgroundImageUrl': image.text.trim(),
                      };
                      return _saveHomeQuick(
                        data,
                        label: 'Visual da Home editado',
                        publish: false,
                      );
                    },
                    onPublish: () {
                      data['visual'] = {
                        ...Map<String, dynamic>.from(data['visual'] as Map),
                        'logoUrl': logo.text.trim(),
                        'backgroundType': type,
                        'backgroundStart': start.text.trim(),
                        'backgroundEnd': end.text.trim(),
                        'backgroundImageUrl': image.text.trim(),
                      };
                      return _saveHomeQuick(
                        data,
                        label: 'Visual da Home publicado',
                        publish: true,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    logo.dispose();
    image.dispose();
    start.dispose();
    end.dispose();
  }

  Future<void> _editSections(HomePageConfig page) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HomeSectionsQuickEditor(
        page: page,
        onSave: (data, {required label, required publish}) =>
            _saveHomeQuick(data, label: label, publish: publish),
      ),
    );
  }

  Future<void> _editSectionTitle(HomePageConfig page, String section) async {
    final data = _editableHomeData(page);
    final title = TextEditingController(
      text: section == 'eventsAgenda'
          ? page.eventAgendaTitle
          : page.titleFor(section),
    );
    await _showHomeQuickSheet(
      title: 'Editar ${_homeSectionName(section)}',
      children: [
        TextField(
          controller: title,
          decoration: _quickField('Título da seção'),
        ),
      ],
      onSaveDraft: () {
        data['sectionTitles'] = {
          ...Map<String, dynamic>.from(data['sectionTitles'] as Map),
          section: title.text.trim(),
        };
        return _saveHomeQuick(
          data,
          label: 'Título da seção ${_homeSectionName(section)} editado',
          publish: false,
        );
      },
      onPublish: () {
        data['sectionTitles'] = {
          ...Map<String, dynamic>.from(data['sectionTitles'] as Map),
          section: title.text.trim(),
        };
        return _saveHomeQuick(
          data,
          label: 'Título da seção ${_homeSectionName(section)} publicado',
          publish: true,
        );
      },
    );
    title.dispose();
  }

  InputDecoration _quickField(String label) =>
      InputDecoration(labelText: label, border: const OutlineInputBorder());

  Widget _quickSheetHeader(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        IconButton(
          tooltip: 'Fechar',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );

  Widget _quickSaveButtons({
    required Future<void> Function() onDraft,
    required Future<void> Function() onPublish,
  }) => Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () async {
            await onDraft();
            if (mounted) Navigator.pop(context);
          },
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Salvar rascunho'),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: FilledButton.icon(
          onPressed: () async {
            await onPublish();
            if (mounted) Navigator.pop(context);
          },
          icon: const Icon(Icons.publish_rounded),
          label: const Text('Publicar'),
        ),
      ),
    ],
  );

  Future<void> _showHomeQuickSheet({
    required String title,
    required List<Widget> children,
    required Future<void> Function() onSaveDraft,
    required Future<void> Function() onPublish,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          18,
          18,
          MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _quickSheetHeader(title),
              ...children,
              const SizedBox(height: 18),
              _quickSaveButtons(onDraft: onSaveDraft, onPublish: onPublish),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(FirestoreCollections.homePages)
            .doc('published')
            .snapshots(),
        builder: (context, snapshot) {
          final config = snapshot.data?.data() ?? const <String, dynamic>{};
          final page = HomePageConfig.fromMap(config);
          final isEditing = _isAdmin && editMode;
          final slivers = <Widget>[
            SliverToBoxAdapter(
              child: WelcomeHero(
                onSearch: () =>
                    showSearch(context: context, delegate: CitySearch()),
                user: widget.user,
                config: page,
                editMode: isEditing,
                onToggleEditMode: _isAdmin
                    ? () => setState(() => editMode = !editMode)
                    : null,
                onEditHero: isEditing ? () => _editHero(page) : null,
                onEditVisual: isEditing ? () => _editVisual(page) : null,
              ),
            ),
          ];
          if (_isAdmin) {
            slivers.add(
              SliverToBoxAdapter(
                child: HomeAdminEditBar(
                  active: editMode,
                  onToggle: () => setState(() => editMode = !editMode),
                  onSections: editMode ? () => _editSections(page) : null,
                  onFullEditor: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const HomeEditor())),
                ),
              ),
            );
          }
          for (final section in page.order) {
            if (!page.enabled(section)) continue;
            final content = _section(context, section, page, isEditing);
            if (content != null) {
              slivers.add(SliverToBoxAdapter(child: content));
            }
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: slivers,
            ),
          );
        },
      );

  Widget? _section(
    BuildContext context,
    String section,
    HomePageConfig page,
    bool isEditing,
  ) {
    final title = page.titleFor(section);
    final amount = page.limitFor(section);
    switch (section) {
      case 'banner':
        return EditableHomeArea(
          enabled: isEditing,
          label: 'Banners',
          onEdit: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  const ContentManager(collection: 'ads', title: 'Banners'),
            ),
          ),
          child: const AdCarousel(),
        );
      case 'categories':
        final ordered = page.categories(homeCatalog).take(amount).toList();
        return Column(
          children: [
            SectionTitle(
              title: title,
              action: 'Ver todas',
              onTap: widget.showExplore,
              editMode: isEditing,
              onEdit: () => _editSectionTitle(page, section),
            ),
            SizedBox(
              height: 103,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                scrollDirection: Axis.horizontal,
                itemCount: ordered.length,
                separatorBuilder: (_, _) => const SizedBox(width: 9),
                itemBuilder: (_, i) => CategoryTile(
                  category: ordered[i],
                  onTap: () => openDirectory(context, ordered[i]),
                ),
              ),
            ),
          ],
        );
      case 'highlights':
        return Column(
          children: [
            SectionTitle(
              title: title,
              action: 'Ver todos',
              onTap: widget.showExplore,
              editMode: isEditing,
              onEdit: () => _editSectionTitle(page, section),
            ),
            PublishedBusinessStrip(
              repository: businessRepository,
              fallbackBusinesses: featured,
              saved: widget.saved,
              favorite: widget.favorite,
              limit: amount,
              cardBuilder: (context, business, saved, onFavorite) =>
                  BusinessCard(
                    business: business,
                    saved: saved,
                    onFavorite: onFavorite,
                    onOpen: () => _openBusinessProfileFromCard(
                      context,
                      business,
                      saved: saved,
                      onFavorite: onFavorite,
                      recordOpenMetric: true,
                    ),
                    onViewBusiness: () => _openBusinessProfileFromCard(
                      context,
                      business,
                      saved: saved,
                      onFavorite: onFavorite,
                      recordOpenMetric: false,
                    ),
                    onWhatsApp: () =>
                        _openBusinessWhatsAppFromCard(context, business),
                    compact: true,
                  ),
            ),
          ],
        );
      case 'offers':
        return Column(
          children: [
            SectionTitle(
              title: title,
              action: 'Ver ofertas',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const OffersView())),
              editMode: isEditing,
              onEdit: () => _editSectionTitle(page, section),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: OfferBanner(),
            ),
          ],
        );
      case 'resources':
        return Column(
          children: [
            SectionTitle(
              title: title,
              action: 'Ver cupons',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const CouponsView())),
              editMode: isEditing,
              onEdit: () => _editSectionTitle(page, section),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: ResourcesPreview(),
            ),
          ],
        );
      case 'jobs':
        return Column(
          children: [
            SectionTitle(
              title: title,
              action: 'Ver todas',
              onTap: () => openFeature(context, Feature.jobs),
              editMode: isEditing,
              onEdit: () => _editSectionTitle(page, section),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: jobs
                    .take(amount)
                    .map(
                      (job) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: JobCard(job: job),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        );
      case 'events':
        return Column(
          children: [
            SectionTitle(
              title: title,
              action: 'Ver notícias',
              onTap: () => openFeature(context, Feature.news),
              editMode: isEditing,
              onEdit: () => _editSectionTitle(page, section),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: LocalNewsCard(),
            ),
            SectionTitle(
              title: page.eventAgendaTitle,
              action: 'Ver agenda',
              onTap: () => openFeature(context, Feature.events),
              editMode: isEditing,
              onEdit: () => _editSectionTitle(page, 'eventsAgenda'),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: EventCard(),
            ),
          ],
        );
      case 'tourism':
        return Column(
          children: [
            SectionTitle(
              title: title,
              action: 'Explorar agora',
              onTap: () => openFeature(context, Feature.tourism),
              editMode: isEditing,
              onEdit: () => _editSectionTitle(page, section),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              child: NatureBanner(
                onTap: () => openFeature(context, Feature.tourism),
              ),
            ),
          ],
        );
    }
    return null;
  }
}

Map<String, dynamic> _editableHomeData(HomePageConfig page) => {
  'heroTitle': page.heroTitle,
  'searchPlaceholder': page.searchPlaceholder,
  'sections': {for (final key in defaultHomeOrder) key: page.enabled(key)},
  'sectionOrder': [
    ...page.order.where(defaultHomeOrder.contains),
    ...defaultHomeOrder.where((key) => !page.order.contains(key)),
  ],
  'sectionTitles': {
    for (final key in defaultHomeOrder) key: page.titleFor(key),
    'eventsAgenda': page.eventAgendaTitle,
  },
  'sectionLimits': {
    for (final key in defaultHomeOrder) key: page.limitFor(key),
  },
  'categoryOrder': page
      .categories(homeCatalog)
      .map((item) => item.name)
      .toList(),
  'categoryIcons': {
    for (final category in page.categories(homeCatalog))
      category.name: category.artwork,
  },
  'visual': {
    ...page.visual,
    'slogan': page.slogan,
    'greeting': page.greeting,
    'location': page.location,
    'logoUrl': page.logoUrl,
    'backgroundType': page.backgroundType,
    'backgroundStart': page.backgroundStart,
    'backgroundEnd': page.backgroundEnd,
    'backgroundImageUrl': page.backgroundImageUrl,
  },
};

Color _homeColor(String raw, Color fallback) {
  final cleaned = raw.replaceAll('#', '').trim();
  if (cleaned.length != 6 || int.tryParse(cleaned, radix: 16) == null) {
    return fallback;
  }
  return Color(0xFF000000 | int.parse(cleaned, radix: 16));
}

ImageProvider? _homeBackgroundImageProvider(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return NetworkImage(cloudinaryOptimizedImageUrl(value));
  }
  return AssetImage(value);
}

class HomeSectionsQuickEditor extends StatefulWidget {
  const HomeSectionsQuickEditor({
    super.key,
    required this.page,
    required this.onSave,
  });

  final HomePageConfig page;
  final Future<void> Function(
    Map<String, dynamic> data, {
    required String label,
    required bool publish,
  })
  onSave;

  @override
  State<HomeSectionsQuickEditor> createState() =>
      _HomeSectionsQuickEditorState();
}

class _HomeSectionsQuickEditorState extends State<HomeSectionsQuickEditor> {
  late final Map<String, TextEditingController> titles;
  late final Map<String, bool> enabled;
  late final List<String> order;
  late Map<String, dynamic> data;

  @override
  void initState() {
    super.initState();
    data = _editableHomeData(widget.page);
    titles = {
      for (final key in defaultHomeOrder)
        key: TextEditingController(text: widget.page.titleFor(key)),
    };
    enabled = {
      for (final key in defaultHomeOrder) key: widget.page.enabled(key),
    };
    order = [
      ...widget.page.order.where(defaultHomeOrder.contains),
      ...defaultHomeOrder.where((key) => !widget.page.order.contains(key)),
    ];
  }

  @override
  void dispose() {
    for (final controller in titles.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save({required bool publish}) async {
    data = {
      ...data,
      'sectionOrder': List<String>.from(order),
      'sections': Map<String, bool>.from(enabled),
      'sectionTitles': {
        for (final key in defaultHomeOrder) key: titles[key]!.text.trim(),
      },
    };
    await widget.onSave(
      data,
      label: publish ? 'Seções da Home publicadas' : 'Seções da Home editadas',
      publish: publish,
    );
    if (mounted) Navigator.pop(context);
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final item = order.removeAt(oldIndex);
      order.insert(newIndex, item);
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        18,
        18,
        MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Seções da Home',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Text(
              'Arraste para reorganizar. Nada é salvo até tocar em salvar.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ReorderableListView.builder(
                itemCount: order.length,
                buildDefaultDragHandles: false,
                onReorderItem: _reorder,
                itemBuilder: (context, index) {
                  final section = order[index];
                  return KeyedSubtree(
                    key: ValueKey('home-section-editor-$section'),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          children: [
                            SwitchListTile(
                              value: enabled[section] ?? true,
                              onChanged: (value) =>
                                  setState(() => enabled[section] = value),
                              title: Text(
                                _homeSectionName(section),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              secondary: ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle_rounded),
                              ),
                            ),
                            TextField(
                              key: ValueKey('home-section-title-$section'),
                              controller: titles[section],
                              decoration: const InputDecoration(
                                labelText: 'Título exibido',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _save(publish: false),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Salvar rascunho'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _save(publish: true),
                    icon: const Icon(Icons.publish_rounded),
                    label: const Text('Publicar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class WelcomeHero extends StatelessWidget {
  const WelcomeHero({
    super.key,
    required this.onSearch,
    required this.user,
    required this.config,
    this.editMode = false,
    this.onToggleEditMode,
    this.onEditHero,
    this.onEditVisual,
  });
  final VoidCallback onSearch;
  final User? user;
  final HomePageConfig config;
  final bool editMode;
  final VoidCallback? onToggleEditMode, onEditHero, onEditVisual;
  @override
  Widget build(BuildContext context) {
    final background = config.backgroundImageUrl.isNotEmpty
        ? config.backgroundType
        : config.backgroundType == 'image'
        ? 'gradient'
        : config.backgroundType;
    final start = _homeColor(config.backgroundStart, const Color(0xFFEAF4FF));
    final end = _homeColor(config.backgroundEnd, soft);
    final imageUrl = config.backgroundImageUrl;
    final imageProvider = _homeBackgroundImageProvider(imageUrl);
    final greetingText = user == null
        ? config.greeting.trim()
        : 'Olá, ${user!.displayName?.split(' ').first ?? 'Visitante'}!';
    final showGreeting =
        greetingText.isNotEmpty &&
        greetingText.toLowerCase() != config.slogan.trim().toLowerCase() &&
        greetingText.toLowerCase() != config.heroTitle.trim().toLowerCase();
    final heroTextShadow = background == 'image'
        ? [
            Shadow(
              color: ink.withValues(alpha: .58),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ]
        : const <Shadow>[];
    return Container(
      decoration: BoxDecoration(
        color: background == 'color' ? start : null,
        gradient: background == 'gradient'
            ? LinearGradient(
                colors: [start, end],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        image: background == 'image' && imageProvider != null
            ? DecorationImage(
                image: imageProvider,
                fit: BoxFit.cover,
                onError: (_, _) {},
              )
            : null,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        decoration: background == 'image'
            ? BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    ink.withValues(alpha: .56),
                    ink.withValues(alpha: .30),
                    ink.withValues(alpha: .18),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: const [0, .52, 1],
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(30),
                ),
              )
            : const BoxDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DynamicBrand(
                    logoUrl: config.logoUrl,
                    slogan: config.slogan,
                    imageBackground: background == 'image',
                  ),
                ),
                const SizedBox(width: 10),
                CircleIcon(
                  icon: Icons.notifications_none_rounded,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NotificationsView(),
                    ),
                  ),
                ),
                if (isAdminUser(user)) ...[
                  const SizedBox(width: 8),
                  CircleIcon(
                    icon: editMode
                        ? Icons.admin_panel_settings_rounded
                        : Icons.edit_outlined,
                    onTap: onToggleEditMode,
                  ),
                ],
              ],
            ),
            SizedBox(height: showGreeting ? 16 : 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showGreeting) ...[
                        Text(
                          greetingText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: background == 'image' ? orange : ocean,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .1,
                            shadows: heroTextShadow,
                          ),
                        ),
                        const SizedBox(height: 5),
                      ],
                      Text(
                        config.heroTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: background == 'image' ? Colors.white : ink,
                              fontWeight: FontWeight.w900,
                              height: 1.02,
                              letterSpacing: -.45,
                              shadows: heroTextShadow,
                            ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        config.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: background == 'image'
                              ? Colors.white.withValues(alpha: .90)
                              : muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          shadows: heroTextShadow,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                HomeWeatherChip(imageBackground: background == 'image'),
              ],
            ),
            const SizedBox(height: 16),
            Material(
              color: Colors.white,
              elevation: 7,
              shadowColor: ocean.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: onSearch,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 33,
                        height: 33,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [orange, yellow],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.search_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          config.searchPlaceholder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(Icons.tune_rounded, color: ocean, size: 21),
                    ],
                  ),
                ),
              ),
            ),
            if (editMode) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  HomeEditChip(
                    icon: Icons.text_fields_rounded,
                    label: 'Textos',
                    onTap: onEditHero,
                  ),
                  const SizedBox(width: 8),
                  HomeEditChip(
                    icon: Icons.wallpaper_rounded,
                    label: 'Visual',
                    onTap: onEditVisual,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HomeEditChip extends StatelessWidget {
  const HomeEditChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: Icon(icon, color: Colors.white, size: 16),
    label: Text(label),
    labelStyle: const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w800,
    ),
    backgroundColor: ocean,
    side: BorderSide.none,
    visualDensity: VisualDensity.compact,
    onPressed: onTap,
  );
}

class HomeAdminEditBar extends StatelessWidget {
  const HomeAdminEditBar({
    super.key,
    required this.active,
    required this.onToggle,
    required this.onSections,
    required this.onFullEditor,
  });
  final bool active;
  final VoidCallback onToggle;
  final VoidCallback? onSections;
  final VoidCallback onFullEditor;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: active ? const Color(0xFFFFF3E8) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: active ? orange : sky.withValues(alpha: .12)),
    ),
    child: Row(
      children: [
        Icon(
          active ? Icons.admin_panel_settings_rounded : Icons.lock_outline,
          color: active ? orange : ocean,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            active ? 'Modo administrativo ativo' : 'Modo administrativo',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, color: ink),
          ),
        ),
        IconButton(
          tooltip: active ? 'Editar seções' : 'Ativar edição visual',
          onPressed: active ? onSections : onToggle,
          icon: Icon(active ? Icons.view_agenda_outlined : Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Editor completo',
          onPressed: onFullEditor,
          icon: const Icon(Icons.open_in_new_rounded),
        ),
      ],
    ),
  );
}

class EditableHomeArea extends StatelessWidget {
  const EditableHomeArea({
    super.key,
    required this.enabled,
    required this.label,
    required this.onEdit,
    required this.child,
  });
  final bool enabled;
  final String label;
  final VoidCallback onEdit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            border: Border.all(color: orange.withValues(alpha: .55)),
            borderRadius: BorderRadius.circular(24),
          ),
          child: child,
        ),
        Positioned(
          top: 0,
          right: 18,
          child: FilledButton.tonalIcon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded, size: 16),
            label: Text(label),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              backgroundColor: const Color(0xFFFFF3E8),
              foregroundColor: orange,
            ),
          ),
        ),
      ],
    );
  }
}

class HomeImagePreview extends StatelessWidget {
  const HomeImagePreview({
    super.key,
    required this.url,
    required this.onRemove,
  });
  final String url;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: mist,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'Sem imagem selecionada. Use uma URL do Cloudinary.',
          style: TextStyle(color: muted),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 16 / 7,
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: mist,
                child: Center(child: Text('Não foi possível carregar preview')),
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: IconButton.filled(
              tooltip: 'Remover imagem',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class CloudinaryUploadHelper extends StatelessWidget {
  const CloudinaryUploadHelper({
    super.key,
    this.title = 'Enviar imagem pelo Cloudinary',
    this.description =
        'Abra o Cloudinary, envie a imagem e cole a URL gerada neste campo.',
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFEFF6FF),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFD8E8FF)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, color: ink),
        ),
        const SizedBox(height: 6),
        Text(description, style: const TextStyle(color: muted, height: 1.35)),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () =>
              openUrl(context, 'https://console.cloudinary.com/', 'Cloudinary'),
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('Abrir Cloudinary'),
        ),
      ],
    ),
  );
}

class HomeWeatherChip extends StatelessWidget {
  const HomeWeatherChip({super.key, required this.imageBackground});
  final bool imageBackground;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: imageBackground
          ? Colors.white.withValues(alpha: .18)
          : Colors.white.withValues(alpha: .78),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: imageBackground
            ? Colors.white.withValues(alpha: .22)
            : sky.withValues(alpha: .12),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.wb_sunny_rounded, color: yellow, size: 16),
        const SizedBox(width: 5),
        Text(
          '26° · Macacu',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: imageBackground ? Colors.white : ink,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class DynamicBrand extends StatelessWidget {
  const DynamicBrand({
    super.key,
    required this.logoUrl,
    required this.slogan,
    this.imageBackground = false,
  });

  final String logoUrl, slogan;
  final bool imageBackground;

  @override
  Widget build(BuildContext context) {
    final titleShadow = imageBackground
        ? [
            Shadow(
              color: ink.withValues(alpha: .55),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ]
        : const <Shadow>[];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: logoUrl.isEmpty
              ? Image.asset(
                  'assets/images/tudo-aqui-macacu-icon-v1.png',
                  width: 39,
                  height: 39,
                  fit: BoxFit.cover,
                )
              : Image.network(
                  logoUrl,
                  width: 39,
                  height: 39,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Image.asset(
                    'assets/images/tudo-aqui-macacu-icon-v1.png',
                    width: 39,
                    height: 39,
                    fit: BoxFit.cover,
                  ),
                ),
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  style: TextStyle(
                    color: imageBackground ? Colors.white : ink,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    fontSize: 14,
                    shadows: titleShadow,
                  ),
                  children: [
                    const TextSpan(text: 'Tudo Aqui '),
                    TextSpan(
                      text: 'Macacu',
                      style: TextStyle(color: imageBackground ? orange : ink),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                slogan,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: imageBackground
                      ? Colors.white.withValues(alpha: .92)
                      : muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  shadows: imageBackground
                      ? [
                          Shadow(
                            color: ink.withValues(alpha: .55),
                            blurRadius: 7,
                            offset: const Offset(0, 1.5),
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AdCarousel extends StatefulWidget {
  const AdCarousel({super.key});
  @override
  State<AdCarousel> createState() => _AdCarouselState();
}

class _AdCarouselState extends State<AdCarousel> {
  static const double bannerHeight = 206;
  final controller = PageController(viewportFraction: .9);
  int page = 0;
  final fallbackAds = const [
    'Anuncie aqui',
    'Destaque sua empresa',
    'Oferta da semana',
    'Conheça Macacu',
    'Comércio local',
    'Serviços em destaque',
    'Gastronomia',
    'Turismo',
    'Eventos',
    'Sua marca aqui',
  ];
  @override
  void initState() {
    super.initState();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted) return false;
      final count = controller.positions.isEmpty
          ? fallbackAds.length
          : (controller.page == null ? fallbackAds.length : fallbackAds.length);
      page = (page + 1) % count;
      controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
      );
      return true;
    });
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection(FirestoreCollections.ads)
        .where('published', isEqualTo: true)
        .snapshots(),
    builder: (context, snapshot) {
      final remote =
          snapshot.data?.docs
              .map((d) => d.data())
              .where(isActiveContent)
              .toList() ??
          [];
      final ads = remote.isEmpty
          ? fallbackAds
                .map(
                  (title) => <String, dynamic>{
                    'title': title,
                    'description': '',
                    'link': '',
                  },
                )
                .toList()
          : remote;
      return SizedBox(
        height: bannerHeight,
        child: PageView.builder(
          controller: controller,
          itemCount: ads.length,
          itemBuilder: (_, i) {
            final ad = ads[i];
            final title = (ad['title'] ?? '').toString();
            final description = (ad['description'] ?? '').toString();
            final link = (ad['link'] ?? '').toString();
            final imageUrl = cloudinaryOptimizedImageUrl(
              (ad['imageUrl'] ?? '').toString(),
            );
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 4, 0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: link.isEmpty
                      ? null
                      : () {
                          unawaited(
                            recordMetric(
                              'banner_view',
                              target: title,
                              targetType: 'ad',
                            ),
                          );
                          openUrl(context, link, title);
                        },
                  borderRadius: BorderRadius.circular(22),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: imageUrl.isEmpty
                          ? const LinearGradient(colors: [ocean, sky])
                          : const LinearGradient(
                              colors: [Color(0x99206090), Color(0x99206090)],
                            ),
                      image: imageUrl.isEmpty
                          ? null
                          : DecorationImage(
                              image: NetworkImage(imageUrl),
                              fit: BoxFit.cover,
                            ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: ocean.withValues(alpha: .10),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ESPAÇO PUBLICITÁRIO',
                            style: TextStyle(
                              color: yellow,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              height: 1.05,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            description.isEmpty
                                ? 'Toque para saber mais'
                                : description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFFDDF4FF)),
                          ),
                        ],
                      ),
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
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Image.asset(
          'assets/images/tudo-aqui-macacu-icon-v1.png',
          width: 43,
          height: 43,
          fit: BoxFit.cover,
        ),
      ),
      const SizedBox(width: 9),
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Tudo Aqui Macacu',
            style: TextStyle(
              color: ink,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          Text(
            'A cidade na sua mão.',
            style: TextStyle(
              color: muted,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ],
  );
}

class App3DButton extends StatefulWidget {
  const App3DButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
  });
  final VoidCallback? onPressed;
  final Widget icon;
  final String label;
  @override
  State<App3DButton> createState() => _App3DButtonState();
}

class _App3DButtonState extends State<App3DButton> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: widget.onPressed == null
        ? null
        : (_) => setState(() => pressed = true),
    onTapCancel: () => setState(() => pressed = false),
    onTapUp: widget.onPressed == null
        ? null
        : (_) {
            setState(() => pressed = false);
            widget.onPressed!();
          },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      transform: Matrix4.translationValues(0, pressed ? 3 : 0, 0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9A18), Color(0xFFFF5A00)],
        ),
        borderRadius: BorderRadius.circular(13),
        boxShadow: pressed
            ? null
            : const [
                BoxShadow(
                  color: Color(0x44082B4C),
                  offset: Offset(0, 3),
                  blurRadius: 0,
                ),
              ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.icon,
          const SizedBox(width: 9),
          Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class CircleIcon extends StatelessWidget {
  const CircleIcon({super.key, required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .94),
    shape: const CircleBorder(),
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: 37,
        height: 37,
        child: Icon(icon, color: ink, size: 20),
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    required this.action,
    required this.onTap,
    this.editMode = false,
    this.onEdit,
  });
  final String title;
  final String action;
  final VoidCallback onTap;
  final bool editMode;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 22, 14, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: ink,
            ),
          ),
        ),
        if (editMode) ...[
          const SizedBox(width: 4),
          IconButton.filledTonal(
            visualDensity: VisualDensity.compact,
            tooltip: 'Editar seção',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded, size: 18),
          ),
        ],
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: ocean,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: Text('$action  ›'),
        ),
      ],
    ),
  );
}

class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.category,
    required this.onTap,
    this.grid = false,
  });
  final Category category;
  final VoidCallback onTap;
  final bool grid;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: grid ? null : 82,
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      shadowColor: ocean.withValues(alpha: .06),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 8, 7, 7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: grid ? 90 : 51,
                height: grid ? 90 : 51,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEAF4FF), Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Center(
                  child: Sprite(index: category.artwork, size: grid ? 80 : 46),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                category.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AppIcon {
  const AppIcon({
    required this.key,
    required this.assetName,
    required this.label,
    required this.legacyIndex,
  });

  final String key;
  final String assetName;
  final String label;
  final int legacyIndex;

  String get assetPath => 'assets/images/icons/$assetName';

  static const comercio = AppIcon(
    key: 'comercio',
    assetName: '01_comercio.png',
    label: 'Comércio',
    legacyIndex: 0,
  );
  static const ondeComer = AppIcon(
    key: 'onde_comer',
    assetName: '02_onde_comer.png',
    label: 'Onde comer',
    legacyIndex: 1,
  );
  static const servicos = AppIcon(
    key: 'servicos',
    assetName: '03_servicos.png',
    label: 'Serviços',
    legacyIndex: 2,
  );
  static const turismo = AppIcon(
    key: 'turismo',
    assetName: '04_turismo.png',
    label: 'Turismo',
    legacyIndex: 5,
  );
  static const saude = AppIcon(
    key: 'saude',
    assetName: '05_saude.png',
    label: 'Saúde',
    legacyIndex: 8,
  );
  static const educacao = AppIcon(
    key: 'educacao',
    assetName: '06_educacao.png',
    label: 'Educação',
    legacyIndex: 14,
  );
  static const empregos = AppIcon(
    key: 'empregos',
    assetName: '07_empregos.png',
    label: 'Empregos',
    legacyIndex: 4,
  );
  static const eventos = AppIcon(
    key: 'eventos',
    assetName: '08_eventos.png',
    label: 'Eventos',
    legacyIndex: 7,
  );
  static const noticias = AppIcon(
    key: 'noticias',
    assetName: '09_noticias.png',
    label: 'Notícias',
    legacyIndex: 6,
  );
  static const utilidades = AppIcon(
    key: 'utilidades',
    assetName: '10_utilidades.png',
    label: 'Utilidades',
    legacyIndex: 17,
  );
  static const cupons = AppIcon(
    key: 'cupons',
    assetName: '11_cupons.png',
    label: 'Cupons',
    legacyIndex: 16,
  );
  static const alertas = AppIcon(
    key: 'alertas',
    assetName: '12_alertas.png',
    label: 'Alertas',
    legacyIndex: 17,
  );
  static const mapa = AppIcon(
    key: 'mapa',
    assetName: '13_mapa.png',
    label: 'Mapa',
    legacyIndex: 17,
  );
  static const onibus = AppIcon(
    key: 'onibus',
    assetName: '14_onibus.png',
    label: 'Ônibus',
    legacyIndex: 10,
  );
  static const coletaLixo = AppIcon(
    key: 'coleta_lixo',
    assetName: '15_coleta_lixo.png',
    label: 'Coleta de lixo',
    legacyIndex: 17,
  );
  static const clima = AppIcon(
    key: 'clima',
    assetName: '16_clima.png',
    label: 'Clima',
    legacyIndex: 17,
  );
  static const plantao = AppIcon(
    key: 'plantao',
    assetName: '17_plantao.png',
    label: 'Plantão',
    legacyIndex: 8,
  );
  static const prefeitura = AppIcon(
    key: 'prefeitura',
    assetName: '18_prefeitura.png',
    label: 'Prefeitura',
    legacyIndex: 0,
  );
  static const telefonesUteis = AppIcon(
    key: 'telefones_uteis',
    assetName: '19_telefones_uteis.png',
    label: 'Telefones úteis',
    legacyIndex: 17,
  );
  static const emergencia = AppIcon(
    key: 'emergencia',
    assetName: '20_emergencia.png',
    label: 'Emergência',
    legacyIndex: 8,
  );
  static const beleza = AppIcon(
    key: 'beleza',
    assetName: '21_beleza.png',
    label: 'Beleza',
    legacyIndex: 12,
  );
  static const pets = AppIcon(
    key: 'pets',
    assetName: '22_pets.png',
    label: 'Pets',
    legacyIndex: 11,
  );
  static const academia = AppIcon(
    key: 'academia',
    assetName: '23_academia.png',
    label: 'Academia',
    legacyIndex: 13,
  );
  static const hospedagem = AppIcon(
    key: 'hospedagem',
    assetName: '24_hospedagem.png',
    label: 'Hospedagem',
    legacyIndex: 15,
  );
  static const imoveis = AppIcon(
    key: 'imoveis',
    assetName: '25_imoveis.png',
    label: 'Imóveis',
    legacyIndex: 9,
  );
  static const transporte = AppIcon(
    key: 'transporte',
    assetName: '26_transporte.png',
    label: 'Transporte',
    legacyIndex: 10,
  );
  static const pontosTuristicos = AppIcon(
    key: 'pontos_turisticos',
    assetName: '27_pontos_turisticos.png',
    label: 'Pontos turísticos',
    legacyIndex: 17,
  );
  static const trilhas = AppIcon(
    key: 'trilhas',
    assetName: '28_trilhas.png',
    label: 'Trilhas',
    legacyIndex: 17,
  );
  static const cachoeiras = AppIcon(
    key: 'cachoeiras',
    assetName: '29_cachoeiras.png',
    label: 'Cachoeiras',
    legacyIndex: 5,
  );
  static const roteiros = AppIcon(
    key: 'roteiros',
    assetName: '30_roteiros.png',
    label: 'Roteiros',
    legacyIndex: 17,
  );

  static const all = <AppIcon>[
    comercio,
    ondeComer,
    servicos,
    turismo,
    saude,
    educacao,
    empregos,
    eventos,
    noticias,
    utilidades,
    cupons,
    alertas,
    mapa,
    onibus,
    coletaLixo,
    clima,
    plantao,
    prefeitura,
    telefonesUteis,
    emergencia,
    beleza,
    pets,
    academia,
    hospedagem,
    imoveis,
    transporte,
    pontosTuristicos,
    trilhas,
    cachoeiras,
    roteiros,
  ];

  static const legacy = <AppIcon>[
    comercio,
    ondeComer,
    servicos,
    servicos,
    empregos,
    turismo,
    noticias,
    eventos,
    saude,
    imoveis,
    transporte,
    pets,
    beleza,
    academia,
    educacao,
    hospedagem,
    cupons,
    utilidades,
  ];

  static AppIcon fromKey(String? key) {
    final normalized = normalizeIconKey(key ?? '');
    return all.firstWhere(
      (icon) => normalizeIconKey(icon.key) == normalized,
      orElse: () {
        debugPrint('Ícone 3D inválido: $key. Usando fallback serviços.');
        return servicos;
      },
    );
  }

  static AppIcon fromLegacyIndex(int index) {
    if (index >= 0 && index < legacy.length) return legacy[index];
    debugPrint(
      'Índice legado de ícone inválido: $index. Usando fallback serviços.',
    );
    return servicos;
  }

  static AppIcon fromCategory(String value, {AppIcon fallback = servicos}) {
    final normalized = normalizeCatalogText(value);
    for (final category in catalog) {
      if (normalizeCatalogText(category.name) == normalized ||
          category.types.any(
            (type) => normalizeCatalogText(type) == normalized,
          )) {
        return fromLegacyIndex(category.artwork);
      }
    }
    if (normalized.contains('comerc')) {
      return comercio;
    }
    if (normalized.contains('comer') || normalized.contains('restaurante')) {
      return ondeComer;
    }
    if (normalized.contains('turismo')) {
      return turismo;
    }
    if (normalized.contains('saude')) {
      return saude;
    }
    if (normalized.contains('educ')) {
      return educacao;
    }
    if (normalized.contains('evento')) {
      return eventos;
    }
    if (normalized.contains('noticia')) {
      return noticias;
    }
    if (normalized.contains('beleza') || normalized.contains('salao')) {
      return beleza;
    }
    if (normalized.contains('pet')) {
      return pets;
    }
    if (normalized.contains('academ')) {
      return academia;
    }
    if (normalized.contains('hosp')) {
      return hospedagem;
    }
    if (normalized.contains('imov')) {
      return imoveis;
    }
    if (normalized.contains('veicul') || normalized.contains('transporte')) {
      return transporte;
    }
    if (normalized.contains('cupom') ||
        normalized.contains('oferta') ||
        normalized.contains('promoc')) {
      return cupons;
    }
    if (normalized.contains('util')) {
      return utilidades;
    }
    return fallback;
  }

  static AppIcon fromUtilityKey(String value) {
    final normalized = normalizeIconKey(value);
    return switch (normalized) {
      'bus' || 'onibus' || 'transport' || 'transporte' => onibus,
      'trash' || 'coleta' || 'lixo' || 'garbage' || 'coletalixo' => coletaLixo,
      'cityhall' || 'prefeitura' => prefeitura,
      'weather' || 'clima' => clima,
      'pharmacy' || 'pharmacyduty' || 'farmacia' || 'plantao' => plantao,
      'emergency' || 'emergencia' || 'sos' => emergencia,
      'phone' ||
      'phones' ||
      'telefone' ||
      'telefones' ||
      'usefulphones' ||
      'telefonesuteis' => telefonesUteis,
      'map' || 'mapa' => mapa,
      'alerts' || 'alert' || 'avisos' => alertas,
      'coupons' || 'coupon' || 'cupons' => cupons,
      'events' || 'event' || 'eventos' => eventos,
      'tourism' || 'turismo' => turismo,
      'news' || 'noticias' => noticias,
      'health' || 'saude' => saude,
      'services' || 'servicos' => servicos,
      _ => utilidades,
    };
  }
}

String normalizeIconKey(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[áàâã]'), 'a')
    .replaceAll(RegExp(r'[éê]'), 'e')
    .replaceAll(RegExp(r'[í]'), 'i')
    .replaceAll(RegExp(r'[óôõ]'), 'o')
    .replaceAll(RegExp(r'[ú]'), 'u')
    .replaceAll('ç', 'c')
    .replaceAll(RegExp(r'[^a-z0-9]+'), '');

class App3DIcon extends StatelessWidget {
  const App3DIcon({super.key, required this.icon, this.size = 56});
  final AppIcon icon;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Image.asset(
      icon.assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          LegacySprite(index: icon.legacyIndex, size: size),
    ),
  );
}

final visualIconNames = [for (final icon in AppIcon.all) icon.label];

class VisualIconPicker extends StatelessWidget {
  const VisualIconPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Ícone',
  });
  final int value;
  final ValueChanged<int> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(AppIcon.all.length, (index) {
          final icon = AppIcon.all[index];
          final selected = icon.legacyIndex == value || index == value;
          return Semantics(
            button: true,
            selected: selected,
            label: icon.label,
            child: InkWell(
              onTap: () => onChanged(icon.legacyIndex),
              borderRadius: BorderRadius.circular(13),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 72,
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFFEAF4FF) : Colors.white,
                  border: Border.all(
                    color: selected ? sky : const Color(0xFFE2E8F0),
                    width: selected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    App3DIcon(icon: icon, size: 38),
                    const SizedBox(height: 3),
                    Text(
                      icon.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: selected ? ocean : ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    ],
  );
}

void _openBusinessProfileFromCard(
  BuildContext context,
  Business business, {
  required bool saved,
  required VoidCallback onFavorite,
  required bool recordOpenMetric,
}) {
  if (recordOpenMetric) {
    unawaited(
      recordMetric(
        'business_open',
        target: business.favoriteKey,
        targetType: 'business',
      ),
    );
  }
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => BusinessProfile(
        business: business,
        saved: saved,
        onFavorite: onFavorite,
      ),
    ),
  );
}

void _openBusinessWhatsAppFromCard(BuildContext context, Business business) {
  openBusinessAction(
    context,
    business,
    action: 'business_whatsapp',
    url: business.whatsappUrl,
    label: 'WhatsApp',
  );
}

class OfferBanner extends StatelessWidget {
  const OfferBanner({super.key});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [ocean, sky],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: ocean.withValues(alpha: .10),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OFERTA EM DESTAQUE',
                  style: TextStyle(
                    color: yellow,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'Condições especiais para a cidade.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'Confira os detalhes no negócio participante.',
                  style: TextStyle(color: Color(0xFFDDF4FF), fontSize: 12),
                ),
              ],
            ),
          ),
          const Sprite(index: 16, size: 64),
        ],
      ),
    ),
  );
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
        child: Row(
          children: [
            Container(
              width: 47,
              height: 47,
              decoration: BoxDecoration(
                color: mist,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Center(child: Sprite(index: 4, size: 41)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${job.company} · ${job.type}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                  Text(
                    job.when,
                    style: const TextStyle(
                      color: orange,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: sky),
          ],
        ),
      ),
    ),
  );
}

class LocalNewsCard extends StatelessWidget {
  const LocalNewsCard({super.key});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: () => openFeature(context, Feature.news),
      borderRadius: BorderRadius.circular(20),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: mist,
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              child: SizedBox(
                width: 70,
                height: 70,
                child: Center(child: Sprite(index: 6, size: 62)),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NOTÍCIA LOCAL',
                    style: TextStyle(
                      color: orange,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .6,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Acontecendo em Macacu',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Conteúdo com fonte parceira identificada.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Fonte demonstrativa · Hoje',
                    style: TextStyle(
                      color: ocean,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0x33FAB71D),
                borderRadius: BorderRadius.all(Radius.circular(14)),
              ),
              child: SizedBox(
                width: 54,
                height: 54,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '18',
                      style: TextStyle(
                        color: orange,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'SET',
                      style: TextStyle(
                        color: ink,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Evento demonstrativo da cidade',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Centro · Cachoeiras de Macacu',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.calendar_month_outlined, color: sky),
          ],
        ),
      ),
    ),
  );
}

class NatureBanner extends StatelessWidget {
  const NatureBanner({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    borderRadius: BorderRadius.circular(23),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 168,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/macacu-waterfall-hero.png',
              fit: BoxFit.cover,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xB3101820), Color(0x00101820)],
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                ),
              ),
            ),
            const Positioned(
              left: 18,
              right: 18,
              bottom: 17,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EXPLORE MACACU',
                    style: TextStyle(
                      color: yellow,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Cachoeiras, trilhas e descobertas.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Conheça nossa cidade no seu ritmo.',
                    style: TextStyle(color: Color(0xFFE1F5FF), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ExploreView extends StatelessWidget {
  const ExploreView({super.key, required this.saved, required this.favorite});
  final Set<String> saved;
  final ValueChanged<Business> favorite;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          title: const Brand(),
          actions: [
            IconButton(
              tooltip: 'Buscar em Macacu',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GlobalSearchView()),
              ),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Text(
              'Encontre tudo em um só lugar',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Compre de quem é daqui. Escolha uma categoria para começar.',
              style: TextStyle(color: muted),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (_, i) => CategoryTile(
                category: catalog[i],
                grid: true,
                onTap: () => openDirectory(context, catalog[i]),
              ),
              childCount: catalog.length,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: .82,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SectionTitle(
            title: 'Negócios em destaque',
            action: 'Ver todos',
            onTap: () {},
          ),
        ),
        SliverToBoxAdapter(
          child: PublishedBusinessList(
            repository: businessRepository,
            fallbackBusinesses: businesses,
            saved: saved,
            favorite: favorite,
            cardBuilder: (context, business, saved, onFavorite) => BusinessCard(
              business: business,
              saved: saved,
              onFavorite: onFavorite,
              onOpen: () => _openBusinessProfileFromCard(
                context,
                business,
                saved: saved,
                onFavorite: onFavorite,
                recordOpenMetric: true,
              ),
              onViewBusiness: () => _openBusinessProfileFromCard(
                context,
                business,
                saved: saved,
                onFavorite: onFavorite,
                recordOpenMetric: false,
              ),
              onWhatsApp: () =>
                  _openBusinessWhatsAppFromCard(context, business),
            ),
          ),
        ),
      ],
    ),
  );
}

class GlobalSearchView extends StatefulWidget {
  const GlobalSearchView({super.key});
  @override
  State<GlobalSearchView> createState() => _GlobalSearchViewState();
}

class _GlobalSearchViewState extends State<GlobalSearchView> {
  final query = TextEditingController();

  static const _contentCollections = <String, String>{
    'offers': 'Ofertas',
    'events': 'Eventos',
    'routes': 'Roteiros',
    'news': 'Notícias',
    'jobs': 'Vagas',
    'health': 'Saúde',
    'coupons': 'Cupons',
    'alerts': 'Avisos',
  };

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<List<_SearchResult>> _search(String term) async {
    if (term.isEmpty) return const [];
    final businessResults = await businessRepository
        .watchPublishedBusinesses()
        .first;
    final searches = await Future.wait([
      ..._contentCollections.keys.map(
        (collection) => FirebaseFirestore.instance
            .collection(collection)
            .where('published', isEqualTo: true)
            .get(),
      ),
    ]);
    final results = <_SearchResult>[];
    for (final business in businessResults) {
      final content =
          '${business.name} ${business.category} ${business.subcategory} ${business.description}'
              .toLowerCase();
      if (content.contains(term)) {
        results.add(_SearchResult.business(business));
      }
    }
    for (var index = 0; index < _contentCollections.length; index++) {
      final collection = _contentCollections.keys.elementAt(index);
      final snapshot = searches[index];
      for (final document in snapshot.docs) {
        final item = document.data();
        if (!isActiveContent(item)) continue;
        final content =
            '${item['title'] ?? ''} ${item['description'] ?? ''} ${item['category'] ?? ''}'
                .toLowerCase();
        if (content.contains(term)) {
          results.add(
            _SearchResult.content(
              title: (item['title'] ?? '').toString(),
              subtitle: (item['description'] ?? '').toString(),
              section: _contentCollections[collection]!,
              link: (item['link'] ?? '').toString(),
            ),
          );
        }
      }
    }
    return results;
  }

  void _openContent(_SearchResult result) {
    if (result.link.isNotEmpty) {
      openUrl(context, result.link, result.section);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              result.subtitle.isEmpty
                  ? 'Conteúdo publicado em ${result.section}.'
                  : result.subtitle,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Buscar em Macacu')),
    body: Builder(
      builder: (context) {
        final term = query.text.trim().toLowerCase();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: query,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Empresas, eventos, ofertas e mais',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            if (term.isEmpty)
              const Text(
                'Busque empresas, ofertas, eventos, vagas, roteiros e notícias.',
                style: TextStyle(color: muted),
              )
            else
              FutureBuilder<List<_SearchResult>>(
                future: _search(term),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return const Text(
                      'Não foi possível pesquisar agora. Tente novamente.',
                      style: TextStyle(color: muted),
                    );
                  }
                  final results = snapshot.data ?? const <_SearchResult>[];
                  if (results.isEmpty) {
                    return const Text(
                      'Nenhum resultado encontrado.',
                      style: TextStyle(color: muted),
                    );
                  }
                  return Column(
                    children: results
                        .map(
                          (result) => ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 6,
                            ),
                            leading: result.business == null
                                ? const CircleAvatar(
                                    child: Icon(Icons.search_rounded),
                                  )
                                : Sprite(
                                    index: result.business!.artwork,
                                    size: 48,
                                  ),
                            title: Text(
                              result.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(result.subtitle),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: sky,
                            ),
                            onTap: () => result.business == null
                                ? _openContent(result)
                                : Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => BusinessProfile(
                                        business: result.business!,
                                        saved: false,
                                        onFavorite: () {},
                                      ),
                                    ),
                                  ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
          ],
        );
      },
    ),
  );
}

class _SearchResult {
  const _SearchResult._({
    this.business,
    required this.title,
    required this.subtitle,
    required this.section,
    this.link = '',
  });
  factory _SearchResult.business(Business business) => _SearchResult._(
    business: business,
    title: business.name,
    subtitle: '${business.category} · ${business.subcategory}',
    section: 'Estabelecimentos',
  );
  factory _SearchResult.content({
    required String title,
    required String subtitle,
    required String section,
    required String link,
  }) => _SearchResult._(
    title: title.isEmpty ? section : title,
    subtitle: subtitle,
    section: section,
    link: link,
  );
  final Business? business;
  final String title, subtitle, section, link;
}

void openDirectory(BuildContext context, Category category) {
  if (category.name == 'Serviços úteis') {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PublicServicesView()));
    return;
  }
  if (category.name == 'Turismo') {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TouristRoutesView()));
    return;
  }
  if (category.name == 'Eventos') {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const EventsReminderView()));
    return;
  }
  if (category.name == 'Promoções') {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const OffersView()));
    return;
  }
  if (category.name == 'Empregos') {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LocalJobsView()));
    return;
  }
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => DirectoryView(category: category)));
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
  Widget build(BuildContext context) => StreamBuilder<List<Business>>(
    stream: businessRepository.watchPublishedBusinesses(),
    builder: (context, snapshot) {
      final remote =
          snapshot.data
              ?.where((item) => item.category == widget.category.name)
              .toList() ??
          const <Business>[];
      final inCategory = remote.isEmpty
          ? businesses
                .where((item) => item.category == widget.category.name)
                .toList()
          : remote;
      final visible = type == 'Todos'
          ? inCategory
          : inCategory.where((item) => item.subcategory == type).toList();
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
                      Text(
                        widget.category.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Escolha um tipo para encontrar o que precisa.',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['Todos', ...widget.category.types]
                  .map(
                    (item) => ChoiceChip(
                      label: Text(item),
                      selected: type == item,
                      onSelected: (_) => setState(() => type = item),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 18),
            Text(
              '${visible.length} resultados',
              style: const TextStyle(
                color: orange,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
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
                    onOpen: () => _openBusinessProfileFromCard(
                      context,
                      item,
                      saved: localSaved.contains(item.name),
                      onFavorite: () => setState(
                        () => localSaved.contains(item.name)
                            ? localSaved.remove(item.name)
                            : localSaved.add(item.name),
                      ),
                      recordOpenMetric: true,
                    ),
                    onViewBusiness: () => _openBusinessProfileFromCard(
                      context,
                      item,
                      saved: localSaved.contains(item.name),
                      onFavorite: () => setState(
                        () => localSaved.contains(item.name)
                            ? localSaved.remove(item.name)
                            : localSaved.add(item.name),
                      ),
                      recordOpenMetric: false,
                    ),
                    onWhatsApp: () =>
                        _openBusinessWhatsAppFromCard(context, item),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Dados demonstrativos. Você cadastra e aprova cada negócio antes de ele aparecer para o público.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
      );
    },
  );
}

class EmptyDirectory extends StatelessWidget {
  const EmptyDirectory({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: mist,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Column(
      children: [
        Icon(Icons.storefront_outlined, color: sky, size: 38),
        SizedBox(height: 10),
        Text(
          'Em breve, novos estabelecimentos aparecerão aqui.',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 5),
        Text(
          'Você decide o que entra na vitrine.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    ),
  );
}

class PublicServicesView extends StatefulWidget {
  const PublicServicesView({super.key});

  @override
  State<PublicServicesView> createState() => _PublicServicesViewState();
}

class _PublicServicesViewState extends State<PublicServicesView> {
  @override
  Widget build(BuildContext context) => const ResourcesHub();
}

class BillTile extends StatelessWidget {
  const BillTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });
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
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color == yellow ? orange : color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => openUrl(context, '', 'canal de $title'),
              icon: const Icon(Icons.open_in_new_rounded, color: sky),
              tooltip: 'Acessar canal oficial',
            ),
          ],
        ),
      ),
    ),
  );
}

class PublishedUtilities extends StatelessWidget {
  const PublishedUtilities({super.key});

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection(FirestoreCollections.alerts)
        .where('published', isEqualTo: true)
        .snapshots(),
    builder: (context, snapshot) {
      final items =
          (snapshot.data?.docs
                    .map((document) => document.data())
                    .where(isActiveContent)
                    .toList() ??
                [])
            ..sort(
              (
                a,
                b,
              ) => ((b['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
                  .compareTo(
                    (a['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
                  ),
            );
      if (items.isEmpty) {
        return const Text(
          'Nenhum aviso adicional publicado no momento.',
          style: TextStyle(color: muted, fontSize: 12),
        );
      }
      return Column(
        children: items.map((item) {
          final title = (item['title'] ?? 'Aviso').toString();
          final description = (item['description'] ?? '').toString();
          final link = (item['link'] ?? item['url'] ?? '').toString();
          return UtilityTile(
            icon: Icons.info_outline_rounded,
            title: title,
            subtitle: description.isEmpty
                ? 'Acesse para saber mais.'
                : description,
            onTap: link.isEmpty ? null : () => openUrl(context, link, title),
          );
        }).toList(),
      );
    },
  );
}

class UtilityTile extends StatelessWidget {
  const UtilityTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 47,
          height: 47,
          decoration: BoxDecoration(
            color: mist,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: ocean),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded, color: sky),
      ),
    ),
  );
}

class BusinessProfile extends StatelessWidget {
  const BusinessProfile({
    super.key,
    required this.business,
    required this.saved,
    required this.onFavorite,
  });
  final Business business;
  final bool saved;
  final VoidCallback onFavorite;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 220,
          pinned: true,
          actions: [
            IconButton(
              tooltip: 'Compartilhar',
              onPressed: () async {
                unawaited(
                  recordMetric(
                    'business_share',
                    target: business.favoriteKey,
                    targetType: 'business',
                  ),
                );
                final link = business.maps.isNotEmpty
                    ? business.maps
                    : business.whatsappUrl;
                await Clipboard.setData(
                  ClipboardData(
                    text:
                        '${business.name}\n${business.location}${link.isEmpty ? '' : '\n$link'}',
                  ),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Informações copiadas para compartilhar.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.share_outlined, color: Colors.white),
            ),
            IconButton(
              onPressed: onFavorite,
              icon: Icon(
                saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: saved ? orange : Colors.white,
              ),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [BusinessHeroMedia(business: business)],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  business.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${business.category} · ${business.subcategory}',
                  style: const TextStyle(
                    color: ocean,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: muted,
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        business.location,
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ),
                    if (business.open)
                      const MiniLabel(
                        text: 'ABERTO AGORA',
                        color: Color(0xFF1E9662),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (business.whatsapp.isNotEmpty)
                      FilledButton.icon(
                        onPressed: () => openBusinessAction(
                          context,
                          business,
                          action: 'business_whatsapp',
                          url: business.whatsappUrl,
                          label: 'WhatsApp',
                        ),
                        icon: const Icon(Icons.chat_outlined),
                        label: const Text('WhatsApp'),
                      ),
                    if (business.phone.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => openBusinessAction(
                          context,
                          business,
                          action: 'business_phone',
                          url: business.phoneUrl,
                          label: 'Ligação',
                        ),
                        icon: const Icon(Icons.call_outlined),
                        label: const Text('Ligar'),
                      ),
                    if (business.instagram.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => openBusinessAction(
                          context,
                          business,
                          action: 'business_instagram',
                          url: business.instagramUrl,
                          label: 'Instagram',
                        ),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Instagram'),
                      ),
                    if (business.maps.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => openBusinessAction(
                          context,
                          business,
                          action: 'business_map',
                          url: business.maps,
                          label: 'Google Maps',
                        ),
                        icon: const Icon(Icons.directions_outlined),
                        label: const Text('Como chegar'),
                      ),
                  ],
                ),
                if (business.description.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  InfoBlock(title: 'Sobre', text: business.description),
                ],
                if (business.services.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  InfoBlock(
                    title: 'Serviços',
                    text: business.services.map((item) => '• $item').join('\n'),
                  ),
                ],
                if (business.products.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  InfoBlock(
                    title: 'Produtos',
                    text: business.products.map((item) => '• $item').join('\n'),
                  ),
                ],
                if (business.hours.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  InfoBlock(title: 'Horários', text: business.hours),
                ],
                if (business.additionalInfo.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  InfoBlock(
                    title: 'Informações adicionais',
                    text: business.additionalInfo,
                  ),
                ],
                if (business.promotionTitle.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0D8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.local_offer_outlined, color: orange),
                            SizedBox(width: 8),
                            Text(
                              'Oferta especial',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: ocean,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          business.promotionTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        if (business.promotionDescription.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            business.promotionDescription,
                            style: const TextStyle(color: muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class OffersView extends StatelessWidget {
  const OffersView({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(FirestoreCollections.offers)
          .where('published', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        final offers =
            (snapshot.data?.docs
                      .map((doc) => doc.data())
                      .where(isActiveContent)
                      .toList() ??
                  [])
              ..sort(
                (a, b) =>
                    ((b['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                            0)
                        .compareTo(
                          (a['updatedAt'] as Timestamp?)
                                  ?.millisecondsSinceEpoch ??
                              0,
                        ),
              );
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            const Brand(),
            const SizedBox(height: 25),
            Text(
              'Ofertas em Macacu',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            const Text(
              'Promoções publicadas pelos estabelecimentos participantes.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 20),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (offers.isEmpty)
              const EmptyOffers()
            else
              ...offers.map((offer) => OfferPublicCard(offer: offer)),
          ],
        );
      },
    ),
  );
}

class EmptyOffers extends StatelessWidget {
  const EmptyOffers({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(28),
    child: Text(
      'Não há ofertas publicadas no momento.',
      textAlign: TextAlign.center,
      style: TextStyle(color: muted),
    ),
  );
}

class OfferPublicCard extends StatelessWidget {
  const OfferPublicCard({super.key, required this.offer});
  final Map<String, dynamic> offer;
  @override
  Widget build(BuildContext context) {
    final image = (offer['imageUrl'] ?? '').toString();
    final title = (offer['title'] ?? 'Oferta').toString();
    final description = (offer['description'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () {
            final link = (offer['link'] ?? '').toString();
            unawaited(
              recordMetric('offer_open', target: title, targetType: 'offer'),
            );
            if (link.isNotEmpty) {
              openUrl(context, link, title);
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    width: 68,
                    height: 68,
                    child: image.isEmpty
                        ? const ColoredBox(
                            color: mist,
                            child: Center(child: Sprite(index: 16, size: 61)),
                          )
                        : Image.network(
                            image,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const ColoredBox(
                              color: mist,
                              child: Center(child: Sprite(index: 16, size: 61)),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MiniLabel(text: 'OFERTA', color: orange),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SavedView extends StatelessWidget {
  const SavedView({super.key, required this.saved, required this.favorite});
  final Set<String> saved;
  final ValueChanged<Business> favorite;
  @override
  Widget build(BuildContext context) => StreamBuilder<List<Business>>(
    stream: businessRepository.watchPublishedBusinesses(),
    builder: (context, snapshot) {
      final remote = snapshot.data ?? const <Business>[];
      final source = remote.isEmpty ? businesses : remote;
      final items = source
          .where(
            (item) =>
                saved.contains(item.favoriteKey) || saved.contains(item.name),
          )
          .toList();
      return Scaffold(
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            const Brand(),
            const SizedBox(height: 25),
            Text(
              'Seus favoritos',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            const Text(
              'Guarde os negócios que quer consultar depois.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 20),
            if (items.isEmpty)
              const EmptyDirectory()
            else
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: BusinessCard(
                    business: item,
                    saved: true,
                    onFavorite: () => favorite(item),
                    onOpen: () => _openBusinessProfileFromCard(
                      context,
                      item,
                      saved: true,
                      onFavorite: () => favorite(item),
                      recordOpenMetric: true,
                    ),
                    onViewBusiness: () => _openBusinessProfileFromCard(
                      context,
                      item,
                      saved: true,
                      onFavorite: () => favorite(item),
                      recordOpenMetric: false,
                    ),
                    onWhatsApp: () =>
                        _openBusinessWhatsAppFromCard(context, item),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class ContactView extends StatefulWidget {
  const ContactView({super.key});
  @override
  State<ContactView> createState() => _ContactViewState();
}

class _ContactViewState extends State<ContactView> {
  final name = TextEditingController();
  final contact = TextEditingController();
  final message = TextEditingController();
  bool sending = false;
  @override
  void dispose() {
    name.dispose();
    contact.dispose();
    message.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (message.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      await FirebaseFirestore.instance
          .collection(FirestoreCollections.contactMessages)
          .add({
            'name': name.text.trim(),
            'contact': contact.text.trim(),
            'message': message.text.trim(),
            'email': user.email,
            'createdAt': FieldValue.serverTimestamp(),
            'read': false,
          });
      name.clear();
      contact.clear();
      message.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mensagem enviada. Obrigado pelo contato!'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível enviar agora. Tente novamente.'),
          ),
        );
      }
    }
    if (mounted) setState(() => sending = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        const Brand(),
        const SizedBox(height: 26),
        Text(
          'Fale com a gente',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Envie sugestões, dúvidas ou solicite a divulgação do seu negócio.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Seu nome',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: contact,
          decoration: const InputDecoration(
            labelText: 'Seu contato',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: message,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Mensagem',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: sending ? null : send,
          icon: const Icon(Icons.send_rounded),
          label: Text(sending ? 'Enviando...' : 'Enviar mensagem'),
        ),
      ],
    ),
  );
}

class ProfileView extends StatelessWidget {
  const ProfileView({super.key, required this.count, required this.user});
  final int count;
  final User? user;
  @override
  Widget build(BuildContext context) {
    final isAdmin = isAdminUser(user);
    if (user == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Brand(),
                const SizedBox(height: 28),
                const Icon(
                  Icons.favorite_outline_rounded,
                  color: orange,
                  size: 54,
                ),
                const SizedBox(height: 12),
                Text(
                  'Entre para personalizar',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Salve seus lugares e receba novidades de Macacu.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const GoogleLoginView()),
                  ),
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Continuar com Google'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          const Brand(),
          const SizedBox(height: 27),
          Row(
            children: [
              CircleAvatar(
                radius: 31,
                backgroundColor: yellow,
                backgroundImage: user!.photoURL == null
                    ? null
                    : NetworkImage(user!.photoURL!),
                child: user!.photoURL == null
                    ? const Icon(
                        Icons.person_outline_rounded,
                        color: ink,
                        size: 31,
                      )
                    : null,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user!.displayName ?? 'Sua área',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      user!.email ?? '',
                      style: const TextStyle(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          MenuRow(
            icon: Icons.favorite_outline_rounded,
            title: 'Itens salvos',
            text: '$count favorito(s) na sua conta',
          ),
          MenuRow(
            icon: Icons.notifications_none_rounded,
            title: 'Notificações',
            text: 'Ofertas, vagas e novidades de Macacu',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsView()),
            ),
          ),
          MenuRow(
            icon: Icons.mail_outline_rounded,
            title: 'Fale com a gente',
            text: 'Sugestões e divulgação',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ContactView()),
            ),
          ),
          if (isAdmin)
            MenuRow(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Administração',
              text: 'Gerencie todo o aplicativo',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminView()),
              ),
            ),
          MenuRow(
            icon: Icons.logout_rounded,
            title: 'Sair da conta',
            text: 'Entrar com outra conta Google',
            onTap: () async {
              final current = FirebaseAuth.instance.currentUser;
              if (current != null) await PushService.deactivate(current);
              await GoogleSignIn(serverClientId: googleWebClientId).signOut();
              await FirebaseAuth.instance.signOut();
            },
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: mist,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nossa cidade. Mais perto de você.',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 5),
                Text(
                  'Tudo de Macacu em um só lugar.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MenuRow extends StatelessWidget {
  const MenuRow({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String text;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: ocean),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(text),
        trailing: const Icon(Icons.chevron_right_rounded, color: sky),
      ),
    ),
  );
}

class AdminView extends StatelessWidget {
  const AdminView({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Administração')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Controle do aplicativo',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Escolha a área que deseja atualizar.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 22),
        AdminMenuTile(
          icon: Icons.home_work_outlined,
          title: 'Home',
          subtitle: 'Aparência, seções, destaques e publicação',
          color: const Color(0xFFEAF4FF),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const HomeEditor()),
          ),
        ),
        AdminMenuTile(
          icon: Icons.storefront_outlined,
          title: 'Estabelecimentos',
          subtitle: 'Cadastre e atualize as empresas da cidade',
          color: Colors.white,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ContentManager(
                collection: 'establishments',
                title: 'Estabelecimentos',
              ),
            ),
          ),
        ),
        AdminMenuTile(
          icon: Icons.campaign_outlined,
          title: 'Conteúdo',
          subtitle: 'Eventos, turismo, utilidades e campanhas',
          color: Colors.white,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminContentHub()),
          ),
        ),
        AdminMenuTile(
          icon: Icons.settings_outlined,
          title: 'Configurações',
          subtitle: 'Notificações, métricas, histórico e importação',
          color: mist,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminSettingsHub()),
          ),
        ),
      ],
    ),
  );
}

class AdminMenuTile extends StatelessWidget {
  const AdminMenuTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      tileColor: color,
      leading: Icon(icon, color: ocean),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded, color: sky),
    ),
  );
}

class AdminContentHub extends StatelessWidget {
  const AdminContentHub({super.key});
  @override
  Widget build(BuildContext context) => _AdminHub(
    title: 'Conteúdo',
    description: 'Escolha o tipo de conteúdo que deseja publicar.',
    items: const [
      ('events', 'Agenda da cidade', Icons.event_note_outlined),
      ('routes', 'Turismo e roteiros', Icons.route_outlined),
      ('ads', 'Banners e campanhas', Icons.campaign_outlined),
      ('utilities', 'Utilidades da cidade', Icons.apps_rounded),
      ('transport', 'Ônibus', Icons.directions_bus_rounded),
      ('trash_collection', 'Coleta', Icons.delete_outline_rounded),
      ('useful_phones', 'Telefones úteis', Icons.phone_outlined),
      (
        'pharmacy_duties',
        'Farmácias de plantão',
        Icons.local_pharmacy_outlined,
      ),
      ('alerts', 'Alertas da cidade', Icons.warning_amber_rounded),
      ('emergency_contacts', 'Emergência', Icons.emergency_outlined),
      ('resolver_subjects', 'Onde Resolver?', Icons.manage_search_rounded),
      ('public_places', 'Locais públicos', Icons.account_balance_outlined),
      ('coupons', 'Cupons', Icons.confirmation_number_outlined),
      ('news', 'Notícias', Icons.newspaper_rounded),
      ('jobs', 'Vagas', Icons.work_outline_rounded),
      ('health', 'Saúde', Icons.health_and_safety_outlined),
      ('polls', 'Enquetes', Icons.poll_outlined),
    ],
  );
}

class AdminSettingsHub extends StatelessWidget {
  const AdminSettingsHub({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Configurações')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AdminMenuTile(
          icon: Icons.file_download_outlined,
          title: 'Importar conteúdo inicial',
          subtitle: 'Leva os exemplos do app para a área editável',
          color: const Color(0xFFFFF0D8),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const InitialContentImporter()),
          ),
        ),
        AdminMenuTile(
          icon: Icons.notifications_active_outlined,
          title: 'Notificações',
          subtitle: 'Crie um aviso específico para o aplicativo',
          color: Colors.white,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationComposer()),
          ),
        ),
        AdminMenuTile(
          icon: Icons.bar_chart_rounded,
          title: 'Métricas',
          subtitle: 'Visualizações e cliques do aplicativo',
          color: mist,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminMetricsView()),
          ),
        ),
        AdminMenuTile(
          icon: Icons.history_rounded,
          title: 'Histórico administrativo',
          subtitle: 'Registros das alterações feitas no app',
          color: mist,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminAuditView()),
          ),
        ),
        AdminMenuTile(
          icon: Icons.rate_review_outlined,
          title: 'Avaliações e correções',
          subtitle: 'Acompanhe mensagens e avaliações',
          color: mist,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ReviewManager()),
          ),
        ),
        AdminMenuTile(
          icon: Icons.mail_rounded,
          title: 'Mensagens recebidas',
          subtitle: 'Contatos enviados pelo aplicativo',
          color: mist,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ContactInbox()),
          ),
        ),
      ],
    ),
  );
}

class _AdminHub extends StatelessWidget {
  const _AdminHub({
    required this.title,
    required this.description,
    required this.items,
  });

  final String title;
  final String description;
  final List<(String, String, IconData)> items;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(description, style: const TextStyle(color: muted)),
        const SizedBox(height: 16),
        ...items.map(
          (item) => AdminMenuTile(
            icon: item.$3,
            title: item.$2,
            subtitle: 'Adicionar, editar, revisar e publicar',
            color: Colors.white,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => item.$1 == 'utilities'
                    ? const UtilityManager()
                    : ContentManager(collection: item.$1, title: item.$2),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class AdminAuditView extends StatelessWidget {
  const AdminAuditView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Histórico administrativo')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(FirestoreCollections.adminAuditLogs)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'Não foi possível carregar o histórico. Tente novamente quando houver conexão.',
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final logs = snapshot.data!.docs;
        if (logs.isEmpty) {
          return const Center(
            child: Text(
              'As próximas alterações administrativas aparecerão aqui.',
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: logs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, index) {
            final item = logs[index].data();
            final timestamp = item['createdAt'] as Timestamp?;
            final when = timestamp == null
                ? 'Sincronizando horário...'
                : '${timestamp.toDate().day.toString().padLeft(2, '0')}/${timestamp.toDate().month.toString().padLeft(2, '0')} às ${timestamp.toDate().hour.toString().padLeft(2, '0')}:${timestamp.toDate().minute.toString().padLeft(2, '0')}';
            return ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: const Icon(Icons.history_rounded, color: ocean),
              title: Text(
                '${item['action'] ?? 'alteração'} · ${item['label'] ?? item['collection'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
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
      final collection = FirebaseFirestore.instance.collection(
        'establishments',
      );
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
      await recordAdminAudit(
        action: 'import_initial_content',
        collection: 'establishments',
        documentId: 'initial-template',
        label: '$added estabelecimento(s) importado(s)',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              added == 0
                  ? 'Os exemplos já estão na área administrável.'
                  : '$added exemplo(s) foram importados. Agora você pode editar ou apagar cada um.',
            ),
          ),
        );
      }
    } on FirebaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível importar agora. Verifique sua conexão e tente novamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Importar conteúdo inicial')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transformar exemplos em conteúdo editável',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          const Text(
            'Isso copia os estabelecimentos demonstrativos para o Firebase uma única vez. Os que já existem não são substituídos. Depois, você controla publicação, destaque, contatos e descrição pela aba Estabelecimentos.',
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: importing ? null : importExamples,
            icon: const Icon(Icons.file_download_outlined),
            label: Text(importing ? 'Importando...' : 'Importar exemplos'),
          ),
        ],
      ),
    ),
  );
}

class HomeEditor extends StatefulWidget {
  const HomeEditor({super.key});
  @override
  State<HomeEditor> createState() => _HomeEditorState();
}

class _HomeEditorState extends State<HomeEditor> {
  final title = TextEditingController(),
      search = TextEditingController(),
      slogan = TextEditingController(),
      greeting = TextEditingController(),
      location = TextEditingController(),
      logoUrl = TextEditingController(),
      backgroundImageUrl = TextEditingController(),
      backgroundStart = TextEditingController(),
      backgroundEnd = TextEditingController();
  final sectionTitles = <String, TextEditingController>{
    for (final key in defaultHomeOrder) key: TextEditingController(),
  };
  final sectionLimits = <String, TextEditingController>{
    for (final key in defaultHomeOrder) key: TextEditingController(),
  };
  final categoryIcons = <String, TextEditingController>{
    for (final category in homeCatalog) category.name: TextEditingController(),
  };
  final enabled = <String, bool>{for (final key in defaultHomeOrder) key: true};
  var order = [...defaultHomeOrder];
  var categoryOrder = homeCatalog.map((item) => item.name).toList();
  String backgroundType = 'gradient';
  bool saving = false, loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final c in [
      title,
      search,
      slogan,
      greeting,
      location,
      logoUrl,
      backgroundImageUrl,
      backgroundStart,
      backgroundEnd,
      ...sectionTitles.values,
      ...sectionLimits.values,
      ...categoryIcons.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    try {
      final db = FirebaseFirestore.instance;
      final draft = await db
          .collection(FirestoreCollections.homePages)
          .doc('draft')
          .get();
      final published = await db
          .collection(FirestoreCollections.homePages)
          .doc('published')
          .get();
      final data = mergeHomePageData(
        published.data() ?? const <String, dynamic>{},
        draft.data() ?? const <String, dynamic>{},
      );
      final page = HomePageConfig.fromMap(data);
      title.text = page.heroTitle;
      search.text = page.searchPlaceholder;
      slogan.text = page.slogan;
      greeting.text = page.greeting;
      location.text = page.location;
      logoUrl.text = page.logoUrl;
      backgroundType = page.backgroundType;
      backgroundImageUrl.text = page.backgroundImageUrl;
      backgroundStart.text = page.backgroundStart;
      backgroundEnd.text = page.backgroundEnd;
      order = [
        ...page.order.where(defaultHomeOrder.contains),
        ...defaultHomeOrder.where((key) => !page.order.contains(key)),
      ];
      categoryOrder = page
          .categories(homeCatalog)
          .map((item) => item.name)
          .toList();
      for (final category in page.categories(homeCatalog)) {
        categoryIcons[category.name]!.text = category.artwork.toString();
      }
      for (final key in defaultHomeOrder) {
        enabled[key] = page.enabled(key);
        sectionTitles[key]!.text = page.titleFor(key);
        sectionLimits[key]!.text = page.limitFor(key).toString();
      }
    } catch (error) {
      debugPrint('Não foi possível carregar editor da Home: $error');
    }
    if (mounted) setState(() => loading = false);
  }

  Map<String, dynamic> _data() => {
    'heroTitle': title.text.trim(),
    'searchPlaceholder': search.text.trim(),
    'sections': enabled,
    'sectionOrder': order,
    'categoryOrder': categoryOrder,
    'categoryIcons': {
      for (final category in homeCatalog)
        category.name:
            (int.tryParse(categoryIcons[category.name]!.text) ??
                    category.artwork)
                .clamp(0, 17),
    },
    'sectionTitles': {
      for (final key in defaultHomeOrder) key: sectionTitles[key]!.text.trim(),
    },
    'sectionLimits': {
      for (final key in defaultHomeOrder)
        key: (int.tryParse(sectionLimits[key]!.text) ?? 2).clamp(1, 12),
    },
    'visual': {
      'slogan': slogan.text.trim(),
      'greeting': greeting.text.trim(),
      'location': location.text.trim(),
      'logoUrl': logoUrl.text.trim(),
      'backgroundType': backgroundType,
      'backgroundStart': backgroundStart.text.trim(),
      'backgroundEnd': backgroundEnd.text.trim(),
      'backgroundImageUrl': backgroundImageUrl.text.trim(),
    },
    'updatedAt': FieldValue.serverTimestamp(),
  };

  Future<void> save(bool publish) async {
    setState(() => saving = true);
    try {
      final data = _data();
      final db = FirebaseFirestore.instance;
      await db
          .collection(FirestoreCollections.homePages)
          .doc('draft')
          .set(data, SetOptions(merge: true));
      if (publish) {
        await db
            .collection(FirestoreCollections.homePages)
            .doc('published')
            .set({
              ...data,
              'publishedAt': FieldValue.serverTimestamp(),
              'version': FieldValue.increment(1),
            }, SetOptions(merge: true));
        await recordAdminAudit(
          action: 'publish_home',
          collection: 'home_pages',
          documentId: 'published',
          label: 'Home publicada',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              publish
                  ? 'Home publicada para todos os usuários.'
                  : 'Rascunho salvo. O app público não mudou.',
            ),
          ),
        );
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível salvar: ${error.code}')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> discard() async {
    setState(() => saving = true);
    try {
      await FirebaseFirestore.instance
          .collection(FirestoreCollections.homePages)
          .doc('draft')
          .delete();
      await recordAdminAudit(
        action: 'discard_home_draft',
        collection: 'home_pages',
        documentId: 'draft',
        label: 'Rascunho da Home descartado',
      );
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Rascunho descartado. A versão publicada foi recarregada.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _move(List<String> list, int index, int direction) {
    final target = index + direction;
    if (target < 0 || target >= list.length) return;
    setState(() {
      final item = list.removeAt(index);
      list.insert(target, item);
    });
  }

  Future<void> _pickCategoryIcon(BuildContext context, String category) async {
    var selected = (int.tryParse(categoryIcons[category]!.text) ?? 0).clamp(
      0,
      17,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ícone de $category',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Escolha o ícone que aparecerá nesta categoria.'),
                  const SizedBox(height: 16),
                  VisualIconPicker(
                    value: selected,
                    onChanged: (value) => setSheetState(() => selected = value),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () {
                      setState(
                        () =>
                            categoryIcons[category]!.text = selected.toString(),
                      );
                      Navigator.pop(context);
                    },
                    child: const Text('Usar este ícone'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _field(String label, {String? helper}) => InputDecoration(
    labelText: label,
    helperText: helper,
    border: const OutlineInputBorder(),
  );
  String _name(String key) =>
      const {
        'banner': 'Banners e anúncios',
        'categories': 'Categorias',
        'highlights': 'Destaques',
        'offers': 'Ofertas',
        'resources': 'Vantagens e avisos',
        'jobs': 'Novos por aqui',
        'events': 'Eventos e notícias',
        'tourism': 'Turismo',
      }[key] ??
      key;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Editor da Home')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Rascunho e publicação',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Edite com segurança. Somente Publicar altera a Home de quem usa o aplicativo.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: title,
                onChanged: (_) => setState(() {}),
                decoration: _field('Frase principal'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: search,
                decoration: _field('Texto da busca'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: slogan,
                decoration: _field('Slogan da marca'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: greeting,
                decoration: _field('Frase para visitante sem login'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: location,
                decoration: _field('Localização'),
              ),
              const SizedBox(height: 22),
              const Text(
                'Identidade visual',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: logoUrl,
                keyboardType: TextInputType.url,
                decoration: _field(
                  'Logo (URL do Cloudinary)',
                  helper: 'Vazio usa o logo atual do aplicativo',
                ),
              ),
              const SizedBox(height: 12),
              const CloudinaryUploadHelper(
                description:
                    'Use o Cloudinary para enviar o logo e cole aqui a URL final da imagem.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: backgroundType,
                decoration: _field('Fundo do cabeçalho'),
                items: const [
                  DropdownMenuItem(value: 'gradient', child: Text('Gradiente')),
                  DropdownMenuItem(value: 'color', child: Text('Cor sólida')),
                  DropdownMenuItem(value: 'image', child: Text('Imagem')),
                ],
                onChanged: (value) =>
                    setState(() => backgroundType = value ?? 'gradient'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: backgroundStart,
                decoration: _field('Cor inicial (hexadecimal, ex.: EAF4FF)'),
              ),
              const SizedBox(height: 12),
              if (backgroundType == 'gradient')
                TextField(
                  controller: backgroundEnd,
                  decoration: _field('Cor final (hexadecimal, ex.: F8FAFC)'),
                ),
              if (backgroundType == 'image')
                Column(
                  children: [
                    TextField(
                      controller: backgroundImageUrl,
                      keyboardType: TextInputType.url,
                      decoration: _field('Imagem de fundo (URL do Cloudinary)'),
                    ),
                    const SizedBox(height: 12),
                    const CloudinaryUploadHelper(
                      description:
                          'Envie a imagem do fundo no Cloudinary e cole aqui a URL para publicar no cabeçalho.',
                    ),
                  ],
                ),
              const SizedBox(height: 22),
              const Text(
                'Ordem e visibilidade das seções',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              const Text(
                'Use as setas para decidir a ordem exibida na Home.',
                style: TextStyle(color: muted),
              ),
              ...order.asMap().entries.map((entry) {
                final key = entry.value;
                final index = entry.key;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 6, 10),
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: enabled[key] ?? true,
                          onChanged: (value) =>
                              setState(() => enabled[key] = value),
                          title: Text(
                            _name(key),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            enabled[key] == false
                                ? 'Não aparece na Home publicada'
                                : 'Aparece na posição ${index + 1}',
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              onPressed: index == 0
                                  ? null
                                  : () => _move(order, index, -1),
                              icon: const Icon(Icons.keyboard_arrow_up_rounded),
                            ),
                            IconButton(
                              onPressed: index == order.length - 1
                                  ? null
                                  : () => _move(order, index, 1),
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: TextField(
                                controller: sectionTitles[key],
                                decoration: _field('Título da seção'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 80,
                              child: TextField(
                                controller: sectionLimits[key],
                                keyboardType: TextInputType.number,
                                decoration: _field('Itens'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 22),
              const Text(
                'Ordem das categorias',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              const Text(
                'As categorias mantêm os ícones oficiais e podem ser reorganizadas.',
                style: TextStyle(color: muted),
              ),
              ...categoryOrder.asMap().entries.map((entry) {
                final category = entry.value;
                final index = entry.key;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: mist,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: ocean,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  title: Text(category),
                  subtitle: Text(
                    'Ícone: ${visualIconNames[(int.tryParse(categoryIcons[category]!.text) ?? 0).clamp(0, 17)]}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _pickCategoryIcon(context, category),
                        icon: const Icon(Icons.image_outlined),
                        tooltip: 'Escolher ícone',
                      ),
                      IconButton(
                        onPressed: index == 0
                            ? null
                            : () => _move(categoryOrder, index, -1),
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      ),
                      IconButton(
                        onPressed: index == categoryOrder.length - 1
                            ? null
                            : () => _move(categoryOrder, index, 1),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 22),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Prévia do rascunho',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title.text.isEmpty
                            ? 'O que você procura hoje?'
                            : title.text,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: ocean,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        search.text.isEmpty
                            ? 'Encontre em Macacu...'
                            : search.text,
                        style: const TextStyle(color: muted),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Ordem: ${order.where((key) => enabled[key] != false).map(_name).join(' › ')}',
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: saving ? null : () => save(false),
                child: Text(saving ? 'Salvando...' : 'Salvar rascunho'),
              ),
              const SizedBox(height: 10),
              FilledButton.tonal(
                onPressed: saving ? null : () => save(true),
                child: const Text('Publicar alterações'),
              ),
              TextButton(
                onPressed: saving ? null : discard,
                child: const Text('Descartar rascunho'),
              ),
            ],
          ),
  );
}

class ContentManager extends StatelessWidget {
  const ContentManager({
    super.key,
    required this.collection,
    required this.title,
  });
  final String collection, title;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ContentEditor(collection: collection),
        ),
      ),
      icon: const Icon(Icons.add_rounded),
      label: const Text('Adicionar'),
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(collection)
          .orderBy('updatedAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(
            child: Text('Não foi possível carregar os itens.'),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text('Ainda não há itens. Use Adicionar para publicar.'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final d = docs[i];
            final data = d.data();
            return ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                (data['title'] ?? data['name'] ?? 'Sem título').toString(),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                data['published'] == false ? 'Rascunho' : 'Publicado',
              ),
              trailing: const Icon(Icons.edit_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ContentEditor(collection: collection, doc: d),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

class ContentEditor extends StatefulWidget {
  const ContentEditor({super.key, required this.collection, this.doc});
  final String collection;
  final DocumentSnapshot<Map<String, dynamic>>? doc;
  @override
  State<ContentEditor> createState() => _ContentEditorState();
}

class _ContentEditorState extends State<ContentEditor> {
  late final TextEditingController title;
  late final TextEditingController description;
  late final TextEditingController link;
  late final TextEditingController imageUrl;
  late final TextEditingController logoUrl;
  late final TextEditingController icon;
  late final TextEditingController expires;
  late final TextEditingController category;
  late final TextEditingController subcategory;
  late final TextEditingController location;
  late final TextEditingController whatsapp;
  late final TextEditingController phone;
  late final TextEditingController instagram;
  late final TextEditingController maps;
  late final TextEditingController galleryUrls;
  late final TextEditingController galleryInput;
  late final TextEditingController eventDate;
  late final TextEditingController contact;
  late final TextEditingController hours;
  late final TextEditingController services;
  late final TextEditingController products;
  late final TextEditingController additionalInfo;
  late final TextEditingController promotionTitle;
  late final TextEditingController promotionDescription;
  bool featured = false;
  bool published = true;
  bool saving = false;
  final galleryItems = <String>[];
  bool get isBusinessContent => widget.collection == 'establishments';
  bool get supportsMediaGallery => const {
    'establishments',
    'events',
    'routes',
    'news',
    'jobs',
    'alerts',
    'coupons',
    'health',
    'transport',
    'trash_collection',
    'useful_phones',
    'pharmacy_duties',
    'emergency_contacts',
    'resolver_subjects',
    'public_places',
  }.contains(widget.collection);
  bool get supportsLocalDetails => const {
    'events',
    'routes',
    'news',
    'jobs',
    'alerts',
    'health',
    'transport',
    'trash_collection',
    'useful_phones',
    'pharmacy_duties',
    'emergency_contacts',
    'resolver_subjects',
    'public_places',
  }.contains(widget.collection);

  @override
  void initState() {
    super.initState();
    final d = widget.doc?.data() ?? {};
    title = TextEditingController(
      text: (d['title'] ?? d['name'] ?? '').toString(),
    );
    description = TextEditingController(
      text: (d['description'] ?? '').toString(),
    );
    link = TextEditingController(
      text: (d['link'] ?? d['url'] ?? '').toString(),
    );
    imageUrl = TextEditingController(
      text: cloudinaryOptimizedImageUrl((d['imageUrl'] ?? '').toString()),
    );
    logoUrl = TextEditingController(
      text: cloudinaryOptimizedImageUrl((d['logoUrl'] ?? '').toString()),
    );
    icon = TextEditingController(text: (d['artwork'] ?? '0').toString());
    category = TextEditingController(text: (d['category'] ?? '').toString());
    subcategory = TextEditingController(
      text: (d['subcategory'] ?? '').toString(),
    );
    location = TextEditingController(
      text: (d['location'] ?? d['address'] ?? '').toString(),
    );
    whatsapp = TextEditingController(text: (d['whatsapp'] ?? '').toString());
    phone = TextEditingController(text: (d['phone'] ?? '').toString());
    instagram = TextEditingController(text: (d['instagram'] ?? '').toString());
    maps = TextEditingController(
      text: (d['maps'] ?? d['mapsUrl'] ?? '').toString(),
    );
    galleryUrls = TextEditingController(
      text: ((d['galleryUrls'] as List?) ?? const [])
          .map((item) => cloudinaryOptimizedImageUrl(item.toString()))
          .join('\n'),
    );
    galleryInput = TextEditingController();
    galleryItems.addAll(
      ((d['galleryUrls'] as List?) ?? const [])
          .map((item) => cloudinaryOptimizedImageUrl(item.toString()))
          .where((item) => item.isNotEmpty),
    );
    final cover = imageUrl.text.trim();
    if (cover.isNotEmpty && !galleryItems.contains(cover)) {
      galleryItems.insert(0, cover);
    }
    eventDate = TextEditingController(
      text: (d['eventDate'] ?? d['date'] ?? '').toString(),
    );
    contact = TextEditingController(text: (d['contact'] ?? '').toString());
    hours = TextEditingController(text: (d['hours'] ?? '').toString());
    services = TextEditingController(
      text: ((d['services'] as List?) ?? const [])
          .map((item) => item.toString())
          .join('\n'),
    );
    products = TextEditingController(
      text: ((d['products'] as List?) ?? const [])
          .map((item) => item.toString())
          .join('\n'),
    );
    additionalInfo = TextEditingController(
      text: (d['additionalInfo'] ?? '').toString(),
    );
    promotionTitle = TextEditingController(
      text: (d['promotionTitle'] ?? '').toString(),
    );
    promotionDescription = TextEditingController(
      text: (d['promotionDescription'] ?? '').toString(),
    );
    final expiry = d['expiresAt'];
    expires = TextEditingController(
      text: expiry is Timestamp
          ? '${expiry.toDate().year}-${expiry.toDate().month.toString().padLeft(2, '0')}-${expiry.toDate().day.toString().padLeft(2, '0')}'
          : '',
    );
    published = d['published'] as bool? ?? true;
    featured = d['featured'] as bool? ?? false;
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    link.dispose();
    imageUrl.dispose();
    logoUrl.dispose();
    icon.dispose();
    expires.dispose();
    category.dispose();
    subcategory.dispose();
    location.dispose();
    whatsapp.dispose();
    phone.dispose();
    instagram.dispose();
    maps.dispose();
    galleryUrls.dispose();
    galleryInput.dispose();
    eventDate.dispose();
    contact.dispose();
    hours.dispose();
    services.dispose();
    products.dispose();
    additionalInfo.dispose();
    promotionTitle.dispose();
    promotionDescription.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (title.text.trim().isEmpty) return;
    setState(() => saving = true);
    try {
      final expiry = DateTime.tryParse(expires.text.trim());
      final normalizedGallery = _normalizedGallery();
      final coverImage = supportsMediaGallery
          ? (normalizedGallery.isNotEmpty
                ? normalizedGallery.first
                : cloudinaryOptimizedImageUrl(imageUrl.text.trim()))
          : cloudinaryOptimizedImageUrl(imageUrl.text.trim());
      final data = {
        'title': title.text.trim(),
        'description': description.text.trim(),
        'link': link.text.trim(),
        'imageUrl': coverImage,
        'artwork': isBusinessContent
            ? artworkForCategory(
                category.text.trim(),
                fallback: int.tryParse(icon.text.trim()) ?? 0,
              )
            : int.tryParse(icon.text.trim()) ?? 0,
        if (supportsMediaGallery) 'galleryUrls': normalizedGallery,
        if (supportsLocalDetails) ...{
          'category': category.text.trim(),
          'location': location.text.trim(),
          'address': location.text.trim(),
          'eventDate': eventDate.text.trim(),
          'date': eventDate.text.trim(),
          'contact': contact.text.trim(),
          'whatsapp': whatsapp.text.trim(),
          'phone': phone.text.trim(),
          'instagram': instagram.text.trim(),
          'maps': maps.text.trim(),
          'additionalInfo': additionalInfo.text.trim(),
        },
        if (isBusinessContent) ...{
          'name': title.text.trim(),
          'category': category.text.trim(),
          'subcategory': subcategory.text.trim(),
          'location': location.text.trim(),
          'whatsapp': whatsapp.text.trim(),
          'phone': phone.text.trim(),
          'instagram': instagram.text.trim(),
          'maps': maps.text.trim(),
          'hours': hours.text.trim(),
          'services': services.text
              .split(RegExp(r'\r?\n'))
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(),
          'products': products.text
              .split(RegExp(r'\r?\n'))
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(),
          'additionalInfo': additionalInfo.text.trim(),
          'promotionTitle': promotionTitle.text.trim(),
          'promotionDescription': promotionDescription.text.trim(),
          'featured': featured,
          'logoUrl': cloudinaryOptimizedImageUrl(logoUrl.text),
        },
        'published': published,
        'updatedAt': FieldValue.serverTimestamp(),
        if (expiry != null)
          'expiresAt': Timestamp.fromDate(
            DateTime(expiry.year, expiry.month, expiry.day, 23, 59, 59),
          ),
      };
      final reference = widget.doc == null
          ? await FirebaseFirestore.instance
                .collection(widget.collection)
                .add(data)
          : widget.doc!.reference;
      if (widget.doc != null) {
        await reference.set(data, SetOptions(merge: true));
      }
      await recordAdminAudit(
        action: widget.doc == null ? 'create' : 'update',
        collection: widget.collection,
        documentId: reference.id,
        label: title.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } on FirebaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível salvar agora. Verifique a internet e tente novamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> remove() async {
    final document = widget.doc;
    if (document == null) return;
    try {
      await document.reference.delete();
      await recordAdminAudit(
        action: 'delete',
        collection: widget.collection,
        documentId: document.id,
        label: title.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } on FirebaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível excluir agora. Tente novamente.'),
          ),
        );
      }
    }
  }

  List<String> _normalizedGallery() {
    return orderedUniqueImageUrls([
      ...galleryItems,
      ...imageUrlsFromInput(galleryUrls.text),
    ]);
  }

  void _addGalleryUrls() {
    final urls = imageUrlsFromInput(
      galleryInput.text,
    ).map(cloudinaryOptimizedImageUrl);
    setState(() {
      for (final url in urls) {
        if (!galleryItems.contains(url)) galleryItems.add(url);
      }
      if (imageUrl.text.trim().isEmpty && galleryItems.isNotEmpty) {
        imageUrl.text = galleryItems.first;
      }
      galleryInput.clear();
      galleryUrls.text = galleryItems.join('\n');
    });
  }

  void _moveGalleryImage(int index, int direction) {
    setState(() {
      galleryItems
        ..clear()
        ..addAll(moveImageUrl(galleryItems, index, direction));
      galleryUrls.text = galleryItems.join('\n');
    });
  }

  void _setCoverImage(int index) {
    setState(() {
      galleryItems
        ..clear()
        ..addAll(setCoverImageUrl(galleryItems, index));
      imageUrl.text = galleryItems.isEmpty ? '' : galleryItems.first;
      galleryUrls.text = galleryItems.join('\n');
    });
  }

  void _removeGalleryImage(int index) {
    setState(() {
      galleryItems
        ..clear()
        ..addAll(removeImageUrl(galleryItems, index));
      imageUrl.text = galleryItems.isEmpty ? '' : galleryItems.first;
      galleryUrls.text = galleryItems.join('\n');
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.doc == null ? 'Adicionar' : 'Editar')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: title,
          decoration: const InputDecoration(
            labelText: 'Título ou nome',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        if (isBusinessContent || supportsLocalDetails) ...[
          TextField(
            controller: category,
            onChanged: isBusinessContent ? (_) => setState(() {}) : null,
            decoration: const InputDecoration(
              labelText: 'Categoria',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (isBusinessContent) ...[
          TextField(
            controller: subcategory,
            decoration: const InputDecoration(
              labelText: 'Subcategoria',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        TextField(
          controller: description,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Descrição',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        if (isBusinessContent || supportsLocalDetails) ...[
          if (widget.collection == 'events') ...[
            TextField(
              controller: eventDate,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Data do evento',
                helperText: 'Ex.: 25/09/2026 às 19h',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: location,
            decoration: const InputDecoration(
              labelText: 'Local, endereço ou referência',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: contact,
            decoration: const InputDecoration(
              labelText: 'Contato ou responsável',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: whatsapp,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'WhatsApp (link wa.me)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Telefone (tel:)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: instagram,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Instagram (URL)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: maps,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Link do Google Maps',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        TextField(
          controller: link,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Link do botão (opcional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        if (isBusinessContent) ...[
          Text(
            'Identidade',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: logoUrl,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Logo da empresa (URL do Cloudinary)',
              helperText:
                  'Recomendado: 800 × 800 px, quadrada, com boa margem. Ela aparece redonda no app.',
              border: OutlineInputBorder(),
            ),
          ),
          if (logoUrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  width: 92,
                  height: 92,
                  child: Image.network(
                    cloudinaryOptimizedImageUrl(logoUrl.text),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: mist,
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'Logo não carregou.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: muted, fontSize: 11),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const CloudinaryUploadHelper(
            title: 'Logo da empresa',
            description:
                'Envie uma imagem quadrada de 800 × 800 px. O app recorta em círculo nos cards; as fotos continuam na área Fotos do estabelecimento.',
          ),
          const SizedBox(height: 14),
        ],
        if (!supportsMediaGallery) ...[
          TextField(
            controller: imageUrl,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Imagem do Cloudinary (URL)',
              helperText: 'Envie pelo Cloudinary e cole aqui a URL da imagem',
              border: OutlineInputBorder(),
            ),
          ),
          if (imageUrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  cloudinaryOptimizedImageUrl(imageUrl.text),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: mist,
                    child: Center(
                      child: Text(
                        'Não foi possível carregar a prévia da imagem.',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const CloudinaryUploadHelper(
            title: 'Imagem do conteúdo',
            description:
                'Envie a imagem no Cloudinary e cole aqui a URL para usar como capa deste conteúdo.',
          ),
        ],
        if (supportsMediaGallery) ...[
          const SizedBox(height: 14),
          ContentMediaGalleryEditor(
            urls: galleryItems,
            input: galleryInput,
            onAdd: _addGalleryUrls,
            onMove: _moveGalleryImage,
            onCover: _setCoverImage,
            onRemove: _removeGalleryImage,
          ),
          const SizedBox(height: 14),
        ],
        if (isBusinessContent) ...[
          TextField(
            controller: hours,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Horários de funcionamento',
              helperText: 'Ex.: Seg–Sex: 08h às 18h | Sáb: 08h às 13h',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: services,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Serviços',
              helperText: 'Um serviço por linha',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: products,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Produtos',
              helperText: 'Um produto por linha',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (isBusinessContent || supportsLocalDetails) ...[
          TextField(
            controller: additionalInfo,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Informações adicionais',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (isBusinessContent) ...[
          TextField(
            controller: promotionTitle,
            decoration: const InputDecoration(
              labelText: 'Título da oferta (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: promotionDescription,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Descrição da oferta (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (isBusinessContent) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: mist,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Sprite(
                  index: artworkForCategory(
                    category.text,
                    fallback: int.tryParse(icon.text) ?? 0,
                  ),
                  size: 42,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'O ícone público é definido automaticamente pela categoria. Logo, capa e fotos ficam separados.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ] else ...[
          VisualIconPicker(
            value: (int.tryParse(icon.text) ?? 0).clamp(0, 17),
            onChanged: (value) => setState(() => icon.text = value.toString()),
            label: 'Ícone exibido no aplicativo',
          ),
          const SizedBox(height: 14),
        ],
        if (widget.collection == 'ads' || widget.collection == 'offers')
          TextField(
            controller: expires,
            keyboardType: TextInputType.datetime,
            decoration: const InputDecoration(
              labelText: 'Encerrar em (AAAA-MM-DD)',
              helperText: 'Deixe vazio para não expirar',
              border: OutlineInputBorder(),
            ),
          ),
        if (isBusinessContent)
          SwitchListTile(
            value: featured,
            onChanged: (v) => setState(() => featured = v),
            title: const Text('Destaque na Home'),
            contentPadding: EdgeInsets.zero,
          ),
        SwitchListTile(
          value: published,
          onChanged: (v) => setState(() => published = v),
          title: const Text('Publicado'),
          subtitle: const Text('Desative para manter como rascunho'),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Salvando...' : 'Salvar alterações'),
        ),
        if (widget.doc != null)
          TextButton.icon(
            onPressed: remove,
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: const Text(
              'Excluir item',
              style: TextStyle(color: Colors.red),
            ),
          ),
      ],
    ),
  );
}

class ContentMediaGalleryEditor extends StatelessWidget {
  const ContentMediaGalleryEditor({
    super.key,
    required this.urls,
    required this.input,
    required this.onAdd,
    required this.onMove,
    required this.onCover,
    required this.onRemove,
  });
  final List<String> urls;
  final TextEditingController input;
  final VoidCallback onAdd;
  final void Function(int index, int direction) onMove;
  final ValueChanged<int> onCover;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Fotos do estabelecimento',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 6),
      const Text(
        'Uma única área para fotos. Cole uma URL do Cloudinary por linha; a primeira foto é a capa.',
        style: TextStyle(color: muted, fontSize: 12),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          OutlinedButton.icon(
            onPressed: () => openUrl(
              context,
              'https://console.cloudinary.com/',
              'Cloudinary',
            ),
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Abrir Cloudinary'),
          ),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Adicionar / atualizar fotos'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      TextField(
        controller: input,
        keyboardType: TextInputType.url,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: 'Links das imagens (Cloudinary)',
          hintText:
              'https://res.cloudinary.com/.../foto1.jpg\nhttps://res.cloudinary.com/.../foto2.jpg',
          helperText:
              'Use uma URL por linha. Linhas vazias e duplicadas são ignoradas.',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      if (urls.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: mist,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            'Nenhuma foto adicionada. Use imagens para deixar a página mais forte.',
            style: TextStyle(color: muted),
          ),
        )
      else
        ...urls.asMap().entries.map((entry) {
          final index = entry.key;
          final url = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 86,
                      height: 58,
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const DecoratedBox(
                          decoration: BoxDecoration(color: mist),
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(6),
                              child: Text(
                                'Não foi possível carregar esta imagem.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 10, color: muted),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          index == 0
                              ? 'Foto ${index + 1} · CAPA'
                              : 'Foto ${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Subir',
                    onPressed: index == 0 ? null : () => onMove(index, -1),
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  ),
                  IconButton(
                    tooltip: 'Descer',
                    onPressed: index == urls.length - 1
                        ? null
                        : () => onMove(index, 1),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  IconButton(
                    tooltip: index == 0 ? 'Capa atual' : 'Usar como capa',
                    onPressed: index == 0 ? null : () => onCover(index),
                    icon: Icon(
                      index == 0
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: index == 0 ? orange : null,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Excluir foto',
                    onPressed: () => onRemove(index),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
          );
        }),
    ],
  );
}

class ContactInbox extends StatelessWidget {
  const ContactInbox({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mensagens recebidas')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(FirestoreCollections.contactMessages)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final docs = s.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('Nenhuma mensagem ainda.'));
        }
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i].data();
            return ListTile(
              title: Text((d['name'] ?? 'Visitante').toString()),
              subtitle: Text(
                '${d['message'] ?? ''}\n${d['contact'] ?? d['email'] ?? ''}',
              ),
              isThreeLine: true,
            );
          },
        );
      },
    ),
  );
}

class ResourcesPreview extends StatelessWidget {
  const ResourcesPreview({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: sky.withValues(alpha: .08)),
      boxShadow: [
        BoxShadow(
          color: ocean.withValues(alpha: .05),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: const Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFFFFF3E8),
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.local_activity_outlined, color: orange, size: 28),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cupons exclusivos',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 3),
              Text(
                'Descontos e vantagens dos estabelecimentos locais.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

const utilityDestinationTypes = ['internal', 'url', 'phone', 'whatsapp', 'map'];

const utilityIconMap = <String, IconData>{
  'bus': Icons.directions_bus_rounded,
  'trash': Icons.delete_outline_rounded,
  'cityHall': Icons.account_balance_outlined,
  'water': Icons.water_drop_outlined,
  'energy': Icons.bolt_outlined,
  'coupons': Icons.confirmation_number_outlined,
  'alerts': Icons.warning_amber_rounded,
  'events': Icons.event_available_outlined,
  'tourism': Icons.route_outlined,
  'map': Icons.map_outlined,
  'news': Icons.newspaper_outlined,
  'polls': Icons.poll_outlined,
  'business': Icons.store_mall_directory_outlined,
  'health': Icons.health_and_safety_outlined,
  'pharmacy': Icons.local_pharmacy_outlined,
  'emergency': Icons.emergency_outlined,
  'resolver': Icons.manage_search_rounded,
  'publicPlace': Icons.account_balance_outlined,
  'phone': Icons.phone_outlined,
  'whatsapp': Icons.chat_outlined,
  'link': Icons.open_in_new_rounded,
  'services': Icons.apps_rounded,
};

const internalUtilityPages = <String, String>{
  'transport': 'Ônibus e transporte',
  'trash': 'Coleta de lixo',
  'usefulPhones': 'Telefones úteis',
  'coupons': 'Cupons exclusivos',
  'alerts': 'Alertas da cidade',
  'pharmacyDuty': 'Farmácia de plantão',
  'emergency': 'Emergência',
  'resolver': 'Onde Resolver?',
  'publicPlaces': 'Locais públicos',
  'events': 'Agenda com lembrete',
  'tourism': 'Roteiros turísticos',
  'map': 'Mapa de Macacu',
  'news': 'Notícias locais',
  'polls': 'Enquetes da cidade',
  'businessProposal': 'Indique uma empresa',
  'health': 'Saúde',
};

const fallbackUtilities = [
  UtilityItem(
    id: 'transport',
    name: 'Ônibus',
    iconKey: 'bus',
    description: 'Horários e linhas quando cadastrados',
    destinationType: 'internal',
    destination: 'transport',
    order: 10,
  ),
  UtilityItem(
    id: 'trash',
    name: 'Coleta de lixo',
    iconKey: 'trash',
    description: 'Dias e horários por bairro',
    destinationType: 'internal',
    destination: 'trash',
    order: 20,
  ),
  UtilityItem(
    id: 'phones',
    name: 'Telefones úteis',
    iconKey: 'phone',
    description: 'Contatos rápidos da cidade',
    destinationType: 'internal',
    destination: 'usefulPhones',
    order: 30,
  ),
  UtilityItem(
    id: 'health',
    name: 'Saúde',
    iconKey: 'health',
    description: 'Unidades, contatos e informações',
    destinationType: 'internal',
    destination: 'health',
    order: 40,
  ),
  UtilityItem(
    id: 'pharmacyDuty',
    name: 'Plantão',
    iconKey: 'pharmacy',
    description: 'Farmácias de plantão cadastradas',
    destinationType: 'internal',
    destination: 'pharmacyDuty',
    order: 45,
  ),
  UtilityItem(
    id: 'cityHall',
    name: 'Prefeitura',
    iconKey: 'cityHall',
    description: 'Serviços e canais oficiais',
    destinationType: 'internal',
    destination: 'cityHall',
    order: 50,
  ),
  UtilityItem(
    id: 'water',
    name: 'Água',
    iconKey: 'water',
    description: 'Alertas, contatos e orientações',
    destinationType: 'internal',
    destination: 'water',
    order: 60,
  ),
  UtilityItem(
    id: 'energy',
    name: 'Energia',
    iconKey: 'energy',
    description: 'Alertas, contatos e orientações',
    destinationType: 'internal',
    destination: 'energy',
    order: 70,
  ),
  UtilityItem(
    id: 'emergency',
    name: 'Emergência',
    iconKey: 'emergency',
    description: 'Contatos rápidos cadastrados',
    destinationType: 'internal',
    destination: 'emergency',
    order: 75,
  ),
  UtilityItem(
    id: 'resolver',
    name: 'Onde resolver?',
    iconKey: 'resolver',
    description: 'Encontre o caminho certo',
    destinationType: 'internal',
    destination: 'resolver',
    order: 78,
  ),
  UtilityItem(
    id: 'tourism',
    name: 'Turismo',
    iconKey: 'tourism',
    description: 'Cachoeiras, trilhas e roteiros',
    destinationType: 'internal',
    destination: 'tourism',
    order: 80,
  ),
  UtilityItem(
    id: 'publicPlaces',
    name: 'Locais públicos',
    iconKey: 'publicPlace',
    description: 'Saúde, educação, lazer e atendimento',
    destinationType: 'internal',
    destination: 'publicPlaces',
    order: 90,
  ),
];

IconData utilityIcon(String key) =>
    utilityIconMap[key.trim()] ?? Icons.apps_rounded;

void openUtilityDestination(BuildContext context, UtilityItem item) {
  unawaited(
    recordMetric('utility_open', target: item.id, targetType: 'utility'),
  );
  switch (item.destinationType) {
    case 'url':
      unawaited(openUrl(context, item.destination, item.name));
      return;
    case 'phone':
      unawaited(openUrl(context, 'tel:${item.destination}', item.name));
      return;
    case 'whatsapp':
      unawaited(
        openUrl(
          context,
          item.destination.startsWith('http')
              ? item.destination
              : 'https://wa.me/${item.destination.replaceAll(RegExp(r'\D'), '')}',
          item.name,
        ),
      );
      return;
    case 'map':
      unawaited(openUrl(context, item.destination, item.name));
      return;
  }
  final page = switch (item.destination) {
    'transport' => const UtilityInfoPage(
      title: 'Ônibus e transporte',
      subtitle:
          'Linhas, horários e informações cadastradas pelo administrador.',
      collection: 'transport',
      searchHint: 'Buscar linha, origem ou destino...',
      empty:
          'Nenhuma linha cadastrada ainda. O administrador pode publicar horários reais quando disponíveis.',
      icon: Icons.directions_bus_rounded,
    ),
    'trash' => const UtilityInfoPage(
      title: 'Coleta de lixo',
      subtitle: 'Dias e períodos de coleta por bairro ou localidade.',
      collection: 'trash_collection',
      searchHint: 'Buscar bairro ou localidade...',
      empty:
          'Nenhuma rota de coleta cadastrada ainda. Não exibimos horários inventados.',
      icon: Icons.delete_outline_rounded,
    ),
    'usefulPhones' => const UtilityInfoPage(
      title: 'Telefones úteis',
      subtitle: 'Contatos rápidos cadastrados e revisados pelo administrador.',
      collection: 'useful_phones',
      searchHint: 'Buscar telefone, órgão ou serviço...',
      empty: 'Nenhum telefone útil cadastrado ainda.',
      icon: Icons.phone_outlined,
      phoneMode: true,
    ),
    'cityHall' => UtilitySubAreaPage(
      title: 'Prefeitura',
      subtitle:
          'Serviços, canais e orientações para resolver assuntos da cidade.',
      iconKey: 'cityHall',
      items: const [
        UtilityItem(
          id: 'resolver-city',
          name: 'Onde Resolver?',
          iconKey: 'resolver',
          description: 'Descubra qual setor procurar',
          destinationType: 'internal',
          destination: 'resolver',
          order: 10,
        ),
        UtilityItem(
          id: 'phones-city',
          name: 'Telefones úteis',
          iconKey: 'phone',
          description: 'Contatos cadastrados pelo admin',
          destinationType: 'internal',
          destination: 'usefulPhones',
          order: 20,
        ),
        UtilityItem(
          id: 'places-city',
          name: 'Locais públicos',
          iconKey: 'publicPlace',
          description: 'Órgãos, unidades e endereços',
          destinationType: 'internal',
          destination: 'publicPlaces',
          order: 30,
        ),
        UtilityItem(
          id: 'alerts-city',
          name: 'Alertas oficiais',
          iconKey: 'alerts',
          description: 'Avisos importantes publicados',
          destinationType: 'internal',
          destination: 'alerts',
          order: 40,
        ),
      ],
    ),
    'water' => UtilitySubAreaPage(
      title: 'Água',
      subtitle: 'Alertas, contatos e orientações cadastradas sobre água.',
      iconKey: 'water',
      items: const [
        UtilityItem(
          id: 'water-alerts',
          name: 'Alertas de água',
          iconKey: 'alerts',
          description: 'Interrupções e avisos quando publicados',
          destinationType: 'internal',
          destination: 'alerts',
          order: 10,
        ),
        UtilityItem(
          id: 'water-phones',
          name: 'Telefones úteis',
          iconKey: 'phone',
          description: 'Canais de atendimento cadastrados',
          destinationType: 'internal',
          destination: 'usefulPhones',
          order: 20,
        ),
        UtilityItem(
          id: 'water-resolver',
          name: 'Onde resolver?',
          iconKey: 'resolver',
          description: 'Orientações e documentos necessários',
          destinationType: 'internal',
          destination: 'resolver',
          order: 30,
        ),
      ],
    ),
    'energy' => UtilitySubAreaPage(
      title: 'Energia',
      subtitle: 'Alertas, contatos e orientações cadastradas sobre energia.',
      iconKey: 'energy',
      items: const [
        UtilityItem(
          id: 'energy-alerts',
          name: 'Alertas de energia',
          iconKey: 'alerts',
          description: 'Quedas, manutenção e avisos publicados',
          destinationType: 'internal',
          destination: 'alerts',
          order: 10,
        ),
        UtilityItem(
          id: 'energy-phones',
          name: 'Telefones úteis',
          iconKey: 'phone',
          description: 'Canais de atendimento cadastrados',
          destinationType: 'internal',
          destination: 'usefulPhones',
          order: 20,
        ),
        UtilityItem(
          id: 'energy-resolver',
          name: 'Onde resolver?',
          iconKey: 'resolver',
          description: 'Orientações e documentos necessários',
          destinationType: 'internal',
          destination: 'resolver',
          order: 30,
        ),
      ],
    ),
    'coupons' => const CouponsView(),
    'alerts' => const CityAlertsView(),
    'pharmacyDuty' => const PharmacyDutyView(),
    'emergency' => const EmergencyContactsView(),
    'resolver' => const ResolverGuideView(),
    'publicPlaces' => const PublicPlacesView(),
    'events' => const CityAgendaView(),
    'tourism' => const TourismHomeView(),
    'map' => const BusinessMapView(),
    'news' => const LocalNewsView(),
    'polls' => const PollsView(),
    'health' => UtilitySubAreaPage(
      title: 'Saúde',
      subtitle:
          'Atalhos para plantão, emergência, unidades e conteúdos de saúde.',
      iconKey: 'health',
      items: const [
        UtilityItem(
          id: 'health-content',
          name: 'Conteúdos de saúde',
          iconKey: 'health',
          description: 'Informações publicadas pelo admin',
          destinationType: 'internal',
          destination: 'healthContent',
          order: 10,
        ),
        UtilityItem(
          id: 'health-pharmacy',
          name: 'Farmácia de plantão',
          iconKey: 'pharmacy',
          description: 'Escalas reais cadastradas',
          destinationType: 'internal',
          destination: 'pharmacyDuty',
          order: 20,
        ),
        UtilityItem(
          id: 'health-emergency',
          name: 'Emergência',
          iconKey: 'emergency',
          description: 'Contatos rápidos cadastrados',
          destinationType: 'internal',
          destination: 'emergency',
          order: 30,
        ),
        UtilityItem(
          id: 'health-places',
          name: 'Locais de saúde',
          iconKey: 'publicPlace',
          description: 'Unidades e locais publicados',
          destinationType: 'internal',
          destination: 'publicPlaces',
          order: 40,
        ),
      ],
    ),
    'healthContent' => const FirestoreContentScaffold(
      title: 'Saúde',
      collection: 'health',
      empty: 'Não há conteúdos de saúde publicados no momento.',
      actionLabel: 'Ver',
    ),
    _ => const BusinessProposalView(),
  };
  Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}

class UtilityIconBadge extends StatelessWidget {
  const UtilityIconBadge({
    super.key,
    required this.iconKey,
    this.size = 48,
    this.iconSize,
  });

  final String iconKey;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final normalized = iconKey.trim().isEmpty ? 'services' : iconKey.trim();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEAF4FF), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * .30),
        boxShadow: [
          BoxShadow(
            color: ocean.withValues(alpha: .07),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Center(
        child: App3DIcon(
          icon: AppIcon.fromUtilityKey(normalized),
          size: iconSize ?? size * .86,
        ),
      ),
    );
  }
}

class UtilityCard extends StatelessWidget {
  const UtilityCard({super.key, required this.item});

  final UtilityItem item;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => openUtilityDestination(context, item),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            UtilityIconBadge(iconKey: item.iconKey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.description,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: sky),
          ],
        ),
      ),
    ),
  );
}

class UtilitySubAreaPage extends StatelessWidget {
  const UtilitySubAreaPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.iconKey,
    required this.items,
  });

  final String title, subtitle, iconKey;
  final List<UtilityItem> items;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [ocean, sky]),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: ocean.withValues(alpha: .16),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              UtilityIconBadge(iconKey: iconKey, size: 64, iconSize: 55),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFFDDF4FF),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: UtilityCard(item: item),
          ),
        ),
      ],
    ),
  );
}

class UtilityInfoPage extends StatefulWidget {
  const UtilityInfoPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.collection,
    required this.searchHint,
    required this.empty,
    required this.icon,
    this.phoneMode = false,
  });

  final String title, subtitle, collection, searchHint, empty;
  final IconData icon;
  final bool phoneMode;

  @override
  State<UtilityInfoPage> createState() => _UtilityInfoPageState();
}

class _UtilityInfoPageState extends State<UtilityInfoPage> {
  String query = '';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(widget.collection)
          .where('published', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        final items =
            (snapshot.data?.docs.map((doc) => doc.data()).toList() ??
                  const <Map<String, dynamic>>[])
              ..sort(
                (a, b) => ((a['order'] as num?)?.toInt() ?? 0).compareTo(
                  ((b['order'] as num?)?.toInt() ?? 0),
                ),
              );
        final filtered = items.where((item) {
          final needle = query.toLowerCase().trim();
          if (needle.isEmpty) return true;
          return [
            item['title'],
            item['name'],
            item['description'],
            item['location'],
            item['category'],
          ].join(' ').toLowerCase().contains(needle);
        }).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [ocean, sky]),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(widget.icon, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle,
                          style: const TextStyle(
                            color: Color(0xFFDDF4FF),
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              onChanged: (value) => setState(() => query = value),
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!snapshot.hasData)
              const Center(child: CircularProgressIndicator())
            else if (filtered.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.empty,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted),
                ),
              )
            else
              ...filtered.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: UtilityInfoCard(
                    item: item,
                    icon: widget.icon,
                    phoneMode: widget.phoneMode,
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class UtilityInfoCard extends StatelessWidget {
  const UtilityInfoCard({
    super.key,
    required this.item,
    required this.icon,
    required this.phoneMode,
  });

  final Map<String, dynamic> item;
  final IconData icon;
  final bool phoneMode;

  @override
  Widget build(BuildContext context) {
    final title = (item['title'] ?? item['name'] ?? 'Informação').toString();
    final description = (item['description'] ?? '').toString();
    final location = (item['location'] ?? item['address'] ?? '').toString();
    final phone = (item['phone'] ?? item['contact'] ?? '').toString();
    final link = (item['link'] ?? item['url'] ?? item['maps'] ?? '').toString();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: sky.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: ocean),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      location,
                      style: const TextStyle(color: ocean, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            if (phoneMode && phone.isNotEmpty)
              IconButton.filledTonal(
                onPressed: () => openUrl(context, 'tel:$phone', title),
                icon: const Icon(Icons.call_rounded),
              )
            else if (link.isNotEmpty)
              IconButton(
                onPressed: () => openUrl(context, link, title),
                icon: const Icon(Icons.open_in_new_rounded, color: sky),
              ),
          ],
        ),
      ),
    );
  }
}

class UtilityManager extends StatelessWidget {
  const UtilityManager({super.key});

  Future<void> _move(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    int delta,
  ) async {
    final item = UtilityItem.fromFirestore(doc);
    await doc.reference.update({
      'order': item.order + delta,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await recordAdminAudit(
      action: 'reorder',
      collection: 'utilities',
      documentId: doc.id,
      label: item.name,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Utilidades da cidade')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UtilityEditor()),
      ),
      icon: const Icon(Icons.add_rounded),
      label: const Text('Adicionar'),
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(FirestoreCollections.utilities)
          .orderBy('order')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'Ainda não há utilidades cadastradas. Use Adicionar para criar a primeira.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final item = UtilityItem.fromFirestore(doc);
            return ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              leading: Icon(utilityIcon(item.iconKey), color: ocean),
              title: Text(
                item.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${item.active ? 'Ativo' : 'Inativo'} · ${item.destinationType} · ordem ${item.order}',
              ),
              trailing: Wrap(
                spacing: 2,
                children: [
                  IconButton(
                    tooltip: 'Subir',
                    onPressed: () => _move(doc, -10),
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  ),
                  IconButton(
                    tooltip: 'Descer',
                    onPressed: () => _move(doc, 10),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  IconButton(
                    tooltip: 'Editar',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UtilityEditor(doc: doc),
                      ),
                    ),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}

class UtilityEditor extends StatefulWidget {
  const UtilityEditor({super.key, this.doc});

  final DocumentSnapshot<Map<String, dynamic>>? doc;

  @override
  State<UtilityEditor> createState() => _UtilityEditorState();
}

class _UtilityEditorState extends State<UtilityEditor> {
  late final TextEditingController name;
  late final TextEditingController description;
  late final TextEditingController destination;
  late final TextEditingController order;
  late String iconKey;
  late String destinationType;
  bool active = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final data = widget.doc?.data() ?? {};
    name = TextEditingController(
      text: (data['name'] ?? data['title'] ?? '').toString(),
    );
    description = TextEditingController(
      text: (data['description'] ?? '').toString(),
    );
    destination = TextEditingController(
      text: (data['destination'] ?? data['link'] ?? '').toString(),
    );
    order = TextEditingController(text: (data['order'] ?? '0').toString());
    iconKey = utilityIconMap.containsKey(data['iconKey'])
        ? data['iconKey'].toString()
        : 'services';
    destinationType =
        utilityDestinationTypes.contains(
          (data['destinationType'] ?? '').toString(),
        )
        ? data['destinationType'].toString()
        : 'internal';
    active = data['active'] as bool? ?? data['published'] as bool? ?? true;
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    destination.dispose();
    order.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) return;
    setState(() => saving = true);
    final data = {
      'name': name.text.trim(),
      'iconKey': iconKey,
      'description': description.text.trim(),
      'destinationType': destinationType,
      'destination': destination.text.trim(),
      'order': int.tryParse(order.text.trim()) ?? 0,
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
      if (widget.doc == null) 'createdAt': FieldValue.serverTimestamp(),
    };
    try {
      final reference = widget.doc == null
          ? await FirebaseFirestore.instance
                .collection(FirestoreCollections.utilities)
                .add(data)
          : widget.doc!.reference;
      if (widget.doc != null) {
        await reference.set(data, SetOptions(merge: true));
      }
      await recordAdminAudit(
        action: widget.doc == null ? 'create' : 'update',
        collection: 'utilities',
        documentId: reference.id,
        label: name.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
      }
    } on FirebaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível salvar a utilidade.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Future<void> remove() async {
    final doc = widget.doc;
    if (doc == null) return;
    try {
      await doc.reference.delete();
      await recordAdminAudit(
        action: 'delete',
        collection: 'utilities',
        documentId: doc.id,
        label: name.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
      }
    } on FirebaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível excluir agora.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.doc == null ? 'Adicionar utilidade' : 'Editar'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Nome',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: description,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Descrição curta',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        UtilityIconPicker(
          value: iconKey,
          onChanged: (value) => setState(() => iconKey = value),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: destinationType,
          decoration: const InputDecoration(
            labelText: 'Tipo de destino',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'internal', child: Text('Página interna')),
            DropdownMenuItem(value: 'url', child: Text('URL')),
            DropdownMenuItem(value: 'phone', child: Text('Telefone')),
            DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp')),
            DropdownMenuItem(value: 'map', child: Text('Mapa')),
          ],
          onChanged: (value) =>
              setState(() => destinationType = value ?? destinationType),
        ),
        const SizedBox(height: 14),
        if (destinationType == 'internal')
          DropdownButtonFormField<String>(
            initialValue: internalUtilityPages.containsKey(destination.text)
                ? destination.text
                : null,
            decoration: const InputDecoration(
              labelText: 'Página interna',
              border: OutlineInputBorder(),
            ),
            items: internalUtilityPages.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: (value) =>
                setState(() => destination.text = value ?? ''),
          )
        else
          TextField(
            controller: destination,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Destino, link, telefone ou mapa',
              border: OutlineInputBorder(),
            ),
          ),
        const SizedBox(height: 14),
        TextField(
          controller: order,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Ordem',
            helperText: 'Menor número aparece primeiro',
            border: OutlineInputBorder(),
          ),
        ),
        SwitchListTile(
          value: active,
          onChanged: (value) => setState(() => active = value),
          title: const Text('Ativo'),
          subtitle: const Text('Somente ativos aparecem para usuários comuns'),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Salvando...' : 'Salvar utilidade'),
        ),
        if (widget.doc != null)
          TextButton.icon(
            onPressed: remove,
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: const Text(
              'Excluir utilidade',
              style: TextStyle(color: Colors.red),
            ),
          ),
      ],
    ),
  );
}

class UtilityIconPicker extends StatelessWidget {
  const UtilityIconPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Ícone', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: utilityIconMap.entries.map((entry) {
          final selected = entry.key == value;
          return ChoiceChip(
            selected: selected,
            avatar: UtilityIconBadge(
              iconKey: entry.key,
              size: 26,
              iconSize: 22,
            ),
            label: Text(entry.key),
            onSelected: (_) => onChanged(entry.key),
            selectedColor: orange,
            labelStyle: TextStyle(color: selected ? Colors.white : ink),
          );
        }).toList(),
      ),
    ],
  );
}

class ResourcesHub extends StatefulWidget {
  const ResourcesHub({super.key});

  @override
  State<ResourcesHub> createState() => _ResourcesHubState();
}

class _ResourcesHubState extends State<ResourcesHub> {
  String query = '';

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: soft,
    appBar: AppBar(title: const Text('Utilidades')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(FirestoreCollections.utilities)
          .orderBy('order')
          .snapshots(),
      builder: (context, snapshot) {
        final remote =
            snapshot.data?.docs
                .map(UtilityItem.fromFirestore)
                .where((item) => item.active)
                .toList() ??
            const <UtilityItem>[];
        final items = remote.isEmpty
            ? fallbackUtilities
            : (remote..sort((a, b) => a.order.compareTo(b.order)));
        final filtered = items.where((item) {
          final needle = query.toLowerCase().trim();
          if (needle.isEmpty) return true;
          return '${item.name} ${item.description} ${item.destination}'
              .toLowerCase()
              .contains(needle);
        }).toList();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [ocean, sky]),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: ocean.withValues(alpha: .16),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Utilidades',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Tudo que você precisa no dia a dia em Cachoeiras de Macacu',
                    style: TextStyle(color: Color(0xFFDDF4FF), height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              onChanged: (value) => setState(() => query = value),
              decoration: InputDecoration(
                hintText: 'Buscar uma utilidade...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhuma utilidade encontrada.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.46,
                ),
                itemBuilder: (context, index) =>
                    UtilityGridCard(item: filtered[index]),
              ),
          ],
        );
      },
    ),
  );
}

class UtilityGridCard extends StatelessWidget {
  const UtilityGridCard({super.key, required this.item});

  final UtilityItem item;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: ocean.withValues(alpha: .10),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openUtilityDestination(context, item),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.white, Color(0xFFEAF4FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFDDEBFF)),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -22,
                top: -28,
                child: Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: orange.withValues(alpha: .13),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: sky.withValues(alpha: .55),
                  size: 20,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(13),
                child: Row(
                  children: [
                    UtilityIconBadge(iconKey: item.iconKey, size: 58),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ink,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            item.description.isEmpty
                                ? 'Toque para abrir'
                                : item.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: muted,
                              fontSize: 12,
                              height: 1.18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class BusinessMapView extends StatelessWidget {
  const BusinessMapView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mapa de Macacu')),
    body: StreamBuilder<List<Business>>(
      stream: businessRepository.watchPublishedBusinesses(),
      builder: (context, snapshot) {
        final businesses =
            snapshot.data?.where((item) => item.maps.isNotEmpty).toList() ??
            const <Business>[];
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (businesses.isEmpty) {
          return const Center(
            child: Text('Ainda não há locais com mapa cadastrado.'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: businesses.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, index) {
            final business = businesses[index];
            return ListTile(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: BusinessAvatar(business: business, size: 48),
              title: Text(
                business.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(business.location),
              trailing: const Icon(Icons.directions_outlined, color: ocean),
              onTap: () => openUrl(context, business.maps, 'Google Maps'),
            );
          },
        );
      },
    ),
  );
}

class FirestoreContentList extends StatelessWidget {
  const FirestoreContentList({
    super.key,
    required this.collection,
    required this.empty,
    this.actionLabel = 'Abrir',
  });
  final String collection, empty, actionLabel;
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(collection)
            .where('published', isEqualTo: true)
            .snapshots(),
        builder: (context, s) {
          final data =
              (s.data?.docs
                  .map((d) => d.data())
                  .where(isActiveContent)
                  .toList() ??
              []);
          if (data.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(empty, textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: data.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final item = data[i];
              return LocalContentCard(
                item: item,
                actionLabel: actionLabel,
                metricAction: collection == 'coupons' ? 'coupon_open' : null,
                metricTargetType: collection,
              );
            },
          );
        },
      );
}

class FirestoreContentScaffold extends StatelessWidget {
  const FirestoreContentScaffold({
    super.key,
    required this.title,
    required this.collection,
    required this.empty,
    this.actionLabel = 'Abrir',
  });

  final String title, collection, empty, actionLabel;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: FirestoreContentList(
      collection: collection,
      empty: empty,
      actionLabel: actionLabel,
    ),
  );
}

class LocalContentCard extends StatelessWidget {
  const LocalContentCard({
    super.key,
    required this.item,
    required this.actionLabel,
    this.metricAction,
    this.metricTargetType,
  });

  final Map<String, dynamic> item;
  final String actionLabel;
  final String? metricAction;
  final String? metricTargetType;

  @override
  Widget build(BuildContext context) {
    final images = contentImageUrls(item);
    final title = (item['title'] ?? '').toString();
    final description = (item['description'] ?? '').toString();
    final link = (item['link'] ?? '').toString();
    final maps = (item['maps'] ?? item['mapsUrl'] ?? '').toString();
    final whatsapp = (item['whatsapp'] ?? '').toString();
    final phone = (item['phone'] ?? '').toString();
    final actionUrl = link.isNotEmpty
        ? link
        : maps.isNotEmpty
        ? maps
        : whatsapp.isNotEmpty
        ? (whatsapp.startsWith('http')
              ? whatsapp
              : 'https://wa.me/${whatsapp.replaceAll(RegExp(r'\D'), '')}')
        : phone.isNotEmpty
        ? (phone.startsWith('tel:') ? phone : 'tel:$phone')
        : '';
    final meta = localContentMeta(item);
    final additionalInfo = (item['additionalInfo'] ?? '').toString().trim();
    void openContentLink() {
      final action = metricAction;
      if (action != null) {
        unawaited(
          recordMetric(
            action,
            target: title,
            targetType: metricTargetType ?? 'content',
          ),
        );
      }
      openUrl(context, actionUrl, actionLabel);
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: actionUrl.isEmpty ? null : openContentLink,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (images.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      images.first,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const ColoredBox(
                          color: mist,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      },
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: mist,
                        child: Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (images.length > 1)
                  Text(
                    '${images.length} fotos disponíveis',
                    style: const TextStyle(
                      color: ocean,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  meta,
                  style: const TextStyle(
                    color: ocean,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(description, style: const TextStyle(color: muted)),
              ],
              if (additionalInfo.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(additionalInfo, style: const TextStyle(fontSize: 12)),
              ],
              if (actionUrl.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: openContentLink,
                    child: Text(actionLabel),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CouponsView extends StatelessWidget {
  const CouponsView({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cupons exclusivos')),
    body: const FirestoreContentList(
      collection: 'coupons',
      empty: 'Novos cupons aparecerão aqui.',
      actionLabel: 'Usar',
    ),
  );
}

class LocalAlertsView extends StatelessWidget {
  const LocalAlertsView({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Avisos importantes')),
    body: const FirestoreContentList(
      collection: 'alerts',
      empty: 'Não há avisos importantes no momento.',
      actionLabel: 'Ver',
    ),
  );
}

class LocalJobsView extends StatelessWidget {
  const LocalJobsView({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Vagas em Macacu')),
    body: const FirestoreContentList(
      collection: 'jobs',
      empty: 'Não há vagas publicadas no momento.',
      actionLabel: 'Ver vaga',
    ),
  );
}

class LocalNewsView extends StatelessWidget {
  const LocalNewsView({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notícias locais')),
    body: const FirestoreContentList(
      collection: 'news',
      empty: 'Não há notícias publicadas no momento.',
      actionLabel: 'Ler',
    ),
  );
}

class TouristRoutesView extends StatelessWidget {
  const TouristRoutesView({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Roteiros turísticos')),
    body: const FirestoreContentList(
      collection: 'routes',
      empty: 'Em breve você verá roteiros para explorar Macacu.',
      actionLabel: 'Ver roteiro',
    ),
  );
}

class EventsReminderView extends StatelessWidget {
  const EventsReminderView({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Agenda com lembrete')),
    body: const FirestoreContentList(
      collection: 'events',
      empty: 'Nenhum evento publicado no momento.',
      actionLabel: 'Lembrar',
    ),
  );
}

class PollsView extends StatelessWidget {
  const PollsView({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Enquetes da cidade')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(FirestoreCollections.polls)
          .where('published', isEqualTo: true)
          .snapshots(),
      builder: (context, s) {
        final docs = s.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Text('Em breve teremos enquetes para a cidade.'),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: docs.map((d) {
            final data = d.data();
            final options = List<String>.from(data['options'] ?? []);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (data['title'] ?? 'Enquete').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    ...options.map(
                      (option) => OutlinedButton(
                        onPressed: FirebaseAuth.instance.currentUser == null
                            ? null
                            : () => d.reference
                                  .collection(FirestoreCollections.votes)
                                  .doc(FirebaseAuth.instance.currentUser!.uid)
                                  .set({
                                    'option': option,
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  }),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(option),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    ),
  );
}

class BusinessProposalView extends StatefulWidget {
  const BusinessProposalView({super.key});
  @override
  State<BusinessProposalView> createState() => _BusinessProposalViewState();
}

class _BusinessProposalViewState extends State<BusinessProposalView> {
  final name = TextEditingController();
  final contact = TextEditingController();
  final details = TextEditingController();
  bool sending = false;
  @override
  void dispose() {
    name.dispose();
    contact.dispose();
    details.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (name.text.trim().isEmpty || details.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      await FirebaseFirestore.instance
          .collection(FirestoreCollections.businessProposals)
          .add({
            'name': name.text.trim(),
            'contact': contact.text.trim(),
            'details': details.text.trim(),
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
          });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recebido. Você fará a revisão antes de publicar.'),
          ),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Indique uma empresa')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Envie os dados. A publicação depende da aprovação do administrador.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Nome da empresa',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: contact,
          decoration: const InputDecoration(
            labelText: 'WhatsApp ou contato',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: details,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Descrição e informações',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: sending ? null : send,
          child: Text(sending ? 'Enviando...' : 'Enviar para aprovação'),
        ),
      ],
    ),
  );
}

class NotificationsView extends StatelessWidget {
  const NotificationsView({super.key});
  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase() ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Notificações')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(FirestoreCollections.notifications)
            .where('published', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          final items =
              (snapshot.data?.docs
                        .map((d) => d.data())
                        .where(
                          (item) =>
                              isActiveContent(item) &&
                              ((item['targetEmail'] ?? '').toString().isEmpty ||
                                  (item['targetEmail'] ?? '')
                                          .toString()
                                          .toLowerCase() ==
                                      email),
                        )
                        .toList() ??
                    [])
                ..sort(
                  (a, b) =>
                      ((b['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                              0)
                          .compareTo(
                            (a['updatedAt'] as Timestamp?)
                                    ?.millisecondsSinceEpoch ??
                                0,
                          ),
                );
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'Você está em dia. As novidades de Macacu aparecerão aqui.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final item = items[i];
              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                tileColor: Colors.white,
                leading: const CircleIcon(
                  icon: Icons.notifications_active_rounded,
                ),
                title: Text(
                  (item['title'] ?? 'Novidade em Macacu').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text((item['description'] ?? '').toString()),
                onTap: () {
                  unawaited(
                    recordMetric(
                      'notification_open',
                      target: (item['title'] ?? '').toString(),
                      targetType: 'notification',
                    ),
                  );
                  openUrl(
                    context,
                    (item['link'] ?? '').toString(),
                    'notificação',
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class NotificationComposer extends StatefulWidget {
  const NotificationComposer({super.key});
  @override
  State<NotificationComposer> createState() => _NotificationComposerState();
}

class _NotificationComposerState extends State<NotificationComposer> {
  final title = TextEditingController();
  final message = TextEditingController();
  final link = TextEditingController();
  final recipient = TextEditingController();
  bool sendToAll = true;
  bool sending = false;
  @override
  void dispose() {
    title.dispose();
    message.dispose();
    link.dispose();
    recipient.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (title.text.trim().isEmpty ||
        message.text.trim().isEmpty ||
        (!sendToAll && recipient.text.trim().isEmpty)) {
      return;
    }
    setState(() => sending = true);
    final targetEmail = sendToAll ? '' : recipient.text.trim().toLowerCase();
    final payload = {
      'title': title.text.trim(),
      'description': message.text.trim(),
      'link': link.text.trim(),
      'targetEmail': targetEmail,
      'published': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    try {
      final notification = await FirebaseFirestore.instance
          .collection(FirestoreCollections.notifications)
          .add(payload);
      await FirebaseFirestore.instance
          .collection(FirestoreCollections.pushQueue)
          .add({
            ...payload,
            'status': 'queued',
            'createdAt': FieldValue.serverTimestamp(),
          });
      await recordAdminAudit(
        action: 'send_notification',
        collection: 'notifications',
        documentId: notification.id,
        label: title.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notificação preparada para envio.')),
        );
        Navigator.pop(context);
      }
    } on FirebaseException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível preparar a notificação.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Enviar notificação')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Aparece dentro do app e, com o push ativado, como alerta no celular.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: title,
          decoration: const InputDecoration(
            labelText: 'Título',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: message,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Mensagem',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: link,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Link ao tocar (opcional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          value: sendToAll,
          onChanged: (value) => setState(() => sendToAll = value),
          title: const Text('Enviar para todos'),
          subtitle: Text(
            sendToAll
                ? 'Todos os usuários que permitiram notificações.'
                : 'Enviar somente para uma conta específica.',
          ),
          contentPadding: EdgeInsets.zero,
        ),
        if (!sendToAll)
          TextField(
            controller: recipient,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-mail da conta',
              border: OutlineInputBorder(),
            ),
          ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: sending ? null : send,
          icon: const Icon(Icons.send_rounded),
          label: Text(sending ? 'Preparando...' : 'Disparar notificação'),
        ),
      ],
    ),
  );
}

class ReviewForm extends StatefulWidget {
  const ReviewForm({super.key, required this.business});
  final Business business;
  @override
  State<ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends State<ReviewForm> {
  final message = TextEditingController();
  int stars = 5;
  bool sending = false;
  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Entre com Google para enviar uma avaliação.'),
          ),
        );
      }
      return;
    }
    if (message.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      await FirebaseFirestore.instance
          .collection(FirestoreCollections.reviews)
          .add({
            'business': widget.business.name,
            'message': message.text.trim(),
            'stars': stars,
            'userId': user.uid,
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
          });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Recebido. O administrador vai revisar antes de publicar.',
            ),
          ),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Avaliar estabelecimento')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          widget.business.name,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Sua avaliação é revisada pelo administrador antes de aparecer.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 20),
        Wrap(
          children: List.generate(
            5,
            (i) => IconButton(
              onPressed: () => setState(() => stars = i + 1),
              icon: Icon(
                i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                color: yellow,
                size: 32,
              ),
            ),
          ),
        ),
        TextField(
          controller: message,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Avaliação ou correção',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: sending ? null : send,
          child: Text(sending ? 'Enviando...' : 'Enviar para revisão'),
        ),
      ],
    ),
  );
}

class ReviewManager extends StatelessWidget {
  const ReviewManager({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Avaliações e correções')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(FirestoreCollections.reviews)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final docs = s.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('Nenhuma avaliação pendente.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final d = docs[i];
            final item = d.data();
            return ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              tileColor: Colors.white,
              title: Text(
                (item['business'] ?? '').toString(),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${item['stars'] ?? 0} estrelas · ${item['message'] ?? ''}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) => d.reference.update({'status': value}),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'approved', child: Text('Aprovar')),
                  PopupMenuItem(value: 'rejected', child: Text('Recusar')),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}

class AdminMetricsView extends StatefulWidget {
  const AdminMetricsView({super.key});

  @override
  State<AdminMetricsView> createState() => _AdminMetricsViewState();
}

class _AdminMetricsViewState extends State<AdminMetricsView> {
  String period = '7d';

  DateTime? get startDate {
    final now = DateTime.now();
    return switch (period) {
      'today' => DateTime(now.year, now.month, now.day),
      '7d' => now.subtract(const Duration(days: 7)),
      '30d' => now.subtract(const Duration(days: 30)),
      _ => null,
    };
  }

  Query<Map<String, dynamic>> metricsQuery() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection(FirestoreCollections.metrics)
        .orderBy('createdAt', descending: true)
        .limit(500);
    final start = startDate;
    if (start != null) {
      query = query.where(
        'createdAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(start),
      );
    }
    return query;
  }

  int countAction(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Set<String> actions,
  ) => docs.where((doc) => actions.contains(doc.data()['action'])).length;

  Map<String, int> countByTarget(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Set<String> actions,
  ) {
    final result = <String, int>{};
    for (final doc in docs) {
      final data = doc.data();
      if (!actions.contains(data['action'])) continue;
      final target = (data['target'] ?? '').toString();
      if (target.isEmpty) continue;
      result[target] = (result[target] ?? 0) + 1;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (!isAdminUser(FirebaseAuth.instance.currentUser)) {
      return const Scaffold(
        body: Center(child: Text('Acesso restrito ao administrador.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Métricas comerciais')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: metricsQuery().snapshots(),
        builder: (context, s) {
          if (s.hasError) {
            return const Center(
              child: Text(
                'Não foi possível carregar as métricas. Tente novamente.',
              ),
            );
          }
          final docs = s.data?.docs ?? [];
          final businessViews = countAction(docs, {'business_open'});
          final whatsapp = countAction(docs, {'business_whatsapp'});
          final calls = countAction(docs, {'business_phone'});
          final maps = countAction(docs, {'business_map'});
          final instagram = countAction(docs, {'business_instagram'});
          final favorites = countAction(docs, {'favorite_add'});
          final shares = countAction(docs, {'business_share'});
          final coupons = countAction(docs, {'coupon_open', 'offer_open'});
          final banners = countAction(docs, {'banner_view', 'ad_view'});
          final contacts = countAction(docs, {
            'business_whatsapp',
            'business_phone',
            'classified_contact',
            'adoption_contact',
          });
          final businessRanking = countByTarget(docs, {
            'business_open',
            'business_whatsapp',
            'business_phone',
            'business_map',
            'business_instagram',
            'favorite_add',
            'business_share',
          }).entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Desempenho comercial',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Dados agregados. O app não grava dados pessoais nas métricas.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'today', label: Text('Hoje')),
                  ButtonSegment(value: '7d', label: Text('7 dias')),
                  ButtonSegment(value: '30d', label: Text('30 dias')),
                  ButtonSegment(value: 'all', label: Text('Tudo')),
                ],
                selected: {period},
                onSelectionChanged: (value) =>
                    setState(() => period = value.first),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  MetricTile(
                    label: 'Visualizações',
                    value: businessViews.toString(),
                    icon: Icons.storefront_outlined,
                  ),
                  MetricTile(
                    label: 'Contatos',
                    value: contacts.toString(),
                    icon: Icons.forum_outlined,
                  ),
                  MetricTile(
                    label: 'WhatsApp',
                    value: whatsapp.toString(),
                    icon: Icons.chat_outlined,
                  ),
                  MetricTile(
                    label: 'Ligações',
                    value: calls.toString(),
                    icon: Icons.call_outlined,
                  ),
                  MetricTile(
                    label: 'Mapa',
                    value: maps.toString(),
                    icon: Icons.map_outlined,
                  ),
                  MetricTile(
                    label: 'Instagram',
                    value: instagram.toString(),
                    icon: Icons.photo_camera_outlined,
                  ),
                  MetricTile(
                    label: 'Favoritos',
                    value: favorites.toString(),
                    icon: Icons.favorite_outline_rounded,
                  ),
                  MetricTile(
                    label: 'Compart.',
                    value: shares.toString(),
                    icon: Icons.ios_share_rounded,
                  ),
                  MetricTile(
                    label: 'Cupons/ofertas',
                    value: coupons.toString(),
                    icon: Icons.confirmation_number_outlined,
                  ),
                  MetricTile(
                    label: 'Banners',
                    value: banners.toString(),
                    icon: Icons.campaign_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                'Estabelecimentos com mais interações',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (businessRanking.isEmpty)
                const Text(
                  'Ainda não há métricas suficientes para ranking.',
                  style: TextStyle(color: muted),
                )
              else
                ...businessRanking
                    .take(12)
                    .map(
                      (entry) => ListTile(
                        leading: const Icon(
                          Icons.insights_rounded,
                          color: ocean,
                        ),
                        title: Text(entry.key),
                        trailing: Text(
                          entry.value.toString(),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
              const SizedBox(height: 18),
              const Text(
                'Últimas interações',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ...docs
                  .take(20)
                  .map(
                    (d) => ListTile(
                      title: Text(
                        (d.data()['target'] ?? d.data()['action'] ?? '')
                            .toString(),
                      ),
                      subtitle: Text((d.data()['action'] ?? '').toString()),
                      leading: const Icon(Icons.timeline_rounded, color: ocean),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: ocean),
          const SizedBox(height: 16),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(label, style: const TextStyle(color: muted, fontSize: 12)),
        ],
      ),
    ),
  );
}

enum Feature { jobs, news, events, tourism }

void openFeature(BuildContext context, Feature feature) =>
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => feature == Feature.tourism
            ? const TourismHomeView()
            : feature == Feature.events
            ? const CityAgendaView()
            : FeatureView(feature: feature),
      ),
    );

class TourismHomeView extends StatelessWidget {
  const TourismHomeView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Turismo')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(FirestoreCollections.routes)
          .where('published', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        final spots =
            snapshot.data?.docs.map(TouristSpot.fromDoc).toList() ??
            const <TouristSpot>[];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          children: [
            NatureBanner(onTap: () {}),
            const SizedBox(height: 18),
            Text(
              'Descubra Cachoeiras de Macacu',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'Cachoeiras, trilhas e roteiros cadastrados com fotos reais pelo administrador.',
              style: TextStyle(color: muted, height: 1.35),
            ),
            const SizedBox(height: 18),
            TourismCategoryCard(
              title: 'Cachoeiras',
              subtitle: 'Explore lugares com água, natureza e visual',
              icon: AppIcon.cachoeiras,
              fallbackAsset: 'assets/images/tourism-bg-cachoeiras.png',
              spots: spots
                  .where((spot) => spot.category.contains('cachoeira'))
                  .toList(),
            ),
            TourismCategoryCard(
              title: 'Trilhas',
              subtitle: 'Aventure-se com informações cadastradas',
              icon: AppIcon.trilhas,
              fallbackAsset: 'assets/images/tourism-bg-trilhas.png',
              spots: spots
                  .where((spot) => spot.category.contains('trilha'))
                  .toList(),
            ),
            TourismCategoryCard(
              title: 'Roteiros',
              subtitle: 'Conheça Macacu por caminhos organizados',
              icon: AppIcon.roteiros,
              fallbackAsset: 'assets/images/tourism-bg-roteiros.png',
              spots: spots
                  .where(
                    (spot) =>
                        spot.category.contains('roteiro') ||
                        spot.category.contains('route'),
                  )
                  .toList(),
            ),
            TourismCategoryCard(
              title: 'Pontos turísticos',
              subtitle: 'História, natureza e lugares para visitar',
              icon: AppIcon.pontosTuristicos,
              fallbackAsset: 'assets/images/tourism-bg-pontos-turisticos.png',
              spots: spots
                  .where(
                    (spot) =>
                        spot.category.contains('ponto') ||
                        spot.category.contains('turistico') ||
                        spot.category.contains('turístico') ||
                        spot.category.contains('atrativo') ||
                        spot.category.contains('hist'),
                  )
                  .toList(),
            ),
            if (spots.isEmpty && snapshot.hasData) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Nenhum ponto turístico publicado ainda. O administrador pode cadastrar fotos, categoria, descrição e rota em Admin → Conteúdo → Turismo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}

class TourismCategoryCard extends StatelessWidget {
  const TourismCategoryCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.fallbackAsset,
    required this.spots,
  });

  final String title, subtitle;
  final AppIcon icon;
  final String fallbackAsset;
  final List<TouristSpot> spots;

  @override
  Widget build(BuildContext context) {
    final image = spots
        .expand((spot) => spot.images)
        .cast<String?>()
        .firstWhere((url) => url != null && url.isNotEmpty, orElse: () => null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TourismCategoryView(title: title, spots: spots),
            ),
          ),
          child: SizedBox(
            height: 172,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (image != null) ...[
                  Image.network(
                    image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Image.asset(fallbackAsset, fit: BoxFit.cover),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          ink.withValues(alpha: .78),
                          ocean.withValues(alpha: .24),
                        ],
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .93),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: ink.withValues(alpha: .22),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: App3DIcon(icon: icon, size: 44),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          title.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 19,
                            height: 1.05,
                            letterSpacing: -.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${spots.length} publicado(s)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFEAF4FF),
                            fontSize: 12.5,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else
                  Image.asset(fallbackAsset, fit: BoxFit.cover),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TourismCategoryView extends StatelessWidget {
  const TourismCategoryView({
    super.key,
    required this.title,
    required this.spots,
  });

  final String title;
  final List<TouristSpot> spots;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: spots.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'Ainda não há locais publicados nesta categoria.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: spots.length,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (context, index) =>
                TouristSpotCard(spot: spots[index]),
          ),
  );
}

class TouristSpotCard extends StatelessWidget {
  const TouristSpotCard({super.key, required this.spot});

  final TouristSpot spot;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TouristSpotDetailView(spot: spot)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: spot.images.isEmpty
                ? const ColoredBox(
                    color: mist,
                    child: Icon(Icons.photo_outlined, color: muted),
                  )
                : Image.network(spot.images.first, fit: BoxFit.cover),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spot.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                if (spot.location.isNotEmpty)
                  Text(
                    '📍 ${spot.location}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TouristSpotDetailView(spot: spot),
                    ),
                  ),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Ver local'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class TouristSpotDetailView extends StatefulWidget {
  const TouristSpotDetailView({super.key, required this.spot});

  final TouristSpot spot;

  @override
  State<TouristSpotDetailView> createState() => _TouristSpotDetailViewState();
}

class _TouristSpotDetailViewState extends State<TouristSpotDetailView> {
  int photo = 0;
  bool saved = false;

  @override
  Widget build(BuildContext context) {
    final spot = widget.spot;
    final images = spot.images;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 310,
            pinned: true,
            title: Text(spot.title),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (images.isEmpty)
                    const ColoredBox(color: mist)
                  else
                    PageView.builder(
                      itemCount: images.length,
                      onPageChanged: (value) => setState(() => photo = value),
                      itemBuilder: (_, index) =>
                          Image.network(images[index], fit: BoxFit.cover),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          ink.withValues(alpha: .62),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  if (images.isNotEmpty)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: ink.withValues(alpha: .70),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${photo + 1} / ${images.length}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (spot.location.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(spot.location, style: const TextStyle(color: muted)),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: spot.maps.isEmpty
                              ? null
                              : () =>
                                    openUrl(context, spot.maps, 'Como chegar'),
                          icon: const Icon(Icons.navigation_rounded),
                          label: const Text('Como chegar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(
                        onPressed: () => setState(() => saved = !saved),
                        icon: Icon(
                          saved
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: () => openUrl(
                          context,
                          spot.maps,
                          'Compartilhar ${spot.title}',
                        ),
                        icon: const Icon(Icons.share_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (spot.description.isNotEmpty) ...[
                    const SectionLabel('Sobre'),
                    Text(
                      spot.description,
                      style: const TextStyle(height: 1.45),
                    ),
                    const SizedBox(height: 22),
                  ],
                  if (spot.additionalInfo.isNotEmpty) ...[
                    const SectionLabel('Antes de ir'),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: mist,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        spot.additionalInfo,
                        style: const TextStyle(color: ink, height: 1.4),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: ocean,
        fontWeight: FontWeight.w900,
        fontSize: 16,
      ),
    ),
  );
}

class FeatureView extends StatelessWidget {
  const FeatureView({super.key, required this.feature});
  final Feature feature;
  @override
  Widget build(BuildContext context) {
    final tourism = feature == Feature.tourism;
    final collection = tourism
        ? 'routes'
        : feature == Feature.jobs
        ? 'jobs'
        : feature == Feature.news
        ? 'news'
        : 'events';
    final title = tourism
        ? 'Explore Macacu'
        : feature == Feature.jobs
        ? 'Vagas em Macacu'
        : feature == Feature.news
        ? 'Notícias de Macacu'
        : 'Agenda Macacu';
    final sprite = tourism
        ? 5
        : feature == Feature.jobs
        ? 4
        : feature == Feature.news
        ? 6
        : 7;
    final subtitle = tourism
        ? 'Natureza, sabores e experiências para montar o seu roteiro.'
        : feature == Feature.jobs
        ? 'Oportunidades locais publicadas e revisadas para a cidade.'
        : feature == Feature.news
        ? 'Conteúdos locais sempre com a fonte responsável identificada.'
        : 'Eventos e encontros que movimentam a cidade.';
    final empty = tourism
        ? 'Em breve você verá roteiros reais para explorar Macacu.'
        : feature == Feature.jobs
        ? 'Não há vagas publicadas no momento.'
        : feature == Feature.news
        ? 'Não há notícias publicadas no momento.'
        : 'Nenhum evento publicado no momento.';
    final actionLabel = tourism
        ? 'Ver roteiro'
        : feature == Feature.jobs
        ? 'Ver vaga'
        : feature == Feature.news
        ? 'Ler'
        : 'Lembrar';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: Column(
              children: [
                if (tourism) ...[
                  NatureBanner(onTap: () {}),
                  const SizedBox(height: 18),
                ],
                Row(
                  children: [
                    Sprite(index: sprite, size: 68),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(subtitle, style: const TextStyle(color: muted)),
                ),
              ],
            ),
          ),
          Expanded(
            child: FirestoreContentList(
              collection: collection,
              empty: empty,
              actionLabel: actionLabel,
            ),
          ),
        ],
      ),
    );
  }
}

class TodayInMacacuSection extends StatelessWidget {
  const TodayInMacacuSection({super.key});

  Future<_TodaySnapshot> _load() async {
    Future<QuerySnapshot<Map<String, dynamic>>> read(String collection) =>
        FirebaseFirestore.instance
            .collection(collection)
            .where('published', isEqualTo: true)
            .limit(10)
            .get(const GetOptions(source: Source.serverAndCache));
    final results = await Future.wait([
      read('alerts'),
      read('events'),
      read('pharmacy_duties'),
      read('transport'),
      read('trash_collection'),
    ]);
    return _TodaySnapshot(
      alerts: results[0].docs
          .map((doc) => doc.data())
          .where(isActiveContent)
          .toList(),
      events: results[1].docs
          .map((doc) => doc.data())
          .where(isActiveContent)
          .toList(),
      pharmacies: results[2].docs
          .map((doc) => doc.data())
          .where(isActiveContent)
          .toList(),
      transport: results[3].docs
          .map((doc) => doc.data())
          .where(isActiveContent)
          .toList(),
      trash: results[4].docs
          .map((doc) => doc.data())
          .where(isActiveContent)
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_TodaySnapshot>(
    future: _load(),
    builder: (context, snapshot) {
      final data = snapshot.data ?? const _TodaySnapshot();
      final cards = [
        _TodayCard(
          title: 'Clima',
          value: '—',
          detail: 'Integração preparada',
          icon: Icons.wb_sunny_outlined,
          color: sky,
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'O clima será exibido quando uma fonte confiável for conectada.',
              ),
            ),
          ),
        ),
        _TodayCard(
          title: 'Ônibus',
          value: data.transport.isEmpty
              ? '—'
              : data.transport.length.toString(),
          detail: data.transport.isEmpty
              ? 'Sem horários publicados'
              : 'informações publicadas',
          icon: Icons.directions_bus_rounded,
          color: ocean,
          onTap: () => openUtilityDestination(context, fallbackUtilities.first),
        ),
        _TodayCard(
          title: 'Plantão',
          value: data.pharmacies.isEmpty
              ? '—'
              : data.pharmacies.length.toString(),
          detail: data.pharmacies.isEmpty
              ? 'Sem escala publicada'
              : 'farmácia cadastrada',
          icon: Icons.local_pharmacy_outlined,
          color: orange,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PharmacyDutyView()),
          ),
        ),
        _TodayCard(
          title: 'Eventos',
          value: data.events.isEmpty ? '—' : data.events.length.toString(),
          detail: data.events.isEmpty ? 'Sem agenda publicada' : 'na agenda',
          icon: Icons.event_available_outlined,
          color: yellow,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CityAgendaView()),
          ),
        ),
        _TodayCard(
          title: 'Avisos',
          value: data.alerts.isEmpty ? '—' : data.alerts.length.toString(),
          detail: data.alerts.isEmpty ? 'Sem alerta ativo' : 'alerta ativo',
          icon: Icons.warning_amber_rounded,
          color: data.hasUrgentAlert ? Colors.redAccent : ink,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CityAlertsView()),
          ),
        ),
        _TodayCard(
          title: 'Coleta',
          value: data.trash.isEmpty ? '—' : data.trash.length.toString(),
          detail: data.trash.isEmpty ? 'Sem rota publicada' : 'rota cadastrada',
          icon: Icons.delete_outline_rounded,
          color: const Color(0xFF475569),
          onTap: () => openUtilityDestination(context, fallbackUtilities[1]),
        ),
      ];
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Hoje em Macacu',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: cards.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, index) => cards[index],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _TodaySnapshot {
  const _TodaySnapshot({
    this.alerts = const [],
    this.events = const [],
    this.pharmacies = const [],
    this.transport = const [],
    this.trash = const [],
  });
  final List<Map<String, dynamic>> alerts, events, pharmacies, transport, trash;
  bool get hasUrgentAlert => alerts.any(
    (item) =>
        (item['priority'] ?? '').toString().toLowerCase().contains('urgent'),
  );
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title, value, detail;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 124,
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: muted, fontSize: 9, height: 1.05),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class CityAlertsView extends StatelessWidget {
  const CityAlertsView({super.key});

  @override
  Widget build(BuildContext context) => const FirestoreContentScaffold(
    title: 'Alertas da cidade',
    collection: 'alerts',
    empty:
        'Nenhum alerta ativo publicado. O administrador pode cadastrar avisos reais por categoria e prioridade.',
    actionLabel: 'Abrir aviso',
  );
}

class PharmacyDutyView extends StatelessWidget {
  const PharmacyDutyView({super.key});

  @override
  Widget build(BuildContext context) => const FirestoreContentScaffold(
    title: 'Farmácia de plantão',
    collection: 'pharmacy_duties',
    empty:
        'Nenhuma farmácia de plantão publicada. Cadastre somente escalas reais e conferidas.',
    actionLabel: 'Ver contato',
  );
}

class EmergencyContactsView extends StatelessWidget {
  const EmergencyContactsView({super.key});

  @override
  Widget build(BuildContext context) => const FirestoreContentScaffold(
    title: 'Emergência',
    collection: 'emergency_contacts',
    empty:
        'Nenhum contato de emergência cadastrado. Inclua apenas telefones oficiais conferidos.',
    actionLabel: 'Ligar',
  );
}

class PublicPlacesView extends StatelessWidget {
  const PublicPlacesView({super.key});

  @override
  Widget build(BuildContext context) => const FirestoreContentScaffold(
    title: 'Locais públicos',
    collection: 'public_places',
    empty: 'Nenhum local público publicado ainda.',
    actionLabel: 'Ver rota',
  );
}

class ResolverGuideView extends StatelessWidget {
  const ResolverGuideView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Onde Resolver?')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [ocean, sky]),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.manage_search_rounded,
                  color: Colors.white,
                  size: 34,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'O que você precisa resolver?',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Busque assuntos cadastrados pelo administrador.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Expanded(
          child: FirestoreContentList(
            collection: 'resolver_subjects',
            empty:
                'Nenhum assunto cadastrado ainda. O administrador pode criar temas como IPTU, vacinação, coleta ou iluminação pública com dados oficiais.',
            actionLabel: 'Abrir orientação',
          ),
        ),
      ],
    ),
  );
}

class CityAgendaView extends StatelessWidget {
  const CityAgendaView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Agenda da cidade')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(FirestoreCollections.events)
          .where('published', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        final items =
            snapshot.data?.docs
                .map((doc) => doc.data())
                .where(isActiveContent)
                .toList() ??
            const <Map<String, dynamic>>[];
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'Nenhum evento publicado. A agenda só exibe informações reais cadastradas pelo administrador.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _AgendaGroup(
              title: 'Hoje',
              items: items.where(_isTodayEvent).toList(),
            ),
            _AgendaGroup(
              title: 'Amanhã',
              items: items.where(_isTomorrowEvent).toList(),
            ),
            _AgendaGroup(
              title: 'Próximos',
              items: items
                  .where(
                    (item) => !_isTodayEvent(item) && !_isTomorrowEvent(item),
                  )
                  .toList(),
            ),
          ],
        );
      },
    ),
  );
}

class _AgendaGroup extends StatelessWidget {
  const _AgendaGroup({required this.title, required this.items});
  final String title;
  final List<Map<String, dynamic>> items;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 6),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
        ),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: LocalContentCard(
              item: item,
              actionLabel: 'Ver evento',
              metricTargetType: 'events',
            ),
          ),
        ),
      ],
    );
  }
}

bool _isTodayEvent(Map<String, dynamic> item) {
  final date = _contentDate(item);
  if (date == null) return false;
  final now = DateTime.now();
  return date.year == now.year &&
      date.month == now.month &&
      date.day == now.day;
}

bool _isTomorrowEvent(Map<String, dynamic> item) {
  final date = _contentDate(item);
  if (date == null) return false;
  final tomorrow = DateTime.now().add(const Duration(days: 1));
  return date.year == tomorrow.year &&
      date.month == tomorrow.month &&
      date.day == tomorrow.day;
}

DateTime? _contentDate(Map<String, dynamic> item) {
  final raw = item['eventDate'] ?? item['date'] ?? item['startsAt'];
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is String) {
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso;
    final match = RegExp(
      r'(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})',
    ).firstMatch(raw);
    if (match != null) {
      final day = int.tryParse(match.group(1)!);
      final month = int.tryParse(match.group(2)!);
      var year = int.tryParse(match.group(3)!);
      if (day != null && month != null && year != null) {
        if (year < 100) year += 2000;
        return DateTime(year, month, day);
      }
    }
  }
  return null;
}

class SearchResultItem {
  const SearchResultItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.imageUrl = '',
  });
  final String title, subtitle, imageUrl;
  final IconData icon;
  final VoidCallback onTap;
}

class SearchResultGroup {
  const SearchResultGroup({required this.title, required this.items});
  final String title;
  final List<SearchResultItem> items;
}

class CitySearch extends SearchDelegate<void> {
  @override
  String get searchFieldLabel => 'Busque empresas, ônibus, turismo, alertas...';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(
      onPressed: () => query = '',
      icon: const Icon(Icons.clear_rounded),
    ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back_rounded),
  );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final term = query.toLowerCase().trim();
    if (term.isEmpty) return _emptySearchIntro(context);
    return FutureBuilder<List<SearchResultGroup>>(
      future: _loadGroups(context, term),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final groups = snapshot.data!
            .where((group) => group.items.isNotEmpty)
            .toList();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              groups.fold<int>(
                        0,
                        (total, group) => total + group.items.length,
                      ) ==
                      0
                  ? 'Nenhum resultado para “$query”'
                  : 'Resultados para “$query”',
              style: const TextStyle(
                color: orange,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            if (groups.isEmpty)
              const EmptyDirectory()
            else
              ...groups.expand(
                (group) => [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: Text(
                      group.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: ink,
                      ),
                    ),
                  ),
                  ...group.items.map((item) => _SearchTile(item: item)),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _emptySearchIntro(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'A busca agora encontra empresas, utilidades, ônibus, telefones, turismo, notícias, eventos, empregos, alertas e assuntos do Onde Resolver.',
        style: TextStyle(color: muted, height: 1.35),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children:
            [
                  'ônibus',
                  'lixo',
                  'farmácia',
                  'Sete Quedas',
                  'emprego',
                  'posto',
                  'alerta',
                ]
                .map(
                  (word) => ActionChip(
                    label: Text(word),
                    onPressed: () => query = word,
                  ),
                )
                .toList(),
      ),
    ],
  );

  Future<List<SearchResultGroup>> _loadGroups(
    BuildContext context,
    String term,
  ) async {
    final expanded = _expandSearchTerms(term);
    bool matches(String text) => expanded.any(text.toLowerCase().contains);
    final db = FirebaseFirestore.instance;
    final businessResults = await businessRepository
        .watchPublishedBusinesses()
        .first;
    final reads = await Future.wait([
      db
          .collection(FirestoreCollections.utilities)
          .limit(50)
          .get(const GetOptions(source: Source.serverAndCache)),
      db
          .collection(FirestoreCollections.routes)
          .where('published', isEqualTo: true)
          .limit(40)
          .get(const GetOptions(source: Source.serverAndCache)),
      db
          .collection(FirestoreCollections.events)
          .where('published', isEqualTo: true)
          .limit(40)
          .get(const GetOptions(source: Source.serverAndCache)),
      db
          .collection(FirestoreCollections.news)
          .where('published', isEqualTo: true)
          .limit(40)
          .get(const GetOptions(source: Source.serverAndCache)),
      db
          .collection(FirestoreCollections.jobs)
          .where('published', isEqualTo: true)
          .limit(40)
          .get(const GetOptions(source: Source.serverAndCache)),
      db
          .collection(FirestoreCollections.alerts)
          .where('published', isEqualTo: true)
          .limit(40)
          .get(const GetOptions(source: Source.serverAndCache)),
      db
          .collection(FirestoreCollections.resolverSubjects)
          .where('published', isEqualTo: true)
          .limit(40)
          .get(const GetOptions(source: Source.serverAndCache)),
      db
          .collection(FirestoreCollections.transport)
          .where('published', isEqualTo: true)
          .limit(30)
          .get(const GetOptions(source: Source.serverAndCache)),
      db
          .collection(FirestoreCollections.usefulPhones)
          .where('published', isEqualTo: true)
          .limit(30)
          .get(const GetOptions(source: Source.serverAndCache)),
      db
          .collection(FirestoreCollections.health)
          .where('published', isEqualTo: true)
          .limit(30)
          .get(const GetOptions(source: Source.serverAndCache)),
    ]);
    final utilitiesDocs = reads[0];
    final routeDocs = reads[1];
    final eventDocs = reads[2];
    final newsDocs = reads[3];
    final jobDocs = reads[4];
    final alertDocs = reads[5];
    final resolverDocs = reads[6];
    final transportDocs = reads[7];
    final phoneDocs = reads[8];
    final healthDocs = reads[9];

    SearchResultItem contentItem(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      String collection,
      IconData icon,
      String fallbackSubtitle,
    ) {
      final data = doc.data();
      final title = (data['title'] ?? data['name'] ?? 'Conteúdo').toString();
      final subtitle =
          (data['description'] ?? data['location'] ?? fallbackSubtitle)
              .toString();
      final link = (data['link'] ?? data['maps'] ?? '').toString();
      return SearchResultItem(
        title: title,
        subtitle: subtitle.isEmpty ? fallbackSubtitle : subtitle,
        icon: icon,
        imageUrl: contentImageUrls(data).isEmpty
            ? ''
            : contentImageUrls(data).first,
        onTap: () {
          close(context, null);
          if (link.isNotEmpty) {
            openUrl(context, link, title);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FirestoreContentScaffold(
                  title: title,
                  collection: collection,
                  empty: 'Nenhum conteúdo publicado.',
                ),
              ),
            );
          }
        },
      );
    }

    final businessesFound = businessResults
        .where(
          (business) => matches(
            '${business.name} ${business.category} ${business.subcategory} ${business.location} ${business.description}',
          ),
        )
        .take(8)
        .map(
          (business) => SearchResultItem(
            title: business.name,
            subtitle: '${business.category} · ${business.location}',
            icon: Icons.store_mall_directory_outlined,
            onTap: () {
              close(context, null);
              final target = business.whatsappUrl.isNotEmpty
                  ? business.whatsappUrl
                  : business.phoneUrl;
              openUrl(context, target, business.name);
            },
          ),
        )
        .toList();

    final utilities =
        [
              ...fallbackUtilities,
              ...utilitiesDocs.docs.map(UtilityItem.fromFirestore),
            ]
            .where(
              (item) =>
                  item.active &&
                  matches(
                    '${item.name} ${item.description} ${item.destination} ${item.iconKey}',
                  ),
            )
            .take(10)
            .map(
              (item) => SearchResultItem(
                title: item.name,
                subtitle: item.description,
                icon: utilityIcon(item.iconKey),
                onTap: () {
                  close(context, null);
                  openUtilityDestination(context, item);
                },
              ),
            )
            .toList();

    List<SearchResultItem> mapped(
      QuerySnapshot<Map<String, dynamic>> docs,
      String collection,
      IconData icon,
      String subtitle,
    ) => docs.docs
        .where((doc) {
          final data = doc.data();
          return isActiveContent(data) &&
              matches(
                '${data['title'] ?? data['name'] ?? ''} ${data['description'] ?? ''} ${data['category'] ?? ''} ${data['location'] ?? ''} ${data['additionalInfo'] ?? ''}',
              );
        })
        .take(8)
        .map((doc) => contentItem(doc, collection, icon, subtitle))
        .toList();

    final tourism = routeDocs.docs
        .map(TouristSpot.fromDoc)
        .where(
          (spot) => matches(
            '${spot.title} ${spot.category} ${spot.description} ${spot.location}',
          ),
        )
        .take(8)
        .map(
          (spot) => SearchResultItem(
            title: spot.title,
            subtitle: spot.location.isEmpty ? 'Turismo' : spot.location,
            icon: Icons.route_outlined,
            imageUrl: spot.images.isEmpty ? '' : spot.images.first,
            onTap: () {
              close(context, null);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TouristSpotDetailView(spot: spot),
                ),
              );
            },
          ),
        )
        .toList();

    return [
      SearchResultGroup(title: 'UTILIDADES', items: utilities),
      SearchResultGroup(title: 'EMPRESAS', items: businessesFound),
      SearchResultGroup(title: 'TURISMO', items: tourism),
      SearchResultGroup(
        title: 'AGENDA',
        items: mapped(
          eventDocs,
          'events',
          Icons.event_available_outlined,
          'Evento',
        ),
      ),
      SearchResultGroup(
        title: 'NOTÍCIAS',
        items: mapped(newsDocs, 'news', Icons.newspaper_outlined, 'Notícia'),
      ),
      SearchResultGroup(
        title: 'EMPREGOS',
        items: mapped(jobDocs, 'jobs', Icons.work_outline_rounded, 'Vaga'),
      ),
      SearchResultGroup(
        title: 'ALERTAS',
        items: mapped(
          alertDocs,
          'alerts',
          Icons.warning_amber_rounded,
          'Alerta',
        ),
      ),
      SearchResultGroup(
        title: 'ONDE RESOLVER',
        items: mapped(
          resolverDocs,
          'resolver_subjects',
          Icons.manage_search_rounded,
          'Orientação',
        ),
      ),
      SearchResultGroup(
        title: 'ÔNIBUS E TELEFONES',
        items: [
          ...mapped(
            transportDocs,
            'transport',
            Icons.directions_bus_rounded,
            'Transporte',
          ),
          ...mapped(
            phoneDocs,
            'useful_phones',
            Icons.phone_outlined,
            'Telefone útil',
          ),
          ...mapped(
            healthDocs,
            'health',
            Icons.health_and_safety_outlined,
            'Saúde',
          ),
        ],
      ),
    ];
  }

  Set<String> _expandSearchTerms(String term) {
    final base = term.toLowerCase().trim();
    final terms = <String>{base, _removeDiacritics(base)};
    const synonyms = {
      'lixo': ['coleta', 'coleta de lixo', 'trash'],
      'onibus': ['ônibus', 'busao', 'busão', 'transporte', 'linha'],
      'busao': ['ônibus', 'onibus', 'transporte'],
      'posto': ['saúde', 'ubs', 'unidade de saúde'],
      'trabalho': ['emprego', 'vaga', 'jobs'],
      'emprego': ['trabalho', 'vaga', 'jobs'],
      'farmacia': ['farmácia', 'plantão', 'remédio'],
      'remedio': ['remédio', 'farmácia', 'farmacia'],
      'emergencia': [
        'emergência',
        'samu',
        'bombeiros',
        'polícia',
        'defesa civil',
      ],
      'mapa': ['rota', 'endereço', 'localização'],
    };
    for (final entry in synonyms.entries) {
      if (terms.contains(entry.key) || entry.value.any(terms.contains)) {
        terms.add(entry.key);
        terms.addAll(entry.value);
      }
    }
    return terms;
  }

  String _removeDiacritics(String text) {
    const from = 'áàãâäéèêëíìîïóòõôöúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    var result = text;
    for (var i = 0; i < from.length; i++) {
      result = result.replaceAll(from[i], to[i]);
    }
    return result;
  }
}

class _SearchTile extends StatelessWidget {
  const _SearchTile({required this.item});
  final SearchResultItem item;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        leading: item.imageUrl.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  item.imageUrl,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
              )
            : CircleAvatar(
                backgroundColor: mist,
                child: Icon(item.icon, color: ocean),
              ),
        title: Text(
          item.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: item.subtitle.isEmpty
            ? null
            : Text(item.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: item.onTap,
      ),
    ),
  );
}

String normalizeCatalogText(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[áàâã]'), 'a')
    .replaceAll(RegExp(r'[éê]'), 'e')
    .replaceAll(RegExp(r'[í]'), 'i')
    .replaceAll(RegExp(r'[óôõ]'), 'o')
    .replaceAll(RegExp(r'[ú]'), 'u')
    .replaceAll('ç', 'c')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

int artworkForCategory(String value, {int fallback = 0}) {
  final normalized = normalizeCatalogText(value);
  for (final category in catalog) {
    if (normalizeCatalogText(category.name) == normalized ||
        category.types.any(
          (type) => normalizeCatalogText(type) == normalized,
        )) {
      return category.artwork;
    }
  }
  return fallback;
}

class Job {
  const Job(this.title, this.company, this.area, this.type, this.when);
  final String title, company, area, type, when;
}

const catalog = [
  Category('Comércio', 0, [
    'Moda e acessórios',
    'Calçados',
    'Infantil',
    'Casa e decoração',
    'Eletrônicos',
    'Presentes',
    'Papelaria',
  ]),
  Category('Onde comer?', 1, [
    'Restaurantes',
    'Pizzarias',
    'Hambúrgueres e lanches',
    'Pastelarias',
    'Salgados',
    'Padarias e confeitarias',
    'Cafés e docerias',
    'Açaí e sorvetes',
    'Comida japonesa',
    'Bares e petiscos',
    'Marmitas e delivery',
  ]),
  Category('Serviços', 2, [
    'Construção e reformas',
    'Eletricista',
    'Encanador',
    'Informática',
    'Fotografia',
    'Contabilidade',
    'Limpeza',
  ]),
  Category('Profissionais', 3, [
    'Autônomos',
    'Manutenção',
    'Consultoria',
    'Cuidados pessoais',
  ]),
  Category('Empregos', 4, [
    'Comércio',
    'Serviços',
    'Gastronomia',
    'Administrativo',
  ]),
  Category('Turismo', 5, [
    'Cachoeiras',
    'Trilhas',
    'Pontos turísticos',
    'Guias e passeios',
    'Artesanato local',
  ]),
  Category('Notícias', 6, ['Cidade', 'Comunidade', 'Cultura', 'Esporte']),
  Category('Eventos', 7, ['Shows', 'Feiras', 'Cultura', 'Família']),
  Category('Saúde', 8, [
    'Farmácias',
    'Clínicas',
    'Dentistas',
    'Laboratórios',
    'Psicologia',
  ]),
  Category('Imóveis', 9, ['Aluguel', 'Compra e venda', 'Temporada']),
  Category('Veículos', 10, [
    'Oficinas',
    'Autopeças',
    'Pneus',
    'Lava jatos',
    'Motos',
  ]),
  Category('Pets', 11, ['Pet shops', 'Veterinários', 'Banho e tosa']),
  Category('Beleza', 12, [
    'Cabeleireiros e salões',
    'Barbearias',
    'Manicure e unhas',
    'Estética',
  ]),
  Category('Academias', 13, ['Academias', 'Personal trainer', 'Pilates']),
  Category('Educação', 14, ['Escolas', 'Cursos', 'Reforço escolar']),
  Category('Hospedagem', 15, [
    'Hotéis e pousadas',
    'Sítios e chalés',
    'Camping',
  ]),
  Category('Promoções', 16, ['Ofertas do dia', 'Cupons', 'Lançamentos']),
  Category('Serviços úteis', 17, [
    'Contas essenciais',
    'Utilidade pública',
    'Emergências',
    'Informações locais',
  ]),
];

final homeCatalog = [...catalog.take(8), catalog.last];

const businesses = [
  Business(
    'Café da Serra',
    'Onde comer?',
    'Cafés e docerias',
    'Sabores acolhedores no coração da cidade.',
    'Centro · Cachoeiras de Macacu',
    1,
    featured: true,
  ),
  Business(
    'Pizzaria Sabor Local',
    'Onde comer?',
    'Pizzarias',
    'Pizzas artesanais para pedir ou retirar.',
    'Centro · Cachoeiras de Macacu',
    1,
    featured: true,
  ),
  Business(
    'Hambúrguer da Serra',
    'Onde comer?',
    'Hambúrgueres e lanches',
    'Lanches, porções e bebidas.',
    'Centro · Cachoeiras de Macacu',
    1,
  ),
  Business(
    'Pastel do Vale',
    'Onde comer?',
    'Pastelarias',
    'Pastéis preparados na hora.',
    'Centro · Cachoeiras de Macacu',
    1,
  ),
  Business(
    'Loja demonstração',
    'Comércio',
    'Moda e acessórios',
    'Moda, presentes e opções para a cidade.',
    'Centro · Cachoeiras de Macacu',
    0,
    featured: true,
  ),
  Business(
    'Estúdio Raiz',
    'Beleza',
    'Cabeleireiros e salões',
    'Cuidado, beleza e autoestima para você.',
    'Centro · Cachoeiras de Macacu',
    12,
    featured: true,
  ),
  Business(
    'Auto Centro demonstração',
    'Veículos',
    'Oficinas',
    'Cuidados para carro e moto.',
    'Bairro demonstração · Macacu',
    10,
  ),
  Business(
    'Clínica demonstração',
    'Saúde',
    'Clínicas',
    'Atendimento e cuidado para a comunidade.',
    'Centro · Cachoeiras de Macacu',
    8,
  ),
  Business(
    'Pousada demonstração',
    'Hospedagem',
    'Hotéis e pousadas',
    'Uma estadia para descobrir Macacu.',
    'Região turística · Macacu',
    15,
  ),
  Business(
    'Serviços demonstração',
    'Serviços',
    'Construção e reformas',
    'Profissionais para o que você precisar.',
    'Atende Cachoeiras de Macacu',
    2,
  ),
  Business(
    'João demonstração',
    'Profissionais',
    'Manutenção',
    'Profissional local para serviços do dia a dia.',
    'Atende Cachoeiras de Macacu',
    3,
  ),
  Business(
    'Roteiro demonstração',
    'Turismo',
    'Cachoeiras',
    'Experiências e paisagens para conhecer.',
    'Cachoeiras de Macacu',
    5,
  ),
];
final featured = businesses.where((item) => item.featured).toList();
const jobs = [
  Job(
    'Auxiliar administrativo',
    'Empresa demonstração',
    'Serviços',
    'CLT',
    'HOJE',
  ),
  Job(
    'Atendente de loja',
    'Comércio demonstração',
    'Comércio',
    'Tempo integral',
    'HOJE',
  ),
  Job(
    'Cozinheiro(a)',
    'Gastronomia demonstração',
    'Gastronomia',
    'CLT',
    'HÁ 2 DIAS',
  ),
];
