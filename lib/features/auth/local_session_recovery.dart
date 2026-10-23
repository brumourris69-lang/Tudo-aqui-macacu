import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/config/local_search_environment.dart';
import '../../core/theme/app_colors.dart';
import 'local_demo_login.dart';

enum LocalSessionFailureKind { credentialInvalid, inconclusive }

LocalSessionFailureKind classifyLocalSessionFailureCode(String? code) {
  final normalized = (code ?? '').toLowerCase().replaceAll('_', '-');
  if (const {
    'invalid-refresh-token',
    'invalid-user-token',
    'user-token-expired',
    'invalid-credential',
    'wrong-password',
    'user-not-found',
    'user-disabled',
  }.contains(normalized)) {
    return LocalSessionFailureKind.credentialInvalid;
  }
  return LocalSessionFailureKind.inconclusive;
}

LocalSessionFailureKind classifyLocalSessionFailure(Object error) =>
    classifyLocalSessionFailureCode(
      error is FirebaseAuthException ? error.code : null,
    );

class LocalSessionRecoveryView extends StatefulWidget {
  const LocalSessionRecoveryView({
    super.key,
    required this.failureKind,
    required this.onSwitchAccount,
    required this.onContinueAsVisitor,
    required this.onValidateCurrentSession,
    required this.onReady,
  });

  final LocalSessionFailureKind failureKind;
  final Future<void> Function(String email, String password) onSwitchAccount;
  final Future<void> Function() onContinueAsVisitor;
  final Future<void> Function() onValidateCurrentSession;
  final WidgetBuilder onReady;

  @override
  State<LocalSessionRecoveryView> createState() =>
      _LocalSessionRecoveryViewState();
}

class _LocalSessionRecoveryViewState extends State<LocalSessionRecoveryView> {
  late LocalSessionFailureKind _failureKind = widget.failureKind;
  bool _busy = false;
  bool _ready = false;
  bool _showLogin = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) {
        setState(() => _failureKind = classifyLocalSessionFailure(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmSessionChange({required bool visitor}) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(visitor ? 'Continuar como visitante?' : 'Trocar de conta?'),
        content: Text(
          visitor
              ? 'A conta registrada será desconectada e uma sessão visitante local será iniciada. Favoritos, perfil e dados da conta anterior permanecem associados a ela e não serão transferidos.'
              : 'A conta atual será mantida até a nova autenticação ser concluída. Perfil, favoritos e dados permanecem vinculados a cada conta e não serão transferidos.',
        ),
        actions: [
          TextButton(
            key: const Key('cancel-session-change'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirm-session-change'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              visitor ? 'Continuar como visitante' : 'Trocar de conta',
            ),
          ),
        ],
      ),
    );
    return accepted == true;
  }

  Future<void> _switchAccount() async {
    if (_busy || !await _confirmSessionChange(visitor: false) || !mounted) {
      return;
    }
    setState(() => _showLogin = true);
  }

  Future<void> _continueAsVisitor() async {
    if (_busy || !await _confirmSessionChange(visitor: true) || !mounted) {
      return;
    }
    await _run(() async {
      await widget.onContinueAsVisitor();
      await widget.onValidateCurrentSession();
    });
  }

  Future<void> _completeAccountSwitch() async {
    await _run(widget.onValidateCurrentSession);
    if (mounted && !_ready) setState(() => _showLogin = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.onReady(context);
    if (!LocalSearchEnvironment.enabled) {
      return const Scaffold(
        body: Center(child: Text('Recuperação local indisponível.')),
      );
    }

    if (_showLogin) {
      return Scaffold(
        backgroundColor: AppColors.soft,
        appBar: AppBar(
          backgroundColor: AppColors.soft,
          title: const Text('Trocar de conta'),
          leading: IconButton(
            key: const Key('cancel-account-switch'),
            tooltip: 'Voltar à recuperação',
            onPressed: _busy ? null : () => setState(() => _showLogin = false),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: LocalDemoLoginForm(
          authenticate: widget.onSwitchAccount,
          onAuthenticated: _completeAccountSwitch,
        ),
      );
    }

    final message = _failureKind == LocalSessionFailureKind.credentialInvalid
        ? 'A sessão salva não foi aceita pelo Auth Emulator. Você pode tentar novamente ou escolher uma forma de acesso; sua conta não foi desconectada.'
        : 'Não foi possível validar a sessão. O erro pode ser temporário; sua conta continua preservada e nenhuma alteração foi feita.';

    return Scaffold(
      backgroundColor: AppColors.soft,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                color: Colors.white,
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.account_circle_outlined,
                        size: 52,
                        color: AppColors.sky,
                        semanticLabel: 'Sessão local',
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Sessão não validada',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.muted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        key: const Key('retry-session'),
                        onPressed: _busy
                            ? null
                            : () => _run(widget.onValidateCurrentSession),
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(_busy ? 'Validando…' : 'Tentar novamente'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        key: const Key('switch-account'),
                        onPressed: _busy ? null : _switchAccount,
                        child: const Text('Trocar de conta'),
                      ),
                      TextButton(
                        key: const Key('continue-visitor'),
                        onPressed: _busy ? null : _continueAsVisitor,
                        child: const Text('Continuar como visitante'),
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
}
