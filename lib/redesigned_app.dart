import 'core/content/public_content_repository.dart';
import 'core/content/public_content_detail_repository.dart';
import 'core/content/user_operations.dart';
import 'core/content/secure_backend.dart';
import 'core/content/hybrid_admin_establishments_repository.dart';
import 'core/content/spark_admin_content_repository.dart';
import 'core/content/initial_content_importer.dart';
import 'core/navigation/incoming_content_link_page.dart';
import 'core/navigation/internal_content_link.dart';
import 'core/navigation/internal_content_link_navigation_queue.dart';
import 'core/navigation/internal_content_link_service.dart';
import 'core/navigation/public_content_link_resolver.dart';
import 'dart:async';
import 'core/auth/app_auth.dart';
import 'core/auth/account_deletion_service.dart';
import 'core/auth/apple_sign_in_configuration.dart';
import 'core/auth/auth_error_message.dart';
import 'core/auth/admin_authorization.dart';
import 'core/config/local_search_environment.dart';
import 'core/config/spark_local_environment.dart';
import 'core/config/spark_local_startup_timeline.dart';
import 'core/config/staging_environment.dart';
import 'core/config/beta_environment.dart';
import 'core/auth/google_sign_in_configuration.dart';
import 'core/auth/google_auth_exchange.dart';
import 'core/widgets/staging_environment_banner.dart';

import 'admin_audit.dart';
import 'core/config/firestore_collections.dart';
import 'core/media/media_url_service.dart';
import 'core/media/media_selection.dart';
import 'core/media/device_image_source.dart';
import 'core/media/single_image_selector.dart';
import 'core/media/media_upload_service.dart';
import 'core/media/image_upload_button.dart';
import 'features/home/widgets/home_tourism_carousel.dart';
import 'features/home/widgets/home_favorites_section.dart';
import 'features/home/widgets/home_weather_chip.dart';
import 'features/home/widgets/home_agenda_card.dart';
import 'features/events/models/public_event.dart';
import 'features/events/pages/event_detail_page.dart';
import 'features/events/pages/my_agenda_view.dart';
import 'features/events/pages/event_reminder_settings_view.dart';
import 'features/events/services/event_reminder_service.dart';
import 'features/events/utils/city_calendar_date.dart';
import 'features/events/widgets/city_month_calendar.dart';
import 'features/search/widgets/universal_search_bar.dart';
import 'features/search/pages/universal_search_page.dart';
import 'features/search/pages/beta_search_unavailable_page.dart';
import 'features/notifications/notification_repository.dart';
import 'core/services/external_link_service.dart';
import 'core/utils/external_url.dart';
import 'core/services/weather_service.dart';
import 'core/services/metrics_service.dart';
import 'core/share/public_share_content.dart';
import 'core/share/public_share_service.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/mini_label.dart';
import 'core/widgets/app_brand.dart';
import 'core/widgets/app_bottom_navigation_bar.dart';
import 'core/widgets/sprite.dart';
import 'features/businesses/models/business.dart';
import 'features/businesses/repositories/business_repository.dart';
import 'features/businesses/screens/business_profile.dart';
import 'features/businesses/services/business_actions.dart';
import 'features/businesses/widgets/business_avatar.dart';
import 'features/businesses/widgets/business_card.dart';
import 'features/businesses/widgets/business_hours.dart';
import 'features/businesses/widgets/published_business_list.dart';
import 'features/businesses/widgets/published_business_strip.dart';
import 'features/utilities/models/utility_item.dart';
import 'features/contact/contact_message_validation.dart';
import 'features/tourism/models/tourist_spot.dart';
import 'features/tourism/models/tourism_category.dart';
import 'features/tourism/models/tourism_config.dart';

import 'features/tourism/widgets/tourism_overview.dart';
import 'features/tourism/widgets/tourism_cover.dart';
import 'features/tourism/screens/tourism_config_editor.dart';
import 'features/jobs/repositories/admin_job_repository.dart';
import 'features/jobs/repositories/admin_job_repository_factory.dart';
import 'features/jobs/pages/job_detail_page.dart';
import 'features/jobs/models/public_job.dart';
import 'features/jobs/repositories/public_job_details_repository.dart';
import 'features/search/repositories/local_universal_search_repository.dart';
import 'features/search/utils/search_normalization.dart';
import 'features/auth/local_demo_login.dart';
import 'features/auth/email_password_auth.dart';
import 'features/home/models/home_page_config.dart';
import 'features/home/widgets/home_title_edit_pilot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
  Widget build(BuildContext context) => AdminAuthorizationScope(
    child: MaterialApp(
      title: 'Tudo Aqui Macacu',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) {
        if (!StagingEnvironment.enabled) {
          return child ?? const SizedBox.shrink();
        }
        return SafeArea(
          bottom: false,
          child: Column(
            children: [
              const StagingEnvironmentBanner(),
              Expanded(child: child ?? const SizedBox.shrink()),
            ],
          ),
        );
      },
      home: const AppStartupGate(),
    ),
  );
}

String googleSignInClientIdForCurrentFlavor() => googleSignInServerClientId(
  betaVariant: BetaEnvironment.enabled,
  betaClientId: BetaEnvironment.googleWebClientId,
);
const appPrivacyPolicyUrl = String.fromEnvironment('PRIVACY_POLICY_URL');

bool isAdminUser(User? user, {BuildContext? context}) {
  final authorization = context == null
      ? AdminAuthorization.instance
      : AdminAuthorizationScope.depend(context);
  return authorization.allows(user);
}

Future<void> syncUserProfile(User user) async {
  if (!isRegisteredUser(user)) return;
  try {
    final ref = FirebaseFirestore.instance
        .collection(FirestoreCollections.users)
        .doc(user.uid);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final profile = <String, dynamic>{
        'displayName': user.displayName ?? '',
        'email': user.email ?? '',
        'photoUrl': user.photoURL ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!snapshot.exists) {
        profile['role'] = 'user';
        profile['createdAt'] = FieldValue.serverTimestamp();
      }
      transaction.set(ref, profile, SetOptions(merge: true));
    });
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
  final rawDate = data['eventDate'] ?? data['date'] ?? '';
  final parts = [
    formatEventDateTimeInBrasilia(rawDate),
    (data['location'] ?? data['address'] ?? '').toString(),
    (data['contact'] ?? '').toString(),
  ].map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
  return parts.join(' · ');
}

class PushService {
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<String>? _tokenSubscription;

  static Future<void> activate(User user, BuildContext context) async {
    if (!isRegisteredUser(user) ||
        LocalSearchEnvironment.enabled ||
        StagingEnvironment.enabled ||
        BetaEnvironment.enabled) {
      return;
    }
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
    if (!isRegisteredUser(user) ||
        LocalSearchEnvironment.enabled ||
        StagingEnvironment.enabled ||
        BetaEnvironment.enabled) {
      return;
    }
    final messaging = FirebaseMessaging.instance;
    await _foregroundSubscription?.cancel();
    await _tokenSubscription?.cancel();
    _foregroundSubscription = null;
    _tokenSubscription = null;
    try {
      final token = await messaging.getToken();
      if (token != null) {
        await writeUserOperation('removeDevice', {'token': token});
      }
    } catch (_) {
      // A backend outage must not prevent local token cleanup or logout.
      debugPrint('Token FCM não removido no servidor.');
    }
    try {
      await messaging.deleteToken();
    } catch (error) {
      debugPrint('Token FCM local não apagado: $error');
    }
  }

  static Future<void> _saveToken(String uid, String token) =>
      writeUserOperation('device', {'token': token, 'platform': 'android'});
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
    SparkLocalStartupTimeline.markOnce('startup_gate_initialized');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SparkLocalStartupTimeline.markOnce('startup_gate_first_frame');
      if (mounted) unawaited(_start());
    });
  }

  Future<void> _start({bool manual = false}) async {
    SparkLocalStartupTimeline.mark('startup_gate_start');
    if (manual) startupAttempts = 0;
    if (!mounted) return;
    setState(() {
      ready = false;
      startupError = null;
      progress = 0;
    });
    try {
      _setProgress(.08);
      SparkLocalStartupTimeline.mark('splash_asset_start');
      await precacheImage(const AssetImage(splashBackgroundAsset), context);
      SparkLocalStartupTimeline.mark('splash_asset_ready');
      _setProgress(.22);

      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _setProgress(.58);

      if (!BetaEnvironment.enabled) {
        try {
          SparkLocalStartupTimeline.mark('session_recovery_start');
          await AppAuth.ensureVisitor();
          SparkLocalStartupTimeline.mark('session_recovery_ready');
        } catch (error) {
          SparkLocalStartupTimeline.mark('session_recovery_error');
          debugPrint('Sessão de busca local indisponível: $error');
        }
      }

      final user = FirebaseAuth.instance.currentUser;
      if (isRegisteredUser(user)) {
        unawaited(syncUserProfile(user!));
      }
      _setProgress(.74);

      SparkLocalStartupTimeline.mark('home_warm_read_start');
      await _warmEssentialConfig();
      SparkLocalStartupTimeline.mark('home_warm_read_ready');
      _setProgress(1);

      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (!mounted) return;
      setState(() => ready = true);
      SparkLocalStartupTimeline.mark('auth_gate_ready');
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
    if (BetaEnvironment.enabled) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(FirestoreCollections.homePages)
          .doc('published')
          .get()
          .timeout(const Duration(seconds: 2));
      if (SparkLocalEnvironment.enabled) {
        SparkLocalStartupTimeline.mark(
          snapshot.metadata.isFromCache
              ? 'home_prefetch_cache_result'
              : 'home_prefetch_server_result',
        );
      }
    } catch (error) {
      SparkLocalStartupTimeline.mark('home_prefetch_error');
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
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 74),
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
      if (SparkLocalEnvironment.enabled &&
          snapshot.connectionState != ConnectionState.waiting) {
        SparkLocalStartupTimeline.markOnce('auth_session_restored');
      }
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      // Anonymous Auth is a search credential, not an account in the interface.
      final sessionUser = snapshot.data;
      if (sessionUser == null &&
          (LocalSearchEnvironment.enabled ||
              SecureBackend.productionAuthorized)) {
        unawaited(
          AppAuth.ensureVisitor().catchError((Object error) {
            debugPrint('Sessão visitante indisponível: $error');
            return null;
          }),
        );
      }
      final user = isRegisteredUser(sessionUser) ? sessionUser : null;
      return CityShell(key: ValueKey(user?.uid ?? 'guest'), user: user);
    },
  );
}

class GoogleLoginView extends StatefulWidget {
  const GoogleLoginView({super.key, this.googleAccountChooserForTesting});

  @visibleForTesting
  final Future<GoogleSignInAccount?> Function()? googleAccountChooserForTesting;
  @override
  State<GoogleLoginView> createState() => _GoogleLoginViewState();
}

class _GoogleLoginViewState extends State<GoogleLoginView> {
  bool loading = false;
  bool success = false;
  String? error;

  bool get _usesLocalDemoLogin =>
      LocalSearchEnvironment.enabled || SparkLocalEnvironment.enabled;

  bool get _showAppleSignIn => shouldOfferAppleSignIn(
    isIos: defaultTargetPlatform == TargetPlatform.iOS,
    betaBuildEnabled:
        BetaEnvironment.iosBuildEnabled &&
        BetaEnvironment.enabled &&
        !BetaEnvironment.sparkLocal,
    betaReady: BetaEnvironment.ready,
    providerConfigured: BetaEnvironment.iosAppleSignInEnabled,
  );

  Future<void> _finishLocalSignIn() async {
    if (!mounted) return;
    setState(() => success = true);
    await Future<void>.delayed(const Duration(milliseconds: 850));
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _signInWithEmail(String email, String password) async {
    final result = await AppAuth.signInEmail(email, password);
    if (result.user != null) await syncUserProfile(result.user!);
  }

  Future<void> _registerWithEmail(
    String displayName,
    String email,
    String password,
  ) async {
    final result = await AppAuth.createEmailAccount(
      email,
      password,
      displayName: displayName,
    );
    if (result.user != null) await syncUserProfile(result.user!);
  }

  Future<void> signIn() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (_usesLocalDemoLogin) {
        throw StateError(
          'Login Google externo indisponível no ambiente local.',
        );
      }
      if (BetaEnvironment.enabled) BetaEnvironment.requireReady();
      final accountChooser = widget.googleAccountChooserForTesting;
      final account = accountChooser == null
          ? await GoogleSignIn(
              clientId: googleSignInNativeClientId(
                betaVariant: BetaEnvironment.enabled,
                ios: defaultTargetPlatform == TargetPlatform.iOS,
                betaIosClientId: BetaEnvironment.iosGoogleClientId,
              ),
              serverClientId: googleSignInClientIdForCurrentFlavor(),
            ).signIn()
          : await accountChooser();
      if (account == null) {
        return;
      }
      final auth = await account.authentication;
      final result = await authenticateGoogleTokens(
        idToken: auth.idToken,
        accessToken: auth.accessToken,
        authenticate: AppAuth.signInCredential,
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
      debugPrint('Google login FirebaseAuthException: ${e.code}');
      if (mounted) {
        setState(
          () =>
              error = authErrorMessage(e, action: AuthErrorAction.googleSignIn),
        );
      }
    } catch (e) {
      debugPrint('Google login falhou.');
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

  Future<void> signInWithApple() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await AppAuth.signInWithApple();
      if (result.user != null) await syncUserProfile(result.user!);
      if (!mounted) return;
      setState(() {
        success = true;
        loading = false;
      });
      await Future<void>.delayed(const Duration(milliseconds: 850));
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (exception) {
      if (isAppleSignInCancellation(exception)) return;
      debugPrint('Apple login FirebaseAuthException: ${exception.code}');
      if (mounted) {
        setState(
          () => error = authErrorMessage(
            exception,
            action: AuthErrorAction.appleSignIn,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Não foi possível entrar com a Apple. Verifique a conexão e tente novamente.',
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
          appBar: _usesLocalDemoLogin
              ? null
              : AppBar(title: const Text('Acesse sua conta')),
          body: _usesLocalDemoLogin
              ? LocalDemoLoginForm(onAuthenticated: _finishLocalSignIn)
              : SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxHeight < 740;
                      return Center(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(
                            compact ? AppSpacing.sm : AppSpacing.page,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: Card(
                              color: Colors.white,
                              elevation: 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadii.feature,
                                ),
                                side: const BorderSide(color: mist),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(
                                  compact ? AppSpacing.md : AppSpacing.xxl,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Brand(),
                                    SizedBox(
                                      height: compact
                                          ? AppSpacing.md
                                          : AppSpacing.xl,
                                    ),
                                    Icon(
                                      Icons.account_circle_rounded,
                                      color: sky,
                                      size: compact ? 42 : 58,
                                      semanticLabel: 'Conta Tudo Aqui Macacu',
                                    ),
                                    SizedBox(
                                      height: compact
                                          ? AppSpacing.sm
                                          : AppSpacing.md,
                                    ),
                                    Text(
                                      'Personalize sua experiência',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    const Text(
                                      'Entre para salvar favoritos e receber novidades. Criar conta é opcional: a cidade continua aberta para você explorar.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: muted,
                                        height: 1.45,
                                      ),
                                    ),
                                    if (error != null) ...[
                                      const SizedBox(height: AppSpacing.md),
                                      Semantics(
                                        liveRegion: true,
                                        child: Text(
                                          error!,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.error,
                                          ),
                                        ),
                                      ),
                                    ],
                                    SizedBox(
                                      height: compact
                                          ? AppSpacing.md
                                          : AppSpacing.xl,
                                    ),
                                    App3DButton(
                                      onPressed: loading ? null : signIn,
                                      icon: loading
                                          ? const SizedBox.square(
                                              dimension: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.login_rounded),
                                      label: 'Continuar com Google',
                                    ),
                                    if (_showAppleSignIn) ...[
                                      SizedBox(
                                        height: compact
                                            ? AppSpacing.xs
                                            : AppSpacing.md,
                                      ),
                                      SizedBox(
                                        height: 48,
                                        child: FilledButton(
                                          key: const Key('apple-sign-in'),
                                          onPressed: loading
                                              ? null
                                              : signInWithApple,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.black,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Text(
                                                '\uF8FF',
                                                style: TextStyle(fontSize: 21),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Iniciar sessão com a Apple',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelLarge
                                                    ?.copyWith(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                    SizedBox(
                                      height: compact
                                          ? AppSpacing.xs
                                          : AppSpacing.md,
                                    ),
                                    OutlinedButton.icon(
                                      key: const Key('open-email-auth'),
                                      onPressed: loading
                                          ? null
                                          : () => Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) => EmailPasswordAuthView(
                                                  signIn: _signInWithEmail,
                                                  register: _registerWithEmail,
                                                  resetPassword: AppAuth
                                                      .sendPasswordResetEmail,
                                                  requireEmailVerification:
                                                      BetaEnvironment.enabled,
                                                  sendEmailVerification:
                                                      BetaEnvironment.enabled
                                                      ? AppAuth
                                                            .sendEmailVerification
                                                      : null,
                                                  refreshEmailVerification:
                                                      BetaEnvironment.enabled
                                                      ? AppAuth
                                                            .refreshEmailVerificationStatus
                                                      : null,
                                                  onAuthenticated:
                                                      _finishLocalSignIn,
                                                ),
                                              ),
                                            ),
                                      icon: const Icon(Icons.email_outlined),
                                      label: const Text('Entrar com e-mail'),
                                    ),
                                    SizedBox(
                                      height: compact ? 0 : AppSpacing.xs,
                                    ),
                                    TextButton.icon(
                                      onPressed: loading
                                          ? null
                                          : () => Navigator.of(
                                              context,
                                            ).maybePop(),
                                      icon: const Icon(Icons.explore_outlined),
                                      label: const Text('Continuar sem conta'),
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
  const CityShell({super.key, required this.user, this.testPages});
  final User? user;

  /// Optional page set used by shell widget tests; production uses app pages.
  final List<Widget>? testPages;
  @override
  State<CityShell> createState() => _CityShellState();
}

Future<void> promptFavoriteSignIn(BuildContext context) async {
  final shouldSignIn = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.favorite_outline_rounded, color: orange),
      title: const Text('Entre para salvar seus favoritos'),
      content: const Text(
        'Entre ou crie uma conta para levar seus lugares salvos com você. Você pode continuar explorando sem entrar.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Agora não'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Entrar ou criar conta'),
        ),
      ],
    ),
  );
  if (shouldSignIn != true || !context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => const GoogleLoginView()),
  );
}

Future<void> promptAgendaSignIn(BuildContext context) async {
  final shouldSignIn = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.event_available_rounded, color: orange),
      title: const Text('Entre para salvar na sua agenda'),
      content: const Text(
        'Entre ou crie uma conta para guardar este evento na sua agenda pessoal. Você pode continuar explorando sem entrar.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Agora não'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Entrar ou criar conta'),
        ),
      ],
    ),
  );
  if (shouldSignIn != true || !context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => const GoogleLoginView()),
  );
}

class _CityShellState extends State<CityShell> {
  int tab = 0;
  final _homeKey = GlobalKey<_HomeViewState>();
  late final StreamSubscription<InternalContentLink?> _contentLinkSubscription;
  late final InternalContentLinkNavigationQueue _incomingContentQueue;

  Future<void> _selectTab(int value) async {
    if (value == tab) return;
    if (tab == 0 && !(await _homeKey.currentState?.requestLeave() ?? true)) {
      return;
    }
    if (mounted) setState(() => tab = value);
  }

  final saved = <String>{};
  final savedBusinessIds = <String>{};
  final savedTourismIds = <String>{};
  final savedAgendaEventIds = <String>{};
  final _favoriteDocumentIds = <String>{};
  final _pendingFavorites = <String>{};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  favoritesSubscription;
  StreamSubscription<List<PublicEvent>>? _agendaReminderSubscription;
  int _favoritesGeneration = 0;
  String? _activeAgendaUid;

  @override
  void initState() {
    super.initState();
    _incomingContentQueue = InternalContentLinkNavigationQueue(
      isActive: () => mounted,
      open: _presentIncomingContentLink,
      onOpenError: (_) => debugPrint('Não foi possível abrir o link interno.'),
    );
    _contentLinkSubscription = InternalContentLinkService.instance.links.listen(
      (link) => unawaited(_incomingContentQueue.enqueue(link)),
    );
    unawaited(InternalContentLinkService.instance.start());
    final user = isRegisteredUser(widget.user) ? widget.user : null;
    if (user != null) {
      unawaited(syncUserProfile(user));
      unawaited(PushService.activate(user, context));
    }
    _watchFavorites(user);
  }

  Future<void> _presentIncomingContentLink(InternalContentLink? link) async {
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => IncomingContentLinkPage(
          link: link,
          resolvePage: _resolveIncomingContentPage,
        ),
      ),
    );
    if (mounted && tab != 0) await _selectTab(0);
  }

  Future<Widget?> _resolveIncomingContentPage(InternalContentLink link) async {
    switch (link.type) {
      case InternalContentType.establishment:
        final business = await businessRepository.getPublicBusiness(link.id);
        if (business == null) return null;
        return StatefulBuilder(
          builder: (context, refresh) => BusinessProfile(
            business: business,
            saved:
                saved.contains(business.favoriteKey) ||
                saved.contains(business.name),
            onFavorite: () {
              favorite(business);
              refresh(() {});
            },
          ),
        );
      case InternalContentType.tourism:
        final data = await PublicContentLinkResolver().resolve(link);
        if (data == null) return null;
        final spot = TouristSpot.fromData(link.id, data);
        return StatefulBuilder(
          builder: (context, refresh) => TouristSpotDetailView(
            spot: spot,
            saved: savedTourismIds.contains(spot.id),
            onFavorite: () {
              favoriteTourism(spot);
              refresh(() {});
            },
          ),
        );
      case InternalContentType.event:
        // EventDetailPage already uses the secure public detail repository and
        // exposes its loading, unavailable, error, and retry states.
        return EventDetailPage(
          eventId: link.id,
          agendaSaved: savedAgendaEventIds.contains(link.id),
          onToggleAgenda: toggleEventAgenda,
        );
    }
  }

  @override
  void didUpdateWidget(covariant CityShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUid = isRegisteredUser(oldWidget.user)
        ? oldWidget.user!.uid
        : null;
    final newUid = isRegisteredUser(widget.user) ? widget.user!.uid : null;
    if (oldUid == newUid) return;
    if (newUid != null) {
      unawaited(syncUserProfile(widget.user!));
      unawaited(PushService.activate(widget.user!, context));
    }
    _watchFavorites(newUid == null ? null : widget.user);
  }

  void _watchFavorites(User? user) {
    final generation = ++_favoritesGeneration;
    final nextUid = isRegisteredUser(user) ? user!.uid : null;
    if (_activeAgendaUid != nextUid) {
      _activeAgendaUid = nextUid;
    }
    unawaited(EventReminderService.instance.clearUsersExcept(nextUid));
    unawaited(_agendaReminderSubscription?.cancel());
    _agendaReminderSubscription = null;
    unawaited(favoritesSubscription?.cancel());
    favoritesSubscription = null;
    saved.clear();
    savedBusinessIds.clear();
    savedTourismIds.clear();
    savedAgendaEventIds.clear();
    _favoriteDocumentIds.clear();
    _pendingFavorites.clear();
    if (!isRegisteredUser(user)) {
      if (mounted) setState(() {});
      return;
    }
    favoritesSubscription = FirebaseFirestore.instance
        .collection(FirestoreCollections.users)
        .doc(user!.uid)
        .collection(FirestoreCollections.favorites)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted || generation != _favoritesGeneration) return;
            final businessKeys = <String>{};
            final businessIds = <String>{};
            final tourismIds = <String>{};
            final agendaEventIds = <String>{};
            final favoriteDocumentIds = <String>{};
            for (final doc in snapshot.docs) {
              favoriteDocumentIds.add(doc.id);
              final data = doc.data();
              final type = (data['type'] ?? 'business').toString();
              final targetId = (data['targetId'] ?? '').toString();
              if (type == 'event') {
                final id = targetId.isNotEmpty
                    ? targetId
                    : doc.id.startsWith('event::')
                    ? doc.id.substring('event::'.length)
                    : '';
                if (id.isNotEmpty) agendaEventIds.add(id);
                continue;
              }
              if (type == 'tourism') {
                final id = targetId.isNotEmpty
                    ? targetId
                    : doc.id.startsWith('tourism::')
                    ? doc.id.substring('tourism::'.length)
                    : '';
                if (id.isNotEmpty) tourismIds.add(id);
                continue;
              }
              if (type != 'business') continue;
              final id = targetId.isNotEmpty
                  ? targetId
                  : doc.id.startsWith('business::')
                  ? doc.id.substring('business::'.length)
                  : doc.id;
              if (id.isEmpty) continue;
              businessIds.add(id);
              businessKeys.add(id);
              final legacyName = (data['name'] ?? '').toString().trim();
              if (legacyName.isNotEmpty) businessKeys.add(legacyName);
            }
            setState(() {
              saved
                ..clear()
                ..addAll(businessKeys);
              savedBusinessIds
                ..clear()
                ..addAll(businessIds);
              savedTourismIds
                ..clear()
                ..addAll(tourismIds);
              savedAgendaEventIds
                ..clear()
                ..addAll(agendaEventIds);
              _favoriteDocumentIds
                ..clear()
                ..addAll(favoriteDocumentIds);
            });
            unawaited(
              EventReminderService.instance.cancelRemovedFromAgenda(
                user.uid,
                agendaEventIds,
              ),
            );
            unawaited(
              _watchSavedAgendaEvents(user.uid, agendaEventIds, generation),
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            if (generation == _favoritesGeneration) {
              debugPrint('Favoritos Firebase indisponíveis: $error');
            }
          },
        );
  }

  Future<void> _watchSavedAgendaEvents(
    String uid,
    Set<String> savedIds,
    int generation,
  ) async {
    final previous = _agendaReminderSubscription;
    _agendaReminderSubscription = null;
    await previous?.cancel();
    if (savedIds.isEmpty ||
        !await EventReminderService.instance.remindersEnabled(uid) ||
        !await EventReminderService.instance.hasReminders(uid) ||
        !mounted ||
        generation != _favoritesGeneration ||
        _activeAgendaUid != uid) {
      return;
    }
    late final StreamSubscription<List<PublicEvent>> subscription;
    subscription = _watchPublicReminderEvents().listen(
      (publicEvents) {
        if (!mounted ||
            generation != _favoritesGeneration ||
            _activeAgendaUid != uid) {
          return;
        }
        unawaited(() async {
          try {
            await EventReminderService.instance.reconcile(
              uid: uid,
              savedEventIds: Set.unmodifiable(savedIds),
              publicEvents: publicEvents,
            );
            if (!await EventReminderService.instance.hasReminders(uid) &&
                identical(_agendaReminderSubscription, subscription)) {
              _agendaReminderSubscription = null;
              await subscription.cancel();
            }
          } catch (_) {
            debugPrint('Lembretes de eventos não puderam ser atualizados.');
          }
        }());
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('Eventos públicos indisponíveis para atualizar lembretes.');
      },
    );
    if (mounted &&
        generation == _favoritesGeneration &&
        _activeAgendaUid == uid) {
      _agendaReminderSubscription = subscription;
    } else {
      await subscription.cancel();
    }
  }

  Stream<List<PublicEvent>> _watchPublicReminderEvents() =>
      watchPublicContent(FirestoreCollections.events).map((snapshot) {
        final publicEvents = <PublicEvent>[];
        for (final document in snapshot.docs) {
          final data = document.data();
          if (data['published'] != true || data['active'] != true) continue;
          if (data.containsKey('deletedAt') ||
              (data.containsKey('deleted') && data['deleted'] != false)) {
            continue;
          }
          final expiresAt = data['expiresAt'];
          if (expiresAt is Timestamp &&
              !expiresAt.toDate().isAfter(DateTime.now())) {
            continue;
          }
          try {
            publicEvents.add(PublicEvent.fromMap({...data, 'id': document.id}));
          } on FormatException {
            // Invalid public records cannot keep a reminder active.
          }
        }
        return List.unmodifiable(publicEvents);
      });

  void favorite(Business business) =>
      unawaited(_toggleBusinessFavorite(business));

  Future<void> _toggleBusinessFavorite(Business business) async {
    final user = isRegisteredUser(widget.user) ? widget.user : null;
    if (user == null) {
      await promptFavoriteSignIn(context);
      return;
    }
    final key = business.favoriteKey;
    final legacyKey = business.name;
    final currentlySaved = saved.contains(key) || saved.contains(legacyKey);
    final storageId = 'business::$key';
    if (!_pendingFavorites.add(storageId)) return;
    setState(() {
      if (currentlySaved) {
        saved
          ..remove(key)
          ..remove(legacyKey);
        savedBusinessIds.remove(key);
      } else {
        saved
          ..add(key)
          ..add(legacyKey);
        savedBusinessIds.add(key);
      }
    });
    try {
      if (currentlySaved) {
        final ids = <String>{
          storageId,
          key,
          legacyKey,
        }.where(_favoriteDocumentIds.contains).toSet();
        if (ids.isEmpty) ids.add(storageId);
        await Future.wait(
          ids.map((id) => writeUserOperation('unfavorite', {'id': id})),
        );
      } else {
        await writeUserOperation('favorite', {
          'id': storageId,
          'name': business.name,
          'type': 'business',
          'targetId': key,
        });
      }
      unawaited(
        recordMetric(
          currentlySaved ? 'favorite_remove' : 'favorite_add',
          target: key,
          targetType: 'business',
        ).catchError((_) {}),
      );
    } catch (_) {
      if (mounted &&
          isRegisteredUser(widget.user) &&
          widget.user!.uid == user.uid) {
        setState(() {
          if (currentlySaved) {
            saved
              ..add(key)
              ..add(legacyKey);
            savedBusinessIds.add(key);
          } else {
            saved
              ..remove(key)
              ..remove(legacyKey);
            savedBusinessIds.remove(key);
          }
        });
        _showFavoriteError();
      }
    } finally {
      _pendingFavorites.remove(storageId);
    }
  }

  void favoriteTourism(TouristSpot spot) =>
      unawaited(_toggleTourismFavorite(spot));

  Future<bool> toggleEventAgenda(PublicEvent event) =>
      _toggleEventAgenda(event);

  Future<bool> _toggleEventAgenda(PublicEvent event) async {
    final user = isRegisteredUser(widget.user) ? widget.user : null;
    if (user == null) {
      await promptAgendaSignIn(context);
      return false;
    }
    final documentId = 'event::${event.id}';
    final currentlySaved = savedAgendaEventIds.contains(event.id);
    if (!_pendingFavorites.add(documentId)) return false;
    setState(() {
      if (currentlySaved) {
        savedAgendaEventIds.remove(event.id);
      } else {
        savedAgendaEventIds.add(event.id);
      }
    });
    try {
      await writeUserOperation(
        currentlySaved ? 'unfavorite' : 'favorite',
        currentlySaved
            ? {'id': documentId}
            : {
                'id': documentId,
                'name': event.title,
                'type': 'event',
                'targetId': event.id,
              },
      );
      return true;
    } catch (_) {
      if (mounted &&
          isRegisteredUser(widget.user) &&
          widget.user!.uid == user.uid) {
        setState(() {
          if (currentlySaved) {
            savedAgendaEventIds.add(event.id);
          } else {
            savedAgendaEventIds.remove(event.id);
          }
        });
        _showFavoriteError();
      }
      return false;
    } finally {
      _pendingFavorites.remove(documentId);
    }
  }

  void openMyAgenda() {
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MyAgendaView(
          savedEventIds: Set.unmodifiable(savedAgendaEventIds),
          isAuthenticated: isRegisteredUser(widget.user),
          uid: isRegisteredUser(widget.user) ? widget.user!.uid : null,
          onRemove: toggleEventAgenda,
          onOpen: _openAgendaEvent,
          onReminderChanged: isRegisteredUser(widget.user)
              ? () => unawaited(
                  _watchSavedAgendaEvents(
                    widget.user!.uid,
                    Set.of(savedAgendaEventIds),
                    _favoritesGeneration,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  void _openAgendaEvent(PublicEvent event) {
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => EventDetailPage(
          eventId: event.id,
          agendaSaved: savedAgendaEventIds.contains(event.id),
          onToggleAgenda: toggleEventAgenda,
        ),
      ),
    );
  }

  Future<void> _toggleTourismFavorite(TouristSpot spot) async {
    final user = isRegisteredUser(widget.user) ? widget.user : null;
    if (user == null) {
      await promptFavoriteSignIn(context);
      return;
    }
    final storageId = 'tourism::${spot.id}';
    final currentlySaved = savedTourismIds.contains(spot.id);
    if (!_pendingFavorites.add(storageId)) return;
    setState(() {
      if (currentlySaved) {
        savedTourismIds.remove(spot.id);
      } else {
        savedTourismIds.add(spot.id);
      }
    });
    try {
      await writeUserOperation(
        currentlySaved ? 'unfavorite' : 'favorite',
        currentlySaved
            ? {'id': storageId}
            : {
                'id': storageId,
                'name': spot.title,
                'type': 'tourism',
                'targetId': spot.id,
              },
      );
      unawaited(
        recordMetric(
          currentlySaved ? 'favorite_remove' : 'favorite_add',
          target: spot.id,
          targetType: 'tourism',
        ).catchError((_) {}),
      );
    } catch (_) {
      if (mounted &&
          isRegisteredUser(widget.user) &&
          widget.user!.uid == user.uid) {
        setState(() {
          if (currentlySaved) {
            savedTourismIds.add(spot.id);
          } else {
            savedTourismIds.remove(spot.id);
          }
        });
        _showFavoriteError();
      }
    } finally {
      _pendingFavorites.remove(storageId);
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
    _agendaReminderSubscription?.cancel();
    _contentLinkSubscription.cancel();
    _incomingContentQueue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages =
        widget.testPages ??
        [
          HomeView(
            key: _homeKey,
            saved: saved,
            savedBusinessIds: savedBusinessIds,
            favorite: favorite,
            savedTourismIds: savedTourismIds,
            favoriteTourism: favoriteTourism,
            showExplore: () => _selectTab(1),
            onViewFavorites: () => unawaited(_selectTab(3)),
            savedAgendaEventIds: savedAgendaEventIds,
            toggleEventAgenda: toggleEventAgenda,
            openMyAgenda: openMyAgenda,
            user: widget.user,
            onProfile: () => _selectTab(4),
          ),
          ExploreView(
            saved: saved,
            favorite: favorite,
            savedTourismIds: savedTourismIds,
            favoriteTourism: favoriteTourism,
          ),
          const PublicServicesView(),
          SavedView(
            saved: saved,
            savedTourismIds: savedTourismIds,
            favorite: favorite,
            favoriteTourism: favoriteTourism,
          ),
          ProfileView(
            count: savedBusinessIds.length + savedTourismIds.length,
            agendaCount: savedAgendaEventIds.length,
            user: widget.user,
            onSaved: () => unawaited(_selectTab(3)),
            onAgenda: openMyAgenda,
            onNotifications: isRegisteredUser(widget.user)
                ? () => Navigator.of(context, rootNavigator: true).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => EventReminderSettingsView(
                        uid: widget.user!.uid,
                        savedEventIdsProvider: () =>
                            Set.unmodifiable(savedAgendaEventIds),
                        eventsStreamFactory: _watchPublicReminderEvents,
                        accountUidStreamFactory: () =>
                            FirebaseAuth.instance.authStateChanges().map(
                              (user) =>
                                  isRegisteredUser(user) ? user!.uid : null,
                            ),
                        onChanged: () => unawaited(
                          _watchSavedAgendaEvents(
                            widget.user!.uid,
                            Set.of(savedAgendaEventIds),
                            _favoritesGeneration,
                          ),
                        ),
                        onOpenInbox: () =>
                            Navigator.of(
                              context,
                              rootNavigator: true,
                            ).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => const NotificationsView(),
                              ),
                            ),
                      ),
                    ),
                  )
                : null,
          ),
        ];
    assert(pages.length == 5, 'CityShell requires exactly five pages.');
    return PopScope<Object?>(
      canPop: tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && tab != 0) unawaited(_selectTab(0));
      },
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(index: tab, children: pages),
        ),
        bottomNavigationBar: AppBottomNavigationBar(
          selectedIndex: tab,
          onDestinationSelected: _selectTab,
        ),
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

typedef HomeConfigurationStreamFactory =
    Stream<Map<String, dynamic>> Function();
typedef HomeConfigurationSaveCallback =
    Future<void> Function(
      Map<String, dynamic> data, {
      required String label,
      required bool publish,
    });

class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
    required this.saved,
    required this.favorite,
    required this.showExplore,
    required this.user,
    this.savedBusinessIds = const <String>{},
    this.savedTourismIds = const <String>{},
    this.favoriteTourism,
    this.configurationStreamFactory,
    this.saveConfiguration,
    this.weatherService,
    this.onProfile,
    this.onViewFavorites,
    this.savedAgendaEventIds = const <String>{},
    this.toggleEventAgenda,
    this.openMyAgenda,
    this.resolveFavoriteBusiness,
    this.resolveFavoriteTourism,
  });
  final Set<String> saved;
  final ValueChanged<Business> favorite;
  final Set<String> savedBusinessIds;
  final Set<String> savedTourismIds;
  final ValueChanged<TouristSpot>? favoriteTourism;
  final VoidCallback showExplore;
  final User? user;
  final HomeConfigurationStreamFactory? configurationStreamFactory;
  final HomeConfigurationSaveCallback? saveConfiguration;
  final WeatherService? weatherService;
  final VoidCallback? onProfile;
  final VoidCallback? onViewFavorites;
  final Set<String> savedAgendaEventIds;
  final Future<bool> Function(PublicEvent event)? toggleEventAgenda;
  final VoidCallback? openMyAgenda;
  final HomeBusinessResolver? resolveFavoriteBusiness;
  final HomeTourismResolver? resolveFavoriteTourism;
  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  bool editMode = false;
  bool _homeDataLoaded = false;
  Map<String, dynamic>? _lastConfiguration;
  late Stream<Map<String, dynamic>> _configurationStream;
  final _titlePilotKey = GlobalKey<HomeTitleEditPilotState>();
  final _favoriteDetails = PublicContentDetailRepository();

  Future<Business?> _resolveFavoriteBusiness(String id) =>
      (widget.resolveFavoriteBusiness ?? businessRepository.getPublicBusiness)(
        id,
      );

  Future<TouristSpot?> _resolveFavoriteTourism(String id) async {
    final data = await (widget.resolveFavoriteTourism ?? _loadFavoriteTourism)(
      id,
    );
    return data;
  }

  Future<TouristSpot?> _loadFavoriteTourism(String id) async {
    final data = await _favoriteDetails.resolve(
      collection: FirestoreCollections.routes,
      id: id,
    );
    return data == null ? null : TouristSpot.fromData(id, data);
  }

  Stream<Map<String, dynamic>> _defaultConfigurationStream() {
    return FirebaseFirestore.instance
        .collection(FirestoreCollections.homePages)
        .doc('published')
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          if (SparkLocalEnvironment.enabled) {
            SparkLocalStartupTimeline.markOnce(
              snapshot.metadata.isFromCache
                  ? 'home_listener_cache_first'
                  : 'home_listener_server_first',
            );
          }
          return snapshot.data() ?? const <String, dynamic>{};
        });
  }

  Stream<Map<String, dynamic>> _createConfigurationStream() =>
      (widget.configurationStreamFactory ?? _defaultConfigurationStream)();

  @override
  void initState() {
    super.initState();
    SparkLocalStartupTimeline.markOnce('home_view_initialized');
    _configurationStream = _createConfigurationStream();
  }

  void _retryConfiguration() {
    setState(() => _configurationStream = _createConfigurationStream());
  }

  Future<bool> requestLeave() async {
    final allowed = await _titlePilotKey.currentState?.requestExit() ?? true;
    if (allowed && mounted) setState(() => editMode = false);
    return allowed;
  }

  @override
  void didUpdateWidget(HomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configurationStreamFactory !=
        widget.configurationStreamFactory) {
      _configurationStream = _createConfigurationStream();
    }
    if (!_isAdmin) editMode = false;
  }

  Future<void> _refresh() {
    return FirebaseFirestore.instance
        .collection(FirestoreCollections.homePages)
        .doc('published')
        .get(const GetOptions(source: Source.server))
        .then((_) {});
  }

  bool get _isAdmin => isAdminUser(widget.user, context: context);

  Future<void> _saveHomeQuick(
    Map<String, dynamic> data, {
    required String label,
    required bool publish,
  }) async {
    if (!_isAdmin || !_homeDataLoaded) return;
    final payload = {...data, 'updatedAt': FieldValue.serverTimestamp()};
    final saveConfiguration = widget.saveConfiguration;
    if (saveConfiguration != null) {
      await saveConfiguration(payload, label: label, publish: publish);
    } else {
      final db = FirebaseFirestore.instance;
      if (BetaEnvironment.enabled) {
        await SparkAdminContentRepository(
          db,
        ).saveHomePage(payload, publish: publish);
      } else {
        await db
            .collection(FirestoreCollections.homePages)
            .doc('draft')
            .set(payload, SetOptions(merge: true));
        if (publish) {
          if (!_isAdmin) throw StateError('Sessão administrativa encerrada.');
          await db
              .collection(FirestoreCollections.homePages)
              .doc('published')
              .set({
                ...payload,
                'publishedAt': FieldValue.serverTimestamp(),
                'version': FieldValue.increment(1),
              }, SetOptions(merge: true));
        }
      }
      await recordAdminAudit(
        action: publish ? 'visual_publish_home' : 'visual_save_home_draft',
        collection: 'home_pages',
        documentId: publish ? 'published' : 'draft',
        label: label,
      );
    }
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
    await _showHomeBottomSheet<void>(
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
                  CloudinaryUploadHelper(
                    controller: logo,
                    onChanged: () => setSheetState(() {}),
                    description:
                        'Selecione e envie o logo do dispositivo ou informe uma URL existente.',
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
                  CloudinaryUploadHelper(
                    controller: image,
                    onChanged: () => setSheetState(() {}),
                    description:
                        'Selecione e envie o fundo do dispositivo ou informe uma URL existente.',
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
    await _showHomeBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HomeSectionsQuickEditor(
        page: page,
        onSave: (data, {required label, required publish}) =>
            _saveHomeQuick(data, label: label, publish: publish),
      ),
    );
  }

  Future<void> _editCategoryShortcut(
    HomePageConfig page,
    Category category,
  ) async {
    if (!_isAdmin || !_homeDataLoaded) return;
    final data = _editableHomeData(page);
    final label = TextEditingController(text: page.categoryLabelFor(category));
    final image = TextEditingController(
      text: page.categoryImageUrlFor(category),
    );
    var iconKey =
        category.iconKey ?? AppIcon.fromLegacyIndex(category.artwork).key;
    var visible = page.categoryVisibleFor(category);

    Future<void> save({required bool publish}) async {
      data['categoryLabels'] = {
        ...Map<String, dynamic>.from(data['categoryLabels'] as Map),
        category.name: label.text.trim(),
      };
      data['categoryImages'] = {
        ...Map<String, dynamic>.from(data['categoryImages'] as Map),
        category.name: image.text.trim(),
      };
      data['categoryIcons'] = {
        ...Map<String, dynamic>.from(data['categoryIcons'] as Map),
        category.name: iconKey,
      };
      data['categoryVisible'] = {
        ...Map<String, dynamic>.from(data['categoryVisible'] as Map),
        category.name: visible,
      };
      await _saveHomeQuick(
        data,
        label: 'Atalho ${category.name} editado',
        publish: publish,
      );
    }

    await _showHomeBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
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
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _quickSheetHeader('Editar atalho'),
                  Text(
                    'Destino: ${category.name}',
                    style: const TextStyle(color: muted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: ValueKey('home-shortcut-label-${category.name}'),
                    controller: label,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: _quickField('Nome exibido'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: ValueKey('home-shortcut-image-${category.name}'),
                    controller: image,
                    keyboardType: TextInputType.url,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: _quickField('Imagem do atalho (URL)'),
                  ),
                  const SizedBox(height: 8),
                  CloudinaryUploadHelper(
                    controller: image,
                    onChanged: () => setSheetState(() {}),
                    description: 'Envie uma imagem ou informe uma URL.',
                  ),
                  const SizedBox(height: 12),
                  NamedVisualIconPicker(
                    value: iconKey,
                    onChanged: (value) => setSheetState(() => iconKey = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: visible,
                    onChanged: (value) => setSheetState(() => visible = value),
                    title: const Text('Mostrar na Home publicada'),
                  ),
                  Card(
                    child: ListTile(
                      leading: SizedBox(
                        width: 48,
                        height: 48,
                        child: image.text.trim().isEmpty
                            ? App3DIcon(
                                icon: AppIcon.fromKey(iconKey),
                                size: 42,
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  image.text.trim(),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => App3DIcon(
                                    icon: AppIcon.fromKey(iconKey),
                                    size: 42,
                                  ),
                                ),
                              ),
                      ),
                      title: Text(
                        label.text.trim().isEmpty
                            ? category.name
                            : label.text.trim(),
                      ),
                      subtitle: Text('Abre ${category.name}'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _quickSaveButtons(
                    onDraft: () => save(publish: false),
                    onPublish: () => save(publish: true),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Cancelar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    label.dispose();
    image.dispose();
  }

  Future<void> _editSectionTitle(HomePageConfig page, String section) async {
    final data = _editableHomeData(page);
    final title = TextEditingController(
      text: section == 'eventsAgenda'
          ? page.eventAgendaTitle
          : page.titleFor(section),
    );
    final description = TextEditingController(
      text: page.descriptionFor(section),
    );
    final image = TextEditingController(text: page.imageUrlFor(section));
    var iconIndex =
        page.iconFor(section) ?? AppIcon.fromCategory(section).legacyIndex;
    Future<void> save({required bool publish}) async {
      data['sectionTitles'] = {
        ...Map<String, dynamic>.from(data['sectionTitles'] as Map),
        section: title.text.trim(),
      };
      data['sectionDescriptions'] = {
        ...Map<String, dynamic>.from(data['sectionDescriptions'] as Map),
        section: description.text.trim(),
      };
      data['sectionImages'] = {
        ...Map<String, dynamic>.from(data['sectionImages'] as Map),
        section: image.text.trim(),
      };
      data['sectionIcons'] = {
        ...Map<String, dynamic>.from(data['sectionIcons'] as Map),
        section: iconIndex,
      };
      await _saveHomeQuick(
        data,
        label: 'Aparência da seção ${_homeSectionName(section)} editada',
        publish: publish,
      );
    }

    await _showHomeBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
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
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _quickSheetHeader('Editar ${_homeSectionName(section)}'),
                  TextField(
                    controller: title,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: _quickField('Título da seção'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: description,
                    maxLines: 2,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: _quickField('Descrição'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: image,
                    keyboardType: TextInputType.url,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: _quickField('Imagem da seção (URL)'),
                  ),
                  const SizedBox(height: 8),
                  CloudinaryUploadHelper(
                    controller: image,
                    onChanged: () => setSheetState(() {}),
                    description:
                        'Envie uma imagem ou use uma URL do Cloudinary.',
                  ),
                  if (image.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    HomeImagePreview(
                      url: image.text.trim(),
                      onRemove: () => setSheetState(image.clear),
                    ),
                  ],
                  const SizedBox(height: 12),
                  VisualIconPicker(
                    value: iconIndex,
                    label: 'Ícone da seção',
                    onChanged: (value) =>
                        setSheetState(() => iconIndex = value),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: image.text.trim().isEmpty
                          ? App3DIcon(
                              icon: AppIcon.fromLegacyIndex(iconIndex),
                              size: 38,
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                image.text.trim(),
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => App3DIcon(
                                  icon: AppIcon.fromLegacyIndex(iconIndex),
                                  size: 38,
                                ),
                              ),
                            ),
                      title: Text(
                        title.text.trim().isEmpty
                            ? _homeSectionName(section)
                            : title.text.trim(),
                      ),
                      subtitle: Text(
                        description.text.trim().isEmpty
                            ? 'Prévia da seção'
                            : description.text.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _quickSaveButtons(
                    onDraft: () => save(publish: false),
                    onPublish: () => save(publish: true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    title.dispose();
    description.dispose();
    image.dispose();
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

  Future<void> _runHomeQuickSave(Future<void> Function() save) async {
    try {
      await save();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível salvar. Confira a conexão e tente novamente.',
            ),
          ),
        );
      }
    }
  }

  Widget _quickSaveButtons({
    required Future<void> Function() onDraft,
    required Future<void> Function() onPublish,
  }) => Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () => _runHomeQuickSave(onDraft),
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Salvar rascunho'),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: FilledButton.icon(
          onPressed: () => _runHomeQuickSave(onPublish),
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
  }) => _showHomeBottomSheet<void>(
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

  Future<T?> _showHomeBottomSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
  }) async {
    Future<void>? routeCompleted;
    final result = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      builder: (sheetContext) {
        routeCompleted = ModalRoute.of(sheetContext)?.completed;
        return builder(sheetContext);
      },
    );
    // The route result completes as soon as it is popped, while its reverse
    // transition can leave TextFields mounted for another frame. Keep their
    // controllers alive until the modal route has removed its overlay entries.
    await routeCompleted;
    return result;
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Map<String, dynamic>>(
    stream: _configurationStream,
    builder: (context, snapshot) {
      if (SparkLocalEnvironment.enabled &&
          (snapshot.hasData || snapshot.hasError)) {
        SparkLocalStartupTimeline.markOnce(
          snapshot.hasError ? 'home_config_error' : 'home_config_first_data',
        );
      }
      if (snapshot.hasData) _lastConfiguration = snapshot.data;
      final hasConfiguration = snapshot.hasData || _lastConfiguration != null;
      _homeDataLoaded = hasConfiguration;
      final config =
          snapshot.data ??
          _lastConfiguration ??
          <String, dynamic>{
            // Keep the first loading frame useful without mounting sections
            // that start their own public-data listeners before the Home
            // configuration stream has delivered its initial snapshot.
            'sections': {
              for (final section in defaultHomeOrder)
                section: section == 'categories',
            },
          };
      final page = HomePageConfig.fromMap(config);
      final canEdit = _isAdmin && hasConfiguration;
      final isEditing = canEdit && editMode;
      final slivers = <Widget>[
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData)
          const SliverToBoxAdapter(
            child: LinearProgressIndicator(
              semanticsLabel: 'Carregando configuração da Home',
            ),
          ),
        if (snapshot.hasError)
          SliverToBoxAdapter(
            child: Card(
              margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: ListTile(
                leading: const Icon(Icons.cloud_off_outlined),
                title: Text(
                  hasConfiguration
                      ? 'Não foi possível atualizar a Home.'
                      : 'Não foi possível carregar a Home.',
                ),
                trailing: TextButton(
                  onPressed: _retryConfiguration,
                  child: const Text('Tentar novamente'),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: HomeTitleEditPilot(
            key: _titlePilotKey,
            isAdmin: canEdit,
            publishedTitle: page.heroTitle,
            onEnter: () => setState(() => editMode = false),
            onSave: (title, publish) {
              if (!canEdit) {
                throw StateError('Sessão administrativa encerrada.');
              }
              return _saveHomeQuick(
                {'heroTitle': title},
                label: 'Título principal da Home editado',
                publish: publish,
              );
            },
            builder: (title, onEdit, onStart, active) => Column(
              children: [
                WelcomeHero(
                  onSearch: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => homeSearchPage(
                        localSearch: LocalSearchEnvironment.enabled,
                        betaSearch: BetaEnvironment.enabled,
                      ),
                    ),
                  ),
                  onProfile: widget.onProfile,
                  weatherService: widget.weatherService,
                  user: widget.user,
                  config: page,
                  titleOverride: title,
                  onEditTitle: canEdit
                      ? isEditing && !active
                            ? onStart
                            : onEdit
                      : null,
                  editMode: isEditing && !active,
                  onToggleEditMode: canEdit
                      ? () => setState(() => editMode = !editMode)
                      : null,
                  editTooltip: editMode ? 'Sair da edição Home' : 'Editar Home',
                  onEditHero: isEditing && !active
                      ? () => _editHero(page)
                      : null,
                  onEditVisual: isEditing && !active
                      ? () => _editVisual(page)
                      : null,
                ),
                if (canEdit && !active)
                  HomeAdminEditBar(
                    active: editMode,
                    onToggle: () => setState(() => editMode = !editMode),
                    onSections: editMode ? () => _editSections(page) : null,
                    onFullEditor: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HomeEditor()),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ];
      if (isRegisteredUser(widget.user) &&
          (widget.savedBusinessIds.isNotEmpty ||
              widget.savedTourismIds.isNotEmpty)) {
        slivers.add(
          SliverToBoxAdapter(
            child: HomeFavoritesSection(
              businessIds: widget.savedBusinessIds.toList(growable: false),
              tourismIds: widget.savedTourismIds.toList(growable: false),
              resolveBusiness: _resolveFavoriteBusiness,
              resolveTourism: _resolveFavoriteTourism,
              onOpenBusiness: (business) => _openBusinessProfileFromCard(
                context,
                business,
                saved: true,
                onFavorite: () => widget.favorite(business),
                recordOpenMetric: true,
              ),
              onOpenTourism: (spot) => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => TouristSpotDetailView(
                    spot: spot,
                    saved: widget.savedTourismIds.contains(spot.id),
                    onFavorite: widget.favoriteTourism == null
                        ? null
                        : () => widget.favoriteTourism!(spot),
                  ),
                ),
              ),
              onRemoveBusiness: widget.favorite,
              onRemoveTourism: (spot) => widget.favoriteTourism?.call(spot),
              onViewAll: widget.onViewFavorites ?? () {},
            ),
          ),
        );
      }
      for (final section in page.order) {
        if (!page.enabled(section)) continue;
        final content = _section(context, section, page, isEditing, config);
        if (content != null) {
          slivers.add(SliverToBoxAdapter(child: content));
        }
      }
      return RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          key: const ValueKey('home-public-scroll-view'),
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
    Map<String, dynamic> publishedConfig,
  ) {
    final title = page.titleFor(section);
    final amount = page.limitFor(section);
    switch (section) {
      case 'banner':
        return EditableHomeArea(
          enabled: isEditing,
          label: 'Gerenciar anúncios',
          onEdit: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  const ContentManager(collection: 'ads', title: 'Banners'),
            ),
          ),
          child: const AdCarousel(),
        );
      case 'categories':
        final categories = page.primaryCategories(
          homeCatalog,
          includeHidden: isEditing,
        );
        final ordered = isEditing
            ? categories
            : categories.take(amount).toList(growable: false);
        return Column(
          children: [
            SectionTitle(
              title: title,
              action: 'Ver todas',
              onTap: widget.showExplore,
              wrapActionsOnLargeText: true,
              editMode: isEditing,
              onEdit: () => _editSectionTitle(page, section),
              description: page.descriptionFor(section),
              imageUrl: page.imageUrlFor(section),
              iconIndex: page.iconFor(section),
            ),
            SizedBox(
              height: 124,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                scrollDirection: Axis.horizontal,
                itemCount: ordered.length,
                separatorBuilder: (_, _) => const SizedBox(width: 9),
                itemBuilder: (_, i) => CategoryTile(
                  category: ordered[i],
                  displayLabel: _homeShortcutLabel(page, ordered[i]),
                  imageUrl: page.categoryImageUrlFor(ordered[i]),
                  editMode: isEditing,
                  onEdit: isEditing
                      ? () => _editCategoryShortcut(page, ordered[i])
                      : null,
                  onTap: () => isEditing
                      ? _editCategoryShortcut(page, ordered[i])
                      : openDirectory(
                          context,
                          ordered[i],
                          savedBusinessIds: widget.savedBusinessIds,
                          favoriteBusiness: widget.favorite,
                          savedTourismIds: widget.savedTourismIds,
                          favoriteTourism: widget.favoriteTourism,
                        ),
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
              description: page.descriptionFor(section),
              imageUrl: page.imageUrlFor(section),
              iconIndex: page.iconFor(section),
            ),
            PublishedBusinessStrip(
              repository: businessRepository,
              saved: widget.saved,
              favorite: widget.favorite,
              limit: amount,
              cardBuilder: (context, business, saved, onFavorite) =>
                  BusinessCard(
                    business: business,
                    saved: saved,
                    iconFallback: _businessIconFallback(business),
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
                    onShare: () => _shareBusiness(context, business),
                    compact: true,
                    featuredShowcase: true,
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
              description: page.descriptionFor(section),
              imageUrl: page.imageUrlFor(section),
              iconIndex: page.iconFor(section),
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
              description: page.descriptionFor(section),
              imageUrl: page.imageUrlFor(section),
              iconIndex: page.iconFor(section),
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
              description: page.descriptionFor(section),
              imageUrl: page.imageUrlFor(section),
              iconIndex: page.iconFor(section),
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
              description: page.descriptionFor(section),
              imageUrl: page.imageUrlFor(section),
              iconIndex: page.iconFor(section),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: LocalNewsCard(),
            ),
            SectionTitle(
              title: page.eventAgendaTitle,
              agendaStyle: true,
              action: 'Ver agenda',
              onTap: () => openFeature(context, Feature.events),
              editMode: isEditing,
              onEdit: () => _editSectionTitle(page, 'eventsAgenda'),
              description: page.descriptionFor('eventsAgenda'),
              imageUrl: page.imageUrlFor('eventsAgenda'),
              iconIndex: page.iconFor('eventsAgenda'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: EventCard(
                savedEventIds: widget.savedAgendaEventIds,
                onToggleAgenda: widget.toggleEventAgenda == null
                    ? null
                    : (event) => unawaited(
                        widget.toggleEventAgenda!(event).then((_) {}),
                      ),
              ),
            ),
          ],
        );
      case 'tourism':
        final raw = publishedConfig['tourism'];
        return HomeTourismCarousel(
          config: TourismConfig.fromMap(
            raw is Map ? Map<String, dynamic>.from(raw) : {},
          ),
          title: page.titleFor(section),
          description: page.descriptionFor(section),
          imageUrl: page.imageUrlFor(section),
          leading: page.iconFor(section) == null
              ? null
              : App3DIcon(
                  icon: AppIcon.fromLegacyIndex(page.iconFor(section)!),
                  size: 38,
                ),
          onCategoryTap: (category) => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TourismHomeView(
                initialCategoryKey: category.key,
                savedTourismIds: widget.savedTourismIds,
                favoriteTourism: widget.favoriteTourism,
              ),
            ),
          ),
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
  'sectionDescriptions': {
    for (final key in defaultHomeOrder) key: page.descriptionFor(key),
    'eventsAgenda': page.descriptionFor('eventsAgenda'),
  },
  'sectionImages': {
    for (final key in defaultHomeOrder) key: page.imageUrlFor(key),
    'eventsAgenda': page.imageUrlFor('eventsAgenda'),
  },
  'sectionIcons': {
    for (final key in defaultHomeOrder)
      if (page.iconFor(key) != null) key: page.iconFor(key),
    if (page.iconFor('eventsAgenda') != null)
      'eventsAgenda': page.iconFor('eventsAgenda'),
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
      category.name:
          category.iconKey ?? AppIcon.fromLegacyIndex(category.artwork).key,
  },
  'categoryLabels': {
    for (final category in page.categories(homeCatalog))
      category.name: page.categoryLabelFor(category),
  },
  'categoryImages': {
    for (final category in page.categories(homeCatalog))
      category.name: page.categoryImageUrlFor(category),
  },
  'categoryVisible': {
    for (final category in page.categories(homeCatalog))
      category.name: page.categoryVisibleFor(category),
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
    this.titleOverride,
    this.onEditTitle,
    this.editTooltip = 'Editar',
    this.weatherService,
    this.onProfile,
  });
  final VoidCallback onSearch;
  final User? user;
  final HomePageConfig config;
  final bool editMode;
  final VoidCallback? onToggleEditMode, onEditHero, onEditVisual, onEditTitle;
  final String? titleOverride;
  final String editTooltip;
  final WeatherService? weatherService;
  final VoidCallback? onProfile;
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
    final displayName = user?.displayName?.trim() ?? '';
    final firstName = displayName.isEmpty
        ? ''
        : displayName.split(RegExp(r'\s+')).first;
    final greetingText = !isRegisteredUser(user)
        ? config.greeting.trim()
        : firstName.isEmpty
        ? 'Olá!'
        : 'Olá, $firstName!';
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
                Tooltip(
                  message: 'Notificações',
                  child: CircleIcon(
                    size: 48,
                    icon: Icons.notifications_none_rounded,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotificationsView(),
                      ),
                    ),
                  ),
                ),
                if (onProfile != null) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Perfil',
                    child: CircleIcon(
                      icon: Icons.person_outline_rounded,
                      onTap: onProfile,
                      size: 48,
                    ),
                  ),
                ],
                if (isAdminUser(user, context: context) &&
                    onToggleEditMode != null) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    key: const ValueKey('home-admin-toggle-hero-edit'),
                    message: editTooltip,
                    child: CircleIcon(
                      icon: editMode
                          ? Icons.admin_panel_settings_rounded
                          : Icons.edit_outlined,
                      onTap: onToggleEditMode,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    constraints.maxWidth < 350 ||
                    MediaQuery.textScalerOf(context).scale(14) > 18;
                final titleBlock = Column(
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
                    Builder(
                      builder: (context) {
                        final title = Text(
                          titleOverride ?? config.heroTitle,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: background == 'image'
                                    ? Colors.white
                                    : ink,
                                fontWeight: FontWeight.w900,
                                height: 1.02,
                                letterSpacing: -.45,
                                shadows: heroTextShadow,
                              ),
                        );
                        if (onEditTitle == null) return title;
                        return Semantics(
                          button: true,
                          label: 'Editar título principal',
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: const ValueKey('home-hero-title-edit'),
                              onTap: onEditTitle,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                ),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: orange),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    title,
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Toque para editar',
                                      style: TextStyle(
                                        color: orange,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 5),
                    Text(
                      config.location,
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
                );
                final weather = HomeWeatherChip(
                  imageBackground: background == 'image',
                  service: weatherService,
                  compact: true,
                );
                return stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          titleBlock,
                          const SizedBox(height: 8),
                          weather,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: titleBlock),
                          const SizedBox(width: 10),
                          weather,
                        ],
                      );
              },
            ),
            const SizedBox(height: 12),
            if (!BetaEnvironment.enabled)
              UniversalSearchBar(
                onTap: onSearch,
                placeholder: config.searchPlaceholder == 'Encontre em Macacu...'
                    ? 'Buscar comércios, serviços e mais'
                    : config.searchPlaceholder,
              ),
            if (editMode) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  HomeEditChip(
                    icon: Icons.text_fields_rounded,
                    label: 'Textos',
                    onTap: onEditHero,
                  ),
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
            active ? 'Edição Admin ativa' : 'Modo Admin',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, color: ink),
          ),
        ),
        IconButton(
          key: const ValueKey('home-admin-toggle-visual-edit'),
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
    this.controller,
    this.onChanged,
    this.enabled = true,
    this.title = 'Enviar imagem pelo Cloudinary',
    this.description =
        'Selecione uma imagem do dispositivo ou use uma URL existente. Salve o formulário para publicar.',
  });

  final String title;
  final String description;
  final TextEditingController? controller;
  final VoidCallback? onChanged;
  final bool enabled;

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
        if (controller != null) ...[
          if (!BetaEnvironment.enabled) ...[
            ImageUploadButton(
              enabled: enabled,
              onUploaded: (url) {
                controller!.text = url;
                onChanged?.call();
              },
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (!BetaEnvironment.enabled)
          OutlinedButton.icon(
            onPressed: () => openUrl(
              context,
              'https://console.cloudinary.com/',
              'Cloudinary',
            ),
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Abrir Cloudinary'),
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
  Widget build(BuildContext context) =>
      AppBrand(logoUrl: logoUrl, tagline: slogan, inverse: imageBackground);
}

class AdCarousel extends StatefulWidget {
  const AdCarousel({super.key, this.adsStream, this.adsSnapshotStreamFactory});
  final Stream<QuerySnapshot<Map<String, dynamic>>>? adsStream;
  final Stream<PublicContentSnapshot> Function()? adsSnapshotStreamFactory;
  static const double bannerAspectRatio = 8 / 3;
  static const int maxAds = 10;
  @override
  State<AdCarousel> createState() => _AdCarouselState();
}

class _AdCarouselState extends State<AdCarousel> {
  static const fallbackImage = 'assets/images/home-ad-anuncie-aqui.png';
  final controller = PageController(viewportFraction: .9);
  Timer? autoplay;
  StreamSubscription<PublicContentSnapshot>? _subscription;
  Timer? _initialLoadTimeout;
  PublicContentSnapshot? _lastSnapshot;
  Object? _streamError;
  bool _loading = true;
  int _subscriptionGeneration = 0;
  int page = 0;
  int adCount = 1;
  static const _initialSnapshotTimeout = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _subscribe();
    autoplay = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!controller.hasClients || adCount < 2) return;
      controller.animateToPage(
        (page + 1) % adCount,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
      );
    });
  }

  Stream<PublicContentSnapshot> _createAdsStream() =>
      widget.adsSnapshotStreamFactory?.call() ??
      widget.adsStream?.map(PublicContentSnapshot.fromFirestore) ??
      watchPublicContent(FirestoreCollections.ads);

  void _subscribe() {
    final generation = ++_subscriptionGeneration;
    unawaited(_subscription?.cancel());
    _initialLoadTimeout?.cancel();
    if (_lastSnapshot == null) {
      _initialLoadTimeout = Timer(_initialSnapshotTimeout, () {
        if (!mounted ||
            generation != _subscriptionGeneration ||
            _lastSnapshot != null ||
            !_loading) {
          return;
        }
        setState(() {
          _streamError = TimeoutException(
            'Timed out waiting for the initial ads snapshot.',
            _initialSnapshotTimeout,
          );
          _loading = false;
        });
      });
    }
    _subscription = _createAdsStream().listen(
      (snapshot) {
        if (!mounted || generation != _subscriptionGeneration) return;
        _initialLoadTimeout?.cancel();
        setState(() {
          _lastSnapshot = snapshot;
          _streamError = null;
          _loading = false;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || generation != _subscriptionGeneration) return;
        _initialLoadTimeout?.cancel();
        setState(() {
          _streamError = error;
          _loading = false;
        });
      },
    );
  }

  bool get _canRetry =>
      widget.adsSnapshotStreamFactory != null || widget.adsStream == null;

  void _retry() {
    setState(() {
      _streamError = null;
      _loading = true;
    });
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant AdCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adsStream != widget.adsStream ||
        oldWidget.adsSnapshotStreamFactory != widget.adsSnapshotStreamFactory) {
      _lastSnapshot = null;
      _streamError = null;
      _loading = true;
      _subscribe();
    }
  }

  Widget _fallbackArtwork() => Image.asset(
    fallbackImage,
    // The supplied artwork has light framing above/below the 8:3 banner.
    // Centered cover removes that framing without cropping its main content.
    fit: BoxFit.cover,
    cacheWidth: 1200,
    alignment: Alignment.center,
    width: double.infinity,
    height: double.infinity,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final remote =
          _lastSnapshot?.docs
              .map((d) => d.data())
              .where((ad) => ad['active'] != false && isActiveContent(ad))
              .toList() ??
          [];
      remote.sort(compareAdOrder);
      final visibleAds = remote.take(AdCarousel.maxAds).toList();
      final ads = visibleAds.isEmpty
          ? [
              <String, dynamic>{'title': 'Anuncie aqui', 'link': ''},
            ]
          : visibleAds;
      adCount = ads.length;
      if (page >= adCount) {
        page = adCount - 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && controller.hasClients) {
            controller.jumpToPage(page);
          }
        });
      }
      final bannerWidth = constraints.maxWidth * .9 - 22;
      final decodeWidth = (bannerWidth * MediaQuery.devicePixelRatioOf(context))
          .ceil()
          .clamp(1, 1600);
      final bannerHeight = bannerWidth / AdCarousel.bannerAspectRatio + 14;
      if (_lastSnapshot == null && _loading) {
        return SizedBox(
          height: bannerHeight,
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(height: 8),
                Text('Carregando anúncios…'),
              ],
            ),
          ),
        );
      }
      if (_lastSnapshot == null && !_loading && _streamError != null) {
        return SizedBox(
          height: bannerHeight,
          child: Material(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(22),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Não foi possível carregar os anúncios.'),
                  if (_canRetry)
                    TextButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tentar novamente'),
                    ),
                ],
              ),
            ),
          ),
        );
      }
      return Column(
        children: [
          SizedBox(
            height: bannerHeight,
            child: PageView.builder(
              controller: controller,
              itemCount: ads.length,
              onPageChanged: (value) => setState(() => page = value),
              itemBuilder: (_, i) {
                final ad = ads[i];
                final title = (ad['title'] ?? '').toString();
                final link = (ad['link'] ?? '').toString();
                final imageUrl = (ad['imageUrl'] ?? '').toString();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 4, 0),
                  child: Semantics(
                    label: title,
                    button: link.isNotEmpty,
                    child: Material(
                      color: const Color(0xFFF8FAFC),
                      surfaceTintColor: Colors.transparent,
                      elevation: 1,
                      shadowColor: AppColors.ocean.withValues(alpha: .08),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.cardLarge),
                        side: BorderSide(
                          color: AppColors.sky.withValues(alpha: .08),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
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
                        child: imageUrl.isEmpty
                            ? _fallbackArtwork()
                            : Image.network(
                                imageUrl,
                                fit: BoxFit.contain,
                                cacheWidth: decodeWidth,
                                alignment: Alignment.center,
                                width: double.infinity,
                                height: double.infinity,
                                loadingBuilder: (context, child, progress) =>
                                    progress == null
                                    ? child
                                    : const Center(
                                        child: SizedBox.square(
                                          dimension: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                errorBuilder: (_, error, stackTrace) =>
                                    _fallbackArtwork(),
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (ads.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 5,
                runSpacing: 4,
                children: List.generate(
                  ads.length,
                  (index) => Semantics(
                    label: 'Anúncio ${index + 1} de ${ads.length}',
                    selected: page == index,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: page == index ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: page == index ? sky : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_loading && _lastSnapshot != null)
            const LinearProgressIndicator(minHeight: 2),
          if (_streamError != null && _lastSnapshot != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Flexible(
                  child: Text('Não foi possível atualizar os anúncios.'),
                ),
                if (_canRetry)
                  TextButton(
                    onPressed: _retry,
                    child: const Text('Tentar novamente'),
                  ),
              ],
            ),
        ],
      );
    },
  );

  @override
  void dispose() {
    autoplay?.cancel();
    ++_subscriptionGeneration;
    _initialLoadTimeout?.cancel();
    unawaited(_subscription?.cancel());
    controller.dispose();
    super.dispose();
  }
}

int compareAdOrder(Map<String, dynamic> a, Map<String, dynamic> b) {
  num order(Map<String, dynamic> ad) =>
      num.tryParse((ad['order'] ?? 0).toString()) ?? 0;
  return order(a).compareTo(order(b));
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => const AppBrand();
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
      child: FittedBox(
        fit: BoxFit.scaleDown,
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
    ),
  );
}

class CircleIcon extends StatelessWidget {
  const CircleIcon({super.key, required this.icon, this.onTap, this.size = 37});
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .94),
    shape: const CircleBorder(),
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: size,
        height: size,
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
    this.agendaStyle = false,
    this.wrapActionsOnLargeText = false,
    this.description = '',
    this.imageUrl = '',
    this.iconIndex,
  });
  final String title;
  final String action;
  final VoidCallback onTap;
  final bool editMode;
  final VoidCallback? onEdit;
  final bool agendaStyle;
  final bool wrapActionsOnLargeText;
  final String description;
  final String imageUrl;
  final int? iconIndex;

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w900,
        color: ink,
        letterSpacing: agendaStyle ? -.2 : null,
      ),
    );
    Widget? leading;
    if (imageUrl.trim().isNotEmpty) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          cloudinaryOptimizedImageUrl(imageUrl.trim()),
          width: 42,
          height: 42,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: 42,
            height: 42,
            color: const Color(0xFFEAF4FF),
            alignment: Alignment.center,
            child: iconIndex == null
                ? const Icon(Icons.image_not_supported_outlined, color: ocean)
                : App3DIcon(
                    icon: AppIcon.fromLegacyIndex(iconIndex!),
                    size: 32,
                  ),
          ),
        ),
      );
    } else if (iconIndex != null) {
      leading = Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF4FF),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: App3DIcon(icon: AppIcon.fromLegacyIndex(iconIndex!), size: 34),
      );
    }
    final titleWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 10)],
            Expanded(child: titleText),
          ],
        ),
        if (description.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            description.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: muted, height: 1.25),
          ),
        ],
      ],
    );
    final actionStyle = TextButton.styleFrom(
      foregroundColor: agendaStyle ? sky : ocean,
      textStyle: agendaStyle
          ? const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)
          : null,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10),
    );
    final editButton = IconButton.filledTonal(
      visualDensity: VisualDensity.compact,
      tooltip: 'Editar seção',
      onPressed: onEdit,
      icon: const Icon(Icons.edit_rounded, size: 18),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.xxl,
        AppSpacing.md,
        agendaStyle ? AppSpacing.md : AppSpacing.sm,
      ),
      child: LayoutBuilder(
        builder: (context, _) {
          final enlargedText = MediaQuery.textScalerOf(context).scale(14) > 14;
          if (wrapActionsOnLargeText && enlargedText) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleWidget,
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (editMode) ...[editButton, const SizedBox(width: 4)],
                    Flexible(
                      child: TextButton(
                        onPressed: onTap,
                        style: actionStyle,
                        child: Text(
                          '$action  ›',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: titleWidget),
              if (editMode) ...[const SizedBox(width: 4), editButton],
              TextButton(
                onPressed: onTap,
                style: actionStyle,
                child: Text('$action  ›'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.category,
    required this.onTap,
    this.grid = false,
    this.displayLabel,
    this.imageUrl = '',
    this.editMode = false,
    this.categoryVisible = true,
    this.onEdit,
  });
  final Category category;
  final VoidCallback onTap;
  final bool grid;
  final String? displayLabel;
  final String imageUrl;
  final bool editMode, categoryVisible;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) {
    final compactGridArtwork =
        grid && MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final artworkExtent = compactGridArtwork ? 68.0 : 90.0;
    final artworkImageExtent = compactGridArtwork ? 60.0 : 80.0;
    return Semantics(
      button: true,
      label: displayLabel ?? category.name,
      onTap: onTap,
      excludeSemantics: true,
      child: Opacity(
        opacity: categoryVisible ? 1 : .52,
        child: SizedBox(
          width: grid ? null : 82,
          child: Material(
            color: Colors.white,
            elevation: 1,
            clipBehavior: Clip.antiAlias,
            shadowColor: AppColors.ocean.withValues(alpha: .08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.card),
              side: BorderSide(color: AppColors.ocean.withValues(alpha: .07)),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadii.card),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(7, 8, 7, 7),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: grid ? artworkExtent : 51,
                          height: grid ? artworkExtent : 51,
                          decoration: BoxDecoration(
                            color: AppColors.skyTint,
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: Center(
                            child: _artwork(grid ? artworkImageExtent : 46),
                          ),
                        ),
                        const SizedBox(height: 5),
                        if (!grid &&
                            (displayLabel ?? category.name) == 'Profissionais')
                          SizedBox(
                            height: 24,
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  displayLabel ?? category.name,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                    color: ink,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          Text(
                            displayLabel ?? category.name,
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
                  if (editMode && onEdit != null)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: IconButton.filledTonal(
                        key: ValueKey('edit-home-shortcut-${category.name}'),
                        tooltip: 'Editar atalho ${category.name}',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 30,
                          height: 30,
                        ),
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_rounded, size: 15),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _artwork(double size) {
    final url = imageUrl.trim();
    if (url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _icon(size),
        ),
      );
    }
    return _icon(size);
  }

  Widget _icon(double size) => category.iconKey == null
      ? Sprite(index: category.artwork, size: size)
      : App3DIcon(icon: AppIcon.fromKey(category.iconKey), size: size);
}

String _homeCategoryLabel(Category category) =>
    category.name == 'Serviços úteis' ? 'Utilidades da Cidade' : category.name;

String _homeShortcutLabel(HomePageConfig page, Category category) {
  final label = page.categoryLabelFor(category);
  return label == category.name ? _homeCategoryLabel(category) : label;
}

class HomeCategoryGrid extends StatelessWidget {
  const HomeCategoryGrid({
    super.key,
    required this.categories,
    this.onCategoryTap,
  });

  final List<Category> categories;
  final ValueChanged<Category>? onCategoryTap;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.crossAxisExtent < 420 ? 2 : 3;
      final enlargedText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
      final tileAspectRatio = constraints.crossAxisExtent >= 600
          ? 1.35
          : columns == 2
          ? enlargedText
                ? .78
                : 1.05
          : .78;
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate((context, index) {
            final category = categories[index];
            return CategoryTile(
              category: category,
              displayLabel: _homeCategoryLabel(category),
              grid: true,
              onTap: () => onCategoryTap?.call(category),
            );
          }, childCount: categories.length),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: tileAspectRatio,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
        ),
      );
    },
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
  static const technology = AppIcon(
    key: 'technology',
    assetName: '31_technology_wifi.png',
    label: 'Tecnologia',
    legacyIndex: 18,
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
    technology,
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
    technology,
  ];

  static AppIcon fromKey(String? key) {
    final normalized = normalizeIconKey(key ?? '');
    final categoryFallback = switch (normalized) {
      'guiasturisticos' => roteiros,
      'historiacidade' => turismo,
      _ => null,
    };
    if (categoryFallback != null) return categoryFallback;
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

Widget? _businessIconFallback(Business business, {double size = 48}) {
  final key = business.iconKey.trim();
  return key.isEmpty ? null : App3DIcon(icon: AppIcon.fromKey(key), size: size);
}

final visualIconNames = [for (final icon in AppIcon.all) icon.label];

class NamedAppIconPicker extends StatelessWidget {
  const NamedAppIconPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Ícone',
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final selected = AppIcon.all.firstWhere(
      (item) => item.key == value,
      orElse: () => AppIcon.turismo,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            App3DIcon(icon: selected, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                key: const ValueKey('tourism-icon-key-dropdown'),
                initialValue: selected.key,
                decoration: const InputDecoration(
                  labelText: 'Escolha pelo nome',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final icon in AppIcon.all)
                    DropdownMenuItem(value: icon.key, child: Text(icon.label)),
                ],
                onChanged: (next) {
                  if (next != null) onChanged(next);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

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

class NamedVisualIconPicker extends StatelessWidget {
  const NamedVisualIconPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Ícone',
  });

  final String value;
  final ValueChanged<String> onChanged;
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
        children: [
          for (final icon in AppIcon.all)
            Semantics(
              button: true,
              selected: icon.key == value,
              label: icon.label,
              child: InkWell(
                key: ValueKey('named-home-icon-${icon.key}'),
                onTap: () => onChanged(icon.key),
                borderRadius: BorderRadius.circular(13),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 72,
                  padding: const EdgeInsets.symmetric(
                    vertical: 7,
                    horizontal: 4,
                  ),
                  decoration: BoxDecoration(
                    color: icon.key == value
                        ? const Color(0xFFEAF4FF)
                        : Colors.white,
                    border: Border.all(
                      color: icon.key == value ? sky : const Color(0xFFE2E8F0),
                      width: icon.key == value ? 2 : 1,
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
                          fontWeight: icon.key == value
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: icon.key == value ? ocean : ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
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
        canEdit: isAdminUser(
          FirebaseAuth.instance.currentUser,
          context: context,
        ),
        onEdit: () =>
            unawaited(_openBusinessEditorIfAuthorized(context, business)),
      ),
    ),
  );
}

Future<void> _openBusinessEditorIfAuthorized(
  BuildContext context,
  Business business,
) async {
  final authorization = AdminAuthorizationScope.depend(context);
  final user = FirebaseAuth.instance.currentUser;
  if (business.id.isEmpty || !authorization.allows(user)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir a edição.')),
      );
    }
    return;
  }

  try {
    // Recheck the central authorization immediately before the server read.
    if (!authorization.allows(FirebaseAuth.instance.currentUser)) return;
    final document = await FirebaseFirestore.instance
        .collection(FirestoreCollections.establishments)
        .doc(business.id)
        .get(const GetOptions(source: Source.server));
    if (!context.mounted) return;
    if (!document.exists ||
        !authorization.allows(FirebaseAuth.instance.currentUser)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir a edição.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContentEditor(
          collection: FirestoreCollections.establishments,
          doc: document,
        ),
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Não foi possível abrir a edição.')),
    );
  }
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

Future<void> _shareBusiness(BuildContext context, Business business) async {
  unawaited(
    recordMetric(
      'business_share',
      target: business.favoriteKey,
      targetType: 'business',
    ),
  );
  await sharePublicContentFromContext(
    context,
    PublicShareContent(title: business.name, description: business.description),
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
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 2004,
                height: 582,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: 2086,
                    maxWidth: 2086,
                    minHeight: 754,
                    maxHeight: 754,
                    child: Transform.translate(
                      offset: const Offset(-42, -98),
                      child: Image.asset(
                        'assets/images/home-offer-cover.png',
                        width: 2086,
                        height: 754,
                        fit: BoxFit.fill,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xE6082B4C),
                    Color(0xA60056D6),
                    Color(0x000056D6),
                  ],
                  stops: [0, .55, 1],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: .64,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
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
            ),
          ),
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

class EventCard extends StatefulWidget {
  const EventCard({
    super.key,
    this.eventsStreamFactory,
    this.savedEventIds = const <String>{},
    this.onToggleAgenda,
  });

  final Stream<PublicContentSnapshot> Function()? eventsStreamFactory;
  final Set<String> savedEventIds;
  final ValueChanged<PublicEvent>? onToggleAgenda;

  @override
  State<EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<EventCard> {
  StreamSubscription<PublicContentSnapshot>? _subscription;
  PublicContentSnapshot? _lastSnapshot;
  Object? _streamError;
  bool _loading = true;
  int _subscriptionGeneration = 0;

  Stream<PublicContentSnapshot> _createStream() =>
      widget.eventsStreamFactory?.call() ??
      watchPublicContent(FirestoreCollections.events);

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    final generation = ++_subscriptionGeneration;
    unawaited(_subscription?.cancel());
    _subscription = _createStream().listen(
      (snapshot) {
        if (!mounted || generation != _subscriptionGeneration) return;
        setState(() {
          _lastSnapshot = snapshot;
          _streamError = null;
          _loading = false;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || generation != _subscriptionGeneration) return;
        setState(() {
          _streamError = error;
          _loading = false;
        });
      },
    );
  }

  void _retry() {
    setState(() {
      _streamError = null;
      _loading = true;
    });
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant EventCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventsStreamFactory != widget.eventsStreamFactory) {
      _lastSnapshot = null;
      _streamError = null;
      _loading = true;
      _subscribe();
    }
  }

  @override
  Widget build(BuildContext context) {
    final events =
        _lastSnapshot?.docs.where((doc) {
          final data = doc.data();
          return data['published'] == true &&
              data['active'] == true &&
              data['deleted'] != true &&
              !data.containsKey('deletedAt') &&
              isActiveContent(data);
        }).toList() ??
        const <PublicContentDocument>[];
    final eventDocument = events.isEmpty ? null : events.first;
    final item = eventDocument?.data();
    final images = item == null ? const <String>[] : contentImageUrls(item);
    final hasError = _streamError != null;
    return HomeAgendaCard(
      title: item == null
          ? _loading
                ? 'Carregando agenda…'
                : hasError
                ? 'Agenda indisponível no momento'
                : 'Nenhum evento publicado no momento'
          : (item['title'] ?? item['name'] ?? 'Evento').toString(),
      date: item == null ? null : _contentDate(item),
      location: (item?['location'] ?? item?['address'] ?? '').toString().trim(),
      category: (item?['category'] ?? '').toString().trim(),
      imageUrl: images.isEmpty ? '' : images.first,
      loading: _loading,
      errorMessage: hasError && item != null
          ? 'Não foi possível atualizar a agenda.'
          : null,
      onRetry: hasError ? _retry : null,
      shareContent: item == null
          ? null
          : PublicShareContent(
              title: (item['title'] ?? item['name'] ?? 'Evento').toString(),
              description: (item['description'] ?? '').toString(),
            ),
      agendaSaved:
          eventDocument != null &&
          widget.savedEventIds.contains(eventDocument.id),
      onToggleAgenda: eventDocument == null || widget.onToggleAgenda == null
          ? null
          : () {
              try {
                widget.onToggleAgenda!(
                  PublicEvent.fromMap({
                    ...eventDocument.data(),
                    'id': eventDocument.id,
                  }),
                );
              } on FormatException {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Este evento não pode ser salvo agora.'),
                  ),
                );
              }
            },
      onTap: () => openFeature(context, Feature.events),
    );
  }

  @override
  void dispose() {
    ++_subscriptionGeneration;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

class NatureBanner extends StatelessWidget {
  const NatureBanner({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: BetaEnvironment.enabled
            ? const Stream.empty()
            : FirebaseFirestore.instance
                  .collection(FirestoreCollections.homePages)
                  .doc('published')
                  .snapshots(),
        builder: (_, snapshot) {
          final raw = snapshot.data?.data()?['tourism'];
          final config = TourismConfig.fromMap(
            raw is Map ? Map<String, dynamic>.from(raw) : {},
          );
          return TourismCover(
            title: config.title,
            description: config.subtitle,
            imageUrl: config.imageUrl,
            onTap: onTap,
          );
        },
      );
}

class ExploreView extends StatelessWidget {
  const ExploreView({
    super.key,
    required this.saved,
    required this.favorite,
    this.savedTourismIds = const <String>{},
    this.favoriteTourism,
    this.businessesStreamFactory,
  });
  final Set<String> saved;
  final ValueChanged<Business> favorite;
  final Set<String> savedTourismIds;
  final ValueChanged<TouristSpot>? favoriteTourism;
  final Stream<List<Business>> Function()? businessesStreamFactory;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          title: const Brand(),
          actions: [
            if (!BetaEnvironment.enabled)
              IconButton(
                tooltip: 'Buscar em Macacu',
                icon: const Icon(Icons.search_rounded),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => homeSearchPage(
                      localSearch: LocalSearchEnvironment.enabled,
                      betaSearch: BetaEnvironment.enabled,
                    ),
                  ),
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
        HomeCategoryGrid(
          categories: exploreCatalog,
          onCategoryTap: (category) => openDirectory(
            context,
            category,
            savedBusinessIds: saved,
            favoriteBusiness: favorite,
            savedTourismIds: savedTourismIds,
            favoriteTourism: favoriteTourism,
          ),
        ),
        SliverToBoxAdapter(
          child: SectionTitle(
            title: 'Negócios em destaque',
            action: 'Ver todos',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DirectoryView.all(
                  savedBusinessIds: saved,
                  favoriteBusiness: favorite,
                  businessesStreamFactory: businessesStreamFactory,
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: PublishedBusinessList(
            repository: businessRepository,
            businessesStreamFactory: businessesStreamFactory,
            saved: saved,
            favorite: favorite,
            cardBuilder: (context, business, saved, onFavorite) => BusinessCard(
              business: business,
              saved: saved,
              iconFallback: _businessIconFallback(business),
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
              onShare: () => _shareBusiness(context, business),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Selects the isolated callable-backed search only for the local demo flavor.
/// The regular app keeps its established search experience unchanged.
Widget homeSearchPage({required bool localSearch, bool betaSearch = false}) {
  if (localSearch && betaSearch) {
    throw ArgumentError('Beta e busca local não podem coexistir.');
  }
  if (localSearch) {
    return const UniversalSearchPage(trackBusinessShareMetrics: false);
  }
  if (betaSearch) {
    return const BetaSearchUnavailablePage();
  }
  return const GlobalSearchView();
}

class GlobalSearchView extends StatefulWidget {
  const GlobalSearchView({super.key, this.dependencies});

  final GlobalSearchViewDependencies? dependencies;

  @override
  State<GlobalSearchView> createState() => _GlobalSearchViewState();
}

/// Optional seams for isolated GlobalSearchView tests. The default widget
/// continues to use the app's existing repositories and local safety checks.
class GlobalSearchViewDependencies {
  const GlobalSearchViewDependencies({
    required this.loadBusinesses,
    required this.loadContent,
    required this.verifyLocalIsolation,
    required this.resolveJob,
  });

  final Future<List<Business>> Function() loadBusinesses;
  final Future<PublicContentSnapshot> Function(String collection) loadContent;
  final Future<void> Function() verifyLocalIsolation;
  final PublicJobResolver resolveJob;
}

class _GlobalSearchViewState extends State<GlobalSearchView> {
  final query = TextEditingController();
  Timer? _queryDebounce;
  String _debouncedTerm = '';
  String? _cachedTerm;
  GlobalSearchViewDependencies? _cachedDependencies;
  Future<List<_SearchResult>>? _cachedSearch;

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
    _queryDebounce?.cancel();
    query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _queryDebounce?.cancel();
    final term = value.trim().toLowerCase();
    if (term.isEmpty) {
      setState(() => _debouncedTerm = '');
      return;
    }
    setState(() {});
    _queryDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _debouncedTerm = term);
    });
  }

  void _retrySearch() {
    _cachedTerm = null;
    _cachedDependencies = null;
    _cachedSearch = null;
    setState(() => _debouncedTerm = query.text.trim().toLowerCase());
  }

  Future<List<_SearchResult>>? _searchForTerm(String term) {
    if (term.isEmpty) {
      _cachedTerm = null;
      _cachedDependencies = null;
      _cachedSearch = null;
      return null;
    }
    if (_cachedTerm != term ||
        !identical(_cachedDependencies, widget.dependencies)) {
      _cachedTerm = term;
      _cachedDependencies = widget.dependencies;
      _cachedSearch = _search(term);
    }
    return _cachedSearch;
  }

  Future<List<_SearchResult>> _search(String term) async {
    if (term.isEmpty) return const [];
    final terms = prepareSearchTerms(term);
    final dependencies = widget.dependencies;
    final businessResults =
        await (dependencies?.loadBusinesses() ??
            businessRepository.watchPublishedBusinesses().first);
    // Keep these authenticated callable reads sequential. A simultaneous burst
    // contends on the per-user rate-limit transaction and can make otherwise
    // healthy local/emulator searches time out.
    final searches = <PublicContentSnapshot>[];
    for (final collection in _contentCollections.keys) {
      searches.add(
        await (dependencies?.loadContent(collection) ??
            getPublicContent(collection)),
      );
    }
    final results = <_SearchResult>[];
    final seenBusinesses = <String>{};
    for (final business in businessResults) {
      final identity = business.id.trim().isNotEmpty
          ? business.id.trim()
          : normalizeSearchText(
              '${business.name} ${business.category} ${business.location}',
            );
      final content = normalizeSearchText(
        '${business.name} ${business.category} ${business.subcategory} '
        '${business.description} ${business.location} ${business.phone} '
        '${business.whatsapp} ${business.instagram}',
      );
      if (identity.isNotEmpty &&
          terms.isNotEmpty &&
          terms.every(content.contains) &&
          seenBusinesses.add(identity)) {
        results.add(_SearchResult.business(business));
      }
    }
    for (var index = 0; index < _contentCollections.length; index++) {
      final collection = _contentCollections.keys.elementAt(index);
      final snapshot = searches[index];
      for (final document in snapshot.docs) {
        final item = document.data();
        if (!isActiveContent(item)) continue;
        final content = normalizeSearchText(
          '${item['title'] ?? ''} ${item['description'] ?? ''} '
          '${item['category'] ?? ''}',
        );
        if (terms.every(content.contains)) {
          results.add(
            _SearchResult.content(
              title: (item['title'] ?? '').toString(),
              subtitle: (item['description'] ?? '').toString(),
              section: _contentCollections[collection]!,
              link: (item['link'] ?? '').toString(),
              documentId: document.id,
              sourceCollection: collection,
            ),
          );
        }
      }
    }
    return results;
  }

  Future<void> _openContent(_SearchResult result) async {
    if (result.sourceCollection == 'jobs' && LocalSearchEnvironment.enabled) {
      final jobId = result.documentId;
      if (jobId == null || jobId.isEmpty || jobId.contains('/')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Esta vaga não está disponível.')),
        );
        return;
      }
      try {
        PublicJob.validateId(jobId);
      } on FormatException {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Esta vaga não está disponível.')),
        );
        return;
      }
      try {
        await (widget.dependencies?.verifyLocalIsolation() ??
            LocalUniversalSearchRepository.verifyIsolation());
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível validar o ambiente local.'),
          ),
        );
        return;
      }
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => JobDetailPage(
            jobId: jobId,
            resolveJob: widget.dependencies?.resolveJob,
          ),
        ),
      );
      return;
    }
    if (result.link.isNotEmpty) {
      await openUrl(context, result.link, result.section);
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
        final typedTerm = query.text.trim().toLowerCase();
        final term = _debouncedTerm;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: query,
              autofocus: true,
              onChanged: _onQueryChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Empresas, eventos, ofertas e mais',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            if (typedTerm.isEmpty)
              const Text(
                'Busque empresas, ofertas, eventos, vagas, roteiros e notícias.',
                style: TextStyle(color: muted),
              )
            else if (typedTerm != term)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              FutureBuilder<List<_SearchResult>>(
                future: _searchForTerm(term)!,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Não foi possível pesquisar agora. Tente novamente.',
                          style: TextStyle(color: muted),
                        ),
                        TextButton.icon(
                          onPressed: _retrySearch,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Tentar novamente'),
                        ),
                      ],
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
                            key: result.identity == null
                                ? null
                                : ValueKey(result.identity),
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
    this.documentId,
    this.sourceCollection,
  });
  factory _SearchResult.business(Business business) => _SearchResult._(
    business: business,
    title: business.name,
    subtitle: [
      business.categoryLabel,
      business.location,
    ].where((value) => value.trim().isNotEmpty).join(' · '),
    section: 'Estabelecimentos',
  );
  factory _SearchResult.content({
    required String title,
    required String subtitle,
    required String section,
    required String link,
    required String documentId,
    required String sourceCollection,
  }) => _SearchResult._(
    title: title.isEmpty ? section : title,
    subtitle: subtitle,
    section: section,
    link: link,
    documentId: documentId,
    sourceCollection: sourceCollection,
  );
  final Business? business;
  final String title, subtitle, section, link;
  final String? documentId, sourceCollection;

  String? get identity => documentId == null || sourceCollection == null
      ? null
      : '$sourceCollection/$documentId';
}

void openDirectory(
  BuildContext context,
  Category category, {
  Set<String> savedBusinessIds = const <String>{},
  ValueChanged<Business>? favoriteBusiness,
  Set<String> savedTourismIds = const <String>{},
  ValueChanged<TouristSpot>? favoriteTourism,
}) {
  if (category.name == 'Serviços úteis') {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PublicServicesView()));
    return;
  }
  if (category.name == 'Turismo') {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TourismHomeView(
          savedTourismIds: savedTourismIds,
          favoriteTourism: favoriteTourism,
        ),
      ),
    );
    return;
  }
  if (category.name == 'Eventos') {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => cityAgendaForContext(context)));
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
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => DirectoryView(
        category: category,
        savedBusinessIds: savedBusinessIds,
        favoriteBusiness: favoriteBusiness,
      ),
    ),
  );
}

class DirectoryView extends StatefulWidget {
  const DirectoryView({
    super.key,
    required this.category,
    this.businessesStream,
    this.businessesStreamFactory,
    this.showAllBusinesses = false,
    this.savedBusinessIds = const <String>{},
    this.favoriteBusiness,
    this.clock,
  });

  const DirectoryView.all({
    super.key,
    this.businessesStreamFactory,
    this.savedBusinessIds = const <String>{},
    this.favoriteBusiness,
    this.clock,
  }) : category = const Category('Estabelecimentos', 0, <String>[]),
       businessesStream = null,
       showAllBusinesses = true;

  final Category category;
  final Stream<List<Business>>? businessesStream;
  final Stream<List<Business>> Function()? businessesStreamFactory;
  final bool showAllBusinesses;
  final Set<String> savedBusinessIds;
  final ValueChanged<Business>? favoriteBusiness;
  final DateTime Function()? clock;
  @override
  State<DirectoryView> createState() => _DirectoryViewState();
}

class _DirectoryViewState extends State<DirectoryView> {
  String type = 'Todos';
  final localSaved = <String>{};
  final _search = TextEditingController();
  late Stream<List<Business>> _businessesStream;
  List<Business>? _lastBusinesses;
  int _streamGeneration = 0;
  bool _openNowOnly = false;
  bool _openBusinessesFirst = false;
  Timer? _openNowTicker;

  Stream<List<Business>> _createBusinessesStream() =>
      widget.businessesStreamFactory?.call() ??
      widget.businessesStream ??
      businessRepository.watchPublishedBusinesses();

  @override
  void initState() {
    super.initState();
    _businessesStream = _createBusinessesStream();
  }

  @override
  void didUpdateWidget(covariant DirectoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessesStream != widget.businessesStream ||
        oldWidget.businessesStreamFactory != widget.businessesStreamFactory) {
      _businessesStream = _createBusinessesStream();
      _lastBusinesses = null;
      _streamGeneration++;
    }
  }

  @override
  void dispose() {
    _openNowTicker?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _retry() => setState(() {
    _businessesStream = _createBusinessesStream();
    _streamGeneration++;
  });

  void _setOpenNowOnly(bool enabled) {
    setState(() => _openNowOnly = enabled);
    _openNowTicker?.cancel();
    _openNowTicker = enabled
        ? Timer.periodic(const Duration(minutes: 1), (_) {
            if (mounted && _openNowOnly) setState(() {});
          })
        : null;
  }

  bool _isSaved(Business business) => widget.favoriteBusiness == null
      ? localSaved.contains(business.name)
      : widget.savedBusinessIds.contains(business.favoriteKey) ||
            widget.savedBusinessIds.contains(business.name);

  void _toggleFavorite(Business business) {
    final onFavorite = widget.favoriteBusiness;
    if (onFavorite == null) {
      setState(() {
        if (!_isSaved(business)) {
          localSaved.add(business.name);
        } else {
          localSaved.remove(business.name);
        }
      });
      return;
    }
    onFavorite(business);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Business>>(
    key: ValueKey(_streamGeneration),
    stream: _businessesStream,
    builder: (context, snapshot) {
      if (snapshot.hasData) _lastBusinesses = snapshot.data;
      final source = snapshot.data ?? _lastBusinesses;
      final categoryBusinesses =
          source
              ?.where(
                (item) =>
                    widget.showAllBusinesses ||
                    item.category == widget.category.name,
              )
              .toList() ??
          const <Business>[];
      final uniqueBusinesses = <String, Business>{};
      for (final business in categoryBusinesses) {
        final identity = business.id.trim().isNotEmpty
            ? business.id.trim()
            : normalizeSearchText(
                '${business.name} ${business.category} ${business.location}',
              );
        if (identity.isNotEmpty) {
          uniqueBusinesses.putIfAbsent(identity, () => business);
        }
      }
      final inCategory = uniqueBusinesses.values.toList();
      final query = _search.text.trim();
      final queryTerms = prepareSearchTerms(query);
      final categoryTypes = widget.showAllBusinesses
          ? inCategory
                .map((item) => item.category.trim())
                .where((item) => item.isNotEmpty)
                .toSet()
                .toList()
          : widget.category.types;
      if (widget.showAllBusinesses) categoryTypes.sort();
      final filters = ['Todos', ...categoryTypes];
      if (!filters.contains(type)) type = 'Todos';
      final orderingInstant = _openNowOnly || _openBusinessesFirst
          ? (widget.clock?.call() ?? DateTime.now())
          : null;
      final filtered = inCategory.where((item) {
        final matchesType =
            type == 'Todos' ||
            (widget.showAllBusinesses
                ? item.category == type
                : item.subcategory == type);
        final searchable = normalizeSearchText(
          '${item.name} ${item.category} ${item.subcategory} '
          '${item.description} ${item.location} ${item.phone} '
          '${item.whatsapp} ${item.instagram}',
        );
        final matchesSearch =
            query.isEmpty ||
            (queryTerms.isNotEmpty && queryTerms.every(searchable.contains));
        final matchesOpenNow =
            !_openNowOnly ||
            BusinessHoursSchedule.parse(
                  item.hours,
                )?.statusAt(orderingInstant!) ==
                BusinessOpeningStatus.open;
        return matchesType && matchesSearch && matchesOpenNow;
      }).toList();
      final visible = <Business>[];
      if (_openBusinessesFirst) {
        final openBusinesses = <Business>[];
        final remainingBusinesses = <Business>[];
        for (final business in filtered) {
          final isOpen =
              BusinessHoursSchedule.parse(
                business.hours,
              )?.statusAt(orderingInstant!) ==
              BusinessOpeningStatus.open;
          (isOpen ? openBusinesses : remainingBusinesses).add(business);
        }
        visible
          ..addAll(openBusinesses)
          ..addAll(remainingBusinesses);
      } else {
        visible.addAll(filtered);
      }
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
                      Text(
                        widget.showAllBusinesses
                            ? 'Busque por nome, categoria ou serviço.'
                            : 'Escolha um tipo para encontrar o que precisa.',
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
              children: [
                ChoiceChip(
                  key: const ValueKey('business-sort-default'),
                  avatar: Icon(
                    Icons.sort_rounded,
                    size: 18,
                    color: !_openBusinessesFirst
                        ? AppColors.ocean
                        : AppColors.muted,
                  ),
                  label: const Text('Padrão'),
                  selected: !_openBusinessesFirst,
                  onSelected: (_) =>
                      setState(() => _openBusinessesFirst = false),
                ),
                ChoiceChip(
                  key: const ValueKey('business-sort-open-first'),
                  avatar: Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: _openBusinessesFirst
                        ? AppColors.ocean
                        : AppColors.muted,
                  ),
                  label: const Text('Abertos primeiro'),
                  selected: _openBusinessesFirst,
                  onSelected: (_) =>
                      setState(() => _openBusinessesFirst = true),
                ),
                FilterChip(
                  key: const ValueKey('business-open-now-filter'),
                  avatar: Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: _openNowOnly ? AppColors.ocean : AppColors.muted,
                  ),
                  label: const Text('Aberto agora'),
                  selected: _openNowOnly,
                  onSelected: _setOpenNowOnly,
                ),
                ...filters.map(
                  (item) => ChoiceChip(
                    label: Text(item),
                    selected: type == item,
                    onSelected: (_) => setState(() => type = item),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('business-directory-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Buscar estabelecimento',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar busca',
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            if (!snapshot.hasData &&
                _lastBusinesses == null &&
                snapshot.hasError)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: const Text(
                    'Não foi possível carregar os estabelecimentos.',
                  ),
                  trailing: TextButton(
                    onPressed: _retry,
                    child: const Text('Tentar novamente'),
                  ),
                ),
              )
            else if (!snapshot.hasData && _lastBusinesses == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (snapshot.hasError)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.cloud_off_outlined),
                    title: const Text(
                      'Não foi possível atualizar os estabelecimentos.',
                    ),
                    trailing: TextButton(
                      onPressed: _retry,
                      child: const Text('Tentar novamente'),
                    ),
                  ),
                ),
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
                EmptyDirectory(
                  searching: query.isNotEmpty,
                  filtering: type != 'Todos',
                  openNow: _openNowOnly,
                )
              else
                ...visible.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: BusinessCard(
                      business: item,
                      saved: _isSaved(item),
                      iconFallback: _businessIconFallback(item),
                      onFavorite: () => _toggleFavorite(item),
                      onOpen: () => _openBusinessProfileFromCard(
                        context,
                        item,
                        saved: _isSaved(item),
                        onFavorite: () => _toggleFavorite(item),
                        recordOpenMetric: true,
                      ),
                      onViewBusiness: () => _openBusinessProfileFromCard(
                        context,
                        item,
                        saved: _isSaved(item),
                        onFavorite: () => _toggleFavorite(item),
                        recordOpenMetric: false,
                      ),
                      onWhatsApp: () =>
                          _openBusinessWhatsAppFromCard(context, item),
                      onShare: () => _shareBusiness(context, item),
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}

class EmptyDirectory extends StatelessWidget {
  const EmptyDirectory({
    super.key,
    this.searching = false,
    this.filtering = false,
    this.openNow = false,
  });
  final bool searching;
  final bool filtering;
  final bool openNow;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: mist,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      children: [
        const Icon(Icons.storefront_outlined, color: sky, size: 38),
        const SizedBox(height: 10),
        Text(
          openNow
              ? 'Nenhum estabelecimento aberto agora corresponde a estes filtros.'
              : searching && filtering
              ? 'Nenhum estabelecimento corresponde à busca e ao filtro selecionado.'
              : searching
              ? 'Nenhum estabelecimento corresponde à busca.'
              : filtering
              ? 'Nenhum estabelecimento nesta categoria por enquanto.'
              : 'Em breve, novos estabelecimentos aparecerão aqui.',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        const Text(
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
      elevation: 1,
      shadowColor: ink.withValues(alpha: .07),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(color: ocean.withValues(alpha: .07)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
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
  Widget build(BuildContext context) => StreamBuilder<PublicContentSnapshot>(
    stream: watchPublicContent(FirestoreCollections.alerts),
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
      elevation: 1,
      shadowColor: ink.withValues(alpha: .07),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(color: ocean.withValues(alpha: .07)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        leading: Container(
          width: 47,
          height: 47,
          decoration: BoxDecoration(
            color: mist,
            borderRadius: BorderRadius.circular(AppRadii.control),
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

class OffersView extends StatefulWidget {
  const OffersView({super.key, this.streamFactory});

  final Stream<PublicContentSnapshot> Function()? streamFactory;

  @override
  State<OffersView> createState() => _OffersViewState();
}

class _OffersViewState extends State<OffersView> {
  late Stream<PublicContentSnapshot> _stream;
  int _streamGeneration = 0;

  Stream<PublicContentSnapshot> _createStream() =>
      widget.streamFactory?.call() ??
      watchPublicContent(FirestoreCollections.offers);

  @override
  void initState() {
    super.initState();
    _stream = _createStream();
  }

  void _retry() => setState(() {
    _stream = _createStream();
    _streamGeneration++;
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: StreamBuilder<PublicContentSnapshot>(
      key: ValueKey(_streamGeneration),
      stream: _stream,
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
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (snapshot.hasError) ...[
              const Text(
                'Não foi possível carregar as ofertas.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted),
              ),
              Center(
                child: TextButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
              ),
              ...offers.map((offer) => OfferPublicCard(offer: offer)),
            ] else if (offers.isEmpty)
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
  const SavedView({
    super.key,
    required this.saved,
    required this.favorite,
    this.savedTourismIds = const <String>{},
    this.favoriteTourism,
    this.businessesStreamFactory,
    this.tourismStreamFactory,
  });
  final Set<String> saved;
  final ValueChanged<Business> favorite;
  final Set<String> savedTourismIds;
  final ValueChanged<TouristSpot>? favoriteTourism;
  final Stream<List<Business>> Function()? businessesStreamFactory;
  final Stream<List<TouristSpot>> Function()? tourismStreamFactory;

  Stream<List<TouristSpot>> _watchTourism() =>
      (tourismStreamFactory?.call() ??
      watchPublicContent(FirestoreCollections.routes).map(
        (snapshot) => snapshot.docs
            .where((document) => isActiveContent(document.data()))
            .map(
              (document) => TouristSpot.fromData(document.id, document.data()),
            )
            .toList(growable: false),
      ));

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Meus Favoritos'),
        bottom: const TabBar(
          tabs: [
            Tab(
              text: 'Estabelecimentos',
              icon: Icon(Icons.storefront_outlined),
            ),
            Tab(
              text: 'Pontos Turísticos',
              icon: Icon(Icons.landscape_outlined),
            ),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _SavedBusinessesTab(
            saved: saved,
            favorite: favorite,
            stream:
                businessesStreamFactory?.call() ??
                businessRepository.watchPublishedBusinesses(),
          ),
          _SavedTourismTab(
            savedIds: savedTourismIds,
            favorite: favoriteTourism,
            stream: _watchTourism(),
          ),
        ],
      ),
    ),
  );
}

class _SavedBusinessesTab extends StatelessWidget {
  const _SavedBusinessesTab({
    required this.saved,
    required this.favorite,
    required this.stream,
  });

  final Set<String> saved;
  final ValueChanged<Business> favorite;
  final Stream<List<Business>> stream;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Business>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _FavoritesMessage(
          icon: Icons.cloud_off_outlined,
          message: 'Não foi possível carregar seus estabelecimentos salvos.',
          onRetry: () => (context as Element).markNeedsBuild(),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final items = snapshot.data!
          .where(
            (item) =>
                saved.contains(item.favoriteKey) || saved.contains(item.name),
          )
          .toList(growable: false);
      if (items.isEmpty) {
        return const _FavoritesMessage(
          icon: Icons.favorite_border_rounded,
          message: 'Os estabelecimentos que você salvar aparecerão aqui.',
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          return BusinessCard(
            business: item,
            saved: true,
            iconFallback: _businessIconFallback(item),
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
            onWhatsApp: () => _openBusinessWhatsAppFromCard(context, item),
            onShare: () => _shareBusiness(context, item),
          );
        },
      );
    },
  );
}

class _SavedTourismTab extends StatelessWidget {
  const _SavedTourismTab({
    required this.savedIds,
    required this.favorite,
    required this.stream,
  });

  final Set<String> savedIds;
  final ValueChanged<TouristSpot>? favorite;
  final Stream<List<TouristSpot>> stream;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<TouristSpot>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _FavoritesMessage(
          icon: Icons.cloud_off_outlined,
          message: 'Não foi possível carregar seus pontos turísticos salvos.',
          onRetry: () => (context as Element).markNeedsBuild(),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final items = snapshot.data!
          .where((spot) => savedIds.contains(spot.id))
          .toList(growable: false);
      if (items.isEmpty) {
        return const _FavoritesMessage(
          icon: Icons.favorite_border_rounded,
          message: 'Os pontos turísticos que você salvar aparecerão aqui.',
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, index) => TouristSpotCard(
          spot: items[index],
          saved: true,
          onFavorite: favorite == null ? null : () => favorite!(items[index]),
        ),
      );
    },
  );
}

class _FavoritesMessage extends StatelessWidget {
  const _FavoritesMessage({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: muted),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
        ],
      ),
    ),
  );
}

class ContactView extends StatefulWidget {
  const ContactView({
    super.key,
    this.authChanges,
    this.submitMessageForTesting,
  });

  @visibleForTesting
  final Stream<User?>? authChanges;

  @visibleForTesting
  final Future<void> Function(String phone, String message)?
  submitMessageForTesting;

  @override
  State<ContactView> createState() => _ContactViewState();
}

class _ContactViewState extends State<ContactView> {
  final formKey = GlobalKey<FormState>();
  final contact = TextEditingController();
  final message = TextEditingController();
  bool sending = false;

  @override
  void dispose() {
    contact.dispose();
    message.dispose();
    super.dispose();
  }

  Future<void> send(User user) async {
    if (!isRegisteredUser(user) ||
        !(formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (user.email?.trim().isNotEmpty != true) return;
    setState(() => sending = true);
    try {
      final phone = normalizeBrazilianPhone(contact.text);
      final body = message.text.trim();
      final submit = widget.submitMessageForTesting;
      if (submit != null) {
        await submit(phone, body);
      } else {
        await writeUserOperation('contact', {
          'contact': phone,
          'message': body,
        });
      }
      contact.clear();
      message.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mensagem enviada. Obrigado pelo contato!'),
          ),
        );
      }
    } on ContactMessageDailyLimitReached {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Você atingiu o limite diário de 3 mensagens. Tente novamente mais tarde.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível enviar. Confira o telefone e tente novamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.authChanges == null ? FirebaseAuth.instance : null;
    return StreamBuilder<User?>(
      stream: widget.authChanges ?? auth!.authStateChanges(),
      initialData: auth?.currentUser,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (!isRegisteredUser(user)) return _loginPrompt(context);
        final email = user!.email?.trim() ?? '';
        if (email.isEmpty) return _emailRequired(context);
        return _contactForm(context, user, email);
      },
    );
  }

  Widget _loginPrompt(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Fale com a gente')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        const Brand(),
        const SizedBox(height: 26),
        const Icon(Icons.mark_email_unread_outlined, size: 48, color: sky),
        const SizedBox(height: 16),
        Text(
          'Entre para enviar uma mensagem',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Assim identificamos sua conta pelo e-mail. Você só precisará informar um telefone com DDD e escrever sua mensagem.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, height: 1.45),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const GoogleLoginView()),
          ),
          icon: const Icon(Icons.login_rounded),
          label: const Text('Entrar ou criar conta'),
        ),
      ],
    ),
  );

  Widget _emailRequired(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Fale com a gente')),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Não foi possível identificar o e-mail desta conta. Entre com uma conta que tenha um e-mail associado para enviar a mensagem.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );

  Widget _contactForm(
    BuildContext context,
    User user,
    String email,
  ) => Scaffold(
    appBar: AppBar(title: const Text('Fale com a gente')),
    body: Form(
      key: formKey,
      child: ListView(
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
          const SizedBox(height: 20),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'E-mail da conta',
              prefixIcon: Icon(Icons.account_circle_outlined),
              border: OutlineInputBorder(),
            ),
            child: Text(email),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: contact,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 11,
            decoration: const InputDecoration(
              labelText: 'Telefone com DDD',
              hintText: '21912345678',
              helperText: 'Informe DDD + número, com 10 ou 11 dígitos.',
              prefixIcon: Icon(Icons.phone_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (value) => isValidBrazilianPhone(value ?? '')
                ? null
                : 'Digite um telefone válido com DDD.',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: message,
            maxLines: 5,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'Mensagem',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            validator: (value) => (value?.trim().isNotEmpty ?? false)
                ? null
                : 'Digite sua mensagem antes de enviar.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Cada conta pode enviar até 3 mensagens por período de 24 horas.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: sending ? null : () => send(user),
            icon: sending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(sending ? 'Enviando...' : 'Enviar mensagem'),
          ),
        ],
      ),
    ),
  );
}

class ProfileView extends StatefulWidget {
  const ProfileView({
    super.key,
    required this.count,
    required this.user,
    this.onSaved,
    this.agendaCount = 0,
    this.onAgenda,
    this.onNotifications,
    this.onUpdateDisplayName,
    this.onPasswordReset,
    this.onSignOut,
    this.onDeleteAccount,
    this.privacyPolicyUrl = appPrivacyPolicyUrl,
  });
  final int count;
  final User? user;
  final VoidCallback? onSaved;
  final int agendaCount;
  final VoidCallback? onAgenda;
  final VoidCallback? onNotifications;

  @visibleForTesting
  final Future<void> Function(String displayName)? onUpdateDisplayName;

  @visibleForTesting
  final Future<void> Function(String email)? onPasswordReset;

  @visibleForTesting
  final Future<void> Function()? onSignOut;

  @visibleForTesting
  final Future<void> Function({
    required Future<String?> Function() requestPassword,
  })?
  onDeleteAccount;

  final String privacyPolicyUrl;

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  late String _displayName;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _displayName = widget.user?.displayName?.trim() ?? '';
  }

  @override
  void didUpdateWidget(covariant ProfileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user?.uid != widget.user?.uid ||
        oldWidget.user?.displayName != widget.user?.displayName) {
      _displayName = widget.user?.displayName?.trim() ?? '';
    }
  }

  bool get _hasPasswordProvider =>
      widget.user?.providerData.any(
        (provider) => provider.providerId == 'password',
      ) ??
      false;

  bool get _hasPrivacyPolicy {
    final uri = Uri.tryParse(widget.privacyPolicyUrl.trim());
    return uri != null && uri.scheme == 'https' && isAllowedExternalUri(uri);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editDisplayName() async {
    if (_busy) return;
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _DisplayNameDialog(initialName: _displayName),
    );
    if (value == null || !mounted) return;

    setState(() => _busy = true);
    try {
      if (widget.onUpdateDisplayName case final update?) {
        await update(value);
      } else {
        final updated = await AppAuth.updateDisplayName(value);
        await syncUserProfile(updated);
      }
      if (!mounted) return;
      setState(() => _displayName = value);
      _showMessage('Nome atualizado.');
    } catch (error) {
      _showMessage(
        authErrorMessage(error, action: AuthErrorAction.updateProfile),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    if (_busy) return;
    final email = widget.user?.email?.trim() ?? '';
    if (!_hasPasswordProvider || email.isEmpty) return;
    setState(() => _busy = true);
    try {
      await (widget.onPasswordReset ?? AppAuth.sendPasswordResetEmail)(email);
      _showMessage(
        'Se existir uma conta para esse e-mail, você receberá instruções para redefinir a senha.',
      );
    } catch (error) {
      _showMessage(
        authErrorMessage(error, action: AuthErrorAction.resetPassword),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmSignOut({required bool visitorAfter}) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.logout_rounded),
          title: const Text('Sair da conta?'),
          content: Text(
            visitorAfter
                ? 'Sua conta será desconectada neste aparelho. Você poderá continuar usando o aplicativo como visitante.'
                : 'Sua conta será desconectada neste aparelho. Você poderá continuar navegando sem entrar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('profile-confirm-sign-out'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Sair'),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _signOut() async {
    if (_busy) return;
    final visitorAfter = LocalSearchEnvironment.enabled;
    if (!await _confirmSignOut(visitorAfter: visitorAfter) || !mounted) return;
    setState(() => _busy = true);
    try {
      if (widget.onSignOut != null) {
        await widget.onSignOut!.call();
      } else {
        final current = FirebaseAuth.instance.currentUser ?? widget.user;
        if (current != null) await PushService.deactivate(current);
        await AppAuth.logout();
        if (!LocalSearchEnvironment.enabled) {
          try {
            await GoogleSignIn(
              clientId: googleSignInNativeClientId(
                betaVariant: BetaEnvironment.enabled,
                ios: defaultTargetPlatform == TargetPlatform.iOS,
                betaIosClientId: BetaEnvironment.iosGoogleClientId,
              ),
              serverClientId: googleSignInClientIdForCurrentFlavor(),
            ).signOut();
          } catch (_) {
            // Firebase Auth is already signed out; Google SDK cleanup is best effort.
            debugPrint('Sessão Google local não pôde ser limpa.');
          }
        }
      }
      _showMessage(
        visitorAfter
            ? 'Você voltou ao modo visitante.'
            : 'Você saiu da sua conta.',
      );
    } catch (error) {
      _showMessage(authErrorMessage(error, action: AuthErrorAction.signOut));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _canOfferAccountDeletion(User? user, bool isAdmin) =>
      isRegisteredUser(user) &&
      !isAdmin &&
      (widget.onDeleteAccount != null ||
          (BetaEnvironment.enabled &&
              !SparkLocalEnvironment.enabled &&
              !LocalSearchEnvironment.enabled));

  Future<bool> _confirmAccountDeletion() async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(
            Icons.delete_forever_outlined,
            color: AppColors.orange,
          ),
          title: const Text('Excluir minha conta?'),
          content: const SingleChildScrollView(
            child: Text(
              'Esta ação é permanente. Serão apagados seu perfil, favoritos, '
              'mensagens enviadas, propostas comerciais, avaliações, votos, '
              'cota de mensagens e lembretes locais deste aparelho.\n\n'
              'Conteúdos públicos e administrativos da cidade e registros '
              'de auditoria não serão apagados. Contas Admin precisam ser '
              'desativadas por um responsável antes de serem removidas.\n\n'
              'Toque em “Excluir conta” para confirmar. Sua identidade no '
              'provedor Google ou Apple não será apagada.',
            ),
          ),
          actions: [
            TextButton(
              key: const Key('profile-cancel-account-deletion'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('profile-confirm-account-deletion'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Excluir conta'),
            ),
          ],
        ),
      ) ==
      true;

  Future<String?> _requestDeletionPassword() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirme sua senha'),
          content: TextField(
            key: const Key('profile-delete-password'),
            controller: controller,
            obscureText: true,
            autofocus: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Senha atual'),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('profile-submit-delete-password'),
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  String _accountDeletionMessage(Object error) {
    if (error is AccountDeletionException) {
      return switch (error.code) {
        'no_registered_session' =>
          'Entre na conta que deseja excluir e tente novamente.',
        'account_changed' =>
          'A conta ativa mudou. Entre novamente e tente outra vez.',
        'admin_account' || 'protected_profile' =>
          'Contas Admin precisam ser desativadas por um responsável antes da exclusão.',
        'apple_provider_not_configured' =>
          'A exclusão para esta conta Apple ficará disponível após a configuração segura do login Apple no iOS.',
        'apple_revocation_code_missing' =>
          'A Apple não confirmou a autorização para revogar o acesso. Nenhum dado foi removido; tente novamente.',
        'reauthentication_cancelled' =>
          'A confirmação de identidade foi cancelada.',
        'reauthentication_failed' =>
          'Não foi possível confirmar sua identidade. Nenhum dado foi removido; confira sua senha ou a conta escolhida.',
        'identity_check_failed' =>
          'Não foi possível confirmar a sessão desta conta. Nenhum dado foi removido; entre novamente e tente outra vez.',
        'provider_not_supported' =>
          'Este método de acesso ainda não permite confirmar a identidade para exclusão.',
        'unsupported_environment' =>
          'A exclusão está disponível somente na versão Beta configurada.',
        'owned_data_mismatch' =>
          'A remoção foi interrompida porque um registro não corresponde à conta ativa.',
        _ =>
          'A exclusão não foi concluída. Seus dados podem ter sido removidos parcialmente; entre novamente e tente de novo.',
      };
    }
    if (error is FirebaseAuthException &&
        error.code == 'requires-recent-login') {
      return 'A confirmação de identidade expirou. Tente excluir a conta novamente.';
    }
    return 'A exclusão não foi concluída. Seus dados podem ter sido removidos parcialmente; entre novamente e tente de novo.';
  }

  Future<void> _deleteAccount(User user) async {
    if (_busy || !_canOfferAccountDeletion(user, false)) return;
    if (!await _confirmAccountDeletion() || !mounted) return;
    setState(() => _busy = true);
    try {
      final requestPassword = _requestDeletionPassword;
      if (widget.onDeleteAccount case final injected?) {
        await injected(requestPassword: requestPassword);
      } else {
        await AccountDeletionService.instance.deleteCurrentAccount(
          expectedUid: user.uid,
          requestPassword: requestPassword,
        );
      }
      _showMessage('Sua conta e os dados pessoais cobertos foram excluídos.');
    } catch (error) {
      _showMessage(_accountDeletionMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _privacyMenuRow() => MenuRow(
    key: const Key('profile-privacy-policy'),
    icon: Icons.privacy_tip_outlined,
    title: 'Política de privacidade',
    text: 'Leia como seus dados são tratados.',
    onTap: () => openUrl(
      context,
      widget.privacyPolicyUrl.trim(),
      'política de privacidade',
    ),
  );

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final isAdmin = isAdminUser(user, context: context);
    if (!isRegisteredUser(user)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Minha Conta')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.page),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  color: Colors.white,
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.feature),
                    side: const BorderSide(color: mist),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Brand(),
                        const SizedBox(height: AppSpacing.xl),
                        Container(
                          width: 76,
                          height: 76,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.orange.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: AppColors.orange.withValues(alpha: .16),
                            ),
                          ),
                          child: const Icon(
                            Icons.favorite_outline_rounded,
                            color: AppColors.orange,
                            size: 38,
                            semanticLabel: 'Favoritos',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Entre para personalizar',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const Text(
                          'Salve seus lugares e receba novidades de Macacu. Entrar é opcional: você pode continuar explorando a cidade.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: muted, height: 1.45),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        FilledButton.icon(
                          key: const Key('profile-open-login'),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const GoogleLoginView(),
                            ),
                          ),
                          icon: const Icon(Icons.login_rounded),
                          label: Text(
                            (LocalSearchEnvironment.enabled ||
                                    SparkLocalEnvironment.enabled)
                                ? 'Entrar com conta demo'
                                : 'Continuar com Google',
                          ),
                        ),
                        if (_hasPrivacyPolicy) ...[
                          const SizedBox(height: AppSpacing.md),
                          _privacyMenuRow(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Minha Conta')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Brand(),
                    const SizedBox(height: AppSpacing.xl),
                    Card(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Row(
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                gradient: AppTheme.brandGradient,
                                shape: BoxShape.circle,
                              ),
                              child: CircleAvatar(
                                backgroundColor: AppColors.yellow,
                                backgroundImage:
                                    user!.photoURL == null ||
                                        user.photoURL!.trim().isEmpty
                                    ? null
                                    : NetworkImage(user.photoURL!),
                                child:
                                    user.photoURL == null ||
                                        user.photoURL!.trim().isEmpty
                                    ? const Icon(
                                        Icons.person_outline_rounded,
                                        color: AppColors.ink,
                                        size: 30,
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _displayName.isEmpty
                                        ? 'Minha Conta'
                                        : _displayName,
                                    key: const Key('profile-display-name'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  if (user.email?.trim().isNotEmpty ?? false)
                                    Text(
                                      user.email!.trim(),
                                      key: const Key('profile-email'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: AppColors.muted),
                                    ),
                                  if (isAdmin) ...[
                                    const SizedBox(height: AppSpacing.xs),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.sm,
                                        vertical: AppSpacing.xs,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.orange.withValues(
                                          alpha: .10,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          AppRadii.pill,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.shield_rounded,
                                            size: 14,
                                            color: AppColors.orange,
                                          ),
                                          const SizedBox(width: AppSpacing.xs),
                                          Flexible(
                                            child: Text(
                                              'Admin autorizado',
                                              key: const Key(
                                                'profile-admin-status',
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color: AppColors.ink,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              key: const Key('profile-edit-name'),
                              tooltip: 'Editar nome',
                              onPressed: _busy ? null : _editDisplayName,
                              constraints: const BoxConstraints.tightFor(
                                width: 40,
                                height: 40,
                              ),
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_busy) const LinearProgressIndicator(),
                    MenuRow(
                      key: const Key('profile-saved-items'),
                      icon: Icons.favorite_outline_rounded,
                      title: 'Itens salvos',
                      text: '${widget.count} favorito(s) na sua conta',
                      onTap: widget.onSaved,
                      showChevron: widget.onSaved != null,
                    ),
                    MenuRow(
                      key: const Key('profile-my-agenda'),
                      icon: Icons.event_available_outlined,
                      title: 'Minha Agenda',
                      text:
                          '${widget.agendaCount} evento(s) salvo(s) na sua conta',
                      onTap: widget.onAgenda,
                      showChevron: widget.onAgenda != null,
                    ),
                    MenuRow(
                      key: const Key('profile-notifications'),
                      icon: Icons.notifications_none_rounded,
                      title: 'Notificações',
                      text: 'Lembretes de eventos e avisos do aplicativo',
                      onTap: widget.onNotifications,
                      showChevron: widget.onNotifications != null,
                    ),
                    if (_hasPasswordProvider &&
                        (user.email?.trim().isNotEmpty ?? false))
                      MenuRow(
                        key: const Key('profile-reset-password'),
                        icon: Icons.lock_reset_outlined,
                        title: 'Redefinir senha',
                        text: 'Enviaremos instruções para o e-mail da conta.',
                        onTap: _busy ? null : _sendPasswordReset,
                      )
                    else
                      MenuRow(
                        key: const Key('profile-password-provider-note'),
                        icon: Icons.verified_user_outlined,
                        title: 'Segurança da conta',
                        text:
                            widget.user!.providerData.any(
                              (provider) => provider.providerId == 'google.com',
                            )
                            ? 'Sua senha é gerenciada pelo Google.'
                            : 'A senha é gerenciada pelo seu provedor de acesso.',
                        showChevron: false,
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
                    if (_hasPrivacyPolicy) _privacyMenuRow(),
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
                      key: const Key('profile-sign-out'),
                      icon: Icons.logout_rounded,
                      title: 'Sair da conta',
                      text: LocalSearchEnvironment.enabled
                          ? 'Voltar ao modo visitante neste aparelho'
                          : 'Entrar com outra conta Google',
                      onTap: _busy ? null : _signOut,
                    ),
                    if (_canOfferAccountDeletion(user, isAdmin))
                      MenuRow(
                        key: const Key('profile-delete-account'),
                        icon: Icons.delete_outline_rounded,
                        title: 'Excluir minha conta',
                        text: 'Apaga a conta e os dados pessoais associados',
                        isDestructive: true,
                        onTap: _busy ? null : () => _deleteAccount(user),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: mist,
                        borderRadius: BorderRadius.circular(AppRadii.card),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisplayNameDialog extends StatefulWidget {
  const _DisplayNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_DisplayNameDialog> createState() => _DisplayNameDialogState();
}

class _DisplayNameDialogState extends State<_DisplayNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Editar nome'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        key: const Key('profile-name-input'),
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        maxLength: 80,
        decoration: const InputDecoration(labelText: 'Nome de exibição'),
        validator: (text) {
          final name = (text ?? '').trim();
          if (name.length < 2) return 'Informe pelo menos 2 caracteres.';
          if (name.length > 80) return 'Use até 80 caracteres.';
          return null;
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('profile-name-save'),
        onPressed: () {
          if (_formKey.currentState?.validate() ?? false) {
            Navigator.of(context).pop(_controller.text.trim());
          }
        },
        child: const Text('Salvar'),
      ),
    ],
  );
}

class MenuRow extends StatelessWidget {
  const MenuRow({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    this.onTap,
    this.showChevron = true,
    this.isDestructive = false,
  });
  final IconData icon;
  final String title;
  final String text;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool isDestructive;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Material(
      color: Colors.white,
      elevation: onTap == null ? 0 : .5,
      shadowColor: AppColors.ocean.withValues(alpha: .08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(color: AppColors.ocean.withValues(alpha: .08)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        minLeadingWidth: 46,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: isDestructive
                ? Colors.red.withValues(alpha: .08)
                : AppColors.skyTint,
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          child: Icon(
            icon,
            color: isDestructive ? Colors.red.shade700 : AppColors.ocean,
            size: 21,
          ),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: isDestructive ? Colors.red.shade700 : AppColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.muted, height: 1.35),
        ),
        trailing: showChevron
            ? const Icon(Icons.chevron_right_rounded, color: AppColors.sky)
            : null,
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
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(AppRadii.feature),
            boxShadow: [
              BoxShadow(
                color: AppColors.ocean.withValues(alpha: .14),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Área administrativa',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Gerencie o conteúdo do aplicativo',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: .88),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Controle do aplicativo',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Escolha a área que deseja atualizar.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.lg),
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
          title: 'Administração',
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

Widget _adminSectionHeading(BuildContext context, String title) => Padding(
  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
  child: Text(
    title,
    style: Theme.of(context).textTheme.titleSmall?.copyWith(
      color: AppColors.ocean,
      fontWeight: FontWeight.w700,
    ),
  ),
);

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
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      minLeadingWidth: 50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(color: AppColors.ocean.withValues(alpha: .09)),
      ),
      tileColor: color,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.skyTint,
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Icon(icon, color: AppColors.ocean, size: 22),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.muted, height: 1.35),
      ),
      trailing: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .72),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.chevron_right_rounded, color: AppColors.sky),
      ),
    ),
  );
}

class AdminContentHub extends StatelessWidget {
  const AdminContentHub({super.key, this.utilitiesStreamFactory});

  final UtilityManagerStreamFactory? utilitiesStreamFactory;
  @override
  Widget build(BuildContext context) => _AdminHub(
    title: 'Conteúdo',
    description: 'Escolha o tipo de conteúdo que deseja publicar.',
    utilitiesStreamFactory: utilitiesStreamFactory,
    sectionForItem: const {
      'events': 'Eventos e divulgação',
      'ads': 'Eventos e divulgação',
      'news': 'Eventos e divulgação',
      'coupons': 'Eventos e divulgação',
      'polls': 'Eventos e divulgação',
      'routes': 'Turismo e história',
      'utilities': 'Serviços da cidade',
      'transport': 'Serviços da cidade',
      'trash_collection': 'Serviços da cidade',
      'useful_phones': 'Serviços da cidade',
      'alerts': 'Serviços da cidade',
      'emergency_contacts': 'Serviços da cidade',
      'resolver_subjects': 'Serviços da cidade',
      'public_places': 'Serviços da cidade',
      'health': 'Serviços da cidade',
      'jobs': 'Trabalho',
    },
    items: const [
      ('events', 'Eventos', Icons.event_note_outlined),
      ('routes', 'Explorar Macacu', Icons.explore_outlined),
      ('ads', 'Banners e campanhas', Icons.campaign_outlined),
      ('utilities', 'Utilidades da cidade', Icons.apps_rounded),
      ('transport', 'Ônibus', Icons.directions_bus_rounded),
      ('trash_collection', 'Coleta', Icons.delete_outline_rounded),
      ('useful_phones', 'Telefones úteis', Icons.phone_outlined),
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
    appBar: AppBar(title: const Text('Administração')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _adminSectionHeading(context, 'Ferramentas de conteúdo'),
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
        const SizedBox(height: AppSpacing.sm),
        _adminSectionHeading(context, 'Acompanhamento'),
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
        const SizedBox(height: AppSpacing.sm),
        _adminSectionHeading(context, 'Atendimento'),
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

class _AdminHub extends StatefulWidget {
  const _AdminHub({
    required this.title,
    required this.description,
    required this.items,
    required this.sectionForItem,
    this.utilitiesStreamFactory,
  });

  final String title;
  final String description;
  final List<(String, String, IconData)> items;
  final Map<String, String> sectionForItem;
  final UtilityManagerStreamFactory? utilitiesStreamFactory;

  @override
  State<_AdminHub> createState() => _AdminHubState();
}

class _AdminHubState extends State<_AdminHub> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupedItems = <String, List<(String, String, IconData)>>{};
    for (final item in widget.items) {
      final section = widget.sectionForItem[item.$1] ?? 'Outros conteúdos';
      groupedItems.putIfAbsent(section, () => []).add(item);
    }
    final normalizedQuery = normalizeSearchText(_query);
    final isSearching = normalizedQuery.isNotEmpty;
    final filteredItems = isSearching
        ? widget.items
              .where(
                (item) =>
                    normalizeSearchText(item.$2).contains(normalizedQuery),
              )
              .toList(growable: false)
        : const <(String, String, IconData)>[];

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: [
          Text(widget.description, style: const TextStyle(color: muted)),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const ValueKey('admin-content-search'),
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Buscar módulo',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('admin-content-search-clear'),
                      tooltip: 'Limpar busca',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.control),
                borderSide: BorderSide(
                  color: AppColors.ocean.withValues(alpha: .12),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.control),
                borderSide: BorderSide(
                  color: AppColors.ocean.withValues(alpha: .12),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.control),
                borderSide: const BorderSide(color: AppColors.sky, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (isSearching && filteredItems.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      color: AppColors.ocean.withValues(alpha: .72),
                      size: 30,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Nenhum módulo encontrado',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'Tente outro nome ou limpe a busca.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            )
          else if (isSearching)
            ...filteredItems.map((item) => _moduleTile(context, item))
          else
            for (final section in groupedItems.entries) ...[
              _adminSectionHeading(context, section.key),
              ...section.value.map((item) => _moduleTile(context, item)),
              const SizedBox(height: AppSpacing.sm),
            ],
        ],
      ),
    );
  }

  Widget _moduleTile(BuildContext context, (String, String, IconData) item) =>
      AdminMenuTile(
        icon: item.$3,
        title: item.$2,
        subtitle: 'Adicionar, editar, revisar e publicar',
        color: Colors.white,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => item.$1 == 'utilities'
                ? UtilityManager(streamFactory: widget.utilitiesStreamFactory)
                : ContentManager(collection: item.$1, title: item.$2),
          ),
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
  const InitialContentImporter({super.key, this.lookupOnServer});

  /// Optional read adapter used by the isolated Android Emulator harness.
  /// Normal application construction continues to use the Firebase SDK.
  final ExistingEstablishmentLookup? lookupOnServer;

  @override
  State<InitialContentImporter> createState() => _InitialContentImporterState();
}

class _InitialContentImporterState extends State<InitialContentImporter> {
  bool importing = false;

  Future<void> importExamples() async {
    if (!isAdminUser(FirebaseAuth.instance.currentUser)) return;
    setState(() => importing = true);
    var otherContentSkipped = 0;
    var alreadyPresent = 0;
    var tombstoned = 0;
    try {
      final collection = FirebaseFirestore.instance.collection(
        'establishments',
      );
      var added = 0;
      if (BetaEnvironment.enabled) {
        final firestore = FirebaseFirestore.instance;
        final repository = SparkAdminContentRepository(firestore);
        for (var index = 0; index < businesses.length; index++) {
          final business = businesses[index];
          final id = 'modelo-${index + 1}';
          final current = await collection
              .doc(id)
              .get(const GetOptions(source: Source.server));
          if (current.exists) {
            if (current.data()?['deleted'] == true ||
                current.data()?['deletedAt'] != null) {
              tombstoned++;
            } else {
              alreadyPresent++;
            }
            continue;
          }
          await repository.save(
            collection: 'establishments',
            id: id,
            data: {
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
              'imageUrl': business.imageUrl,
              'logoUrl': business.logoUrl,
              'galleryUrls': business.galleryUrls,
              'hours': business.hours,
              'services': business.services,
              'products': business.products,
              'additionalInfo': business.additionalInfo,
              'promotionTitle': business.promotionTitle,
              'promotionDescription': business.promotionDescription,
              'publicContactApproved': false,
              'active': true,
              'published': true,
            },
          );
          added++;
        }
      } else if (HybridAdminRuntime.enabled) {
        final repository = HybridAdminRuntime.createIfEnabled();
        if (repository == null) {
          throw const HybridAdminException(HybridAdminFailure.notConfigured);
        }
        final importer = InitialContentImporterService(
          repository: repository,
          lookupOnServer:
              widget.lookupOnServer ??
              (id) async {
                final snapshot = await collection
                    .doc(id)
                    .get(const GetOptions(source: Source.server));
                return classifyExistingEstablishment(snapshot.data());
              },
        );
        final report = await importer.import([
          for (var index = 0; index < businesses.length; index++)
            () {
              final business = businesses[index];
              return InitialContentImportItem(
                entityId: 'modelo-${index + 1}',
                category: business.category,
                editorData: {
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
                  'imageUrl': business.imageUrl,
                  'logoUrl': business.logoUrl,
                  'galleryUrls': business.galleryUrls,
                  'hours': business.hours,
                  'services': business.services,
                  'products': business.products,
                  'additionalInfo': business.additionalInfo,
                  'promotionTitle': business.promotionTitle,
                  'promotionDescription': business.promotionDescription,
                  'publicContactApproved': false,
                  'active': true,
                  'published': true,
                },
              );
            }(),
        ], authorized: true);
        added = report.created;
        alreadyPresent = report.alreadyPresent;
        tombstoned = report.tombstoned;
        otherContentSkipped = report.skippedOtherContent;
      } else {
        final existing = await collection.get();
        final ids = existing.docs.map((document) => document.id).toSet();
        final batch = FirebaseFirestore.instance.batch();
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
      }
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
              added == 0 && otherContentSkipped == 0
                  ? 'Os exemplos já estão na área administrável.'
                  : '$added exemplo(s) foram importados.${alreadyPresent > 0 ? ' $alreadyPresent já tinham marcadores de outbox e foram preservados.' : ''}${tombstoned > 0 ? ' $tombstoned possuem exclusão lógica e não foram republicados.' : ''}${otherContentSkipped > 0 ? ' $otherContentSkipped item(ns) de outras categorias não foram tratados como estabelecimentos.' : ''} Agora você pode editar cada estabelecimento.',
            ),
          ),
        );
      }
    } on FirebaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível importar agora. Verifique sua conexão e tente novamente.',
            ),
          ),
        );
      }
    } on InitialContentImportException catch (error) {
      if (mounted) {
        final progress =
            error.created + error.alreadyPresent + error.tombstoned;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.failure == HybridAdminFailure.conflict
                  ? 'Há um registro legado ou inconsistente com um ID modelo-*. Nenhum dado foi sobrescrito; reconcilie esse item antes de continuar.'
                  : progress == 0
                  ? 'A importação foi recusada ou não pôde começar. Nenhum item foi confirmado.'
                  : 'A importação foi interrompida após $progress item(ns) confirmado(s). Itens anteriores serão reconhecidos ao tentar novamente.',
            ),
          ),
        );
      }
    } on HybridAdminException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível importar todos os exemplos pelo serviço administrativo.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível importar todos os exemplos.'),
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
  const HomeEditor({
    super.key,
    this.loadConfiguration,
    this.saveConfiguration,
    this.imageSource,
    this.imageUploadService,
  });
  final Future<Map<String, dynamic>> Function()? loadConfiguration;
  final Future<void> Function(Map<String, dynamic> data, bool publish)?
  saveConfiguration;
  final ImageSelectionSource? imageSource;
  final ImageUploadService? imageUploadService;
  @override
  State<HomeEditor> createState() => _HomeEditorState();
}

class _HomeEditorState extends State<HomeEditor> {
  late final ImageUploadService _imageUploadService =
      widget.imageUploadService ?? WorkerImageUploadService();
  final title = TextEditingController(),
      search = TextEditingController(),
      slogan = TextEditingController(),
      greeting = TextEditingController(),
      location = TextEditingController(),
      backgroundImageUrl = TextEditingController(),
      backgroundStart = TextEditingController(),
      backgroundEnd = TextEditingController();
  final sectionTitles = <String, TextEditingController>{
    for (final key in defaultHomeOrder) key: TextEditingController(),
  };
  final sectionLimits = <String, TextEditingController>{
    for (final key in defaultHomeOrder) key: TextEditingController(),
  };
  final sectionDescriptions = <String, TextEditingController>{
    for (final key in defaultHomeOrder) key: TextEditingController(),
  };
  final sectionImages = <String, TextEditingController>{
    for (final key in defaultHomeOrder) key: TextEditingController(),
  };
  final sectionIcons = <String, int?>{
    for (final key in defaultHomeOrder) key: null,
  };
  final categoryIcons = <String, String>{
    for (final category in homeCatalog)
      category.name: AppIcon.fromLegacyIndex(category.artwork).key,
  };
  final categoryLabels = <String, TextEditingController>{
    for (final category in homeCatalog)
      category.name: TextEditingController(text: category.name),
  };
  final categoryImages = <String, TextEditingController>{
    for (final category in homeCatalog) category.name: TextEditingController(),
  };
  final categoryVisible = <String, bool>{
    for (final category in homeCatalog) category.name: true,
  };
  final enabled = <String, bool>{for (final key in defaultHomeOrder) key: true};
  var order = [...defaultHomeOrder];
  var categoryOrder = [...HomePageConfig.primaryCategoryNames];
  MediaSelection logoSelection = const MediaSelection.empty();
  String backgroundType = 'gradient';
  bool saving = false, loading = true, loadFailed = false, loaded = false;

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
      backgroundImageUrl,
      backgroundStart,
      backgroundEnd,
      ...sectionTitles.values,
      ...sectionLimits.values,
      ...sectionDescriptions.values,
      ...sectionImages.values,
      ...categoryLabels.values,
      ...categoryImages.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    if (mounted) {
      setState(() {
        loading = true;
        loadFailed = false;
      });
    }
    try {
      Map<String, dynamic> data;
      if (widget.loadConfiguration != null) {
        data = await widget.loadConfiguration!();
      } else {
        final db = FirebaseFirestore.instance;
        final draft = await db
            .collection(FirestoreCollections.homePages)
            .doc('draft')
            .get();
        final published = await db
            .collection(FirestoreCollections.homePages)
            .doc('published')
            .get();
        data = mergeHomePageData(
          published.data() ?? const <String, dynamic>{},
          draft.data() ?? const <String, dynamic>{},
        );
      }
      if (!mounted) return;
      final page = HomePageConfig.fromMap(data);
      title.text = page.heroTitle;
      search.text = page.searchPlaceholder;
      slogan.text = page.slogan;
      greeting.text = page.greeting;
      location.text = page.location;
      logoSelection = page.logoUrl.isEmpty
          ? const MediaSelection.empty()
          : MediaSelection.existing(page.logoUrl);
      backgroundType = page.backgroundType;
      backgroundImageUrl.text = page.backgroundImageUrl;
      backgroundStart.text = page.backgroundStart;
      backgroundEnd.text = page.backgroundEnd;
      order = [
        ...page.order.where(defaultHomeOrder.contains),
        ...defaultHomeOrder.where((key) => !page.order.contains(key)),
      ];
      categoryOrder = page
          .primaryCategories(homeCatalog, includeHidden: true)
          .map((item) => item.name)
          .toList();
      for (final category in page.categories(homeCatalog)) {
        categoryIcons[category.name] =
            category.iconKey ?? AppIcon.fromLegacyIndex(category.artwork).key;
        categoryLabels[category.name]!.text = page.categoryLabelFor(category);
        categoryImages[category.name]!.text = page.categoryImageUrlFor(
          category,
        );
        categoryVisible[category.name] = page.categoryVisibleFor(category);
      }
      for (final key in defaultHomeOrder) {
        enabled[key] = page.enabled(key);
        sectionTitles[key]!.text = page.titleFor(key);
        sectionLimits[key]!.text = page.limitFor(key).toString();
        sectionDescriptions[key]!.text = page.descriptionFor(key);
        sectionImages[key]!.text = page.imageUrlFor(key);
        sectionIcons[key] = page.iconFor(key);
      }
      loaded = true;
    } catch (_) {
      loadFailed = true;
    }
    if (mounted) setState(() => loading = false);
  }

  Map<String, dynamic> _data() => {
    'heroTitle': title.text.trim(),
    'searchPlaceholder': search.text.trim(),
    'sections': enabled,
    'sectionOrder': order,
    'categoryOrder': categoryOrder,
    'categoryIcons': Map<String, String>.from(categoryIcons),
    'categoryLabels': {
      for (final category in homeCatalog)
        category.name: categoryLabels[category.name]!.text.trim(),
    },
    'categoryImages': {
      for (final category in homeCatalog)
        category.name: categoryImages[category.name]!.text.trim(),
    },
    'categoryVisible': Map<String, bool>.from(categoryVisible),
    'sectionTitles': {
      for (final key in defaultHomeOrder) key: sectionTitles[key]!.text.trim(),
    },
    'sectionDescriptions': {
      for (final key in defaultHomeOrder)
        key: sectionDescriptions[key]!.text.trim(),
    },
    'sectionImages': {
      for (final key in defaultHomeOrder) key: sectionImages[key]!.text.trim(),
    },
    'sectionIcons': {
      for (final key in defaultHomeOrder)
        if (sectionIcons[key] != null) key: sectionIcons[key],
    },
    'sectionLimits': {
      for (final key in defaultHomeOrder)
        key: (int.tryParse(sectionLimits[key]!.text) ?? 2).clamp(1, 12),
    },
    'visual': {
      'slogan': slogan.text.trim(),
      'greeting': greeting.text.trim(),
      'location': location.text.trim(),
      'logoUrl': logoSelection.requireRemoteUrl(),
      'backgroundType': backgroundType,
      'backgroundStart': backgroundStart.text.trim(),
      'backgroundEnd': backgroundEnd.text.trim(),
      'backgroundImageUrl': backgroundImageUrl.text.trim(),
    },
    'updatedAt': FieldValue.serverTimestamp(),
  };

  Future<void> save(bool publish) async {
    if (!loaded || loading || saving) return;
    if (logoSelection.isLocal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aguarde o envio ou envie a imagem selecionada antes de salvar ou publicar. O preview foi mantido.',
          ),
        ),
      );
      return;
    }
    setState(() => saving = true);
    try {
      final data = _data();
      if (widget.saveConfiguration != null) {
        await widget.saveConfiguration!(data, publish);
      } else if (BetaEnvironment.enabled) {
        await SparkAdminContentRepository(
          FirebaseFirestore.instance,
        ).saveHomePage(data, publish: publish);
      } else {
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
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível salvar: ${error.code}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível salvar as alterações. Tente novamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> cancelChanges() async {
    if (!loaded || loading || saving) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar edição?'),
        content: const Text(
          'As alterações ainda não salvas serão descartadas. O rascunho que já está salvo será mantido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar editando'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar edição'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    await load();
    if (mounted && loaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Alterações não salvas descartadas. Rascunho preservado.',
          ),
        ),
      );
    }
  }

  Future<void> discard() async {
    if (!loaded || loading || saving) return;
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

  void _reorderCategory(int oldIndex, int newIndex) {
    setState(() {
      final item = categoryOrder.removeAt(oldIndex);
      categoryOrder.insert(newIndex, item);
    });
  }

  Future<void> _pickCategoryIcon(BuildContext context, String category) async {
    var selected =
        categoryIcons[category] ?? AppIcon.fromCategory(category).key;
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
                  NamedVisualIconPicker(
                    value: selected,
                    onChanged: (value) => setSheetState(() => selected = value),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () {
                      setState(() => categoryIcons[category] = selected);
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

  Future<void> _pickSectionIcon(BuildContext context, String section) async {
    var selected =
        sectionIcons[section] ?? AppIcon.fromCategory(section).legacyIndex;
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
                    'Ícone da seção ${_name(section)}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('O ícone aparece ao lado do título da seção.'),
                  const SizedBox(height: 16),
                  VisualIconPicker(
                    value: selected,
                    onChanged: (value) => setSheetState(() => selected = value),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () {
                      setState(() => sectionIcons[section] = selected);
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
        ? const Center(
            child: CircularProgressIndicator(
              semanticsLabel: 'Carregando configuração da Home',
            ),
          )
        : !loaded
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    loadFailed
                        ? 'Não foi possível carregar a configuração da Home.'
                        : 'A configuração da Home ainda não foi carregada.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          )
        : ListView(
            key: const ValueKey('home-editor-scroll'),
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
              SingleImageSelector(
                label: 'Logo da Home',
                value: logoSelection,
                source: widget.imageSource,
                uploadService: BetaEnvironment.enabled
                    ? null
                    : _imageUploadService,
                allowDeviceSelection: !BetaEnvironment.enabled,
                enabled: !saving,
                onChanged: (value) => setState(() => logoSelection = value),
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
                    CloudinaryUploadHelper(
                      controller: backgroundImageUrl,
                      enabled: !saving,
                      onChanged: () => setState(() {}),
                      description:
                          'Selecione e envie uma imagem do dispositivo ou use uma URL existente para o fundo.',
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
                'Arraste pelo ícone para reorganizar. Abra “Personalizar aparência” para editar descrição, imagem e ícone.',
                style: TextStyle(color: muted),
              ),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: order.length,
                onReorderItem: (oldIndex, newIndex) => setState(() {
                  final item = order.removeAt(oldIndex);
                  order.insert(newIndex, item);
                }),
                itemBuilder: (context, index) {
                  final key = order[index];
                  return Card(
                    key: ValueKey('home-editor-section-$key'),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 6, 10),
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: enabled[key] ?? true,
                            onChanged: saving
                                ? null
                                : (value) =>
                                      setState(() => enabled[key] = value),
                            secondary: Semantics(
                              label: 'Arrastar ${_name(key)}',
                              child: ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle_rounded),
                              ),
                            ),
                            title: Text(
                              _name(key),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              enabled[key] == false
                                  ? 'Não aparece na Home publicada'
                                  : 'Aparece na posição ${index + 1}',
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: sectionTitles[key],
                                  enabled: !saving,
                                  decoration: _field('Título da seção'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 80,
                                child: TextField(
                                  controller: sectionLimits[key],
                                  enabled: !saving,
                                  keyboardType: TextInputType.number,
                                  decoration: _field('Itens'),
                                ),
                              ),
                            ],
                          ),
                          ExpansionTile(
                            key: ValueKey('home-section-appearance-$key'),
                            leading: const Icon(Icons.tune_rounded),
                            title: const Text('Personalizar aparência'),
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextField(
                                      key: ValueKey(
                                        'home-section-description-$key',
                                      ),
                                      controller: sectionDescriptions[key],
                                      enabled: !saving,
                                      maxLines: 2,
                                      onChanged: (_) => setState(() {}),
                                      decoration: _field(
                                        'Descrição da seção',
                                        helper: 'Opcional',
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      key: ValueKey('home-section-image-$key'),
                                      controller: sectionImages[key],
                                      enabled: !saving,
                                      keyboardType: TextInputType.url,
                                      onChanged: (_) => setState(() {}),
                                      decoration: _field(
                                        'Imagem da seção (URL Cloudinary)',
                                        helper: 'Opcional',
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    CloudinaryUploadHelper(
                                      controller: sectionImages[key],
                                      enabled: !saving,
                                      onChanged: () => setState(() {}),
                                      description:
                                          'Envie uma imagem do dispositivo ou use uma URL existente.',
                                    ),
                                    if (sectionImages[key]!.text
                                        .trim()
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      HomeImagePreview(
                                        url: sectionImages[key]!.text.trim(),
                                        onRemove: () =>
                                            setState(sectionImages[key]!.clear),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 8,
                                      children: [
                                        if (sectionIcons[key] != null)
                                          App3DIcon(
                                            icon: AppIcon.fromLegacyIndex(
                                              sectionIcons[key]!,
                                            ),
                                            size: 38,
                                          )
                                        else
                                          const Icon(
                                            Icons.widgets_outlined,
                                            size: 32,
                                          ),
                                        OutlinedButton.icon(
                                          onPressed: saving
                                              ? null
                                              : () => _pickSectionIcon(
                                                  context,
                                                  key,
                                                ),
                                          icon: const Icon(
                                            Icons.palette_outlined,
                                          ),
                                          label: Text(
                                            sectionIcons[key] == null
                                                ? 'Escolher ícone'
                                                : AppIcon.fromLegacyIndex(
                                                    sectionIcons[key]!,
                                                  ).label,
                                          ),
                                        ),
                                        if (sectionIcons[key] != null)
                                          TextButton(
                                            onPressed: saving
                                                ? null
                                                : () => setState(
                                                    () => sectionIcons[key] =
                                                        null,
                                                  ),
                                            child: const Text('Remover ícone'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 22),
              const Text(
                'Ordem das categorias',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              const Text(
                'Arraste para ordenar. O nome muda só na tela; o destino da categoria é preservado.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 8),
              ReorderableListView.builder(
                key: const ValueKey('home-category-shortcut-order'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorderItem: _reorderCategory,
                itemCount: categoryOrder.length,
                itemBuilder: (context, index) {
                  final category = categoryOrder[index];
                  final icon = AppIcon.fromKey(categoryIcons[category]);
                  final image = categoryImages[category]!;
                  return Card(
                    key: ValueKey('home-category-shortcut-$category'),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.drag_handle_rounded),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  category,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Switch(
                                key: ValueKey(
                                  'home-category-visible-$category',
                                ),
                                value: categoryVisible[category] ?? true,
                                onChanged: (value) => setState(
                                  () => categoryVisible[category] = value,
                                ),
                              ),
                            ],
                          ),
                          TextField(
                            key: ValueKey('home-category-label-$category'),
                            controller: categoryLabels[category],
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Nome exibido',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            key: ValueKey('home-category-image-$category'),
                            controller: image,
                            keyboardType: TextInputType.url,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Imagem do atalho (URL)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 6),
                          CloudinaryUploadHelper(
                            controller: image,
                            onChanged: () => setState(() {}),
                            description:
                                'Envie uma imagem ou informe uma URL pública.',
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: image.text.trim().isEmpty
                                ? App3DIcon(icon: icon, size: 42)
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.network(
                                      image.text.trim(),
                                      width: 42,
                                      height: 42,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          App3DIcon(icon: icon, size: 42),
                                    ),
                                  ),
                            title: Text(icon.label),
                            trailing: TextButton.icon(
                              onPressed: () =>
                                  _pickCategoryIcon(context, category),
                              icon: const Icon(Icons.palette_outlined),
                              label: const Text('Ícone'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
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
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final category in categoryOrder)
                            if (categoryVisible[category] ?? true)
                              Chip(
                                avatar: App3DIcon(
                                  icon: AppIcon.fromKey(
                                    categoryIcons[category],
                                  ),
                                  size: 26,
                                ),
                                label: Text(
                                  categoryLabels[category]!.text.trim().isEmpty
                                      ? category
                                      : categoryLabels[category]!.text.trim(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                        ],
                      ),
                      const Divider(height: 24),
                      ...order.where((key) => enabled[key] != false).map((key) {
                        final imageUrl = sectionImages[key]!.text.trim();
                        final iconIndex = sectionIcons[key];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: SizedBox(
                            width: 48,
                            height: 48,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: imageUrl.isNotEmpty
                                  ? Image.network(
                                      imageUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Icon(
                                        Icons.widgets_outlined,
                                        color: ocean,
                                      ),
                                    )
                                  : iconIndex == null
                                  ? const Icon(
                                      Icons.widgets_outlined,
                                      color: ocean,
                                    )
                                  : App3DIcon(
                                      icon: AppIcon.fromLegacyIndex(iconIndex),
                                      size: 38,
                                    ),
                            ),
                          ),
                          title: Text(
                            sectionTitles[key]!.text.trim().isEmpty
                                ? _name(key)
                                : sectionTitles[key]!.text.trim(),
                          ),
                          subtitle: Text(
                            sectionDescriptions[key]!.text.trim().isEmpty
                                ? 'Descrição da seção'
                                : sectionDescriptions[key]!.text.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
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
              TextButton.icon(
                onPressed: saving ? null : cancelChanges,
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Cancelar alterações não salvas'),
              ),
              TextButton(
                onPressed: saving ? null : discard,
                child: const Text('Apagar rascunho salvo'),
              ),
            ],
          ),
  );
}

enum _EstablishmentStatusFilter { all, published, drafts, inactive }

class ContentManager extends StatefulWidget {
  const ContentManager({
    super.key,
    required this.collection,
    required this.title,
    this.itemsStreamFactory,
    this.jobRepository,
  });
  final String collection, title;
  final AdminJobRepository? jobRepository;
  final Stream<QuerySnapshot<Map<String, dynamic>>> Function()?
  itemsStreamFactory;

  @override
  State<ContentManager> createState() => _ContentManagerState();
}

class _ContentManagerState extends State<ContentManager> {
  final _search = TextEditingController();
  _EstablishmentStatusFilter _establishmentFilter =
      _EstablishmentStatusFilter.all;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _itemsStream;
  AdminJobRepository? _jobs;
  final _jobItems = <AdminJobSummary>[];
  bool _jobsLoading = false;
  bool _jobsLoaded = false;
  Object? _jobsError;
  String? _nextJobCursor;
  int _jobsGeneration = 0;
  bool get _isJobsManager => widget.collection == 'jobs';
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _lastDocuments;
  int _streamGeneration = 0;

  bool get _isBusinessManager => widget.collection == 'establishments';
  bool get _isRoutesManager => widget.collection == 'routes';
  bool get _isEventsManager => widget.collection == 'events';
  bool get _isAdsManager => widget.collection == 'ads';
  int? _adCount;
  bool _savingRouteOrder = false;

  void _syncAdCount(int count) {
    if (!_isAdsManager || _adCount == count) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _adCount != count) setState(() => _adCount = count);
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _createItemsStream() {
    final injected = widget.itemsStreamFactory;
    if (injected != null) return injected();
    final collection = FirebaseFirestore.instance.collection(widget.collection);
    // Legacy route documents may not have updatedAt/order. Keep them in the
    // Admin list; ordering is applied deterministically after the snapshot.
    return (_isRoutesManager || _isAdsManager
            ? collection
            : collection.orderBy('updatedAt', descending: true))
        .snapshots();
  }

  @override
  void initState() {
    super.initState();
    _initializeItems();
  }

  void _initializeItems() {
    _jobsGeneration++;
    _jobsLoading = false;
    _jobsLoaded = false;
    _jobsError = null;
    _jobItems.clear();
    _nextJobCursor = null;
    if (_isJobsManager) {
      _itemsStream = null;
      _jobs =
          widget.jobRepository ??
          createAdminJobRepository(sparkBeta: BetaEnvironment.enabled);
      unawaited(_loadJobs());
    } else {
      _jobs = null;
      _itemsStream = _createItemsStream();
    }
  }

  @override
  void didUpdateWidget(covariant ContentManager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collection != widget.collection ||
        (_isJobsManager
            ? oldWidget.jobRepository != widget.jobRepository
            : oldWidget.itemsStreamFactory != widget.itemsStreamFactory)) {
      _initializeItems();
      _lastDocuments = null;
      _streamGeneration++;
    }
  }

  Future<void> _loadJobs({bool reset = false}) async {
    if (!_isJobsManager || (_jobsLoading && !reset)) return;
    final generation = reset ? ++_jobsGeneration : _jobsGeneration;
    final cursor = reset ? null : _nextJobCursor;
    setState(() {
      _jobsLoading = true;
      _jobsError = null;
      if (reset) {
        _jobItems.clear();
        _nextJobCursor = null;
        _jobsLoaded = false;
      }
    });
    try {
      final page = await _jobs!.list(cursor: cursor);
      if (!mounted || generation != _jobsGeneration) return;
      setState(() {
        final ids = _jobItems.map((item) => item.id).toSet();
        _jobItems.addAll(page.items.where((item) => ids.add(item.id)));
        _nextJobCursor = page.nextCursor;
        _jobsLoaded = true;
      });
    } catch (error) {
      if (!mounted || generation != _jobsGeneration) return;
      setState(() => _jobsError = error);
    } finally {
      if (mounted && generation == _jobsGeneration) {
        setState(() => _jobsLoading = false);
      }
    }
  }

  Future<void> _openJobEditor([AdminJobSummary? job]) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ContentEditor(
          collection: 'jobs',
          jobId: job?.id,
          jobSummary: job,
          jobRepository: _jobs,
        ),
      ),
    );
    if (mounted && _isJobsManager) await _loadJobs(reset: true);
  }

  Widget _jobsList() {
    if (!_jobsLoaded) {
      return _managerStatus(
        _jobsError != null
            ? 'Não foi possível carregar os itens.'
            : 'Carregando itens…',
        retry: _jobsError != null,
      );
    }
    if (_jobItems.isEmpty) {
      return const Center(
        child: Text('Ainda não há itens. Use Adicionar para publicar.'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount:
          _jobItems.length +
          ((_nextJobCursor != null || _jobsLoading || _jobsError != null)
              ? 1
              : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        if (index == _jobItems.length) {
          if (_jobsError != null) {
            return _managerStatus(
              'Não foi possível atualizar os itens.',
              retry: true,
            );
          }
          if (_jobsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return TextButton(
            onPressed: () => _loadJobs(),
            child: const Text('Carregar mais'),
          );
        }
        final item = _jobItems[index];
        return ListTile(
          key: ValueKey(item.id),
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            item.title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(item.published ? 'Publicado' : 'Rascunho'),
          trailing: const Icon(Icons.edit_rounded),
          onTap: () => _openJobEditor(item),
        );
      },
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _retry() {
    if (_isJobsManager) {
      unawaited(_loadJobs());
      return;
    }
    setState(() {
      _itemsStream = _createItemsStream();
      _streamGeneration++;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    floatingActionButton: FloatingActionButton.extended(
      key: _isAdsManager ? const ValueKey('add-advertisement') : null,
      onPressed:
          _isAdsManager && (_adCount == null || _adCount! >= AdCarousel.maxAds)
          ? null
          : _isJobsManager
          ? () => _openJobEditor()
          : () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ContentEditor(collection: widget.collection),
              ),
            ),
      icon: const Icon(Icons.add_rounded),
      label: Text(
        _isAdsManager
            ? _adCount == null
                  ? 'Carregando anúncios…'
                  : _adCount! >= AdCarousel.maxAds
                  ? 'Limite atingido (10/10)'
                  : 'Adicionar anúncio ($_adCount/10)'
            : 'Adicionar',
      ),
    ),
    body: Column(
      children: [
        if (_isAdsManager)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _adCount == null
                    ? 'Carregando limite de anúncios…'
                    : '$_adCount de ${AdCarousel.maxAds} anúncios · toque em um item para editar. Ao tocar na imagem, a página HTTPS configurada abre diretamente.',
                key: const ValueKey('advertisement-capacity'),
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            ),
          ),
        if (_isBusinessManager || _isRoutesManager || _isEventsManager)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              key: ValueKey(
                _isRoutesManager
                    ? 'tourism-admin-search'
                    : _isEventsManager
                    ? 'events-admin-search'
                    : 'establishment-admin-search',
              ),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _isRoutesManager
                    ? 'Buscar em Explorar Macacu'
                    : _isEventsManager
                    ? 'Buscar eventos'
                    : 'Buscar estabelecimentos',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar busca',
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        if (_isBusinessManager || _isRoutesManager || _isEventsManager)
          _contentFilters(),
        Expanded(
          child: _isJobsManager
              ? _jobsList()
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  key: ValueKey(_streamGeneration),
                  stream: _itemsStream,
                  builder: (context, snap) {
                    if (snap.hasData) {
                      _lastDocuments = snap.data!.docs.toList();
                      _syncAdCount(_lastDocuments!.length);
                    }
                    final docs = snap.data?.docs.toList() ?? _lastDocuments;
                    if (docs == null && snap.hasError) {
                      return _managerStatus(
                        'Não foi possível carregar os itens.',
                        retry: true,
                      );
                    }
                    if (docs == null) {
                      return _managerStatus('Carregando itens…');
                    }
                    if (_isRoutesManager || _isEventsManager) {
                      docs.sort(_compareTourismDocuments);
                    } else if (widget.collection == 'ads') {
                      docs.sort((a, b) => compareAdOrder(a.data(), b.data()));
                    }
                    final query = _search.text.trim();
                    final visibleDocs = _filterContent(docs);
                    if (snap.hasError) {
                      return Column(
                        children: [
                          _managerStatus(
                            'Não foi possível atualizar os itens.',
                            retry: true,
                          ),
                          Expanded(
                            child: visibleDocs.isEmpty
                                ? Center(child: Text(_emptyItemsMessage(query)))
                                : _managerList(visibleDocs),
                          ),
                        ],
                      );
                    }
                    if (visibleDocs.isEmpty) {
                      return Center(child: Text(_emptyItemsMessage(query)));
                    }
                    return _managerList(visibleDocs);
                  },
                ),
        ),
      ],
    ),
  );

  Widget _managerStatus(String text, {bool retry = false}) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!retry) const CircularProgressIndicator(),
        if (!retry) const SizedBox(height: 10),
        Text(text),
        if (retry)
          TextButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
          ),
      ],
    ),
  );

  int _compareTourismDocuments(
    QueryDocumentSnapshot<Map<String, dynamic>> first,
    QueryDocumentSnapshot<Map<String, dynamic>> second,
  ) {
    final firstData = first.data();
    final secondData = second.data();
    final order = ((firstData['order'] as num?)?.toInt() ?? 0).compareTo(
      (secondData['order'] as num?)?.toInt() ?? 0,
    );
    if (order != 0) return order;
    final title = (firstData['title'] ?? firstData['name'] ?? '')
        .toString()
        .toLowerCase()
        .compareTo(
          (secondData['title'] ?? secondData['name'] ?? '')
              .toString()
              .toLowerCase(),
        );
    return title == 0 ? first.id.compareTo(second.id) : title;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterContent(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
  ) {
    if (!_isBusinessManager && !_isRoutesManager && !_isEventsManager) {
      return documents;
    }
    final query = _search.text.trim().toLowerCase();
    return documents.where((document) {
      final data = document.data();
      final matchesStatus = switch (_establishmentFilter) {
        _EstablishmentStatusFilter.all => true,
        _EstablishmentStatusFilter.published =>
          data['published'] != false && data['deleted'] != true,
        _EstablishmentStatusFilter.drafts =>
          data['published'] == false && data['deleted'] != true,
        _EstablishmentStatusFilter.inactive =>
          data['active'] == false || data['deleted'] == true,
      };
      if (!matchesStatus) return false;
      if (query.isEmpty) return true;
      return [
        data['name'],
        data['title'],
        data['category'],
        data['subcategory'],
        data['type'],
        data['location'],
        data['address'],
        data['description'],
      ].any((value) => value.toString().toLowerCase().contains(query));
    }).toList();
  }

  String _emptyItemsMessage(String query) {
    if (query.isNotEmpty) {
      return _isRoutesManager
          ? 'Nenhum conteúdo corresponde à busca.'
          : _isEventsManager
          ? 'Nenhum evento corresponde à busca.'
          : 'Nenhum estabelecimento corresponde à busca.';
    }
    if ((_isBusinessManager || _isRoutesManager || _isEventsManager) &&
        _establishmentFilter != _EstablishmentStatusFilter.all) {
      return _isRoutesManager
          ? 'Nenhum conteúdo nesse status.'
          : _isEventsManager
          ? 'Nenhum evento nesse status.'
          : 'Nenhum estabelecimento nesse status.';
    }
    return 'Ainda não há itens. Use Adicionar para publicar.';
  }

  Widget _contentFilters() {
    const filters = [
      (_EstablishmentStatusFilter.all, 'Todos', 'all'),
      (_EstablishmentStatusFilter.published, 'Publicados', 'published'),
      (_EstablishmentStatusFilter.drafts, 'Rascunhos', 'drafts'),
      (_EstablishmentStatusFilter.inactive, 'Inativos', 'inactive'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final (filter, label, key) in filters)
            ChoiceChip(
              key: ValueKey(
                '${_isRoutesManager
                    ? 'tourism'
                    : _isEventsManager
                    ? 'events'
                    : 'establishment'}-filter-$key',
              ),
              label: Text(label),
              selected: _establishmentFilter == filter,
              onSelected: (selected) {
                if (selected) setState(() => _establishmentFilter = filter);
              },
            ),
        ],
      ),
    );
  }

  void _openItemEditor(QueryDocumentSnapshot<Map<String, dynamic>> document) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            ContentEditor(collection: widget.collection, doc: document),
      ),
    );
  }

  Widget _managerList(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final ordered = [...docs];
    if (_isRoutesManager || _isEventsManager) {
      ordered.sort(_compareTourismDocuments);
    }
    final orderIsUnfiltered =
        _search.text.trim().isEmpty &&
        _establishmentFilter == _EstablishmentStatusFilter.all;
    if ((_isRoutesManager || _isEventsManager) && orderIsUnfiltered) {
      return ReorderableListView.builder(
        key: ValueKey(
          _isRoutesManager
              ? 'tourism-admin-reorder-list'
              : 'events-admin-reorder-list',
        ),
        padding: const EdgeInsets.all(16),
        itemCount: ordered.length,
        onReorderItem: _savingRouteOrder
            ? (_, _) {}
            : (oldIndex, newIndex) =>
                  _persistContentOrder(ordered, oldIndex, newIndex),
        itemBuilder: (context, index) {
          final document = ordered[index];
          return Card(
            key: ValueKey(
              '${_isEventsManager ? 'events' : 'tourism'}-admin-${document.id}',
            ),
            margin: const EdgeInsets.only(bottom: 8),
            child: _managerTile(document, index: index),
          );
        },
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, index) => _managerTile(docs[index]),
    );
  }

  Widget _managerTile(
    QueryDocumentSnapshot<Map<String, dynamic>> document, {
    int? index,
  }) {
    final data = document.data();
    final status = data['deleted'] == true
        ? 'Removido logicamente'
        : data['published'] == false
        ? 'Rascunho'
        : 'Publicado';
    final active = data['active'] != false;
    final subtitle = _isRoutesManager || _isBusinessManager || _isEventsManager
        ? '$status · ${active ? 'Ativo' : 'Inativo'}${_isRoutesManager || _isEventsManager ? ' · ordem ${(data['order'] as num?)?.toInt() ?? 0}' : ''}'
        : status;
    final name = (data['title'] ?? data['name'] ?? 'Sem título').toString();
    final (statusIcon, statusColor) = data['deleted'] == true
        ? (Icons.delete_outline_rounded, AppColors.muted)
        : data['published'] == false
        ? (Icons.edit_note_rounded, AppColors.orange)
        : (Icons.public_rounded, const Color(0xFF188038));
    return ListTile(
      tileColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(color: AppColors.ocean.withValues(alpha: .08)),
      ),
      leading: Tooltip(
        message: status,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          child: Icon(statusIcon, color: statusColor, size: 21),
        ),
      ),
      title: Text(
        name,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.muted, height: 1.35),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Editar $name',
            onPressed: () => _openItemEditor(document),
            icon: const Icon(Icons.edit_rounded),
          ),
          if (index != null)
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.drag_handle_rounded),
              ),
            ),
        ],
      ),
      onTap: () => _openItemEditor(document),
    );
  }

  Future<void> _persistContentOrder(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
    int oldIndex,
    int newIndex,
  ) async {
    if ((!_isRoutesManager && !_isEventsManager) || _savingRouteOrder) return;
    if (!isAdminUser(FirebaseAuth.instance.currentUser, context: context)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acesso administrativo necessário.')),
      );
      return;
    }
    final reordered = [...documents];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    final updates = <(QueryDocumentSnapshot<Map<String, dynamic>>, int)>[];
    for (var index = 0; index < reordered.length; index++) {
      final document = reordered[index];
      if ((document.data()['order'] as num?)?.toInt() != index) {
        updates.add((document, index));
      }
    }
    if (updates.isEmpty) return;
    if (updates.length > 450) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reordene um grupo menor de conteúdos por vez.'),
        ),
      );
      return;
    }
    setState(() => _savingRouteOrder = true);
    try {
      if (BetaEnvironment.enabled) {
        await SparkAdminContentRepository(
          FirebaseFirestore.instance,
        ).reorderContent(widget.collection, [
          for (final (document, order) in updates)
            (id: document.id, order: order),
        ]);
      } else {
        final batch = FirebaseFirestore.instance.batch();
        for (final (document, order) in updates) {
          batch.update(document.reference, {
            'order': order,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
      await recordAdminAudit(
        action: 'reorder',
        collection: widget.collection,
        documentId: moved.id,
        label: 'Conteúdo turístico reordenado',
      );
    } on FirebaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível salvar a ordem. Tente novamente.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingRouteOrder = false);
    }
  }
}

class ContentEditor extends StatefulWidget {
  const ContentEditor({
    super.key,
    required this.collection,
    this.doc,
    this.initialDocumentData,
    this.initialDocumentId,
    this.jobRepository,
    this.jobId,
    this.jobSummary,
    this.sparkContentOperations,
    this.auditRecorder,
  });
  final String collection;
  final DocumentSnapshot<Map<String, dynamic>>? doc;
  final Map<String, dynamic>? initialDocumentData;
  final String? initialDocumentId;
  final AdminJobRepository? jobRepository;
  final String? jobId;
  final AdminJobSummary? jobSummary;
  final SparkAdminContentOperations? sparkContentOperations;
  final AdminAuditRecorder? auditRecorder;
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
  late final TextEditingController videoUrls;
  late final TextEditingController eventDate;
  late final TextEditingController eventEndDate;
  late final TextEditingController eventStartTime;
  late final TextEditingController eventEndTime;
  late final TextEditingController eventOrganizer;
  late final TextEditingController eventRegistrationUrl;
  late final TextEditingController eventContactUrl;
  late final TextEditingController contact;
  late final TextEditingController hours;
  late final TextEditingController services;
  late final TextEditingController products;
  late final TextEditingController additionalInfo;
  late final TextEditingController promotionTitle;
  late final TextEditingController promotionDescription;
  late final TextEditingController bannerOrder;
  bool bannerActive = true;
  bool businessActive = true;
  bool tourismActive = true;
  bool eventActive = true;
  late String tourismIconKey;
  bool publicContactApproved = false;
  bool featured = false;
  bool published = true;
  bool saving = false;
  late final AdminJobRepository? _jobRepository;
  String? _reservedJobId;
  final _hybridRequestReservation = HybridAdminRequestReservation();
  Map<String, dynamic>? get _businessDocumentData =>
      widget.doc?.data() ?? widget.initialDocumentData;
  String? get _businessDocumentId => widget.doc?.id ?? widget.initialDocumentId;
  Map<String, String> _initialJobPrivate = {};
  String _initialJobMaps = '';
  bool get _isEditing => isJobContent
      ? widget.jobId != null
      : widget.doc != null || widget.initialDocumentId != null;
  bool _privateJobLoading = false;
  bool _privateJobLoaded = false;
  bool _legacyJobWithoutPrivate = false;
  Object? _privateJobLoadError;
  final galleryItems = <String>[];
  final _businessFormScrollController = ScrollController();
  final _businessStepKeys = List<GlobalKey>.generate(4, (_) => GlobalKey());
  final _businessValidationErrors = <String, String>{};
  int _selectedBusinessStep = 0;
  late final Map<String, String> _initialBusinessUrls;
  late final Set<String> _initialBusinessMediaUrls;
  bool get isBusinessContent => widget.collection == 'establishments';
  bool get isJobContent => widget.collection == 'jobs';
  SparkAdminContentOperations get _sparkContentOperations =>
      widget.sparkContentOperations ??
      SparkAdminContentRepository(FirebaseFirestore.instance);
  AdminAuditRecorder get _auditRecorder =>
      widget.auditRecorder ?? recordAdminAudit;
  bool get isEventContent => widget.collection == 'events';
  bool get _jobSaveReady =>
      !isJobContent ||
      !_isEditing ||
      (_privateJobLoaded && !_privateJobLoading && !_legacyJobWithoutPrivate);
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
    final d = isJobContent
        ? <String, dynamic>{
            if (widget.jobSummary != null) 'title': widget.jobSummary!.title,
          }
        : _businessDocumentData ?? {};
    _initialBusinessUrls = {
      'link': (d['link'] ?? d['url'] ?? '').toString().trim(),
      'maps': (d['maps'] ?? d['mapsUrl'] ?? '').toString().trim(),
      'phone': (d['phone'] ?? '').toString().trim(),
      'whatsapp': (d['whatsapp'] ?? '').toString().trim(),
      'instagram': (d['instagram'] ?? '').toString().trim(),
    };
    _initialBusinessMediaUrls = {
      for (final key in ['imageUrl', 'logoUrl'])
        cloudinaryOptimizedImageUrl((d[key] ?? '').toString()),
      ...((d['galleryUrls'] as List?) ?? const []).map(
        (value) => cloudinaryOptimizedImageUrl(value.toString()),
      ),
    };
    _jobRepository = isJobContent
        ? widget.jobRepository ??
              createAdminJobRepository(sparkBeta: BetaEnvironment.enabled)
        : null;
    title = TextEditingController(
      text: (d['title'] ?? d['name'] ?? '').toString(),
    );
    description = TextEditingController(
      text: (d['description'] ?? '').toString(),
    );
    link = TextEditingController(
      text: isJobContent ? '' : (d['link'] ?? d['url'] ?? '').toString(),
    );
    imageUrl = TextEditingController(
      text: cloudinaryOptimizedImageUrl((d['imageUrl'] ?? '').toString()),
    );
    logoUrl = TextEditingController(
      text: cloudinaryOptimizedImageUrl((d['logoUrl'] ?? '').toString()),
    );
    icon = TextEditingController(text: (d['artwork'] ?? '0').toString());
    final storedTourismIcon = (d['iconKey'] ?? '').toString();
    tourismIconKey = AppIcon.all.any((item) => item.key == storedTourismIcon)
        ? storedTourismIcon
        : AppIcon.fromLegacyIndex(int.tryParse(icon.text) ?? 5).key;
    category = TextEditingController(text: (d['category'] ?? '').toString());
    subcategory = TextEditingController(
      text: (d['subcategory'] ?? '').toString(),
    );
    location = TextEditingController(
      text: (d['location'] ?? d['address'] ?? '').toString(),
    );
    whatsapp = TextEditingController(
      text: isJobContent ? '' : (d['whatsapp'] ?? '').toString(),
    );
    phone = TextEditingController(
      text: isJobContent ? '' : (d['phone'] ?? '').toString(),
    );
    instagram = TextEditingController(
      text: isJobContent ? '' : (d['instagram'] ?? '').toString(),
    );
    maps = TextEditingController(
      text: isJobContent ? '' : (d['maps'] ?? d['mapsUrl'] ?? '').toString(),
    );
    galleryUrls = TextEditingController(
      text: ((d['galleryUrls'] as List?) ?? const [])
          .map((item) => cloudinaryOptimizedImageUrl(item.toString()))
          .join('\n'),
    );
    galleryInput = TextEditingController();
    videoUrls = TextEditingController(
      text: ((d['videoUrls'] as List?) ?? const [])
          .map((item) => item.toString())
          .join('\n'),
    );
    final cover = imageUrl.text.trim();
    galleryItems.addAll(
      orderedUniqueImageUrls([
        if (cover.isNotEmpty) cover,
        ...((d['galleryUrls'] as List?) ?? const []).map(
          (item) => item.toString(),
        ),
      ]),
    );
    eventDate = TextEditingController(
      text: isJobContent ? '' : (d['eventDate'] ?? d['date'] ?? '').toString(),
    );
    eventEndDate = TextEditingController(text: (d['endDate'] ?? '').toString());
    eventStartTime = TextEditingController(
      text: (d['startTime'] ?? '').toString(),
    );
    eventEndTime = TextEditingController(text: (d['endTime'] ?? '').toString());
    eventOrganizer = TextEditingController(
      text: (d['organizer'] ?? '').toString(),
    );
    eventRegistrationUrl = TextEditingController(
      text: (d['registrationUrl'] ?? '').toString(),
    );
    eventContactUrl = TextEditingController(
      text: (d['contactUrl'] ?? '').toString(),
    );
    contact = TextEditingController(
      text: isJobContent ? '' : (d['contact'] ?? '').toString(),
    );
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
      text: isJobContent ? '' : (d['additionalInfo'] ?? '').toString(),
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
    published =
        d['published'] as bool? ??
        (!BetaEnvironment.enabled &&
            !(isBusinessContent && !_isEditing) &&
            !(isEventContent && !_isEditing));
    featured = d['featured'] as bool? ?? false;
    bannerOrder = TextEditingController(text: (d['order'] ?? 0).toString());
    bannerActive = d['active'] as bool? ?? true;
    tourismActive = d['active'] as bool? ?? true;
    eventActive = d['active'] as bool? ?? true;
    businessActive = d['active'] as bool? ?? true;
    publicContactApproved = d['publicContactApproved'] == true;
    if (isJobContent && _isEditing) {
      _privateJobLoading = true;
      unawaited(_loadPrivateJobData());
    }
  }

  Future<void> _loadPrivateJobData() async {
    try {
      final record = await _jobRepository!.get(widget.jobId!);
      if (!mounted) return;
      if (record.jobId != widget.jobId) {
        throw AdminJobException('invalid-response');
      }
      final data = record.publicData;
      final privateData = record.privateData;
      setState(() {
        title.text = (data['title'] ?? '').toString();
        description.text = (data['description'] ?? '').toString();
        category.text = (data['category'] ?? '').toString();
        location.text = (data['location'] ?? data['address'] ?? '').toString();
        icon.text = (data['artwork'] ?? 0).toString();
        imageUrl.text = cloudinaryOptimizedImageUrl(
          (data['imageUrl'] ?? '').toString(),
        );
        galleryItems
          ..clear()
          ..addAll(
            (data['galleryUrls'] as List? ?? const <String>[])
                .map((item) => cloudinaryOptimizedImageUrl(item.toString()))
                .where((item) => item.isNotEmpty),
          );
        if (imageUrl.text.isNotEmpty && !galleryItems.contains(imageUrl.text)) {
          galleryItems.insert(0, imageUrl.text);
        }
        galleryUrls.text = galleryItems.join('\n');
        final expiry = DateTime.tryParse(
          (data['expiresAt'] ?? '').toString(),
        )?.toLocal();
        expires.text = expiry == null
            ? ''
            : '${expiry.year}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')}';
        published = data['published'] as bool? ?? true;
        contact.text = (privateData['contact'] ?? '').toString();
        phone.text = (privateData['phone'] ?? '').toString();
        whatsapp.text = (privateData['whatsapp'] ?? '').toString();
        link.text = (privateData['link'] ?? '').toString();
        instagram.text = (privateData['instagram'] ?? '').toString();
        final privateMaps = (privateData['maps'] ?? '').toString();
        maps.text = privateMaps.isNotEmpty
            ? privateMaps
            : (privateData['mapsUrl'] ?? '').toString();
        additionalInfo.text = (privateData['additionalInfo'] ?? '').toString();
        _initialJobPrivate = _jobPrivateValues();
        _initialJobMaps = maps.text.trim();
        _privateJobLoading = false;
        _privateJobLoaded = true;
        _legacyJobWithoutPrivate = false;
        _privateJobLoadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _privateJobLoading = false;
        _privateJobLoaded = false;
        _legacyJobWithoutPrivate =
            error is AdminJobException && error.code == 'failed-precondition';
        _privateJobLoadError = _legacyJobWithoutPrivate ? null : error;
      });
    }
  }

  Map<String, String> _jobPrivateValues() => {
    'contact': contact.text.trim(),
    'phone': phone.text.trim(),
    'whatsapp': whatsapp.text.trim(),
    'link': link.text.trim(),
    'instagram': instagram.text.trim(),
    'maps': maps.text.trim(),
    'mapsUrl': maps.text.trim(),
    'additionalInfo': additionalInfo.text.trim(),
  };

  Map<String, dynamic> _jobPrivatePatch() {
    final values = _jobPrivateValues();
    if (!_isEditing) return values;
    return {
      for (final entry in values.entries)
        if ((entry.key == 'maps' || entry.key == 'mapsUrl')
            ? maps.text.trim() != _initialJobMaps
            : entry.value != _initialJobPrivate[entry.key])
          entry.key: entry.value,
    };
  }

  Future<void> _recordJobAudit({
    required String action,
    required String documentId,
  }) async {
    try {
      await _auditRecorder(
        action: action,
        collection: widget.collection,
        documentId: documentId,
        label: title.text.trim(),
      );
    } catch (error) {
      // The callable has already confirmed the operation. Audit logging is best-effort and
      // must not turn a successful save/delete into a misleading failure.
      debugPrint('Auditoria da vaga não registrada (${error.runtimeType}).');
    }
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
    videoUrls.dispose();
    eventDate.dispose();
    eventEndDate.dispose();
    eventStartTime.dispose();
    eventEndTime.dispose();
    eventOrganizer.dispose();
    eventRegistrationUrl.dispose();
    eventContactUrl.dispose();
    contact.dispose();
    hours.dispose();
    services.dispose();
    products.dispose();
    additionalInfo.dispose();
    promotionTitle.dispose();
    promotionDescription.dispose();
    bannerOrder.dispose();
    _businessFormScrollController.dispose();
    super.dispose();
  }

  Map<String, dynamic> prepareSaveData() {
    final expiry = DateTime.tryParse(expires.text.trim());
    final normalizedGallery = _normalizedGallery();
    final coverImage = supportsMediaGallery
        ? (normalizedGallery.isNotEmpty
              ? normalizedGallery.first
              : cloudinaryOptimizedImageUrl(imageUrl.text.trim()))
        : widget.collection == 'ads'
        ? imageUrl.text.trim()
        : cloudinaryOptimizedImageUrl(imageUrl.text.trim());
    return <String, dynamic>{
      'title': title.text.trim(),
      'description': description.text.trim(),
      if (!isJobContent) 'link': link.text.trim(),
      'imageUrl': coverImage,
      if (widget.collection == 'ads') ...{
        'order': int.tryParse(bannerOrder.text.trim()) ?? 0,
        'active': bannerActive,
      },
      if (widget.collection == 'routes') ...{
        'iconKey': tourismIconKey,
        'order': int.tryParse(bannerOrder.text.trim()) ?? 0,
        'active': tourismActive,
        'deleted': false,
        'deletedAt': FieldValue.delete(),
      },
      if (isEventContent) ...{
        'order': int.tryParse(bannerOrder.text.trim()) ?? 0,
        'active': eventActive,
        'deleted': false,
        'deletedAt': FieldValue.delete(),
        'startTime': eventStartTime.text.trim(),
        'endTime': eventEndTime.text.trim(),
        'endDate': eventEndDate.text.trim(),
        'organizer': eventOrganizer.text.trim(),
        'registrationUrl': eventRegistrationUrl.text.trim(),
        'contactUrl': eventContactUrl.text.trim(),
      },
      if (isBusinessContent) 'active': businessActive,
      if (isBusinessContent) 'publicContactApproved': publicContactApproved,
      if (isBusinessContent) 'iconKey': tourismIconKey,
      'artwork': isBusinessContent
          ? artworkForCategory(
              category.text.trim(),
              fallback: int.tryParse(icon.text.trim()) ?? 0,
            )
          : int.tryParse(icon.text.trim()) ?? 0,
      if (supportsMediaGallery) 'galleryUrls': normalizedGallery,
      if (isBusinessContent) 'videoUrls': _normalizedVideoUrls(),
      if (supportsLocalDetails) ...{
        'category': category.text.trim(),
        'location': location.text.trim(),
        'address': location.text.trim(),
        if (!isJobContent) ...{
          'eventDate': eventDate.text.trim(),
          'date': eventDate.text.trim(),
          'contact': contact.text.trim(),
          'whatsapp': whatsapp.text.trim(),
          'phone': phone.text.trim(),
          'instagram': instagram.text.trim(),
          'maps': maps.text.trim(),
          'additionalInfo': additionalInfo.text.trim(),
        },
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
      if (isJobContent)
        'expiresAt': expiry == null
            ? null
            : DateTime(
                expiry.year,
                expiry.month,
                expiry.day,
                23,
                59,
                59,
              ).toUtc().toIso8601String(),
      if (!isJobContent) 'updatedAt': FieldValue.serverTimestamp(),
      if (!isJobContent &&
          (widget.doc != null || widget.initialDocumentId != null) &&
          expiry == null)
        'expiresAt': FieldValue.delete(),
      if (!isJobContent && expiry != null)
        'expiresAt': Timestamp.fromDate(
          DateTime(expiry.year, expiry.month, expiry.day, 23, 59, 59),
        ),
    };
  }

  bool _businessUrlsAreSafe() {
    bool safeDestination(String key, String raw, {String? normalized}) {
      final value = raw.trim();
      if (value.isEmpty || value == _initialBusinessUrls[key]) return true;
      final candidate = normalized ?? value;
      final uri = Uri.tryParse(candidate);
      return uri != null &&
          isAllowedExternalUri(uri) &&
          (uri.scheme.toLowerCase() != 'https' || _isSafeHttpsUri(uri));
    }

    bool unchanged(String key, String value) =>
        value.trim() == _initialBusinessUrls[key];

    final whatsApp = whatsapp.text.trim();
    final whatsAppUri = whatsApp.startsWith('http')
        ? whatsApp
        : 'https://wa.me/${whatsApp.replaceAll(RegExp(r'\D'), '')}';
    final phoneValue = phone.text.trim();
    final phoneUri = phoneValue.startsWith('tel:')
        ? phoneValue
        : 'tel:$phoneValue';
    final instagramValue = instagram.text.trim();
    final instagramUri = instagramValue.startsWith('http')
        ? instagramValue
        : 'https://instagram.com/${instagramValue.replaceFirst('@', '')}';

    if (!safeDestination('link', link.text)) return false;
    if (!safeDestination('maps', maps.text)) return false;
    if (!safeDestination('whatsapp', whatsApp, normalized: whatsAppUri)) {
      return false;
    }
    if (!safeDestination('phone', phoneValue, normalized: phoneUri)) {
      return false;
    }
    if (!safeDestination(
      'instagram',
      instagramValue,
      normalized: instagramUri,
    )) {
      return false;
    }

    if (whatsApp.isNotEmpty && !unchanged('whatsapp', whatsApp)) {
      if (whatsApp.length > 2048) return false;
      if (whatsApp.startsWith('http')) {
        final uri = Uri.tryParse(whatsApp);
        if (uri == null ||
            !_isSafeHttpsUri(uri) ||
            !{
              'wa.me',
              'www.wa.me',
              'whatsapp.com',
              'www.whatsapp.com',
              'api.whatsapp.com',
            }.contains(uri.host.toLowerCase()) ||
            uri.pathSegments.isEmpty ||
            !RegExp(r'^\d{8,15}$').hasMatch(uri.pathSegments.last)) {
          return false;
        }
      } else {
        final digits = whatsApp.replaceAll(RegExp(r'\D'), '');
        if (!RegExp(r'^[+()\d\s.-]+$').hasMatch(whatsApp) ||
            !RegExp(r'^\d{8,15}$').hasMatch(digits)) {
          return false;
        }
      }
    }

    if (phoneValue.isNotEmpty && !unchanged('phone', phoneValue)) {
      if (phoneValue.length > 64) return false;
      final phoneNumber = phoneValue.startsWith('tel:')
          ? phoneValue.substring(4)
          : phoneValue;
      final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
      if (!RegExp(r'^[+()\d\s.-]+$').hasMatch(phoneNumber) ||
          !RegExp(r'^\d{8,15}$').hasMatch(digits)) {
        return false;
      }
    }

    if (instagramValue.isNotEmpty && !unchanged('instagram', instagramValue)) {
      if (instagramValue.length > 512) return false;
      if (instagramValue.startsWith('http')) {
        final uri = Uri.tryParse(instagramValue);
        if (uri == null ||
            !_isSafeHttpsUri(uri) ||
            !{
              'instagram.com',
              'www.instagram.com',
            }.contains(uri.host.toLowerCase()) ||
            uri.pathSegments.isEmpty ||
            !RegExp(
              r'^[A-Za-z0-9._]{1,30}$',
            ).hasMatch(uri.pathSegments.first)) {
          return false;
        }
      } else if (!RegExp(r'^@?[A-Za-z0-9._]{1,30}$').hasMatch(instagramValue)) {
        return false;
      }
    }

    if (maps.text.trim().isNotEmpty && !unchanged('maps', maps.text)) {
      if (maps.text.trim().length > 2048) return false;
      final uri = Uri.tryParse(maps.text.trim());
      if (uri == null || !_isSafeHttpsUri(uri)) return false;
    }

    final originalVideos =
        ((_businessDocumentData?['videoUrls'] as List?) ?? const [])
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .join('\n');
    final currentVideos = _normalizedVideoUrls();
    if (videoUrls.text.trim() != originalVideos &&
        (currentVideos.length > 5 ||
            currentVideos.any((url) => url.length > 2048) ||
            !currentVideos.every(_isSupportedBusinessVideoUrl))) {
      return false;
    }

    if (link.text.trim().length > 2048 ||
        [
          ..._normalizedGallery(),
          imageUrl.text.trim(),
          logoUrl.text.trim(),
        ].any((value) => value.length > 2048)) {
      return false;
    }

    final newMedia =
        <String>{
          cloudinaryOptimizedImageUrl(imageUrl.text),
          cloudinaryOptimizedImageUrl(logoUrl.text),
          ..._normalizedGallery(),
        }.where(
          (value) =>
              value.isNotEmpty && !_initialBusinessMediaUrls.contains(value),
        );
    return newMedia.every((value) {
      final uri = Uri.tryParse(value);
      return uri != null && _isSafeHttpsUri(uri);
    });
  }

  bool _isSafeHttpsUri(Uri uri) {
    final host = uri.host.toLowerCase();
    return uri.scheme.toLowerCase() == 'https' &&
        host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        host != 'localhost' &&
        !host.endsWith('.localhost') &&
        !host.endsWith('.local') &&
        host != '127.0.0.1' &&
        host != '::1';
  }

  bool _isSafeAdUrl(String value) {
    final normalized = value.trim();
    final uri = Uri.tryParse(normalized);
    return normalized.isNotEmpty &&
        normalized.length <= 2048 &&
        uri != null &&
        _isSafeHttpsUri(uri);
  }

  List<String> _normalizedVideoUrls() => videoUrls.text
      .split(RegExp(r'\r?\n'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();

  bool _isSupportedBusinessVideoUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !_isSafeHttpsUri(uri)) return false;
    const hosts = {
      'youtu.be',
      'youtube.com',
      'www.youtube.com',
      'm.youtube.com',
      'youtube-nocookie.com',
      'www.youtube-nocookie.com',
      'vimeo.com',
      'www.vimeo.com',
      'player.vimeo.com',
    };
    return hosts.contains(uri.host.toLowerCase()) &&
        (uri.pathSegments.isNotEmpty || uri.queryParameters.isNotEmpty);
  }

  void _previewBusiness() {
    final data = prepareSaveData();
    data['shortDescription'] = description.text.trim();
    if (!publicContactApproved) {
      data['whatsapp'] = '';
      data['phone'] = '';
      data['instagram'] = '';
    }
    final preview = Business.fromData(
      _businessDocumentId ?? 'preview-establishment',
      data,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BusinessProfile(
          business: preview,
          saved: false,
          onFavorite: () {},
          trackShareMetric: false,
          previewMode: true,
        ),
      ),
    );
  }

  Future<void> _goToBusinessStep(int index) async {
    if (index < 0 || index >= _businessStepKeys.length) return;
    setState(() => _selectedBusinessStep = index);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_businessFormScrollController.hasClients) return;
    await _businessFormScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _businessStepNavigator() {
    const labels = [
      '1 Dados',
      '2 Contato',
      '3 Fotos',
      '4 Detalhes e publicação',
    ];
    final currentTitles = [
      'Apresente o estabelecimento',
      'Como o público encontra você',
      'Escolha capa e galeria',
      'Revise os detalhes e publique',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: const Color(0xFFF1F5F9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Etapa ${_selectedBusinessStep + 1} de ${labels.length}',
                    style: const TextStyle(
                      color: ocean,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  '${((_selectedBusinessStep + 1) / labels.length * 100).round()}%',
                  style: const TextStyle(
                    color: muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            LinearProgressIndicator(
              value: (_selectedBusinessStep + 1) / labels.length,
              minHeight: 5,
              borderRadius: BorderRadius.circular(10),
              backgroundColor: Colors.white,
              color: const Color(0xFFFF7A00),
            ),
            const SizedBox(height: 7),
            Text(
              currentTitles[_selectedBusinessStep],
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var index = 0; index < labels.length; index++) ...[
                    if (index > 0) const SizedBox(width: 7),
                    ChoiceChip(
                      key: ValueKey('establishment-step-$index'),
                      label: Text(labels[index]),
                      selected: _selectedBusinessStep == index,
                      onSelected: (_) => _goToBusinessStep(index),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      selectedColor: const Color(0xFFFFE6D0),
                      side: BorderSide(
                        color: _selectedBusinessStep == index
                            ? const Color(0xFFFF7A00)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _businessStepFooter() => Row(
    children: [
      if (_selectedBusinessStep > 0) ...[
        OutlinedButton.icon(
          key: const ValueKey('establishment-step-back'),
          onPressed: saving
              ? null
              : () => _goToBusinessStep(_selectedBusinessStep - 1),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Voltar'),
        ),
        const SizedBox(width: 10),
      ],
      Expanded(
        child: FilledButton.icon(
          key: _selectedBusinessStep == _businessStepKeys.length - 1
              ? const ValueKey('content-editor-save')
              : const ValueKey('establishment-step-next'),
          onPressed: saving || !_jobSaveReady
              ? null
              : _selectedBusinessStep == _businessStepKeys.length - 1
              ? save
              : () => _goToBusinessStep(_selectedBusinessStep + 1),
          icon: Icon(
            _selectedBusinessStep == _businessStepKeys.length - 1
                ? Icons.save_outlined
                : Icons.arrow_forward_rounded,
          ),
          label: Text(
            _selectedBusinessStep == _businessStepKeys.length - 1
                ? (saving ? 'Salvando…' : 'Salvar estabelecimento')
                : 'Continuar',
          ),
        ),
      ),
    ],
  );

  Widget _formSection(
    String title,
    String subtitle,
    IconData icon, {
    Key? key,
  }) => Padding(
    key: key,
    padding: const EdgeInsets.fromLTRB(0, 18, 0, 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: ocean, size: 20),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> save() async {
    if ((isJobContent && saving) ||
        (isBusinessContent && HybridAdminRuntime.enabled && saving)) {
      return;
    }
    if (shouldBlockLegacyEstablishmentWrite(
      isEstablishment: isBusinessContent,
      hybridEnabled: HybridAdminRuntime.enabled,
      source: _businessDocumentData,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este estabelecimento já usa a outbox. Reabra o fluxo administrativo autorizado para editá-lo.',
          ),
        ),
      );
      return;
    }
    if (isBusinessContent) {
      final errors = <String, String>{};
      if (title.text.trim().isEmpty) {
        errors['name'] = 'Informe o nome do estabelecimento.';
      }
      final storedCategory = (_businessDocumentData?['category'] ?? '')
          .toString()
          .trim();
      if (category.text.trim().isEmpty &&
          (!_isEditing || storedCategory.isNotEmpty)) {
        errors['category'] = 'Escolha uma categoria para continuar.';
      }
      if (errors.isNotEmpty) {
        setState(() {
          _businessValidationErrors
            ..clear()
            ..addAll(errors);
          _selectedBusinessStep = 0;
        });
        return;
      }
    }
    if (title.text.trim().isEmpty || !_jobSaveReady) return;
    if (widget.collection == 'ads' &&
        (!_isSafeAdUrl(imageUrl.text) || !_isSafeAdUrl(link.text))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Informe o link HTTPS direto da imagem e a página HTTPS que será aberta ao tocar no anúncio.',
          ),
        ),
      );
      return;
    }
    if (isBusinessContent &&
        HybridAdminRuntime.enabled &&
        _normalizedVideoUrls().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'O envio de vídeos ainda não está disponível no fluxo híbrido deste estabelecimento.',
          ),
        ),
      );
      return;
    }
    if (widget.collection == 'routes' && category.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione uma categoria para o local.')),
      );
      return;
    }
    if (widget.collection == 'routes' &&
        !AppIcon.all.any((item) => item.key == tourismIconKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escolha um ícone da lista pelo nome.')),
      );
      return;
    }
    if (widget.collection == 'routes' &&
        !_isSafeTourismMapDestination(maps.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Use uma URL HTTPS ou um endereço geo: permitido.'),
        ),
      );
      return;
    }
    if (isEventContent) {
      final dateIsValid =
          _contentDate({'eventDate': eventDate.text.trim()}) != null;
      final parsedStart = _contentDate({'eventDate': eventDate.text.trim()});
      final endDateText = eventEndDate.text.trim();
      final parsedEnd = endDateText.isEmpty
          ? parsedStart
          : _contentDate({'eventDate': endDateText});
      final timePattern = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
      final start = eventStartTime.text.trim();
      final end = eventEndTime.text.trim();
      if (title.text.trim().isEmpty ||
          category.text.trim().isEmpty ||
          !dateIsValid ||
          parsedEnd == null ||
          (parsedStart != null &&
              DateUtils.dateOnly(
                parsedEnd,
              ).isBefore(DateUtils.dateOnly(parsedStart))) ||
          (start.isNotEmpty && !timePattern.hasMatch(start)) ||
          (end.isNotEmpty && !timePattern.hasMatch(end))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Informe título, categoria, data e horários válidos (HH:mm).',
            ),
          ),
        );
        return;
      }
      if (!_isSafeTourismMapDestination(maps.text) ||
          !_isSafeHttpsEventUrl(eventRegistrationUrl.text) ||
          !_isSafeHttpsEventUrl(eventContactUrl.text)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Use um link HTTPS válido para Maps, inscrição ou contato.',
            ),
          ),
        );
        return;
      }
    }
    if (isBusinessContent && !_businessUrlsAreSafe()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Use destinos externos seguros e imagens com URL HTTPS válida. Os vídeos devem usar YouTube ou Vimeo.',
          ),
        ),
      );
      return;
    }
    setState(() => saving = true);
    String? attemptedHybridRequestId;
    try {
      final data = prepareSaveData();
      // Jobs always use the variant-selected AdminJobRepository: Spark Beta
      // uses Firestore directly, while other variants retain the callable.
      if (isJobContent) {
        final privateData = _jobPrivatePatch();
        if (_isEditing) {
          await _jobRepository!.update(
            jobId: widget.jobId!,
            publicData: data,
            privateData: privateData,
          );
        } else {
          final id = _reservedJobId ??= _jobRepository!.reserveCreateId();
          final confirmedId = await _jobRepository!.create(
            jobId: id,
            publicData: data,
            privateData: privateData,
          );
          if (confirmedId != id) throw AdminJobException('invalid-response');
        }
        await _recordJobAudit(
          action: _isEditing ? 'update' : 'create',
          documentId: _isEditing ? widget.jobId! : _reservedJobId!,
        );
        if (mounted) Navigator.pop(context);
        return;
      }
      if (BetaEnvironment.enabled) {
        final id =
            _businessDocumentId ??
            _sparkContentOperations.reserveId(widget.collection);
        await _sparkContentOperations.save(
          collection: widget.collection,
          id: id,
          data: data,
        );
        await _auditRecorder(
          action: _isEditing ? 'update' : 'create',
          collection: widget.collection,
          documentId: id,
          label: title.text.trim(),
        );
        if (mounted) Navigator.pop(context);
        return;
      }
      if (isBusinessContent && HybridAdminRuntime.enabled) {
        final repository = HybridAdminRuntime.createIfEnabled();
        if (repository == null) {
          throw const HybridAdminException(HybridAdminFailure.notConfigured);
        }
        final payload = hybridAdminPayloadFromEditor(
          Map<String, Object?>.from(data),
        );
        final selectedCategory = payload['category'];
        if (selectedCategory is! String ||
            !isHybridAdminEstablishmentCategory(selectedCategory)) {
          throw const HybridAdminException(HybridAdminFailure.invalidRequest);
        }
        final source = _businessDocumentData;
        final storedVersion = source?['catalogVersion'];
        final expectedVersion = _businessDocumentId == null
            ? null
            : storedVersion == null
            ? 0
            : storedVersion is int
            ? storedVersion
            : null;
        if (_businessDocumentId != null && expectedVersion == null) {
          throw const HybridAdminException(HybridAdminFailure.conflict);
        }
        final wasPublished = _businessDocumentId == null
            ? null
            : source?['published'] != false;
        if (payload['published'] == false) payload['active'] = false;
        final requestId = _hybridRequestIdFor(
          entityId: _businessDocumentId,
          expectedVersion: expectedVersion,
          payload: payload,
        );
        attemptedHybridRequestId = requestId;
        final result = await saveHybridEstablishment(
          repository: repository,
          requestId: requestId,
          entityId: _businessDocumentId,
          expectedVersion: expectedVersion,
          wasPublished: wasPublished,
          data: payload,
        );
        _clearHybridRequest(requestId);
        await recordAdminAudit(
          action: _businessDocumentId == null ? 'create' : 'update',
          collection: FirestoreCollections.establishments,
          documentId: result.entityId,
          label: title.text.trim(),
        );
        if ((_businessDocumentId ?? result.entityId) != result.entityId) {
          throw const HybridAdminException(HybridAdminFailure.invalidResponse);
        }
        if (mounted) Navigator.pop(context);
        return;
      }
      final existingReference =
          widget.doc?.reference ??
          (_businessDocumentId == null
              ? null
              : FirebaseFirestore.instance
                    .collection(widget.collection)
                    .doc(_businessDocumentId));
      final reference =
          existingReference ??
          await FirebaseFirestore.instance
              .collection(widget.collection)
              .add(data);
      if (existingReference != null) {
        await reference.update(data);
      }
      await _auditRecorder(
        action: widget.doc == null ? 'create' : 'update',
        collection: widget.collection,
        documentId: reference.id,
        label: title.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } on FirebaseException catch (error) {
      debugPrint('Conteúdo não salvo: ${error.code}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isJobContent
                  ? 'Não foi possível confirmar a gravação da vaga. Tente novamente.'
                  : 'Não foi possível salvar agora (${error.code}). Verifique a internet e tente novamente.',
            ),
          ),
        );
      }
    } on HybridAdminException catch (error) {
      if (error.failure == HybridAdminFailure.invalidRequest &&
          attemptedHybridRequestId != null) {
        _clearHybridRequest(attemptedHybridRequestId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível salvar o estabelecimento.'),
          ),
        );
      }
    } catch (error) {
      if (isJobContent &&
          !_isEditing &&
          error is AdminJobException &&
          error.createReservationReleased) {
        _reservedJobId = null;
      }
      debugPrint('Conteúdo não salvo (${error.runtimeType}).');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isJobContent &&
                      error is AdminJobException &&
                      error.createPayloadConflict
                  ? error.message
                  : isJobContent
                  ? 'Não foi possível confirmar a gravação da vaga. Tente novamente.'
                  : 'Não foi possível salvar todos os dados. Tente novamente.',
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
    if (!_isEditing ||
        ((isJobContent ||
                widget.collection == 'routes' ||
                isEventContent ||
                (isBusinessContent && HybridAdminRuntime.enabled)) &&
            saving)) {
      return;
    }
    if (shouldBlockLegacyEstablishmentWrite(
      isEstablishment: isBusinessContent,
      hybridEnabled: HybridAdminRuntime.enabled,
      source: _businessDocumentData,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este estabelecimento já usa a outbox e não pode ser excluído fisicamente. Use o fluxo de exclusão lógica autorizado.',
          ),
        ),
      );
      return;
    }
    final useHybridAdmin = isBusinessContent && HybridAdminRuntime.enabled;
    final isTourismContent = widget.collection == 'routes';
    if (isJobContent || useHybridAdmin || isTourismContent || isEventContent) {
      setState(() => saving = true);
    }
    String? attemptedHybridRequestId;
    try {
      if (BetaEnvironment.enabled) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Excluir conteúdo?'),
            content: const Text(
              'O item será removido da área pública e permanecerá salvo para auditoria. Essa exclusão lógica não pode ser desfeita pelo aplicativo.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        final id = isJobContent ? widget.jobId! : _businessDocumentId!;
        if (isJobContent) {
          await _jobRepository!.delete(id);
        } else {
          await _sparkContentOperations.softDelete(
            collection: widget.collection,
            id: id,
          );
        }
        await _auditRecorder(
          action: 'soft_delete',
          collection: widget.collection,
          documentId: id,
          label: title.text.trim(),
        );
      } else if (isJobContent) {
        await _jobRepository!.delete(widget.jobId!);
        await _recordJobAudit(action: 'delete', documentId: widget.jobId!);
      } else if (useHybridAdmin) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Excluir estabelecimento?'),
            content: const Text(
              'A exclusão será lógica e permanente para o catálogo público. '
              'O registro não poderá ser republicado depois.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        final repository = HybridAdminRuntime.createIfEnabled();
        if (repository == null) {
          throw const HybridAdminException(HybridAdminFailure.notConfigured);
        }
        final source = _businessDocumentData;
        final storedVersion = source?['catalogVersion'];
        final expectedVersion = storedVersion == null
            ? 0
            : storedVersion is int
            ? storedVersion
            : null;
        if (expectedVersion == null) {
          throw const HybridAdminException(HybridAdminFailure.conflict);
        }
        final requestId = _hybridRequestIdFor(
          entityId: _businessDocumentId,
          expectedVersion: expectedVersion,
          payload: const {'operation': 'logical_delete'},
        );
        attemptedHybridRequestId = requestId;
        final result = await repository.delete(
          requestId: requestId,
          entityId: _businessDocumentId!,
          expectedVersion: expectedVersion,
        );
        _clearHybridRequest(requestId);
        await recordAdminAudit(
          action: 'delete',
          collection: FirestoreCollections.establishments,
          documentId: result.entityId,
          label: title.text.trim(),
        );
      } else if (isTourismContent) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Remover conteúdo turístico?'),
            content: const Text(
              'O item será ocultado do público, mas continuará salvo para que o Admin possa recuperá-lo depois.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Remover'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        final reference =
            document?.reference ??
            FirebaseFirestore.instance
                .collection(FirestoreCollections.routes)
                .doc(_businessDocumentId);
        await reference.update({
          'active': false,
          'published': false,
          'deleted': true,
          'deletedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await recordAdminAudit(
          action: 'soft_delete',
          collection: FirestoreCollections.routes,
          documentId: _businessDocumentId!,
          label: title.text.trim(),
        );
      } else if (isEventContent) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Excluir evento?'),
            content: const Text(
              'O evento será ocultado do público e permanecerá salvo para recuperação administrativa.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Excluir evento'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        final reference =
            document?.reference ??
            FirebaseFirestore.instance
                .collection(widget.collection)
                .doc(_businessDocumentId);
        await reference.update({
          'active': false,
          'published': false,
          'deleted': true,
          'deletedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await recordAdminAudit(
          action: 'soft_delete',
          collection: widget.collection,
          documentId: document?.id ?? _businessDocumentId!,
          label: title.text.trim(),
        );
      } else {
        final reference =
            document?.reference ??
            FirebaseFirestore.instance
                .collection(widget.collection)
                .doc(_businessDocumentId);
        await reference.delete();
        await recordAdminAudit(
          action: 'delete',
          collection: widget.collection,
          documentId: document?.id ?? _businessDocumentId!,
          label: title.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context);
    } on FirebaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível excluir agora. Tente novamente.'),
          ),
        );
      }
    } on HybridAdminException catch (error) {
      if (error.failure == HybridAdminFailure.invalidRequest &&
          attemptedHybridRequestId != null) {
        _clearHybridRequest(attemptedHybridRequestId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível excluir agora. Tente novamente.'),
          ),
        );
      }
    } catch (error) {
      debugPrint('Conteúdo não excluído (${error.runtimeType}).');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível excluir agora. Tente novamente.'),
          ),
        );
      }
    } finally {
      if (mounted &&
          (isJobContent ||
              useHybridAdmin ||
              isTourismContent ||
              isEventContent)) {
        setState(() => saving = false);
      }
    }
  }

  String _hybridRequestIdFor({
    required String? entityId,
    required int? expectedVersion,
    required Map<String, Object?> payload,
  }) {
    return _hybridRequestReservation.reserve(
      entityId: entityId,
      expectedVersion: expectedVersion,
      payload: payload,
    );
  }

  void _clearHybridRequest(String requestId) =>
      _hybridRequestReservation.clear(requestId);

  List<String> _normalizedGallery() {
    return orderedUniqueImageUrls([
      ...galleryItems,
      ...imageUrlsFromInput(galleryUrls.text),
    ]);
  }

  void _addGalleryUrls() {
    final rawLines = galleryInput.text
        .split(RegExp(r'\r?\n'))
        .map(normalizeImageUrl)
        .where((item) => item.isNotEmpty)
        .toList();
    if (rawLines.isEmpty) {
      final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Cole pelo menos um link HTTPS de imagem antes de adicionar.',
          ),
        ),
      );
      return;
    }
    if (isBusinessContent &&
        rawLines.any((value) {
          final uri = Uri.tryParse(value);
          return uri == null ||
              uri.scheme.toLowerCase() != 'https' ||
              uri.host.isEmpty;
        })) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('As fotos precisam usar URLs HTTPS válidas.'),
        ),
      );
      return;
    }
    final urls = imageUrlsFromInput(
      galleryInput.text,
    ).map(cloudinaryOptimizedImageUrl).toList();
    if (urls.isEmpty) {
      final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Nenhum link de imagem válido foi encontrado.'),
        ),
      );
      return;
    }
    final updated = orderedUniqueImageUrls([...galleryItems, ...urls]);
    if (updated.length == galleryItems.length) {
      final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Esses links já estão na galeria.')),
      );
      return;
    }
    if (widget.collection == 'routes' && updated.length > 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Turismo permite até 3 imagens por local.'),
        ),
      );
      return;
    }
    setState(() {
      galleryItems
        ..clear()
        ..addAll(updated);
      if (imageUrl.text.trim().isEmpty && galleryItems.isNotEmpty) {
        imageUrl.text = galleryItems.first;
      }
      galleryInput.clear();
      galleryUrls.text = galleryItems.join('\n');
    });
  }

  void _moveGalleryImage(int index, int direction) {
    final updated = moveImageUrl(galleryItems, index, direction);
    setState(() {
      galleryItems
        ..clear()
        ..addAll(updated);
      galleryUrls.text = galleryItems.join('\n');
    });
  }

  void _reorderGalleryImage(int oldIndex, int newIndex) {
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= galleryItems.length ||
        newIndex < 0 ||
        newIndex >= galleryItems.length) {
      return;
    }
    final updated = [...galleryItems];
    final image = updated.removeAt(oldIndex);
    updated.insert(newIndex, image);
    setState(() {
      galleryItems
        ..clear()
        ..addAll(updated);
      imageUrl.text = galleryItems.first;
      galleryUrls.text = galleryItems.join('\n');
    });
  }

  void _setCoverImage(int index) {
    final updated = setCoverImageUrl(galleryItems, index);
    setState(() {
      galleryItems
        ..clear()
        ..addAll(updated);
      imageUrl.text = galleryItems.isEmpty ? '' : galleryItems.first;
      galleryUrls.text = galleryItems.join('\n');
    });
  }

  void _removeGalleryImage(int index) {
    final updated = removeImageUrl(galleryItems, index);
    setState(() {
      galleryItems
        ..clear()
        ..addAll(updated);
      imageUrl.text = galleryItems.isEmpty ? '' : galleryItems.first;
      galleryUrls.text = galleryItems.join('\n');
    });
  }

  Widget _jobPrivateStatus() {
    if (!isJobContent) return const SizedBox.shrink();
    if (!_isEditing) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Os contatos administrativos desta vaga serão salvos somente na área privada.',
          ),
        ),
      );
    }
    if (_privateJobLoading) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(),
          SizedBox(height: 8),
          Text('Carregando contatos administrativos privados…'),
        ],
      );
    }
    if (_privateJobLoadError != null) {
      return Card(
        color: Colors.red.shade50,
        child: ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('Não foi possível ler os contatos privados.'),
          subtitle: const Text(
            'O salvamento ficará bloqueado até a leitura funcionar.',
          ),
          trailing: TextButton(
            onPressed: saving
                ? null
                : () {
                    setState(() {
                      _privateJobLoading = true;
                      _privateJobLoadError = null;
                    });
                    unawaited(_loadPrivateJobData());
                  },
            child: const Text('Tentar novamente'),
          ),
        ),
      );
    }
    if (_legacyJobWithoutPrivate) {
      return Card(
        color: Colors.orange.shade50,
        child: const ListTile(
          leading: Icon(Icons.warning_amber_outlined),
          title: Text('Vaga legada pendente de migração'),
          subtitle: Text(
            'Não existe documento privado para esta vaga. A edição está bloqueada para evitar perda ou cópia automática de contatos antigos.',
          ),
        ),
      );
    }
    return const Card(
      child: ListTile(
        leading: Icon(Icons.lock_outline),
        title: Text('Contatos administrativos carregados da área privada.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        isBusinessContent
            ? (_isEditing ? 'Editar estabelecimento' : 'Novo estabelecimento')
            : (_isEditing ? 'Editar' : 'Adicionar'),
      ),
      actions: [
        if (isBusinessContent)
          IconButton(
            tooltip: 'Pré-visualizar perfil',
            onPressed: _previewBusiness,
            icon: const Icon(Icons.visibility_outlined),
          ),
      ],
    ),
    body: ListView(
      controller: _businessFormScrollController,
      padding: const EdgeInsets.all(20),
      children: [
        if (isBusinessContent) _businessStepNavigator(),
        if (isJobContent) ...[_jobPrivateStatus(), const SizedBox(height: 14)],
        if (isBusinessContent && _selectedBusinessStep == 0)
          _formSection(
            'Informações principais',
            'Como o estabelecimento aparece no aplicativo.',
            Icons.storefront_outlined,
            key: _businessStepKeys[0],
          ),
        if (!isBusinessContent || _selectedBusinessStep == 0)
          TextField(
            key: const ValueKey('content-editor-primary-name'),
            enabled: isJobContent ? _jobSaveReady && !saving : null,
            controller: title,
            onChanged: (_) {
              if (_businessValidationErrors.isNotEmpty) {
                setState(_businessValidationErrors.clear);
              }
            },
            decoration: InputDecoration(
              labelText: 'Título ou nome',
              border: OutlineInputBorder(),
              errorText: _businessValidationErrors['name'],
            ),
          ),
        if (!isBusinessContent || _selectedBusinessStep == 0)
          const SizedBox(height: 14),
        if (isBusinessContent && _selectedBusinessStep == 0) ...[
          DropdownButtonFormField<String>(
            key: const ValueKey('content-editor-business-category'),
            initialValue: catalog.any((item) => item.name == category.text)
                ? category.text
                : null,
            decoration: InputDecoration(
              labelText: 'Categoria',
              helperText: 'Escolha onde este estabelecimento vai aparecer.',
              border: OutlineInputBorder(),
              errorText: _businessValidationErrors['category'],
            ),
            items: catalog
                .map(
                  (item) => DropdownMenuItem(
                    key: ValueKey(
                      'content-editor-category-option-${item.name}',
                    ),
                    value: item.name,
                    child: Text(item.name),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              final selected = catalog.firstWhere((item) => item.name == value);
              setState(() {
                _businessValidationErrors.remove('category');
                category.text = selected.name;
                if (!selected.types.contains(subcategory.text)) {
                  subcategory.text = selected.types.isEmpty
                      ? ''
                      : selected.types.first;
                }
              });
            },
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue:
                catalog
                    .where((item) => item.name == category.text)
                    .expand((item) => item.types)
                    .contains(subcategory.text)
                ? subcategory.text
                : null,
            decoration: const InputDecoration(
              labelText: 'Subcategoria',
              helperText:
                  'Ajuda o público a filtrar melhor dentro da categoria.',
              border: OutlineInputBorder(),
            ),
            items: catalog
                .where((item) => item.name == category.text)
                .expand((item) => item.types)
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => subcategory.text = value);
            },
          ),
          const SizedBox(height: 14),
        ] else if (widget.collection == 'routes') ...[
          DropdownButtonFormField<String>(
            initialValue: category.text.isEmpty
                ? null
                : TourismCategory.normalize(category.text),
            decoration: const InputDecoration(
              labelText: 'Categoria',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final c in TourismCategory.values)
                DropdownMenuItem(value: c.key, child: Text(c.name)),
              if (category.text.isNotEmpty &&
                  !TourismCategory.values.any(
                    (c) => c.key == TourismCategory.normalize(category.text),
                  ))
                DropdownMenuItem(
                  value: TourismCategory.normalize(category.text),
                  child: Text(category.text),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => category.text = value);
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: bannerOrder,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            decoration: const InputDecoration(
              labelText: 'Ordem na categoria',
              helperText: 'Números menores aparecem primeiro',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ] else if (supportsLocalDetails) ...[
          TextField(
            enabled: isJobContent ? _jobSaveReady && !saving : null,
            controller: category,
            decoration: const InputDecoration(
              labelText: 'Categoria',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (!isBusinessContent || _selectedBusinessStep == 0)
          TextField(
            enabled: isJobContent ? _jobSaveReady && !saving : null,
            controller: description,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Descrição',
              border: OutlineInputBorder(),
            ),
          ),
        if (!isBusinessContent || _selectedBusinessStep == 0)
          const SizedBox(height: 14),
        if ((isBusinessContent && _selectedBusinessStep == 1) ||
            supportsLocalDetails) ...[
          if (isBusinessContent && _selectedBusinessStep == 1)
            _formSection(
              'Contato e localização',
              'Canais para o público encontrar e falar com o comércio.',
              Icons.place_outlined,
              key: _businessStepKeys[1],
            ),
          if (widget.collection == 'events') ...[
            TextField(
              controller: eventDate,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Data do evento',
                helperText: 'Use AAAA-MM-DD ou DD/MM/AAAA',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: eventEndDate,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Último dia (opcional)',
                helperText: 'Para eventos que duram mais de um dia.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: eventStartTime,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Horário de início (opcional)',
                hintText: '19:30',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: eventEndTime,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Horário de término (opcional)',
                hintText: '22:00',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: eventOrganizer,
              decoration: const InputDecoration(
                labelText: 'Organizador (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: eventRegistrationUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Inscrição (link HTTPS, opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: eventContactUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Contato público (link HTTPS, opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            enabled: isJobContent ? _jobSaveReady && !saving : null,
            controller: location,
            decoration: const InputDecoration(
              labelText: 'Local, endereço ou referência',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          if (!isEventContent) ...[
            if (!isBusinessContent)
              TextField(
                enabled: isJobContent ? _jobSaveReady && !saving : null,
                controller: contact,
                decoration: const InputDecoration(
                  labelText: 'Contato administrativo (privado)',
                  helperText:
                      'Não será exibido como contato público de candidatura.',
                  border: OutlineInputBorder(),
                ),
              ),
            const SizedBox(height: 14),
            TextField(
              enabled: isJobContent ? _jobSaveReady && !saving : null,
              controller: whatsapp,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: isJobContent
                    ? 'WhatsApp administrativo (privado)'
                    : 'WhatsApp (número ou link)',
                helperText: isBusinessContent
                    ? 'Informe o número com DDD ou cole um link wa.me.'
                    : null,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              enabled: isJobContent ? _jobSaveReady && !saving : null,
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: isJobContent
                    ? 'Telefone administrativo (privado)'
                    : 'Telefone (tel:)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              enabled: isJobContent ? _jobSaveReady && !saving : null,
              controller: instagram,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: isJobContent
                    ? 'Instagram administrativo (privado)'
                    : 'Instagram (URL)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            enabled: isJobContent ? _jobSaveReady && !saving : null,
            controller: maps,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: isJobContent
                  ? 'Link do Google Maps (privado)'
                  : 'Link do Google Maps',
              helperText: widget.collection == 'routes'
                  ? 'Use uma URL HTTPS válida ou um endereço geo:.'
                  : null,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (!isBusinessContent || _selectedBusinessStep == 1)
          TextField(
            enabled: isJobContent ? _jobSaveReady && !saving : null,
            controller: link,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: isJobContent
                  ? 'Link administrativo (privado)'
                  : isBusinessContent
                  ? 'Site ou outro link público (opcional)'
                  : widget.collection == 'ads'
                  ? 'Página que abre ao tocar no anúncio (HTTPS)'
                  : 'Link do botão (opcional)',
              helperText: isBusinessContent
                  ? 'WhatsApp, telefone e Maps têm campos próprios.'
                  : widget.collection == 'ads'
                  ? 'A imagem abre diretamente este endereço, sem tela intermediária.'
                  : null,
              hintText: widget.collection == 'ads'
                  ? 'https://exemplo.com/pagina'
                  : null,
              border: OutlineInputBorder(),
            ),
          ),
        if (!isBusinessContent || _selectedBusinessStep == 2)
          const SizedBox(height: 14),
        if (isBusinessContent && _selectedBusinessStep == 2) ...[
          _formSection(
            'Identidade visual',
            'Logo, capa e fotos do estabelecimento.',
            Icons.photo_library_outlined,
            key: _businessStepKeys[2],
          ),
          TextField(
            enabled: isJobContent ? _jobSaveReady && !saving : null,
            controller: logoUrl,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Logo da empresa (800 × 800 px)',
              hintText: 'Cole o link HTTPS da logo',
              helperText:
                  'Imagem quadrada; aparece nos cards do estabelecimento.',
              border: OutlineInputBorder(),
            ),
          ),
          if (logoUrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Image.network(
                      cloudinaryOptimizedImageUrl(logoUrl.text),
                      fit: BoxFit.cover,
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
                const SizedBox(width: 10),
                const Text('Prévia da logo', style: TextStyle(color: muted)),
              ],
            ),
          ],
          const SizedBox(height: 14),
        ],
        if (!supportsMediaGallery) ...[
          if (widget.collection == 'ads') ...[
            const Text(
              'Arte publicitária: 1600 × 600 px (8:3). Mantenha textos e logos afastados das bordas. Artes em outras proporções serão exibidas inteiras, com margens.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              enabled: isJobContent ? _jobSaveReady && !saving : null,
              controller: bannerOrder,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: const InputDecoration(
                labelText: 'Ordem do anúncio',
                helperText: 'Números menores aparecem primeiro',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              value: bannerActive,
              onChanged: saving
                  ? null
                  : (value) => setState(() => bannerActive = value),
              title: const Text('Anúncio ativo'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            enabled: isJobContent ? _jobSaveReady && !saving : null,
            controller: imageUrl,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: widget.collection == 'ads'
                  ? 'Link direto da imagem (HTTPS)'
                  : 'Imagem do Cloudinary (URL)',
              hintText: widget.collection == 'ads'
                  ? 'https://exemplo.com/banner.jpg'
                  : null,
              helperText: widget.collection == 'ads'
                  ? 'O banner é exibido no carrossel; ao tocar nele, abre a página configurada acima.'
                  : 'Envie pelo Cloudinary e cole aqui a URL da imagem',
              border: const OutlineInputBorder(),
            ),
          ),
          if (imageUrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: AspectRatio(
                aspectRatio: widget.collection == 'ads'
                    ? AdCarousel.bannerAspectRatio
                    : 16 / 9,
                child: Image.network(
                  cloudinaryOptimizedImageUrl(imageUrl.text),
                  fit: widget.collection == 'ads'
                      ? BoxFit.contain
                      : BoxFit.cover,
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
          if (widget.collection != 'ads')
            CloudinaryUploadHelper(
              controller: imageUrl,
              enabled: !saving && _jobSaveReady,
              onChanged: () => setState(() {}),
              title: 'Imagem do conteúdo',
              description:
                  'Selecione e envie uma imagem do dispositivo ou use uma URL existente para a capa.',
            ),
        ],
        if (supportsMediaGallery &&
            (!isBusinessContent || _selectedBusinessStep == 2)) ...[
          const SizedBox(height: 14),
          ContentMediaGalleryEditor(
            key: null,
            enabled: !saving && _jobSaveReady,
            maxImages: widget.collection == 'routes' ? 3 : null,
            title: isBusinessContent ? 'Capa e galeria' : null,
            description: isBusinessContent
                ? 'A primeira foto é a capa. Cole links HTTPS de imagens já hospedadas e arraste para mudar a ordem.'
                : null,
            urlLabel: isBusinessContent
                ? 'Links das fotos (uma por linha)'
                : null,
            urlHint: isBusinessContent
                ? 'Cole aqui a URL HTTPS real da imagem'
                : null,
            urlHelperText: isBusinessContent
                ? 'O texto cinza é apenas uma dica. Cole o link da imagem e toque em “Adicionar à galeria”.'
                : null,
            addButtonLabel: isBusinessContent ? 'Adicionar à galeria' : null,
            urlMaxLines: isBusinessContent ? 2 : null,
            urls: galleryItems,
            input: galleryInput,
            onAdd: _addGalleryUrls,
            onMove: _moveGalleryImage,
            onReorder: _reorderGalleryImage,
            onCover: _setCoverImage,
            onRemove: _removeGalleryImage,
          ),
          const SizedBox(height: 14),
        ],
        if (isBusinessContent && _selectedBusinessStep == 2) ...[
          TextField(
            controller: videoUrls,
            keyboardType: TextInputType.url,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Vídeos (YouTube ou Vimeo)',
              hintText: 'https://youtu.be/...\nhttps://vimeo.com/...',
              helperText: 'Cole uma URL HTTPS por linha.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (isBusinessContent && _selectedBusinessStep == 3) ...[
          _formSection(
            'Informações comerciais',
            'Horários, serviços, produtos e ofertas.',
            Icons.info_outline_rounded,
          ),
          BusinessHoursEditor(
            value: hours.text,
            enabled: !saving,
            onChanged: (value) {
              hours.value = hours.value.copyWith(text: value);
            },
          ),
          const SizedBox(height: 14),
          TextField(
            enabled: isJobContent ? _jobSaveReady && !saving : null,
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
            enabled: isJobContent ? _jobSaveReady && !saving : null,
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
        if ((isBusinessContent && _selectedBusinessStep == 3) ||
            supportsLocalDetails) ...[
          TextField(
            enabled: isJobContent ? _jobSaveReady && !saving : null,
            controller: additionalInfo,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: isJobContent
                  ? 'Informações administrativas (privadas)'
                  : 'Informações adicionais',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (isBusinessContent && _selectedBusinessStep == 3) ...[
          TextField(
            enabled: isJobContent ? _jobSaveReady && !saving : null,
            controller: promotionTitle,
            decoration: const InputDecoration(
              labelText: 'Título da oferta (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            enabled: isJobContent ? _jobSaveReady && !saving : null,
            controller: promotionDescription,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Descrição da oferta (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (isBusinessContent && _selectedBusinessStep == 3) ...[
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
                    'O ícone escolhido aparece quando o estabelecimento não tem logo. A categoria, a capa e as fotos continuam separadas.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ] else if (isBusinessContent && _selectedBusinessStep == 0) ...[
          NamedVisualIconPicker(
            key: const ValueKey('establishment-icon-key-picker'),
            value: tourismIconKey,
            onChanged: (value) => setState(() => tourismIconKey = value),
            label: 'Ícone exibido no aplicativo',
          ),
          const SizedBox(height: 14),
        ] else if (widget.collection == 'routes') ...[
          NamedAppIconPicker(
            key: const ValueKey('tourism-icon-key-picker'),
            value: tourismIconKey,
            onChanged: (value) => setState(() => tourismIconKey = value),
            label: 'Ícone exibido no aplicativo',
          ),
          const SizedBox(height: 14),
        ] else if (!isBusinessContent) ...[
          VisualIconPicker(
            value: (int.tryParse(icon.text) ?? 0).clamp(0, 17),
            onChanged: (value) => setState(() => icon.text = value.toString()),
            label: 'Ícone exibido no aplicativo',
          ),
          const SizedBox(height: 14),
        ],
        if (widget.collection == 'ads' ||
            widget.collection == 'offers' ||
            isEventContent)
          TextField(
            enabled: isJobContent ? _jobSaveReady && !saving : null,
            controller: isEventContent ? bannerOrder : expires,
            keyboardType: isEventContent
                ? const TextInputType.numberWithOptions(signed: true)
                : TextInputType.datetime,
            decoration: InputDecoration(
              labelText: isEventContent
                  ? 'Ordem de exibição'
                  : 'Encerrar em (AAAA-MM-DD)',
              helperText: isEventContent
                  ? 'Números menores aparecem primeiro'
                  : 'Deixe vazio para não expirar',
              border: OutlineInputBorder(),
            ),
          ),
        if (isBusinessContent && _selectedBusinessStep == 3)
          _formSection(
            'Publicação e visibilidade',
            'Controle onde e como o cadastro aparece.',
            Icons.publish_outlined,
            key: _businessStepKeys[3],
          ),
        if (isBusinessContent && _selectedBusinessStep == 3)
          SwitchListTile(
            value: businessActive,
            onChanged: saving
                ? null
                : (value) => setState(() => businessActive = value),
            title: const Text('Estabelecimento ativo'),
            subtitle: const Text(
              'Desative temporariamente sem excluir o cadastro.',
            ),
            contentPadding: EdgeInsets.zero,
          ),
        if (widget.collection == 'routes')
          _formSection(
            'Publicação e visibilidade',
            'Conteúdo inativo ou em rascunho não aparece para usuários comuns.',
            Icons.publish_outlined,
          ),
        if (isEventContent)
          _formSection(
            'Publicação e visibilidade',
            'Rascunhos e eventos inativos não aparecem ao público.',
            Icons.publish_outlined,
          ),
        if (isEventContent)
          SwitchListTile(
            value: eventActive,
            onChanged: saving
                ? null
                : (value) => setState(() => eventActive = value),
            title: const Text('Evento ativo'),
            subtitle: const Text('Desative sem apagar os dados do evento.'),
            contentPadding: EdgeInsets.zero,
          ),
        if (widget.collection == 'routes')
          SwitchListTile(
            value: tourismActive,
            onChanged: saving
                ? null
                : (value) => setState(() => tourismActive = value),
            title: const Text('Conteúdo ativo'),
            subtitle: const Text('Desative sem apagar o cadastro.'),
            contentPadding: EdgeInsets.zero,
          ),
        if (isBusinessContent && _selectedBusinessStep == 3)
          SwitchListTile(
            value: publicContactApproved,
            onChanged: saving
                ? null
                : (value) => setState(() => publicContactApproved = value),
            title: const Text('Permitir exibição pública dos contatos'),
            subtitle: const Text(
              'Autoriza telefone, WhatsApp e Instagram no perfil público. Os dados continuam salvos ao desativar.',
            ),
            contentPadding: EdgeInsets.zero,
          ),
        if (isBusinessContent && _selectedBusinessStep == 3)
          SwitchListTile(
            value: featured,
            onChanged: (v) => setState(() => featured = v),
            title: const Text('Destaque na Home'),
            contentPadding: EdgeInsets.zero,
          ),
        if (!isBusinessContent || _selectedBusinessStep == 3)
          SwitchListTile(
            key: const ValueKey('content-editor-published-toggle'),
            value: published,
            onChanged: isJobContent && (!_jobSaveReady || saving)
                ? null
                : (v) => setState(() => published = v),
            title: const Text('Publicado'),
            subtitle: Text(
              isBusinessContent
                  ? 'Novos estabelecimentos começam como rascunho. Ative somente quando estiver pronto para o público.'
                  : 'Desative para manter como rascunho',
            ),
            contentPadding: EdgeInsets.zero,
          ),
        const SizedBox(height: 10),
        if (isBusinessContent)
          _businessStepFooter()
        else
          FilledButton(
            key: const ValueKey('content-editor-save'),
            onPressed: saving || !_jobSaveReady ? null : save,
            child: Text(saving ? 'Salvando...' : 'Salvar alterações'),
          ),
        if (_isEditing && (!isBusinessContent || _selectedBusinessStep == 3))
          TextButton.icon(
            key: const ValueKey('content-editor-delete'),
            onPressed: isJobContent && (saving || _privateJobLoading)
                ? null
                : remove,
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: Text(
              widget.collection == 'routes'
                  ? 'Remover conteúdo'
                  : 'Excluir item',
              style: const TextStyle(color: Colors.red),
            ),
          ),
      ],
    ),
  );
}

class ContentMediaGalleryEditor extends StatelessWidget {
  const ContentMediaGalleryEditor({
    super.key,
    this.enabled = true,
    this.maxImages,
    this.title,
    this.description,
    this.urlLabel,
    this.urlHint,
    this.urlHelperText,
    this.addButtonLabel,
    this.urlMaxLines,
    required this.urls,
    required this.input,
    required this.onAdd,
    required this.onMove,
    required this.onReorder,
    required this.onCover,
    required this.onRemove,
  });
  final List<String> urls;
  final bool enabled;
  final int? maxImages;
  final String? title;
  final String? description;
  final String? urlLabel;
  final String? urlHint;
  final String? urlHelperText;
  final String? addButtonLabel;
  final int? urlMaxLines;
  final TextEditingController input;
  final VoidCallback onAdd;
  final void Function(int index, int direction) onMove;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<int> onCover;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final atLimit = maxImages != null && urls.length >= maxImages!;
    final legacyOverLimit = maxImages != null && urls.length > maxImages!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title ?? 'Fotos do conteúdo',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          description ??
              (BetaEnvironment.enabled
                  ? 'Cole uma URL HTTPS de mídia previamente hospedada. Nesta versão gratuita não há envio de arquivos pelo aplicativo.'
                  : maxImages == null
                  ? 'Envie fotos do dispositivo ou cole URLs. A primeira foto é a capa; use os controles para reorganizar.'
                  : legacyOverLimit
                  ? 'Este local legado tem mais de $maxImages fotos. Nada será removido automaticamente; remova fotos conscientemente para adicionar outras.'
                  : 'Envie fotos do dispositivo ou cole URLs. A primeira foto é a capa; Turismo permite até $maxImages imagens.'),
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (!BetaEnvironment.enabled)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ImageUploadButton(
                enabled: enabled && !atLimit,
                onUploaded: (url) {
                  input.text = [
                    input.text.trim(),
                    url,
                  ].where((value) => value.isNotEmpty).join('\n');
                  onAdd();
                },
              ),
              OutlinedButton.icon(
                onPressed: () => openUrl(
                  context,
                  'https://console.cloudinary.com/',
                  'Cloudinary',
                ),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Abrir Cloudinary'),
              ),
            ],
          ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('gallery-url-input'),
          controller: input,
          keyboardType: TextInputType.url,
          maxLines: urlMaxLines ?? 5,
          enabled: enabled && !atLimit,
          decoration: InputDecoration(
            labelText: urlLabel ?? 'Links das imagens (Cloudinary)',
            hintText:
                urlHint ??
                'https://res.cloudinary.com/.../foto1.jpg\nhttps://res.cloudinary.com/.../foto2.jpg',
            helperText:
                urlHelperText ??
                (maxImages == null
                    ? 'Use uma URL por linha. Linhas vazias e duplicadas são ignoradas.'
                    : 'Use uma URL por linha. Turismo permite até $maxImages imagens.'),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey('add-gallery-photos'),
            onPressed: enabled && !atLimit ? onAdd : null,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(addButtonLabel ?? 'Adicionar / atualizar fotos'),
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
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: urls.length,
            onReorderItem: onReorder,
            itemBuilder: (context, index) {
              final url = urls[index];
              final isCover = index == 0;
              return Card(
                key: ValueKey('gallery-photo-$url'),
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 76,
                              height: 58,
                              child: Material(
                                color: mist,
                                child: InkWell(
                                  key: ValueKey('gallery-preview-$index'),
                                  onTap: () =>
                                      _showGalleryPreview(context, url),
                                  child: Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      final expected =
                                          progress.expectedTotalBytes;
                                      return Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            value: expected == null
                                                ? null
                                                : progress.cumulativeBytesLoaded /
                                                      expected,
                                          ),
                                        ),
                                      );
                                    },
                                    errorBuilder: (_, _, _) => const Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: muted,
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
                                  isCover
                                      ? 'Foto ${index + 1} · CAPA'
                                      : 'Foto ${index + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  url,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Toque para ampliar',
                                  style: TextStyle(color: muted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        alignment: WrapAlignment.end,
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: IconButton(
                              key: ValueKey('gallery-drag-handle-$index'),
                              tooltip: 'Arrastar para reordenar',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(
                                width: 44,
                                height: 44,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: null,
                              icon: const Icon(Icons.drag_handle_rounded),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Subir',
                            onPressed: index == 0
                                ? null
                                : () => onMove(index, -1),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 44,
                              height: 44,
                            ),
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.keyboard_arrow_up_rounded),
                          ),
                          IconButton(
                            tooltip: 'Descer',
                            onPressed: index == urls.length - 1
                                ? null
                                : () => onMove(index, 1),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 44,
                              height: 44,
                            ),
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          ),
                          IconButton(
                            tooltip: isCover ? 'Capa atual' : 'Usar como capa',
                            onPressed: isCover ? null : () => onCover(index),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 44,
                              height: 44,
                            ),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              isCover
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: isCover ? orange : null,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Excluir foto',
                            onPressed: () => onRemove(index),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 44,
                              height: 44,
                            ),
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  void _showGalleryPreview(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 900,
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: InteractiveViewer(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                          ? child
                          : const Center(
                              child: CircularProgressIndicator(color: orange),
                            ),
                      errorBuilder: (_, _, _) => const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image_outlined, size: 44),
                            SizedBox(height: 8),
                            Text('Não foi possível carregar esta foto.'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton.filledTonal(
                  key: const ValueKey('gallery-preview-close'),
                  tooltip: 'Fechar prévia',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
            final email = (d['email'] ?? '').toString().trim();
            final phone = (d['contact'] ?? '').toString().trim();
            return ListTile(
              title: Text(
                email.isNotEmpty
                    ? email
                    : (d['name'] ?? 'Conta legada').toString(),
              ),
              subtitle: Text(
                '${d['message'] ?? ''}\nTelefone: ${phone.isEmpty ? 'não informado' : phone}',
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

const utilityDestinationTypes = supportedUtilityDestinationTypes;

const utilityIconMap = <String, IconData>{
  'bus': Icons.directions_bus_rounded,
  'trash': Icons.delete_outline_rounded,
  'cityHall': Icons.account_balance_outlined,
  'water': Icons.water_drop_outlined,
  'energy': Icons.bolt_outlined,
  'waterEnergy': Icons.receipt_long_outlined,
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

const internalUtilityPages = supportedUtilityInternalPages;

bool _availableCityUtility(UtilityItem item) =>
    item.active &&
    item.id.toLowerCase() != 'pharmacyduty' &&
    item.destination.toLowerCase() != 'pharmacyduty' &&
    item.id.toLowerCase() != 'tourism' &&
    item.destination.toLowerCase() != 'tourism' &&
    item.id.toLowerCase() != 'resolver' &&
    item.destination.toLowerCase() != 'resolver' &&
    item.id.toLowerCase() != 'emergency' &&
    item.destination.toLowerCase() != 'emergency';

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
    id: 'cityHall',
    name: 'Prefeitura',
    iconKey: 'cityHall',
    description: 'Serviços e canais oficiais',
    destinationType: 'internal',
    destination: 'cityHall',
    order: 50,
  ),
  UtilityItem(
    id: 'waterEnergy',
    name: 'Conta de Água e Energia',
    iconKey: 'waterEnergy',
    description: 'Informações e avisos sobre água e energia',
    destinationType: 'internal',
    destination: 'waterEnergy',
    order: 60,
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

List<UtilityItem> mergeWaterEnergyUtilities(Iterable<UtilityItem> source) {
  final items = source.toList();
  bool related(UtilityItem item) =>
      item.destinationType == 'internal' &&
      const {
        'water',
        'energy',
        'waterenergy',
      }.contains(item.destination.toLowerCase());
  final relatedItems = items.where(related).toList();
  if (relatedItems.isEmpty) return items;
  final combined = relatedItems.where(
    (item) => item.destination.toLowerCase() == 'waterenergy',
  );
  final first = combined.isNotEmpty ? combined.first : relatedItems.first;
  return [
    ...items.where((item) => !related(item)),
    UtilityItem(
      id: first.destination.toLowerCase() == 'waterenergy'
          ? first.id
          : 'waterEnergy',
      name: 'Conta de Água e Energia',
      iconKey: 'waterEnergy',
      description: 'Informações e avisos sobre água e energia',
      destinationType: 'internal',
      destination: 'waterEnergy',
      order: relatedItems
          .map((item) => item.order)
          .reduce((a, b) => a < b ? a : b),
      category: first.category,
      active: relatedItems.any((item) => item.active),
    ),
  ];
}

/// Keep the built-in utility destinations navigable when the Beta public
/// catalog has not been populated yet. Published remote entries override the
/// matching local shortcut, while unrelated Admin-created entries are kept.
List<UtilityItem> mergeAvailableUtilities(Iterable<UtilityItem> source) {
  final remote = source.where(_availableCityUtility).toList();
  final byDestination = <String, UtilityItem>{
    for (final item in remote)
      '${item.destinationType}:${item.destination.toLowerCase()}': item,
  };
  final fallbackKeys = fallbackUtilities
      .map(
        (item) => '${item.destinationType}:${item.destination.toLowerCase()}',
      )
      .toSet();
  final result = <UtilityItem>[
    for (final fallback in fallbackUtilities)
      byDestination.remove(
            '${fallback.destinationType}:${fallback.destination.toLowerCase()}',
          ) ??
          fallback,
    ...byDestination.values,
    ...remote
        .where(
          (item) => !fallbackKeys.contains(
            '${item.destinationType}:${item.destination.toLowerCase()}',
          ),
        )
        .where(
          (item) => !byDestination.containsKey(
            '${item.destinationType}:${item.destination.toLowerCase()}',
          ),
        ),
  ];
  // De-duplicate aliases that share a destination while retaining first order.
  final seen = <String>{};
  return mergeWaterEnergyUtilities(
    result.where(
      (item) =>
          seen.add('${item.destinationType}:${item.destination.toLowerCase()}'),
    ),
  );
}

void openUtilityDestination(BuildContext context, UtilityItem item) {
  if (!isSupportedUtilityDestination(item.destinationType, item.destination)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Este destino de utilidade não está disponível.'),
      ),
    );
    return;
  }
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
    'waterEnergy' => UtilitySubAreaPage(
      title: 'Conta de Água e Energia',
      coverAsset: 'assets/images/utility-water-energy-cover.png',
      subtitle: 'Informações e avisos cadastrados sobre água e energia.',
      iconKey: 'waterEnergy',
      items: const [
        UtilityItem(
          id: 'water-alerts',
          name: 'Conta de Água',
          iconKey: 'water',
          description: 'Interrupções e avisos quando publicados',
          destinationType: 'internal',
          destination: 'alerts',
          order: 10,
        ),
        UtilityItem(
          id: 'energy-alerts',
          name: 'Conta de Energia',
          iconKey: 'energy',
          description: 'Quedas, manutenção e avisos publicados',
          destinationType: 'internal',
          destination: 'alerts',
          order: 20,
        ),
      ],
    ),
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
      coverAsset: 'assets/images/utility-prefeitura-cover.png',
      subtitle:
          'Serviços, canais e orientações para resolver assuntos da cidade.',
      iconKey: 'cityHall',
      items: const [],
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
      ],
    ),
    'coupons' => const CouponsView(),
    'alerts' => const CityAlertsView(),
    'pharmacyDuty' => const PharmacyDutyView(),
    'emergency' => const EmergencyContactsView(),
    'resolver' => const ResolverGuideView(),
    'publicPlaces' => const PublicPlacesView(),
    'events' => cityAgendaForContext(context),
    'tourism' => const TourismHomeView(),
    'map' => const BusinessMapView(),
    'news' => const LocalNewsView(),
    'polls' => const PollsView(),
    'health' => UtilitySubAreaPage(
      title: 'Saúde',
      subtitle: 'Atalhos para emergência, unidades e conteúdos de saúde.',
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
        child: normalized == 'waterEnergy'
            ? SizedBox.square(
                dimension: iconSize ?? size * .86,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Icon(
                        Icons.receipt_long_rounded,
                        color: ocean,
                        size: (iconSize ?? size * .86) * .9,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: Icon(
                        Icons.water_drop_rounded,
                        color: sky,
                        size: (iconSize ?? size * .86) * .43,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Icon(
                        Icons.bolt_rounded,
                        color: orange,
                        size: (iconSize ?? size * .86) * .47,
                      ),
                    ),
                  ],
                ),
              )
            : App3DIcon(
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
    this.coverAsset,
  });

  final String title, subtitle, iconKey;
  final List<UtilityItem> items;
  final String? coverAsset;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Container(
          clipBehavior: coverAsset == null ? Clip.none : Clip.antiAlias,
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
          child: Stack(
            children: [
              if (coverAsset != null)
                Positioned.fill(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        coverAsset!,
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        cacheWidth: 1400,
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xED082B4C),
                              Color(0xB3082B4C),
                              Color(0x330056D6),
                            ],
                            stops: [0, .55, 1],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(18),
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

typedef UtilityInfoStreamFactory =
    Stream<List<Map<String, dynamic>>> Function(String collection);

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
    this.utilitiesStreamFactory,
  });

  final String title, subtitle, collection, searchHint, empty;
  final IconData icon;
  final bool phoneMode;
  final UtilityInfoStreamFactory? utilitiesStreamFactory;

  @override
  State<UtilityInfoPage> createState() => _UtilityInfoPageState();
}

class _UtilityInfoPageState extends State<UtilityInfoPage> {
  String query = '';
  late Stream<List<Map<String, dynamic>>> _itemsStream;

  @override
  void initState() {
    super.initState();
    _itemsStream = _createItemsStream();
  }

  Stream<List<Map<String, dynamic>>> _createItemsStream() =>
      widget.utilitiesStreamFactory?.call(widget.collection) ??
      watchPublicContent(
        widget.collection,
      ).map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());

  void _retry() {
    setState(() => _itemsStream = _createItemsStream());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: StreamBuilder<List<Map<String, dynamic>>>(
      stream: _itemsStream,
      builder: (context, snapshot) {
        final items = (snapshot.data ?? const <Map<String, dynamic>>[]).toList()
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
            if (snapshot.hasError)
              Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      const Icon(Icons.cloud_off_outlined, color: muted),
                      const SizedBox(height: 8),
                      const Text(
                        'Não foi possível carregar as informações.',
                        textAlign: TextAlign.center,
                      ),
                      TextButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              )
            else if (!snapshot.hasData)
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

typedef UtilityManagerStreamFactory =
    Stream<QuerySnapshot<Map<String, dynamic>>> Function();
typedef UtilityReorderHandler =
    Future<void> Function(List<UtilityItem> orderedItems);

class UtilityManager extends StatefulWidget {
  const UtilityManager({super.key, this.streamFactory, this.reorderHandler});

  final UtilityManagerStreamFactory? streamFactory;
  final UtilityReorderHandler? reorderHandler;

  @override
  State<UtilityManager> createState() => _UtilityManagerState();
}

class _UtilityManagerState extends State<UtilityManager> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _utilitiesStream;

  @override
  void initState() {
    super.initState();
    _utilitiesStream = _createStream();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _createStream() =>
      widget.streamFactory?.call() ??
      FirebaseFirestore.instance
          .collection(FirestoreCollections.utilities)
          .orderBy('order')
          .snapshots();

  void _retry() {
    setState(() => _utilitiesStream = _createStream());
  }

  Future<void> _move(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    int direction,
  ) async {
    final items = docs.map(UtilityItem.fromFirestore).toList();
    final reordered = reorderUtilityItems(items, doc.id, direction);
    final orderChanged = reordered.asMap().entries.any(
      (entry) => entry.value.id != items[entry.key].id,
    );
    if (!orderChanged) {
      return;
    }
    try {
      final handler = widget.reorderHandler;
      if (handler != null) {
        await handler(reordered);
      } else if (BetaEnvironment.enabled) {
        await SparkAdminContentRepository(
          FirebaseFirestore.instance,
        ).reorderUtilities([
          for (final item in reordered) (id: item.id, order: item.order),
        ]);
      } else {
        final batch = FirebaseFirestore.instance.batch();
        final references = {
          for (final entry in docs) entry.id: entry.reference,
        };
        for (final item in reordered) {
          batch.update(references[item.id]!, {
            'order': item.order,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
      final item = items.firstWhere((candidate) => candidate.id == doc.id);
      if (handler == null) {
        await recordAdminAudit(
          action: 'reorder',
          collection: 'utilities',
          documentId: doc.id,
          label: item.name,
        );
      }
    } catch (error) {
      debugPrint('Ordem da utilidade não alterada (${error.runtimeType}).');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível alterar a ordem.')),
        );
      }
    }
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
      stream: _utilitiesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, color: muted),
                  const SizedBox(height: 8),
                  const Text(
                    'Não foi possível carregar as utilidades.',
                    textAlign: TextAlign.center,
                  ),
                  TextButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          );
        }
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
                    onPressed: index == 0 ? null : () => _move(docs, doc, -1),
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  ),
                  IconButton(
                    tooltip: 'Descer',
                    onPressed: index == docs.length - 1
                        ? null
                        : () => _move(docs, doc, 1),
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
  const UtilityEditor({
    super.key,
    this.doc,
    this.sparkContentOperations,
    this.auditRecorder,
  });

  final DocumentSnapshot<Map<String, dynamic>>? doc;
  final SparkAdminContentOperations? sparkContentOperations;
  final AdminAuditRecorder? auditRecorder;

  @override
  State<UtilityEditor> createState() => _UtilityEditorState();
}

class _UtilityEditorState extends State<UtilityEditor> {
  SparkAdminContentOperations get _sparkContentOperations =>
      widget.sparkContentOperations ??
      SparkAdminContentRepository(FirebaseFirestore.instance);
  AdminAuditRecorder get _auditRecorder =>
      widget.auditRecorder ?? recordAdminAudit;
  late final TextEditingController name;
  late final TextEditingController description;
  late final TextEditingController category;
  late final TextEditingController destination;
  late final TextEditingController order;
  late String iconKey;
  late String destinationType;
  bool active = true;
  bool published = true;
  bool saving = false;
  String? validationError;

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
    category = TextEditingController(text: (data['category'] ?? '').toString());
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
    published =
        data['published'] as bool? ??
        !(BetaEnvironment.enabled && widget.doc == null);
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    category.dispose();
    destination.dispose();
    order.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final error = validateUtilityConfiguration(
      name: name.text,
      description: description.text,
      category: category.text,
      destinationType: destinationType,
      destination: destination.text,
      order: order.text,
    );
    if (error != null) {
      setState(() => validationError = error);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() {
      saving = true;
      validationError = null;
    });
    final data = {
      'name': name.text.trim(),
      'iconKey': iconKey,
      'description': description.text.trim(),
      'category': category.text.trim(),
      'destinationType': destinationType,
      'destination': destination.text.trim(),
      'order': int.tryParse(order.text.trim()) ?? 0,
      'active': active,
      'published': published,
      'updatedAt': FieldValue.serverTimestamp(),
      if (widget.doc == null) 'createdAt': FieldValue.serverTimestamp(),
    };
    try {
      final referenceId =
          widget.doc?.id ??
          _sparkContentOperations.reserveId(FirestoreCollections.utilities);
      if (BetaEnvironment.enabled) {
        await _sparkContentOperations.save(
          collection: FirestoreCollections.utilities,
          id: referenceId,
          data: data,
        );
      } else if (widget.doc == null) {
        await FirebaseFirestore.instance
            .collection(FirestoreCollections.utilities)
            .doc(referenceId)
            .set(data);
      } else {
        await widget.doc!.reference.set(data, SetOptions(merge: true));
      }
      await _auditRecorder(
        action: widget.doc == null ? 'create' : 'update',
        collection: 'utilities',
        documentId: referenceId,
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
    } catch (error) {
      debugPrint('Utilidade não salva (${error.runtimeType}).');
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
    final utilityName = name.text.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir utilidade?'),
        content: Text('Tem certeza de que deseja excluir “$utilityName”?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (BetaEnvironment.enabled) {
        await _sparkContentOperations.softDelete(
          collection: 'utilities',
          id: doc.id,
        );
      } else {
        await doc.reference.delete();
      }
      await _auditRecorder(
        action: 'delete',
        collection: 'utilities',
        documentId: doc.id,
        label: utilityName,
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
        if (validationError != null) ...[
          Semantics(
            liveRegion: true,
            child: Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(validationError!),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: name,
          onChanged: (_) => setState(() => validationError = null),
          decoration: const InputDecoration(
            labelText: 'Nome',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: description,
          maxLines: 2,
          onChanged: (_) => setState(() => validationError = null),
          decoration: const InputDecoration(
            labelText: 'Descrição curta',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: category,
          maxLength: 60,
          onChanged: (_) => setState(() => validationError = null),
          decoration: const InputDecoration(
            labelText: 'Categoria',
            helperText: 'Opcional. A categoria organiza os atalhos públicos.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        UtilityIconPicker(
          value: iconKey,
          onChanged: (value) => setState(() => iconKey = value),
        ),
        const SizedBox(height: 14),
        SwitchListTile(
          value: published,
          onChanged: saving
              ? null
              : (value) => setState(() => published = value),
          title: const Text('Publicado'),
          subtitle: const Text('Desative para manter como rascunho.'),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: active,
          onChanged: saving ? null : (value) => setState(() => active = value),
          title: const Text('Ativo'),
          contentPadding: EdgeInsets.zero,
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
          onChanged: (value) => setState(() {
            destinationType = value ?? destinationType;
            validationError = null;
          }),
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
            onChanged: (value) => setState(() {
              destination.text = value ?? '';
              validationError = null;
            }),
          )
        else
          TextField(
            controller: destination,
            keyboardType: switch (destinationType) {
              'phone' => TextInputType.phone,
              'whatsapp' => TextInputType.text,
              _ => TextInputType.url,
            },
            onChanged: (_) => setState(() => validationError = null),
            decoration: InputDecoration(
              labelText: switch (destinationType) {
                'url' => 'Endereço HTTPS',
                'phone' => 'Telefone',
                'whatsapp' => 'Telefone ou link wa.me',
                'map' => 'URL HTTPS ou URI geo',
                _ => 'Destino',
              },
              helperText: switch (destinationType) {
                'url' => 'Informe uma URL HTTPS começando com https://.',
                'phone' => 'Informe o número com DDD; use de 8 a 15 dígitos.',
                'whatsapp' =>
                  'Informe um telefone ou https://wa.me/ seguido dos dígitos.',
                'map' => 'Aceita URL HTTPS ou URI geo com caminho preenchido.',
                _ => null,
              },
              border: OutlineInputBorder(),
            ),
          ),
        const SizedBox(height: 14),
        TextField(
          controller: order,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() => validationError = null),
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

typedef UtilityItemsStreamFactory = Stream<List<UtilityItem>> Function();

class ResourcesHub extends StatefulWidget {
  const ResourcesHub({super.key, this.utilitiesStreamFactory});

  final UtilityItemsStreamFactory? utilitiesStreamFactory;

  @override
  State<ResourcesHub> createState() => _ResourcesHubState();
}

class _ResourcesHubState extends State<ResourcesHub> {
  String query = '';
  String selectedCategory = 'Todas';
  late Stream<List<UtilityItem>> _utilitiesStream;

  @override
  void initState() {
    super.initState();
    _utilitiesStream = _createUtilitiesStream();
  }

  Stream<List<UtilityItem>> _createUtilitiesStream() =>
      widget.utilitiesStreamFactory?.call() ??
      watchPublicContent(FirestoreCollections.utilities).map(
        (snapshot) => snapshot.docs
            .map((doc) => UtilityItem.fromData(doc.id, doc.data()))
            .toList(),
      );

  void _retryUtilities() {
    setState(() => _utilitiesStream = _createUtilitiesStream());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: soft,
    appBar: AppBar(title: const Text('Utilidades')),
    body: StreamBuilder<List<UtilityItem>>(
      stream: _utilitiesStream,
      builder: (context, snapshot) {
        final items = mergeAvailableUtilities(
          snapshot.data ?? const <UtilityItem>[],
        )..sort((a, b) => a.order.compareTo(b.order));
        final categories = groupUtilitiesByCategory(items).keys.toList();
        final effectiveCategory = categories.contains(selectedCategory)
            ? selectedCategory
            : 'Todas';
        final categoryItems = effectiveCategory == 'Todas'
            ? items
            : items.where(
                (item) =>
                    (item.category.trim().isEmpty
                        ? 'Geral'
                        : item.category.trim()) ==
                    effectiveCategory,
              );
        final filtered = categoryItems.where((item) {
          final needle = query.toLowerCase().trim();
          if (needle.isEmpty) return true;
          return '${item.name} ${item.category} ${item.description} ${item.destination}'
              .toLowerCase()
              .contains(needle);
        }).toList();
        final groups = groupUtilitiesByCategory(filtered);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: ocean,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: ocean.withValues(alpha: .12),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      alignment: const Alignment(.65, 0),
                      // Display only the banner inside the supplied file's light frame.
                      // The asset itself remains unchanged.
                      child: SizedBox(
                        width: 2022,
                        height: 526,
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.topLeft,
                            minWidth: 2086,
                            maxWidth: 2086,
                            minHeight: 754,
                            maxHeight: 754,
                            child: Transform.translate(
                              offset: const Offset(-32, -110),
                              child: Image.asset(
                                'assets/images/utilities-main-cover.png',
                                width: 2086,
                                height: 754,
                                cacheWidth: 1400,
                                fit: BoxFit.fill,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xCC082B4C),
                            Color(0x990056D6),
                            Color(0x11007BFF),
                          ],
                          stops: [0, .55, 1],
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: .62,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Utilidades',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.4,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Tudo que você precisa no dia a dia em Cachoeiras de Macacu',
                              style: TextStyle(
                                color: Color(0xFFF0F7FF),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
            if (categories.isNotEmpty)
              Semantics(
                label: 'Filtrar utilidades por categoria',
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final category in ['Todas', ...categories])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            key: ValueKey('utility-category-$category'),
                            label: Text(category),
                            selected: effectiveCategory == category,
                            onSelected: (_) =>
                                setState(() => selectedCategory = category),
                            selectedColor: orange,
                            labelStyle: TextStyle(
                              color: effectiveCategory == category
                                  ? Colors.white
                                  : ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            if (snapshot.hasError)
              Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      const Icon(Icons.cloud_off_outlined, color: muted),
                      const SizedBox(height: 8),
                      const Text(
                        'Não foi possível carregar as utilidades.',
                        textAlign: TextAlign.center,
                      ),
                      TextButton.icon(
                        onPressed: _retryUtilities,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              )
            else if (!snapshot.hasData)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhuma utilidade encontrada.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
              )
            else
              ...groups.entries.map(
                (group) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (group.key != 'Geral' || groups.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 9),
                        child: Semantics(
                          header: true,
                          child: Text(
                            group.key,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: ink,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final enlargedText =
                            MediaQuery.textScalerOf(context).scale(1) > 1.2;
                        final columns = enlargedText
                            ? 1
                            : constraints.maxWidth >= 760
                            ? 3
                            : constraints.maxWidth >= 520
                            ? 2
                            : 1;
                        if (columns == 1) {
                          return Column(
                            children: group.value
                                .map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: UtilityGridCard(item: item),
                                  ),
                                )
                                .toList(),
                          );
                        }
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: group.value.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 1.0,
                              ),
                          itemBuilder: (context, index) =>
                              UtilityGridCard(item: group.value[index]),
                        );
                      },
                    ),
                  ],
                ),
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
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadii.card),
      onTap: () => openUtilityDestination(context, item),
      child: Ink(
        color: Colors.white,
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
                  color: AppColors.orange.withValues(alpha: .09),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Icon(
                Icons.arrow_forward_rounded,
                color: AppColors.sky.withValues(alpha: .55),
                size: 20,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                38,
                30,
              ),
              child: Row(
                children: [
                  UtilityIconBadge(iconKey: item.iconKey, size: 58),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          softWrap: true,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          item.description.isEmpty
                              ? 'Toque para abrir'
                              : item.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.muted, height: 1.25),
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
              leading: BusinessAvatar(
                business: business,
                size: 48,
                iconFallback: _businessIconFallback(business, size: 38),
              ),
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

class FirestoreContentList extends StatefulWidget {
  const FirestoreContentList({
    super.key,
    required this.collection,
    required this.empty,
    this.actionLabel = 'Abrir',
    this.streamFactory,
    this.jobDetailsRepository,
  });
  final String collection, empty, actionLabel;

  /// Override point for deterministic widget tests; production uses the
  /// secure public-content repository below.
  final Stream<PublicContentSnapshot> Function(String collection)?
  streamFactory;

  /// Optional test seam; job details remain demo-only regardless of injection.
  final PublicJobDetailsRepository? jobDetailsRepository;

  @override
  State<FirestoreContentList> createState() => _FirestoreContentListState();
}

class _FirestoreContentListState extends State<FirestoreContentList> {
  static const _jobCardFields = {
    'title',
    'description',
    'location',
    'address',
    'imageUrl',
    'galleryUrls',
  };

  StreamSubscription<PublicContentSnapshot>? _subscription;
  PublicContentSnapshot? _snapshot;
  Object? _error;
  int _generation = 0;
  bool _refreshing = false;

  bool get _canOpenJobDetails {
    if (widget.collection != 'jobs' || !LocalSearchEnvironment.enabled) {
      return false;
    }
    try {
      LocalSearchEnvironment.requireDemo(LocalSearchEnvironment.project);
      return true;
    } on StateError {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _restart(clearSnapshot: true);
  }

  @override
  void didUpdateWidget(covariant FirestoreContentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collection != widget.collection ||
        oldWidget.streamFactory != widget.streamFactory) {
      _snapshot = null;
      _restart(clearSnapshot: true, force: true);
    }
  }

  void _restart({required bool clearSnapshot, bool force = false}) {
    if (_refreshing && !force) return;
    final generation = ++_generation;
    final previous = _subscription;
    _subscription = null;
    if (mounted) {
      setState(() {
        if (clearSnapshot) _snapshot = null;
        _error = null;
        _refreshing = true;
      });
    }
    if (previous != null) unawaited(previous.cancel());
    if (!mounted || generation != _generation) return;

    try {
      final stream = (widget.streamFactory ?? watchPublicContent)(
        widget.collection,
      );
      _subscription = stream.listen(
        (snapshot) {
          if (!mounted || generation != _generation) return;
          setState(() {
            _snapshot = snapshot;
            _error = null;
            _refreshing = false;
          });
        },
        onError: (Object error, StackTrace stack) {
          if (!mounted || generation != _generation) return;
          setState(() {
            _error = error;
            _refreshing = false;
          });
        },
      );
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _refreshing = false;
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }

  Widget _retryButton({required bool prominent}) => prominent
      ? FilledButton.icon(
          onPressed: _refreshing ? null : () => _restart(clearSnapshot: false),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        )
      : TextButton.icon(
          onPressed: _refreshing ? null : () => _restart(clearSnapshot: false),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Tentar novamente'),
        );

  Widget _initialState() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, color: muted, size: 36),
              const SizedBox(height: 12),
              const Text(
                'Não foi possível carregar este conteúdo.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              _retryButton(prominent: true),
            ],
          ),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }

  Widget _content(BuildContext context) {
    final snapshot = _snapshot;
    if (snapshot == null) return _initialState();
    final documents = snapshot.docs
        .where((document) => isActiveContent(document.data()))
        .toList();
    final canOpenJobDetails = _canOpenJobDetails;

    return Column(
      children: [
        if (_refreshing) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Material(
            color: const Color(0xFFFFF4E5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Não foi possível atualizar. Tente novamente.',
                      style: TextStyle(color: ink, fontSize: 12),
                    ),
                  ),
                  _retryButton(prominent: false),
                ],
              ),
            ),
          ),
        if (documents.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(widget.empty, textAlign: TextAlign.center),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: documents.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final document = documents[i];
                final data = document.data();
                final cardData = widget.collection == 'jobs'
                    ? {
                        for (final key in _jobCardFields)
                          if (data.containsKey(key)) key: data[key],
                      }
                    : data;
                return LocalContentCard(
                  item: cardData,
                  actionLabel: widget.actionLabel,
                  onOpen: canOpenJobDetails
                      ? () {
                          LocalSearchEnvironment.requireDemo(
                            LocalSearchEnvironment.project,
                          );
                          final repository =
                              widget.jobDetailsRepository ??
                              PublicJobDetailsRepository();
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => JobDetailPage(
                                jobId: document.id,
                                resolveJob: repository.resolveById,
                              ),
                            ),
                          );
                        }
                      : null,
                  metricAction: widget.collection == 'coupons'
                      ? 'coupon_open'
                      : null,
                  metricTargetType: widget.collection,
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => _content(context);
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
    this.externalActionLabel,
    this.metricAction,
    this.metricTargetType,
    this.onOpen,
    this.shareContent,
    this.trailingAction,
    this.wrapActionsOnLargeText = false,
  });

  final Map<String, dynamic> item;
  final String actionLabel;
  final String? externalActionLabel;
  final String? metricAction;
  final String? metricTargetType;
  final VoidCallback? onOpen;
  final PublicShareContent? shareContent;
  final Widget? trailingAction;
  final bool wrapActionsOnLargeText;

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

    final actionWidgets = <Widget>[
      ?trailingAction,
      if (shareContent != null)
        PublicShareButton(
          content: shareContent!,
          tooltip: 'Compartilhar $title',
        ),
      TextButton(
        onPressed: actionUrl.isNotEmpty
            ? openContentLink
            : onOpen ?? openContentLink,
        child: Text(
          actionUrl.isNotEmpty
              ? externalActionLabel ?? actionLabel
              : actionLabel,
        ),
      ),
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onOpen ?? (actionUrl.isEmpty ? null : openContentLink),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (images.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.control),
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
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
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
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.muted,
                    height: 1.45,
                  ),
                ),
              ],
              if (additionalInfo.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(additionalInfo, style: const TextStyle(fontSize: 12)),
              ],
              if (actionUrl.isNotEmpty || onOpen != null) ...[
                const SizedBox(height: 8),
                if (wrapActionsOnLargeText &&
                    MediaQuery.textScalerOf(context).scale(1) > 1.2)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 4,
                      children: actionWidgets,
                    ),
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actionWidgets,
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
  const LocalJobsView({
    super.key,
    this.streamFactory,
    this.jobDetailsRepository,
  });

  final Stream<PublicContentSnapshot> Function(String collection)?
  streamFactory;
  final PublicJobDetailsRepository? jobDetailsRepository;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Vagas em Macacu')),
    body: FirestoreContentList(
      collection: 'jobs',
      empty: 'Não há vagas publicadas no momento.',
      actionLabel: 'Ver vaga',
      streamFactory: streamFactory,
      jobDetailsRepository: jobDetailsRepository,
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

/// Mantém compatibilidade com os acessos antigos para a mesma área Turismo.
class TouristRoutesView extends StatelessWidget {
  const TouristRoutesView({super.key});
  @override
  Widget build(BuildContext context) => const TourismHomeView();
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
    body: StreamBuilder<PublicContentSnapshot>(
      stream: watchPublicContent(FirestoreCollections.polls),
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
                        onPressed:
                            !isRegisteredUser(FirebaseAuth.instance.currentUser)
                            ? null
                            : () async {
                                try {
                                  await writeUserOperation('vote', {
                                    'pollId': d.id,
                                    'option': option,
                                  });
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Não foi possível registrar o voto. Tente novamente em instantes.',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
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
      await writeUserOperation('proposal', {
        'name': name.text.trim(),
        'contact': contact.text.trim(),
        'details': details.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recebido. Você fará a revisão antes de publicar.'),
          ),
        );
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível enviar agora. Tente novamente em instantes.',
            ),
          ),
        );
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

class NotificationsView extends StatefulWidget {
  const NotificationsView({super.key, this.notifications});
  final Stream<List<Map<String, dynamic>>>? notifications;

  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  int _retryGeneration = 0;

  void _retry() => setState(() => _retryGeneration++);

  @override
  Widget build(BuildContext context) {
    if (widget.notifications != null) {
      return _content(widget.notifications!);
    }
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, auth) => _content(
        NotificationRepository().watch(
          uid: isRegisteredUser(auth.data) ? auth.data!.uid : null,
        ),
        uid: auth.data?.uid,
      ),
    );
  }

  Widget _content(
    Stream<List<Map<String, dynamic>>> stream, {
    String? uid,
  }) => Scaffold(
    appBar: AppBar(title: const Text('Notificações')),
    body: StreamBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('notifications:${uid ?? 'public'}:$_retryGeneration'),
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Não foi possível carregar as notificações.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = (snapshot.data?.where(isActiveContent).toList() ?? [])
          ..sort(
            (a, b) =>
                ((b['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
                    .compareTo(
                      (a['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ??
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
    try {
      final notificationId = await NotificationRepository().send(
        title: title.text,
        description: message.text,
        link: link.text,
        recipientEmail: sendToAll ? null : recipient.text,
      );
      await recordAdminAudit(
        action: 'send_notification',
        collection: sendToAll
            ? FirestoreCollections.notifications
            : FirestoreCollections.privateNotifications,
        documentId: notificationId,
        label: title.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notificação preparada para envio.')),
        );
        Navigator.pop(context);
      }
    } on NotificationRecipientException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi encontrada uma conta única para esse e-mail.',
            ),
          ),
        );
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
    if (!isRegisteredUser(user)) {
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
      await writeUserOperation('review', {
        'businessId': widget.business.id,
        'message': message.text.trim(),
        'stars': stars,
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível enviar agora. Tente novamente em instantes.',
            ),
          ),
        );
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
    if (!isAdminUser(FirebaseAuth.instance.currentUser, context: context)) {
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

CityAgendaView cityAgendaForContext(BuildContext context) {
  final shell = context.findAncestorStateOfType<_CityShellState>();
  return CityAgendaView(
    savedEventIds: shell?.savedAgendaEventIds ?? const <String>{},
    isAuthenticated: isRegisteredUser(shell?.widget.user),
    onToggleAgenda: shell?.toggleEventAgenda,
    onOpenMyAgenda: shell?.openMyAgenda,
  );
}

void openFeature(BuildContext context, Feature feature) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => feature == Feature.tourism
          ? const TourismHomeView()
          : feature == Feature.events
          ? cityAgendaForContext(context)
          : FeatureView(feature: feature),
    ),
  );
}

typedef TourismRoutesStreamFactory = Stream<PublicContentSnapshot> Function();
typedef TourismConfigStreamFactory = Stream<Map<String, dynamic>?> Function();

class TourismHomeView extends StatefulWidget {
  const TourismHomeView({
    super.key,
    this.routesStreamFactory,
    this.configStreamFactory,
    this.adminOverride,
    this.initialCategoryKey,
    this.savedTourismIds = const <String>{},
    this.favoriteTourism,
  });

  final TourismRoutesStreamFactory? routesStreamFactory;
  final TourismConfigStreamFactory? configStreamFactory;
  final bool? adminOverride;
  final String? initialCategoryKey;
  final Set<String> savedTourismIds;
  final ValueChanged<TouristSpot>? favoriteTourism;

  @override
  State<TourismHomeView> createState() => _TourismHomeViewState();
}

class _TourismHomeViewState extends State<TourismHomeView> {
  final _searchController = TextEditingController();
  Stream<User?>? _authStream;
  late Stream<PublicContentSnapshot> _routesStream;
  late Stream<Map<String, dynamic>?> _configStream;
  PublicContentSnapshot? _lastRoutesSnapshot;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _editTourismSpot(TouristSpot spot) async {
    if (!isAdminUser(FirebaseAuth.instance.currentUser, context: context)) {
      return;
    }
    try {
      final document = await FirebaseFirestore.instance
          .collection(FirestoreCollections.routes)
          .doc(spot.id)
          .get();
      if (!mounted) return;
      if (!document.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este conteúdo não está mais disponível.'),
          ),
        );
        return;
      }
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ContentEditor(collection: 'routes', doc: document),
        ),
      );
    } on FirebaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir a edição deste conteúdo.'),
          ),
        );
      }
    }
  }

  Stream<PublicContentSnapshot> _defaultRoutesStream() =>
      watchPublicContent(FirestoreCollections.routes);

  Stream<Map<String, dynamic>?> _defaultConfigStream() {
    if (BetaEnvironment.enabled) return Stream.value(null);
    return FirebaseFirestore.instance
        .collection(FirestoreCollections.homePages)
        .doc('published')
        .snapshots()
        .map((snapshot) {
          final value = snapshot.data()?['tourism'];
          return value is Map ? Map<String, dynamic>.from(value) : null;
        });
  }

  @override
  void initState() {
    super.initState();
    if (widget.adminOverride == null) {
      _authStream = FirebaseAuth.instance.authStateChanges();
    }
    _routesStream = (widget.routesStreamFactory ?? _defaultRoutesStream)();
    _configStream = (widget.configStreamFactory ?? _defaultConfigStream)();
  }

  @override
  void didUpdateWidget(covariant TourismHomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adminOverride != widget.adminOverride) {
      _authStream = widget.adminOverride == null
          ? FirebaseAuth.instance.authStateChanges()
          : null;
    }
    if (oldWidget.routesStreamFactory != widget.routesStreamFactory) {
      _routesStream = (widget.routesStreamFactory ?? _defaultRoutesStream)();
    }
    if (oldWidget.configStreamFactory != widget.configStreamFactory) {
      _configStream = (widget.configStreamFactory ?? _defaultConfigStream)();
    }
  }

  void _retryRoutes() {
    setState(() {
      _routesStream = (widget.routesStreamFactory ?? _defaultRoutesStream)();
    });
  }

  void _retryConfig() {
    setState(() {
      _configStream = (widget.configStreamFactory ?? _defaultConfigStream)();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.adminOverride != null) {
      return _build(context, widget.adminOverride!);
    }
    return StreamBuilder<User?>(
      stream: _authStream!,
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, auth) =>
          _build(context, isAdminUser(auth.data, context: context)),
    );
  }

  Future<void> _edit(
    BuildContext context,
    Map<String, dynamic> data, {
    String? categoryKey,
  }) async {
    if (!isAdminUser(FirebaseAuth.instance.currentUser)) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TourismConfigEditor(
          data: data,
          category: categoryKey != null,
          mediaHelper: const CloudinaryUploadHelper(),
          onSave: (value) async {
            if (!isAdminUser(FirebaseAuth.instance.currentUser)) {
              throw StateError('Acesso administrativo necessário');
            }
            final patch = categoryKey == null
                ? value
                : {
                    'categories': {categoryKey: value},
                  };
            await FirebaseFirestore.instance
                .collection(FirestoreCollections.homePages)
                .doc('published')
                .set({
                  'tourism': patch,
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
            await recordAdminAudit(
              action: 'update_tourism',
              collection: 'home_pages',
              documentId: 'published',
              label: categoryKey ?? 'Hero Turismo',
            );
          },
        ),
      ),
    );
  }

  Widget _tourismSearchResults(List<TouristSpot> spots, bool admin) {
    final query = _searchController.text.trim().toLowerCase();
    final results = spots
        .where((spot) {
          return [
            spot.title,
            spot.description,
            spot.location,
            spot.category,
            _tourismHomeCategoryName(TourismCategory.normalize(spot.category)),
          ].any((value) => value.toLowerCase().contains(query));
        })
        .toList(growable: false);
    if (results.isEmpty) {
      return const Padding(
        key: ValueKey('tourism-search-results'),
        padding: EdgeInsets.all(24),
        child: Text(
          'Nenhum conteúdo cadastrado corresponde à busca.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      key: const ValueKey('tourism-search-results'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Resultados',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ),
        for (final spot in results)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TouristSpotCard(
              spot: spot,
              admin: admin,
              saved: widget.savedTourismIds.contains(spot.id),
              onFavorite: widget.favoriteTourism == null
                  ? null
                  : () => widget.favoriteTourism!(spot),
              onEdit: () => _editTourismSpot(spot),
            ),
          ),
      ],
    );
  }

  Widget _build(BuildContext context, bool admin) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.initialCategoryKey == null
            ? 'Explorar Macacu'
            : _tourismHomeCategoryName(widget.initialCategoryKey!),
      ),
      actions: [
        if (admin)
          IconButton(
            tooltip: 'Gerenciar conteúdos de Explorar Macacu',
            icon: const Icon(Icons.edit_note),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ContentManager(
                  collection: 'routes',
                  title: 'Explorar Macacu',
                ),
              ),
            ),
          ),
      ],
    ),
    body: StreamBuilder<Map<String, dynamic>?>(
      stream: _configStream,
      builder: (context, configSnapshot) {
        final config = TourismConfig.fromMap(configSnapshot.data ?? const {});
        return StreamBuilder<PublicContentSnapshot>(
          stream: _routesStream,
          builder: (context, snapshot) {
            if (snapshot.hasData) _lastRoutesSnapshot = snapshot.data;
            final cachedSnapshot = _lastRoutesSnapshot;
            final hasData = snapshot.hasData || cachedSnapshot != null;
            final spots =
                (snapshot.data ?? cachedSnapshot)?.docs
                    .map((doc) => TouristSpot.fromData(doc.id, doc.data()))
                    .toList() ??
                <TouristSpot>[];
            spots.sort((a, b) {
              final order = a.order.compareTo(b.order);
              return order == 0 ? a.title.compareTo(b.title) : order;
            });
            if (widget.initialCategoryKey != null && !hasData) {
              final selectedCategory = config.categories
                  .firstWhere(
                    (item) => item.key == widget.initialCategoryKey,
                    orElse: () => config.categories.first,
                  )
                  .name;
              return Center(
                child: snapshot.hasError
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_outlined),
                          const SizedBox(height: 8),
                          Text(
                            'Não foi possível carregar os locais de $selectedCategory.',
                            textAlign: TextAlign.center,
                          ),
                          TextButton.icon(
                            onPressed: _retryRoutes,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Tentar novamente'),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            semanticsLabel: 'Carregando locais turísticos',
                          ),
                          const SizedBox(height: 12),
                          Text('Carregando locais de $selectedCategory…'),
                        ],
                      ),
              );
            }
            if (widget.initialCategoryKey != null && hasData) {
              final category = config.categories.firstWhere(
                (item) => item.key == widget.initialCategoryKey,
                orElse: () => config.categories.first,
              );
              return Column(
                children: [
                  if (snapshot.hasError && hasData)
                    MaterialBanner(
                      content: const Text(
                        'Não foi possível atualizar os locais. Os dados anteriores continuam disponíveis.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: _retryRoutes,
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: TourismCategoryView(
                      title: category.name,
                      categoryKey: widget.initialCategoryKey,
                      spots: spots,
                      admin: admin,
                      onEditSpot: _editTourismSpot,
                      savedTourismIds: widget.savedTourismIds,
                      favoriteTourism: widget.favoriteTourism,
                      embedded: true,
                    ),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (!BetaEnvironment.enabled)
                  TextField(
                    key: const ValueKey('tourism-global-search'),
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: 'Buscar em Explorar Macacu',
                      hintText: 'Pontos, trilhas, guias e história',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpar busca',
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (configSnapshot.connectionState == ConnectionState.waiting &&
                    !configSnapshot.hasData)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Carregando configuração de Turismo',
                  ),
                if (configSnapshot.hasError)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.cloud_off_outlined),
                      title: const Text(
                        'Não foi possível carregar a configuração de Turismo.',
                      ),
                      trailing: TextButton(
                        onPressed: _retryConfig,
                        child: const Text('Tentar novamente'),
                      ),
                    ),
                  ),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !hasData)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: 'Carregando locais turísticos',
                      ),
                    ),
                  ),
                if (snapshot.hasError && !hasData)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.cloud_off_outlined),
                      title: const Text(
                        'Não foi possível carregar os locais turísticos.',
                      ),
                      trailing: TextButton(
                        onPressed: _retryRoutes,
                        child: const Text('Tentar novamente'),
                      ),
                    ),
                  ),
                if (_searchController.text.trim().isNotEmpty)
                  _tourismSearchResults(spots, admin)
                else
                  TourismOverview(
                    config: config,
                    iconBuilder: (key) =>
                        App3DIcon(icon: AppIcon.fromKey(key), size: 56),
                    admin: admin,
                    onEditHero: () => _edit(context, config.toMap()),
                    onEditCategory: (c) =>
                        _edit(context, c.toMap(), categoryKey: c.key),
                    onCategoryTap: (c) {
                      if (!hasData) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              snapshot.hasError
                                  ? 'Atualize os locais antes de abrir a categoria.'
                                  : 'Aguarde o carregamento dos locais.',
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TourismCategoryView(
                            title: c.name,
                            categoryKey: c.key,
                            spots: spots,
                            admin: admin,
                            onEditSpot: _editTourismSpot,
                            savedTourismIds: widget.savedTourismIds,
                            favoriteTourism: widget.favoriteTourism,
                          ),
                        ),
                      );
                    },
                  ),
                if (snapshot.hasError && hasData)
                  MaterialBanner(
                    content: const Text(
                      'Não foi possível atualizar os locais. Os dados anteriores continuam disponíveis.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: _retryRoutes,
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                if (hasData && !snapshot.hasError && spots.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('Nenhum local publicado ainda.'),
                  ),
              ],
            );
          },
        );
      },
    ),
  );
}

class TourismCategoryView extends StatefulWidget {
  const TourismCategoryView({
    super.key,
    required this.title,
    required this.spots,
    this.categoryKey,
    this.embedded = false,
    this.admin = false,
    this.onEditSpot,
    this.savedTourismIds = const <String>{},
    this.favoriteTourism,
  });
  final String title;
  final String? categoryKey;
  final List<TouristSpot> spots;
  final bool embedded;
  final bool admin;
  final ValueChanged<TouristSpot>? onEditSpot;
  final Set<String> savedTourismIds;
  final ValueChanged<TouristSpot>? favoriteTourism;

  @override
  State<TourismCategoryView> createState() => _TourismCategoryViewState();
}

bool _isSafeTourismMapDestination(String value) {
  final target = value.trim();
  if (target.isEmpty) return true;
  final uri = Uri.tryParse(target);
  return uri != null &&
      isAllowedExternalUri(uri) &&
      const {'https', 'geo'}.contains(uri.scheme.toLowerCase());
}

Future<void> _openTourismMap(
  BuildContext context,
  TouristSpot spot,
  Future<void> Function(String destination)? onOpenMap,
) async {
  final destination = spot.mapDestination;
  if (destination.isEmpty) return;
  try {
    if (onOpenMap != null) {
      await onOpenMap(destination);
    } else {
      await openUrl(context, destination, 'Como chegar');
    }
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Não foi possível abrir o mapa.')),
    );
  }
}

bool _isSafeHttpsEventUrl(String value) {
  final target = value.trim();
  if (target.isEmpty) return true;
  final uri = Uri.tryParse(target);
  return uri != null &&
      uri.scheme.toLowerCase() == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

class _TourismCategoryViewState extends State<TourismCategoryView> {
  final _searchController = TextEditingController();
  String _searchField = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _categoryLabel(String category) {
    final normalized = TourismCategory.normalize(category);
    if (normalized == 'roteiros') return 'Roteiros existentes';
    for (final value in TourismCategory.values) {
      if (value.key == normalized) return value.name;
    }
    return category;
  }

  List<TouristSpot> _visibleSpots() {
    final query = _searchController.text.trim().toLowerCase();
    final visible = widget.spots.where((spot) {
      final normalizedCategory = TourismCategory.normalize(spot.category);
      final selectedCategory = widget.categoryKey;
      final inCategory =
          selectedCategory == null ||
          normalizedCategory == selectedCategory ||
          (selectedCategory == 'guias_turisticos' &&
              normalizedCategory == 'roteiros');
      if (!inCategory) return false;
      if (query.isEmpty) return true;
      final values = switch (_searchField) {
        'title' => [spot.title],
        'location' => [spot.location],
        'description' => [spot.description],
        _ => [
          spot.title,
          spot.location,
          spot.description,
          spot.category,
          _categoryLabel(spot.category),
        ],
      };
      return values.any((value) => value.toLowerCase().contains(query));
    }).toList();
    visible.sort((a, b) {
      final order = a.order.compareTo(b.order);
      return order == 0 ? a.title.compareTo(b.title) : order;
    });
    return visible;
  }

  Widget _list(List<TouristSpot> items) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            _searchController.text.trim().isEmpty
                ? 'Nenhum local cadastrado nesta categoria ainda.'
                : 'Nenhum local corresponde à busca.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final legacyRoteiros = widget.categoryKey == 'guias_turisticos'
        ? items
              .where(
                (spot) =>
                    TourismCategory.normalize(spot.category) == 'roteiros',
              )
              .toList(growable: false)
        : const <TouristSpot>[];
    final guides = legacyRoteiros.isEmpty
        ? items
        : items.where((spot) => !legacyRoteiros.contains(spot)).toList();
    final showLegacyHeading = legacyRoteiros.isNotEmpty;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      itemCount:
          guides.length + legacyRoteiros.length + (showLegacyHeading ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (_, index) {
        if (index < guides.length) {
          final spot = guides[index];
          return TouristSpotCard(
            spot: spot,
            admin: widget.admin,
            saved: widget.savedTourismIds.contains(spot.id),
            onFavorite: widget.favoriteTourism == null
                ? null
                : () => widget.favoriteTourism!(spot),
            onEdit: widget.onEditSpot == null
                ? null
                : () => widget.onEditSpot!(spot),
          );
        }
        if (showLegacyHeading && index == guides.length) {
          return Padding(
            padding: EdgeInsets.only(top: 10),
            child: Semantics(
              header: true,
              child: Text(
                'Roteiros existentes',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ),
          );
        }
        final legacyIndex = index - guides.length - (showLegacyHeading ? 1 : 0);
        final spot = legacyRoteiros[legacyIndex];
        return TouristSpotCard(
          spot: spot,
          admin: widget.admin,
          saved: widget.savedTourismIds.contains(spot.id),
          onFavorite: widget.favoriteTourism == null
              ? null
              : () => widget.favoriteTourism!(spot),
          onEdit: widget.onEditSpot == null
              ? null
              : () => widget.onEditSpot!(spot),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _visibleSpots();
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            children: [
              if (!BetaEnvironment.enabled)
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Buscar locais',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpar busca',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              if (!BetaEnvironment.enabled) const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _searchField,
                decoration: const InputDecoration(
                  labelText: 'Pesquisar em',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'all',
                    child: Text('Todos os campos'),
                  ),
                  DropdownMenuItem(value: 'title', child: Text('Nome')),
                  DropdownMenuItem(
                    value: 'location',
                    child: Text('Localização'),
                  ),
                  DropdownMenuItem(
                    value: 'description',
                    child: Text('Descrição'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _searchField = value);
                },
              ),
            ],
          ),
        ),
        Expanded(child: _list(items)),
      ],
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: content,
    );
  }
}

String _tourismHomeCategoryName(String key) =>
    const {
      'pontos_turisticos': 'Pontos turísticos',
      'trilhas': 'Trilhas',
      'guias_turisticos': 'Guias turísticos',
      'historia_cidade': 'História da cidade',
    }[key] ??
    'Turismo';

Future<void> _openTourismSpotEditor(BuildContext context, String id) async {
  if (!isAdminUser(FirebaseAuth.instance.currentUser, context: context)) return;
  try {
    final document = await FirebaseFirestore.instance
        .collection(FirestoreCollections.routes)
        .doc(id)
        .get();
    if (!context.mounted) return;
    if (!document.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este conteúdo não está mais disponível.'),
        ),
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ContentEditor(collection: 'routes', doc: document),
      ),
    );
  } on FirebaseException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir a edição deste conteúdo.'),
        ),
      );
    }
  }
}

class TouristSpotCard extends StatelessWidget {
  const TouristSpotCard({
    super.key,
    required this.spot,
    this.admin = false,
    this.onEdit,
    this.saved = false,
    this.onFavorite,
    this.onShare,
    this.onOpenMap,
  });

  final TouristSpot spot;
  final bool admin;
  final VoidCallback? onEdit;
  final bool saved;
  final VoidCallback? onFavorite;
  final Future<void> Function(PublicShareContent content)? onShare;
  final Future<void> Function(String destination)? onOpenMap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadii.card),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TouristSpotDetailView(
            spot: spot,
            admin: admin,
            onEdit: onEdit,
            saved: saved,
            onFavorite: onFavorite,
            onShare: onShare,
            onOpenMap: onOpenMap,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (spot.images.isEmpty)
                  const TourismPlaceholder()
                else
                  Image.network(
                    spot.images.first,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const TourismPlaceholder(),
                    loadingBuilder: (_, child, progress) =>
                        progress == null ? child : const TourismPlaceholder(),
                  ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: CircleAvatar(
                    backgroundColor: Colors.white.withValues(alpha: .94),
                    child: App3DIcon(
                      icon: AppIcon.fromKey(
                        spot.iconKey.isEmpty ? 'turismo' : spot.iconKey,
                      ),
                      size: 34,
                    ),
                  ),
                ),
                if (admin)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: IconButton.filledTonal(
                      tooltip: 'Editar ${spot.title}',
                      onPressed:
                          onEdit ??
                          () => _openTourismSpotEditor(context, spot.id),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                if (onFavorite != null)
                  Positioned(
                    right: 56,
                    top: 8,
                    child: IconButton.filledTonal(
                      key: ValueKey('favorite-tourism-${spot.id}'),
                      tooltip: saved
                          ? 'Desfavoritar ${spot.title}'
                          : 'Favoritar ${spot.title}',
                      onPressed: onFavorite,
                      icon: Icon(
                        saved
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: saved ? orange : null,
                      ),
                    ),
                  ),
                if (!admin)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: PublicShareButton(
                      content: PublicShareContent(
                        title: spot.title,
                        description: spot.description,
                      ),
                      onShare: onShare == null
                          ? null
                          : () => onShare!(
                              PublicShareContent(
                                title: spot.title,
                                description: spot.description,
                              ),
                            ),
                      tooltip: 'Compartilhar ${spot.title}',
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spot.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (spot.location.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: AppColors.orange,
                        size: 17,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          spot.location,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TouristSpotDetailView(
                        spot: spot,
                        admin: admin,
                        onEdit: onEdit,
                        saved: saved,
                        onFavorite: onFavorite,
                        onShare: onShare,
                        onOpenMap: onOpenMap,
                      ),
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
  const TouristSpotDetailView({
    super.key,
    required this.spot,
    this.admin = false,
    this.onEdit,
    this.saved = false,
    this.onFavorite,
    this.onShare,
    this.onOpenMap,
  });

  final TouristSpot spot;
  final bool admin;
  final VoidCallback? onEdit;
  final bool saved;
  final VoidCallback? onFavorite;
  final Future<void> Function(PublicShareContent content)? onShare;
  final Future<void> Function(String destination)? onOpenMap;

  @override
  State<TouristSpotDetailView> createState() => _TouristSpotDetailViewState();
}

class _TouristSpotDetailViewState extends State<TouristSpotDetailView> {
  int photo = 0;
  bool localSaved = false;

  @override
  Widget build(BuildContext context) {
    final spot = widget.spot;
    final images = spot.images;
    final mapDestination = spot.mapDestination;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 310,
            pinned: true,
            backgroundColor: AppColors.ocean,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            titleSpacing: AppSpacing.md,
            title: Text(spot.title),
            actions: [
              if (!widget.admin)
                PublicShareButton(
                  content: PublicShareContent(
                    title: spot.title,
                    description: spot.description,
                  ),
                  onShare: widget.onShare == null
                      ? null
                      : () => widget.onShare!(
                          PublicShareContent(
                            title: spot.title,
                            description: spot.description,
                          ),
                        ),
                  color: Colors.white,
                  tooltip: 'Compartilhar ${spot.title}',
                ),
              if (widget.admin)
                IconButton(
                  tooltip: 'Editar ${spot.title}',
                  onPressed:
                      widget.onEdit ??
                      () => _openTourismSpotEditor(context, spot.id),
                  icon: const Icon(Icons.edit_outlined),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (images.isEmpty)
                    const TourismPlaceholder()
                  else
                    PageView.builder(
                      itemCount: images.length,
                      onPageChanged: (value) => setState(() => photo = value),
                      itemBuilder: (_, index) => Image.network(
                        images[index],
                        fit: BoxFit.cover,
                        semanticLabel: 'Foto ${index + 1} de ${spot.title}',
                        errorBuilder: (_, _, _) => const TourismPlaceholder(),
                        loadingBuilder: (_, child, progress) => progress == null
                            ? child
                            : const TourismPlaceholder(),
                      ),
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
                          borderRadius: BorderRadius.circular(AppRadii.pill),
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
              padding: const EdgeInsets.all(AppSpacing.xl),
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
                      if (mapDestination.isNotEmpty) ...[
                        Expanded(
                          child: FilledButton.icon(
                            key: ValueKey('tourism-map-action-${spot.id}'),
                            onPressed: () => _openTourismMap(
                              context,
                              spot,
                              widget.onOpenMap,
                            ),
                            icon: const Icon(Icons.navigation_rounded),
                            label: const Text('Como chegar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      IconButton.filledTonal(
                        tooltip:
                            (widget.onFavorite == null
                                ? localSaved
                                : widget.saved)
                            ? 'Desfavoritar ${spot.title}'
                            : 'Favoritar ${spot.title}',
                        onPressed:
                            widget.onFavorite ??
                            () => setState(() => localSaved = !localSaved),
                        icon: Icon(
                          (widget.onFavorite == null
                                  ? localSaved
                                  : widget.saved)
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color:
                              (widget.onFavorite == null
                                  ? localSaved
                                  : widget.saved)
                              ? orange
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),
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
                        borderRadius: BorderRadius.circular(AppRadii.card),
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
    if (feature == Feature.tourism) return const TourismHomeView();
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
    Future<PublicContentSnapshot> read(String collection) =>
        getPublicContent(collection, limit: 10);
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
          onTap: () => openFeature(context, Feature.events),
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

class CityAgendaView extends StatefulWidget {
  const CityAgendaView({
    super.key,
    this.eventsStreamFactory,
    this.clock,
    this.resolveEvent,
    this.savedEventIds = const <String>{},
    this.onToggleAgenda,
    this.onOpenMyAgenda,
    this.isAuthenticated = false,
  });

  final Stream<PublicContentSnapshot> Function()? eventsStreamFactory;
  final DateTime Function()? clock;
  final Future<PublicEvent?> Function(String id)? resolveEvent;
  final Set<String> savedEventIds;
  final Future<bool> Function(PublicEvent event)? onToggleAgenda;
  final VoidCallback? onOpenMyAgenda;
  final bool isAuthenticated;

  @override
  State<CityAgendaView> createState() => _CityAgendaViewState();
}

class _CityAgendaViewState extends State<CityAgendaView> {
  final _searchController = TextEditingController();
  _AgendaDateFilter _dateFilter = _AgendaDateFilter.all;
  String? _selectedCategory;
  DateTime? _selectedDay;
  late DateTime _displayedMonth;
  bool _calendarMode = false;
  late Stream<PublicContentSnapshot> _events;
  late Set<String> _savedEventIds;

  Stream<PublicContentSnapshot> _createEventsStream() =>
      widget.eventsStreamFactory?.call() ??
      watchPublicContent(FirestoreCollections.events);

  DateTime _nowBrasilia() =>
      dateInBrasilia(widget.clock?.call()) ?? currentBrasiliaDateTime();

  @override
  void initState() {
    super.initState();
    _events = _createEventsStream();
    _savedEventIds = Set.of(widget.savedEventIds);
    final today = _nowBrasilia();
    _displayedMonth = DateTime(today.year, today.month);
  }

  @override
  void didUpdateWidget(covariant CityAgendaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventsStreamFactory != widget.eventsStreamFactory) {
      _events = _createEventsStream();
    }
    if (oldWidget.savedEventIds.length != widget.savedEventIds.length ||
        !oldWidget.savedEventIds.containsAll(widget.savedEventIds)) {
      _savedEventIds = Set.of(widget.savedEventIds);
    }
  }

  void _retry() {
    setState(() => _events = _createEventsStream());
  }

  void _setCalendarMode(bool calendar) {
    final today = _nowBrasilia();
    setState(() {
      _calendarMode = calendar;
      _selectedDay = calendar
          ? DateTime(today.year, today.month, today.day)
          : null;
      if (calendar) _displayedMonth = DateTime(today.year, today.month);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Agenda da cidade'),
      actions: [
        if (widget.onOpenMyAgenda != null)
          IconButton(
            tooltip: 'Minha Agenda',
            onPressed: widget.onOpenMyAgenda,
            icon: const Icon(Icons.event_available_outlined),
          ),
      ],
    ),
    body: StreamBuilder<PublicContentSnapshot>(
      stream: _events,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, color: sky, size: 40),
                  const SizedBox(height: 14),
                  const Text(
                    'Não foi possível carregar a agenda.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final documents = snapshot.data!.docs.where((document) {
          final data = document.data();
          return data['published'] == true &&
              data['active'] == true &&
              data['deleted'] != true &&
              !data.containsKey('deletedAt') &&
              isActiveContent(data);
        }).toList();
        if (documents.isEmpty) {
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
        final now = _nowBrasilia();
        final today = DateTime(now.year, now.month, now.day);
        final tomorrow = today.add(const Duration(days: 1));
        final allDatedEvents = <_AgendaEvent>[];
        for (var index = 0; index < documents.length; index++) {
          final document = documents[index];
          final data = document.data();
          final date = _contentDate(data);
          if (date == null) continue;
          allDatedEvents.add(
            _AgendaEvent(
              document: document,
              data: data,
              date: date,
              endDate: eventEndDateInBrasilia(data, date),
              sourceOrder: index,
            ),
          );
        }
        allDatedEvents.sort((a, b) {
          final byDate = a.date.compareTo(b.date);
          return byDate != 0 ? byDate : a.sourceOrder.compareTo(b.sourceOrder);
        });
        if (allDatedEvents.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'Nenhum evento futuro com data válida.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final categories =
            allDatedEvents
                .map(
                  (event) => (event.data['category'] ?? '').toString().trim(),
                )
                .where((value) => value.isNotEmpty)
                .toSet()
                .toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        if (_selectedCategory != null &&
            !categories.contains(_selectedCategory)) {
          _selectedCategory = null;
        }
        final query = _searchController.text.trim().toLowerCase();
        final datedEvents = allDatedEvents.where((event) {
          final data = event.data;
          if (_selectedCategory != null &&
              data['category'] != _selectedCategory) {
            return false;
          }
          if (query.isNotEmpty &&
              ![
                data['title'],
                data['name'],
                data['description'],
                data['category'],
                data['location'],
                data['address'],
                data['organizer'],
              ].any(
                (value) => value.toString().toLowerCase().contains(query),
              )) {
            return false;
          }
          final ended = _eventHasEnded(event, now, today);
          return switch (_dateFilter) {
            _AgendaDateFilter.all => true,
            _AgendaDateFilter.today =>
              !ended &&
                  occursOnBrasiliaDay(
                    start: event.date,
                    end: event.endDate,
                    day: today,
                  ),
            _AgendaDateFilter.upcoming =>
              !ended && _eventStartsAfter(event, now, today),
            _AgendaDateFilter.happening => !ended,
            _AgendaDateFilter.ended => ended,
          };
        }).toList();
        if (_dateFilter == _AgendaDateFilter.ended) {
          datedEvents.sort((a, b) => b.date.compareTo(a.date));
        } else if (_dateFilter == _AgendaDateFilter.upcoming) {
          _sortUpcomingEvents(datedEvents);
        }
        final emptyFilterMessage = switch (_dateFilter) {
          _AgendaDateFilter.today => 'Não há eventos acontecendo hoje.',
          _AgendaDateFilter.upcoming => 'Não há próximos eventos cadastrados.',
          _ => 'Nenhum evento corresponde aos filtros selecionados.',
        };
        final selectedEvents =
            _selectedDay == null
                  ? <_AgendaEvent>[]
                  : datedEvents
                        .where(
                          (event) => occursOnBrasiliaDay(
                            start: event.date,
                            end: event.endDate,
                            day: _selectedDay!,
                          ),
                        )
                        .toList()
              ..sort((a, b) => a.date.compareTo(b.date));
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              key: const ValueKey('city-event-search'),
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Buscar eventos',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar busca',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear_rounded),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final (filter, label, key) in const [
                  (_AgendaDateFilter.all, 'Todos', 'all'),
                  (_AgendaDateFilter.today, 'Hoje', 'today'),
                  (_AgendaDateFilter.upcoming, 'Próximos', 'upcoming'),
                  (_AgendaDateFilter.happening, 'A acontecer', 'happening'),
                  (_AgendaDateFilter.ended, 'Histórico', 'ended'),
                ])
                  ChoiceChip(
                    key: ValueKey('city-event-date-filter-$key'),
                    label: Text(label),
                    selected: _dateFilter == filter,
                    onSelected: (_) => setState(() => _dateFilter = filter),
                  ),
              ],
            ),
            if (categories.length > 1) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Todas as categorias'),
                    selected: _selectedCategory == null,
                    onSelected: (_) => setState(() => _selectedCategory = null),
                  ),
                  for (final category in categories)
                    ChoiceChip(
                      label: Text(category),
                      selected: _selectedCategory == category,
                      onSelected: (_) =>
                          setState(() => _selectedCategory = category),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, _) {
                final compact =
                    MediaQuery.sizeOf(context).width < 360 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.2;
                if (compact) {
                  return Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        key: const ValueKey('city-event-mode-list'),
                        label: const Text('Lista'),
                        selected: !_calendarMode,
                        onSelected: (_) => _setCalendarMode(false),
                      ),
                      ChoiceChip(
                        key: const ValueKey('city-event-mode-calendar'),
                        label: const Text('Calendário'),
                        selected: _calendarMode,
                        onSelected: (_) => _setCalendarMode(true),
                      ),
                    ],
                  );
                }
                return Center(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.view_agenda_outlined),
                        label: Text('Lista'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.calendar_month_outlined),
                        label: Text('Calendário'),
                      ),
                    ],
                    selected: {_calendarMode},
                    onSelectionChanged: (selection) =>
                        _setCalendarMode(selection.single),
                  ),
                );
              },
            ),
            if (_calendarMode) ...[
              const SizedBox(height: 14),
              CityMonthCalendar(
                month: _displayedMonth,
                selectedDate: _selectedDay,
                hasEvents: (day) => datedEvents.any(
                  (event) => occursOnBrasiliaDay(
                    start: event.date,
                    end: event.endDate,
                    day: day,
                  ),
                ),
                onDateSelected: (day) => setState(() => _selectedDay = day),
                onMonthChanged: (delta) => setState(() {
                  _displayedMonth = DateTime(
                    _displayedMonth.year,
                    _displayedMonth.month + delta,
                  );
                  _selectedDay = null;
                }),
                onToday: () {
                  final localToday = _nowBrasilia();
                  setState(() {
                    _displayedMonth = DateTime(
                      localToday.year,
                      localToday.month,
                    );
                    _selectedDay = DateTime(
                      localToday.year,
                      localToday.month,
                      localToday.day,
                    );
                  });
                },
              ),
              const SizedBox(height: 14),
              if (_selectedDay != null) ...[
                Text(
                  _formatBrasiliaDate(_selectedDay!),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 10),
                if (selectedEvents.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Nenhum evento nesta data.'),
                  )
                else
                  ...selectedEvents.map(
                    (event) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CalendarEventCard(
                        event: event,
                        onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => EventDetailPage(
                              eventId: event.document.id,
                              resolveEvent: widget.resolveEvent,
                              agendaSaved: _savedEventIds.contains(
                                event.document.id,
                              ),
                              onToggleAgenda: widget.onToggleAgenda == null
                                  ? null
                                  : (_) => _toggleAgendaEvent(
                                      _publicAgendaEvent(event),
                                    ),
                            ),
                          ),
                        ),
                        agendaSaved: _savedEventIds.contains(event.document.id),
                        onToggleAgenda: widget.onToggleAgenda == null
                            ? null
                            : () => unawaited(
                                _toggleAgendaEvent(_publicAgendaEvent(event)),
                              ),
                      ),
                    ),
                  ),
              ] else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Selecione um dia para ver os eventos.'),
                ),
            ] else ...[
              _AgendaGroup(
                title: 'Hoje',
                items: datedEvents
                    .where(
                      (event) =>
                          !_eventHasEnded(event, now, today) &&
                          occursOnBrasiliaDay(
                            start: event.date,
                            end: event.endDate,
                            day: today,
                          ),
                    )
                    .toList(),
                resolveEvent: widget.resolveEvent,
                savedEventIds: _savedEventIds,
                onToggleAgenda: widget.onToggleAgenda == null
                    ? null
                    : _toggleAgendaEvent,
              ),
              _AgendaGroup(
                title: 'Amanhã',
                items: datedEvents
                    .where(
                      (event) =>
                          !_eventHasEnded(event, now, today) &&
                          DateUtils.isSameDay(event.date, tomorrow),
                    )
                    .toList(),
                resolveEvent: widget.resolveEvent,
                savedEventIds: _savedEventIds,
                onToggleAgenda: widget.onToggleAgenda == null
                    ? null
                    : _toggleAgendaEvent,
              ),
              _AgendaGroup(
                title: 'Próximos',
                items: datedEvents
                    .where(
                      (event) =>
                          !_eventHasEnded(event, now, today) &&
                          event.date.isAfter(tomorrow),
                    )
                    .toList(),
                resolveEvent: widget.resolveEvent,
                savedEventIds: _savedEventIds,
                onToggleAgenda: widget.onToggleAgenda == null
                    ? null
                    : _toggleAgendaEvent,
              ),
              _AgendaGroup(
                title: 'Encerrados',
                items: datedEvents
                    .where((event) => _eventHasEnded(event, now, today))
                    .toList(),
                resolveEvent: widget.resolveEvent,
                savedEventIds: _savedEventIds,
                onToggleAgenda: widget.onToggleAgenda == null
                    ? null
                    : _toggleAgendaEvent,
              ),
              if (datedEvents.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(emptyFilterMessage),
                ),
            ],
          ],
        );
      },
    ),
  );

  Future<bool> _toggleAgendaEvent(PublicEvent event) async {
    final callback = widget.onToggleAgenda;
    if (callback == null) return false;
    try {
      final updated = await callback(event);
      if (updated && mounted) {
        setState(() {
          if (_savedEventIds.contains(event.id)) {
            _savedEventIds.remove(event.id);
          } else {
            _savedEventIds.add(event.id);
          }
        });
      }
      return updated;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este evento não pode ser salvo agora.')),
      );
      return false;
    }
  }
}

enum _AgendaDateFilter { all, today, upcoming, happening, ended }

bool _eventHasEnded(_AgendaEvent event, DateTime now, DateTime today) {
  return hasEventEndedInBrasilia(
    start: event.date,
    end: event.endDate,
    endTime: (event.data['endTime'] ?? '').toString(),
    now: now,
  );
}

DateTime? _eventStartDateTime(_AgendaEvent event) {
  final explicitTime = (event.data['startTime'] ?? '').toString().trim();
  final timeText = explicitTime.isNotEmpty
      ? explicitTime
      : _agendaEventStartTime(event.data);
  if (timeText.isNotEmpty) {
    final match = RegExp(
      r'^(\d{1,2})(?::(\d{2}))?\s*h?$',
      caseSensitive: false,
    ).firstMatch(timeText);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
    if (hour > 23 || minute > 59) return null;
    return DateTime(
      event.date.year,
      event.date.month,
      event.date.day,
      hour,
      minute,
    );
  }

  // A time carried by an ISO timestamp is reliable. A midnight date-only
  // value does not establish an event start time.
  if (event.date.hour != 0 ||
      event.date.minute != 0 ||
      event.date.second != 0 ||
      event.date.millisecond != 0) {
    return event.date;
  }
  return null;
}

bool _eventStartsAfter(_AgendaEvent event, DateTime now, DateTime today) {
  final start = _eventStartDateTime(event);
  if (start != null) return start.isAfter(now);
  final startDay = DateTime(event.date.year, event.date.month, event.date.day);
  // A date-only event today has no reliable future start time.
  return startDay.isAfter(today);
}

void _sortUpcomingEvents(List<_AgendaEvent> events) {
  final byDay = <DateTime, List<_AgendaEvent>>{};
  for (final event in events) {
    final day = DateTime(event.date.year, event.date.month, event.date.day);
    byDay.putIfAbsent(day, () => <_AgendaEvent>[]).add(event);
  }
  final days = byDay.keys.toList()..sort();
  final ordered = <_AgendaEvent>[];
  for (final day in days) {
    final dayEvents = byDay[day]!;
    final knownTimes =
        dayEvents.where((event) => _eventStartDateTime(event) != null).toList()
          ..sort((a, b) {
            final byStart = _eventStartDateTime(
              a,
            )!.compareTo(_eventStartDateTime(b)!);
            return byStart != 0
                ? byStart
                : a.sourceOrder.compareTo(b.sourceOrder);
          });
    var nextKnown = 0;
    for (final event in dayEvents) {
      if (_eventStartDateTime(event) == null) {
        // Keep date-only entries in their source positions: their time within
        // that day cannot be inferred from the public data.
        ordered.add(event);
      } else {
        ordered.add(knownTimes[nextKnown++]);
      }
    }
  }
  events
    ..clear()
    ..addAll(ordered);
}

class _AgendaGroup extends StatelessWidget {
  const _AgendaGroup({
    required this.title,
    required this.items,
    required this.resolveEvent,
    required this.savedEventIds,
    this.onToggleAgenda,
  });
  final String title;
  final List<_AgendaEvent> items;
  final Future<PublicEvent?> Function(String id)? resolveEvent;
  final Set<String> savedEventIds;
  final Future<bool> Function(PublicEvent event)? onToggleAgenda;
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
            key: ValueKey('agenda-group-title-$title'),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
        ),
        ...items.map((event) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: LocalContentCard(
              item: event.data,
              actionLabel: 'Ver evento',
              externalActionLabel: 'Abrir link',
              metricTargetType: 'events',
              shareContent: PublicShareContent(
                title: (event.data['title'] ?? event.data['name'] ?? 'Evento')
                    .toString(),
                description: (event.data['description'] ?? '').toString(),
              ),
              wrapActionsOnLargeText: true,
              trailingAction: onToggleAgenda == null
                  ? null
                  : IconButton(
                      tooltip: savedEventIds.contains(event.document.id)
                          ? 'Remover evento da Minha Agenda'
                          : 'Adicionar evento à Minha Agenda',
                      onPressed: () {
                        try {
                          unawaited(
                            onToggleAgenda!(
                              PublicEvent.fromMap({
                                ...event.data,
                                'id': event.document.id,
                              }),
                            ),
                          );
                        } on FormatException {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Este evento não pode ser salvo agora.',
                              ),
                            ),
                          );
                        }
                      },
                      icon: Icon(
                        savedEventIds.contains(event.document.id)
                            ? Icons.event_available_rounded
                            : Icons.event_available_outlined,
                      ),
                    ),
              onOpen: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EventDetailPage(
                    eventId: event.document.id,
                    resolveEvent: resolveEvent,
                    agendaSaved: savedEventIds.contains(event.document.id),
                    onToggleAgenda: onToggleAgenda == null
                        ? null
                        : (_) => onToggleAgenda!(
                            PublicEvent.fromMap({
                              ...event.data,
                              'id': event.document.id,
                            }),
                          ),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _CalendarEventCard extends StatelessWidget {
  const _CalendarEventCard({
    required this.event,
    required this.onOpen,
    this.agendaSaved = false,
    this.onToggleAgenda,
  });

  final _AgendaEvent event;
  final VoidCallback onOpen;
  final bool agendaSaved;
  final VoidCallback? onToggleAgenda;

  @override
  Widget build(BuildContext context) {
    final images = contentImageUrls(event.data);
    final category = (event.data['category'] ?? '').toString().trim();
    final startTime = _agendaEventStartTime(event.data);
    final endTime = (event.data['endTime'] ?? '').toString().trim();
    final time = [
      if (startTime.isNotEmpty) startTime,
      if (endTime.isNotEmpty) 'até $endTime',
    ].join(' · ');
    final isMultiDay = !DateUtils.isSameDay(event.date, event.endDate);
    final title = (event.data['title'] ?? event.data['name'] ?? 'Evento')
        .toString();
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (category.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            category,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.ocean,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (time.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(time, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (isMultiDay) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${_formatBrasiliaDate(event.date)} – ${_formatBrasiliaDate(event.endDate)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ],
        if (onToggleAgenda != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onToggleAgenda,
              icon: Icon(
                agendaSaved
                    ? Icons.event_available_rounded
                    : Icons.event_available_outlined,
              ),
              label: Text(
                agendaSaved ? 'Na Minha Agenda' : 'Adicionar à agenda',
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            PublicShareButton(
              content: PublicShareContent(
                title: title,
                description: (event.data['description'] ?? '').toString(),
              ),
              tooltip: 'Compartilhar evento',
            ),
            TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('Detalhes'),
            ),
          ],
        ),
      ],
    );

    Widget cover({double? width}) {
      final image = images.isEmpty
          ? const DecoratedBox(
              decoration: BoxDecoration(gradient: AppTheme.brandGradient),
              child: Center(
                child: Icon(Icons.event_rounded, color: Colors.white, size: 34),
              ),
            )
          : Image.network(
              images.first,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: AppColors.skyTint,
                child: Center(
                  child: Icon(
                    Icons.event_rounded,
                    color: AppColors.ocean,
                    size: 30,
                  ),
                ),
              ),
            );
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.control),
        child: SizedBox(width: width, height: width, child: image),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 380 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.25;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AspectRatio(aspectRatio: 16 / 9, child: cover()),
                        const SizedBox(height: AppSpacing.md),
                        details,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        cover(width: 88),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: details),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

String _agendaEventStartTime(Map<String, dynamic> data) {
  final explicit = (data['startTime'] ?? '').toString().trim();
  if (explicit.isNotEmpty) return explicit;
  final rawDate = (data['eventDate'] ?? data['date'] ?? '').toString();
  final match = RegExp(
    r'às\s+(\d{1,2})(?::(\d{2}))?h?',
    caseSensitive: false,
  ).firstMatch(rawDate);
  if (match == null) return '';
  return '${match.group(1)!.padLeft(2, '0')}:'
      '${(match.group(2) ?? '00').padLeft(2, '0')}';
}

class _AgendaEvent {
  const _AgendaEvent({
    required this.document,
    required this.data,
    required this.date,
    required this.endDate,
    required this.sourceOrder,
  });

  final PublicContentDocument document;
  final Map<String, dynamic> data;
  final DateTime date;
  final DateTime endDate;
  final int sourceOrder;
}

DateTime? _contentDate(Map<String, dynamic> item) {
  final raw = item['eventDate'] ?? item['date'] ?? item['startsAt'];
  return dateInBrasilia(raw);
}

PublicEvent _publicAgendaEvent(_AgendaEvent event) =>
    PublicEvent.fromMap({...event.data, 'id': event.document.id});

String _formatBrasiliaDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

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
    final businessResults = await businessRepository
        .watchPublishedBusinesses()
        .first;
    final reads = await Future.wait([
      getPublicContent(FirestoreCollections.utilities, limit: 50),

      getPublicContent(FirestoreCollections.events, limit: 40),
      getPublicContent(FirestoreCollections.news, limit: 40),
      getPublicContent(FirestoreCollections.jobs, limit: 40),
      getPublicContent(FirestoreCollections.alerts, limit: 40),
      getPublicContent(FirestoreCollections.resolverSubjects, limit: 40),
      getPublicContent(FirestoreCollections.transport, limit: 30),
      getPublicContent(FirestoreCollections.usefulPhones, limit: 30),
      getPublicContent(FirestoreCollections.health, limit: 30),
    ]);
    final utilitiesDocs = reads[0];
    final eventDocs = reads[1];
    final newsDocs = reads[2];
    final jobDocs = reads[3];
    final alertDocs = reads[4];
    final resolverDocs = reads[5];
    final transportDocs = reads[6];
    final phoneDocs = reads[7];
    final healthDocs = reads[8];

    SearchResultItem contentItem(
      PublicContentDocument doc,
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
        mergeWaterEnergyUtilities([
              ...fallbackUtilities,
              ...utilitiesDocs.docs.map(
                (doc) => UtilityItem.fromData(doc.id, doc.data()),
              ),
            ])
            .where(
              (item) =>
                  _availableCityUtility(item) &&
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
      PublicContentSnapshot docs,
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

    return [
      SearchResultGroup(title: 'UTILIDADES', items: utilities),
      SearchResultGroup(title: 'EMPRESAS', items: businessesFound),
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
  Category('Tecnologia', 18, [
    'Informática',
    'Assistência técnica',
    'Provedores de internet',
    'Celulares',
    'Eletrônicos',
    'Tecnologia e acessórios',
  ]),
];

List<Category> get exploreCatalog => catalog
    .where((category) => category.name != 'Turismo')
    .toList(growable: false);
List<Category> get homeCatalog => [
  ...catalog.take(8),
  catalog.firstWhere((category) => category.name == 'Serviços úteis'),
  ...catalog.where((category) => category.artwork >= 18),
];

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
// Mantido para compatibilidade com consumidores e testes do catálogo; não é
// usado como fallback para conteúdo público carregado do backend.
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
