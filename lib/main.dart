import 'dart:async';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import 'core/config/local_network_isolation.dart';
import 'core/config/local_firebase_bootstrap.dart';
import 'core/media/device_image_source.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'core/config/local_search_environment.dart';
import 'core/config/staging_environment.dart';
import 'core/auth/app_check_setup.dart';
import 'core/auth/app_auth.dart';
import 'core/auth/admin_authorization.dart';
import 'core/auth/local_auth_diagnostics.dart';
import 'features/auth/local_session_recovery.dart';

import 'redesigned_app.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (LocalSearchEnvironment.enabled || StagingEnvironment.enabled) return;
  await Firebase.initializeApp();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (LocalSearchEnvironment.enabled || StagingEnvironment.enabled) {
    GoogleFonts.config.allowRuntimeFetching = false;
  }
  ErrorWidget.builder = (details) => const AppRuntimeErrorView();
  Object? localStartupError;
  LocalAuthBootstrapFailure? localAuthStartupFailure;
  Future<void> Function()? retryLocalSession;
  Future<void> Function(String email, String password)? switchLocalAccount;
  Future<void> Function()? continueLocalAsVisitor;
  var stagingStartupFailed = false;
  try {
    if (LocalSearchEnvironment.authHttpDiagnosticsEnabled) {
      LocalSearchEnvironment.authEmulatorPort;
    }
    if (StagingEnvironment.enabled) {
      if (LocalSearchEnvironment.enabled || !Platform.isAndroid) {
        throw StateError('Variante de homologação incompatível.');
      }
      await Firebase.initializeApp();
      final nativeIdentity = await StagingEnvironment.readNativeIdentity();
      if (nativeIdentity['local'] == true ||
          nativeIdentity['staging'] != true) {
        throw StateError('Identidade nativa de homologação inválida.');
      }
      StagingEnvironment.markReady(
        actualProjectId: Firebase.app().options.projectId,
        nativeExpectedProjectId: nativeIdentity['expectedProject'] is String
            ? nativeIdentity['expectedProject'] as String
            : '',
        applicationId: nativeIdentity['package'] is String
            ? nativeIdentity['package'] as String
            : '',
      );
      if (!StagingEnvironment.appCheckEnabled) {
        throw StateError('App Check de homologação não foi habilitado.');
      }
      await AppCheckSetup.prepareStaging();
      await AppAuth.ensureVisitor().timeout(const Duration(seconds: 20));
      await AdminAuthorization.instance.start();
    } else if (LocalSearchEnvironment.enabled) {
      Future<void> validateServicesAfterAuth() async {
        await FirebaseFirestore.instance
            .collection('home_pages')
            .doc('published')
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 15));
        final probe = HttpClient();
        try {
          final request = await probe
              .getUrl(Uri.parse('http://${LocalSearchEnvironment.host}:5007/'))
              .timeout(const Duration(seconds: 5));
          final response = await request.close().timeout(
            const Duration(seconds: 5),
          );
          if (response.statusCode != 404) {
            throw StateError('Functions Emulator inesperado.');
          }
          await response.drain<void>();
        } finally {
          probe.close(force: true);
        }
      }

      Future<void> validateServicesAndAdminAfterAuth() async {
        await validateServicesAfterAuth();
        await AdminAuthorization.instance.start();
      }

      retryLocalSession = () async {
        final user = FirebaseAuth.instance.currentUser;
        final session = user == null
            ? LocalAuthSessionCategory.none
            : user.isAnonymous
            ? LocalAuthSessionCategory.anonymous
            : LocalAuthSessionCategory.registered;
        await runLocalSessionRetryDiagnostics(
          session: session,
          enabled: LocalSearchEnvironment.enabled,
          validateAuth: () async {
            await AppAuth.validateCurrentLocalSession().timeout(
              const Duration(seconds: 15),
            );
          },
          validateServices: validateServicesAfterAuth,
          checkAdminAuthorization: AdminAuthorization.instance.start,
        );
        unawaited(DeviceImageSource.instance.primeRecovery());
      };
      switchLocalAccount = (email, password) async {
        await AppAuth.signInEmail(email, password);
      };
      continueLocalAsVisitor = () async {
        await AppAuth.continueAsLocalVisitor().timeout(
          const Duration(seconds: 15),
        );
      };

      await runLocalFirebaseBootstrap(
        establishNetworkIsolation: () async {
          if (Platform.isAndroid) await LocalNetworkIsolation.prepare();
          LocalSearchEnvironment.requireDemo(LocalSearchEnvironment.project);
        },
        initializeDemoProject: () async {
          await Firebase.initializeApp(
            options: const FirebaseOptions(
              apiKey: 'demo-emulator-api-key',
              appId: '1:000000000000:android:demo',
              messagingSenderId: '000000000000',
              projectId: LocalSearchEnvironment.project,
            ),
          );
          LocalSearchEnvironment.requireDemo(Firebase.app().options.projectId);
          for (final app in Firebase.apps) {
            LocalSearchEnvironment.requireDemo(app.options.projectId);
            await app.setAutomaticDataCollectionEnabled(false);
          }
        },
        configureAuthEmulator: () => FirebaseAuth.instance.useAuthEmulator(
          LocalSearchEnvironment.host,
          LocalSearchEnvironment.authEmulatorPort,
          automaticHostMapping: false,
        ),
        configureFirestoreSettings: () async {
          // Firestore settings must be established before emulator routing.
          FirebaseFirestore.instance.settings = const Settings(
            persistenceEnabled: false,
          );
        },
        configureFirestoreEmulator: () async {
          FirebaseFirestore.instance.useFirestoreEmulator(
            LocalSearchEnvironment.host,
            8087,
            automaticHostMapping: false,
          );
          final settings = FirebaseFirestore.instance.settings;
          if (!isLocalFirestoreConfiguration(
            host: settings.host,
            sslEnabled: settings.sslEnabled,
            persistenceEnabled: settings.persistenceEnabled,
            expectedHost: '${LocalSearchEnvironment.host}:8087',
          )) {
            throw StateError('Firestore Emulator não foi configurado.');
          }
        },
        configureFunctionsEmulators: () async {
          for (final functions in [
            FirebaseFunctions.instanceFor(region: 'southamerica-east1'),
            FirebaseFunctions.instance,
            FirebaseFunctions.instanceFor(region: 'us-central1'),
          ]) {
            functions.useFunctionsEmulator(
              LocalSearchEnvironment.host,
              5007,
              automaticHostMapping: false,
            );
          }
        },
        prepareLocalAppCheck: AppCheckSetup.prepare,
        validateLocalAuthSession: () async {
          await AppAuth.ensureVisitor().timeout(const Duration(seconds: 15));
        },
        validateLocalServices: validateServicesAndAdminAfterAuth,
      );
      debugPrint(
        'LOCAL ISOLATION VALIDATED: demo-universal-search; Auth=${LocalSearchEnvironment.authEmulatorPort} Firestore=8087 Functions=5007; FCM off; native VPN active',
      );
    } else {
      if (Platform.isAndroid) await LocalNetworkIsolation.prepare();
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await AppCheckSetup.prepare();
      await AdminAuthorization.instance.start();
    }
  } catch (error, stackTrace) {
    // Never fall back to the production app after a demo bootstrap failure.
    if (LocalSearchEnvironment.enabled ||
        LocalSearchEnvironment.authHttpDiagnosticsEnabled) {
      if (error is LocalAuthBootstrapFailure &&
          LocalSearchEnvironment.enabled) {
        localAuthStartupFailure = error;
      } else {
        localStartupError = error;
      }
      final cause = error is LocalAuthBootstrapFailure ? error.cause : error;
      final localFailureCode = cause is FirebaseAuthException
          ? 'firebase-auth-${cause.code}'
          : cause is LocalSearchSessionExpired
          ? 'local-auth-session-expired'
          : cause.runtimeType.toString();
      debugPrint('Local Firebase startup stopped safely: $localFailureCode');
    } else if (StagingEnvironment.enabled) {
      StagingEnvironment.resetAfterStartupFailure();
      stagingStartupFailed = true;
      debugPrint(
        'Staging startup stopped safely: ${error.runtimeType}. No fallback was attempted.',
      );
    } else if (AppCheckSetup.enabled ||
        AppCheckSetup.normalFirebaseDebugOptIn) {
      rethrow;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: localAuthStartupFailure != null
            ? StateError('Local Auth session validation failed.')
            : error,
        stack: stackTrace,
        library: 'Tudo Aqui Macacu main',
      ),
    );
  }
  if (localStartupError == null &&
      localAuthStartupFailure == null &&
      !stagingStartupFailed) {
    // Plugin recovery starts only after local network and Firebase policy are
    // established. It does not access Firebase, but must not race bootstrap.
    unawaited(DeviceImageSource.instance.primeRecovery());
    runApp(const RedesignedApp());
  } else if (localAuthStartupFailure != null &&
      LocalSearchEnvironment.enabled &&
      retryLocalSession != null &&
      switchLocalAccount != null &&
      continueLocalAsVisitor != null) {
    runApp(
      MaterialApp(
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
        ),
        home: LocalSessionRecoveryView(
          failureKind: classifyLocalSessionFailure(
            localAuthStartupFailure.cause,
          ),
          onSwitchAccount: switchLocalAccount,
          onContinueAsVisitor: continueLocalAsVisitor,
          onValidateCurrentSession: retryLocalSession,
          onReady: (_) => const RedesignedApp(),
        ),
      ),
    );
  } else {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: AppRuntimeErrorView(
          message: stagingStartupFailed
              ? 'A configuração de homologação não pôde ser validada. Confira os arquivos e as opções de staging e tente novamente.'
              : localSearchStartupMessage(localStartupError!),
        ),
      ),
    );
  }
}

class AppRuntimeErrorView extends StatelessWidget {
  const AppRuntimeErrorView({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) => Material(
    color: soft,
    child: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: ink.withValues(alpha: .08),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: orange.withValues(alpha: .12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: orange,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Ops, algo não carregou',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message ??
                          'Feche e abra o app novamente. Se continuar, avise a gente para corrigirmos.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, height: 1.35),
                    ),
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
