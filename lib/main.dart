import 'dart:async';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart';
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
import 'core/config/beta_environment.dart';
import 'core/config/spark_local_environment.dart';
import 'core/config/spark_local_startup_timeline.dart';
import 'core/config/beta_startup_diagnostics.dart';
import 'core/auth/app_check_setup.dart';
import 'core/auth/app_auth.dart';
import 'core/auth/admin_authorization.dart';
import 'core/auth/local_auth_diagnostics.dart';
import 'features/auth/local_session_recovery.dart';

import 'redesigned_app.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (LocalSearchEnvironment.enabled || StagingEnvironment.enabled) return;
  if (BetaEnvironment.enabled) return;
  await Firebase.initializeApp();
}

Future<void> main() async {
  SparkLocalStartupTimeline.mark('dart_main_enter');
  WidgetsFlutterBinding.ensureInitialized();
  SparkLocalStartupTimeline.mark('flutter_binding_ready');
  if (LocalSearchEnvironment.enabled ||
      StagingEnvironment.enabled ||
      SparkLocalEnvironment.enabled) {
    GoogleFonts.config.allowRuntimeFetching = false;
  }
  ErrorWidget.builder = (details) => const AppRuntimeErrorView();
  Object? localStartupError;
  LocalAuthBootstrapFailure? localAuthStartupFailure;
  Future<void> Function()? retryLocalSession;
  Future<void> Function(String email, String password)? switchLocalAccount;
  Future<void> Function()? continueLocalAsVisitor;
  var stagingStartupFailed = false;
  var betaStartupFailed = false;
  String? betaStartupFailure;
  Future<T> betaStartupStep<T>(
    BetaStartupStage stage,
    Future<T> Function() action,
  ) => runBetaStartupStep<T>(
    stage,
    action,
    onFailure: (code) => betaStartupFailure = code,
  );
  try {
    if (LocalSearchEnvironment.authHttpDiagnosticsEnabled) {
      LocalSearchEnvironment.authEmulatorPort;
    }
    if (SparkLocalEnvironment.enabled) {
      if (!Platform.isAndroid || LocalSearchEnvironment.enabled) {
        throw StateError('Variante Spark local incompatível.');
      }
      SparkLocalStartupTimeline.mark('network_isolation_start');
      await LocalNetworkIsolation.prepareSparkLocal();
      SparkLocalStartupTimeline.mark('network_isolation_ready');
      SparkLocalStartupTimeline.mark('firebase_init_start');
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'demo-emulator-api-key',
          appId: '1:000000000000:android:spark-local-demo',
          messagingSenderId: '000000000000',
          projectId: SparkLocalEnvironment.project,
        ),
      );
      SparkLocalStartupTimeline.mark('firebase_init_ready');
      SparkLocalEnvironment.requireDemo(Firebase.app().options.projectId);
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
      );
      SparkLocalStartupTimeline.mark('firestore_settings_ready');
      SparkLocalStartupTimeline.mark('auth_emulator_start');
      FirebaseAuth.instance.useAuthEmulator(
        SparkLocalEnvironment.host,
        SparkLocalEnvironment.authPort,
        automaticHostMapping: false,
      );
      SparkLocalStartupTimeline.mark('auth_emulator_ready');
      SparkLocalStartupTimeline.mark('firestore_emulator_start');
      FirebaseFirestore.instance.useFirestoreEmulator(
        SparkLocalEnvironment.host,
        SparkLocalEnvironment.firestorePort,
        automaticHostMapping: false,
      );
      SparkLocalStartupTimeline.mark('firestore_emulator_ready');
      BetaEnvironment.markSparkLocalReady(
        actualProjectId: Firebase.app().options.projectId,
      );
      SparkLocalStartupTimeline.mark('admin_authorization_start');
      await AdminAuthorization.instance.start();
      SparkLocalStartupTimeline.mark('admin_authorization_ready');
      debugPrint(
        'SPARK LOCAL ISOLATION VALIDATED: demo-universal-search; Auth=9097 Firestore=8087; Functions/Storage/FCM off; native VPN active',
      );
    } else if (BetaEnvironment.enabled) {
      await betaStartupStep<void>(BetaStartupStage.environment, () async {
        if (LocalSearchEnvironment.enabled ||
            (!Platform.isAndroid && !Platform.isIOS) ||
            (Platform.isIOS && !BetaEnvironment.iosBuildEnabled)) {
          throw BetaStartupDiagnosticException(
            BetaStartupStage.environment,
            Platform.isIOS
                ? 'ios_beta_not_explicitly_enabled'
                : 'unsupported_platform',
          );
        }
      });
      final nativeIdentity = await betaStartupStep<Map<String, dynamic>>(
        BetaStartupStage.nativeIdentity,
        Platform.isIOS
            ? () async => BetaEnvironment.readIosBuildIdentity()
            : BetaEnvironment.readNativeIdentity,
      );
      if (nativeIdentity['beta'] != true || nativeIdentity['local'] == true) {
        throw StateError('Identidade nativa do Beta inválida.');
      }
      final nativeProjectId = nativeIdentity['expectedProject'] is String
          ? nativeIdentity['expectedProject'] as String
          : '';
      final applicationId = nativeIdentity['package'] is String
          ? nativeIdentity['package'] as String
          : nativeIdentity['bundleIdentifier'] is String
          ? nativeIdentity['bundleIdentifier'] as String
          : '';
      final iosGoogleClientId = nativeIdentity['iosGoogleClientId'] is String
          ? nativeIdentity['iosGoogleClientId'] as String
          : '';
      final googleWebClientId = nativeIdentity['googleWebClientId'] is String
          ? nativeIdentity['googleWebClientId'] as String
          : '';
      final firebaseAppId = nativeIdentity['firebaseAppId'] is String
          ? nativeIdentity['firebaseAppId'] as String
          : '';
      final messagingSenderId = nativeIdentity['messagingSenderId'] is String
          ? nativeIdentity['messagingSenderId'] as String
          : '';
      if (kDebugMode) {
        debugPrint(
          '[BETA_STARTUP] check=configuration_identity '
          'configured_project_present=${BetaEnvironment.expectedProjectId.isNotEmpty} '
          'native_project_present=${nativeProjectId.trim().isNotEmpty} '
          'project_match=${nativeProjectId.trim() == BetaEnvironment.expectedProjectId.trim()} '
          'package_match=${Platform.isIOS ? applicationId == BetaEnvironment.iosBundleIdentifier : applicationId == BetaEnvironment.applicationId} '
          'ios_oauth_present=${iosGoogleClientId.trim().isNotEmpty} '
          'oauth_web_present=${googleWebClientId.trim().isNotEmpty} '
          'firebase_app_id_present=${firebaseAppId.trim().isNotEmpty} '
          'sender_id_present=${messagingSenderId.trim().isNotEmpty}',
        );
      }
      await betaStartupStep<void>(BetaStartupStage.configuration, () async {
        final code = BetaEnvironment.validateCompiledConfigurationFailureCode(
          nativeExpectedProjectId: nativeProjectId,
          applicationId: applicationId,
          nativeGoogleWebClientId: googleWebClientId,
          nativeFirebaseAppId: firebaseAppId,
          nativeMessagingSenderId: messagingSenderId,
          android: Platform.isAndroid,
          ios: Platform.isIOS,
          iosBundleIdentifier: Platform.isIOS
              ? BetaEnvironment.iosBundleIdentifier
              : '',
          iosGoogleClientId: iosGoogleClientId,
        );
        if (code != null) {
          throw BetaStartupDiagnosticException(
            BetaStartupStage.configuration,
            code,
          );
        }
      });

      // Android's Gradle task consumes only src/beta/google-services.json.
      // iOS uses its separately provisioned GoogleService-Info.plist plus the
      // explicit build identity above; FirebaseOptions are checked before any
      // App Check, Auth, Firestore, or other Firebase service is used.
      await betaStartupStep<FirebaseApp>(
        BetaStartupStage.firebaseInitialization,
        Firebase.initializeApp,
      );
      await betaStartupStep<void>(BetaStartupStage.firebaseIdentity, () async {
        BetaEnvironment.markReady(
          actualProjectId: Firebase.app().options.projectId,
          actualAppId: Firebase.app().options.appId,
          actualMessagingSenderId: Firebase.app().options.messagingSenderId,
          actualIosGoogleClientId: Firebase.app().options.iosClientId ?? '',
          actualIosBundleIdentifier: Firebase.app().options.iosBundleId ?? '',
          nativeExpectedProjectId: nativeProjectId,
          applicationId: applicationId,
          nativeGoogleWebClientId: googleWebClientId,
          nativeFirebaseAppId: firebaseAppId,
          nativeMessagingSenderId: messagingSenderId,
          android: Platform.isAndroid,
          ios: Platform.isIOS,
          iosBundleIdentifier: Platform.isIOS
              ? BetaEnvironment.iosBundleIdentifier
              : '',
          iosGoogleClientId: iosGoogleClientId,
        );
      });
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await betaStartupStep<void>(
        BetaStartupStage.appCheck,
        AppCheckSetup.prepareBeta,
      );
      // Public catalog reads use Firestore Rules and do not need anonymous Auth.
      // A visitor remains signed out until they choose to create an account.
      await betaStartupStep<void>(
        BetaStartupStage.adminAuthorization,
        AdminAuthorization.instance.start,
      );
    } else if (StagingEnvironment.enabled) {
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
        await validateServicesAndAdminAfterAuth();
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
    } else if (BetaEnvironment.enabled) {
      BetaEnvironment.resetAfterStartupFailure();
      betaStartupFailed = true;
      betaStartupFailure ??= betaStartupFailureCode(
        BetaStartupStage.unknown,
        error,
      );
      if (kDebugMode) {
        debugPrint(
          '[BETA_STARTUP] result=stopped code=$betaStartupFailure. No fallback was attempted.',
        );
      }
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
      !stagingStartupFailed &&
      !betaStartupFailed) {
    // Plugin recovery starts only after local network and Firebase policy are
    // established. It does not access Firebase, but must not race bootstrap.
    unawaited(DeviceImageSource.instance.primeRecovery());
    if (SparkLocalEnvironment.enabled) {
      SparkLocalStartupTimeline.mark('run_app');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        SparkLocalStartupTimeline.mark('first_flutter_frame');
      });
    }
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
              : betaStartupFailed
              ? kDebugMode && betaStartupFailure != null
                    ? betaStartupFailureMessage(betaStartupFailure!)
                    : 'A configuração do Beta não está pronta. Esta versão exige um Firebase de testes separado, cliente OAuth próprio e App Check configurado.'
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
