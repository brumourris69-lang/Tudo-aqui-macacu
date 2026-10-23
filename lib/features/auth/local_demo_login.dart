import 'package:flutter/material.dart';
import '../../core/auth/app_auth.dart';
import '../../core/config/local_search_environment.dart';

typedef LocalDemoAuthenticate =
    Future<void> Function(String email, String password);

class LocalDemoLoginForm extends StatefulWidget {
  const LocalDemoLoginForm({
    super.key,
    this.authenticate,
    this.onAuthenticated,
  });

  final LocalDemoAuthenticate? authenticate;
  final Future<void> Function()? onAuthenticated;

  @override
  State<LocalDemoLoginForm> createState() => _LocalDemoLoginFormState();
}

class _LocalDemoLoginFormState extends State<LocalDemoLoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  Future<void> _authenticate(String email, String password) async {
    await AppAuth.signInEmail(email, password);
  }

  Future<void> _submit() async {
    if (!LocalSearchEnvironment.enabled ||
        _loading ||
        !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await (widget.authenticate ?? _authenticate)(
        _email.text.trim(),
        _password.text,
      );
      _password.clear();
      await widget.onAuthenticated?.call();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível entrar. Confira o e-mail e a senha.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!LocalSearchEnvironment.enabled) return const SizedBox.shrink();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 58),
                const SizedBox(height: 14),
                Text(
                  'Conta de demonstração',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Entre com a conta criada no Firebase Emulator local.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('local-demo-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(
                    labelText: 'E-mail de demonstração',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value != null &&
                          RegExp(
                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                          ).hasMatch(value.trim())
                      ? null
                      : 'Informe um e-mail válido.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('local-demo-password'),
                  controller: _password,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword
                          ? 'Mostrar senha'
                          : 'Ocultar senha',
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Informe a senha.'
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    key: const Key('local-demo-login-error'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _loading ? null : _submit,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login_rounded),
                  label: Text(
                    _loading ? 'Entrando…' : 'Entrar no Emulator local',
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
