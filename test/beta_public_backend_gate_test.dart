import 'package:flutter_test/flutter_test.dart';
import 'package:tudo_aqui_macacu/core/content/secure_backend.dart';

void main() {
  const betaProject = 'macacu-beta-261030-cf4a81';

  bool allowed({
    bool betaBuild = true,
    bool betaReady = true,
    bool localSearch = false,
    bool staging = false,
    String? projectId = betaProject,
    String operation = 'listPublicContent',
  }) => isBetaPublicReadAuthorized(
    betaBuild: betaBuild,
    betaReady: betaReady,
    localSearch: localSearch,
    staging: staging,
    projectId: projectId,
    expectedBetaProjectId: betaProject,
    operation: operation,
  );

  test('Spark Beta does not authorize any Cloud Function callable', () {
    expect(SecureBackend.betaPublicReadOperations, isEmpty);
    expect(allowed(), isFalse);
    expect(allowed(operation: 'getPublicContentDetail'), isFalse);
    expect(allowed(operation: 'searchPublicContent'), isFalse);
    expect(allowed(operation: 'submitUserOperation'), isFalse);
    expect(allowed(operation: 'manageAdminJob'), isFalse);
    expect(allowed(operation: 'getPublicJob'), isFalse);
  });

  test('Beta callable gate fails closed for wrong environment or identity', () {
    expect(allowed(betaBuild: false), isFalse);
    expect(allowed(betaReady: false), isFalse);
    expect(allowed(localSearch: true), isFalse);
    expect(allowed(staging: true), isFalse);
    expect(allowed(projectId: 'tudo-aqui-macacu'), isFalse);
    expect(allowed(projectId: 'macacu-staging-261022'), isFalse);
    expect(allowed(projectId: null), isFalse);
  });
}
