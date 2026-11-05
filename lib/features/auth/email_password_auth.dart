import 'package:flutter/material.dart';

import '../../core/auth/auth_error_message.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_brand.dart';

typedef EmailPasswordSignIn =
    Future<void> Function(String email, String password);
typedef EmailPasswordRegister =
    Future<void> Function(String displayName, String email, String password);
typedef EmailPasswordReset = Future<void> Function(String email);
typedef EmailVerificationSend = Future<void> Function();
typedef EmailVerificationRefresh = Future<bool> Function();

class EmailPasswordAuthView extends StatefulWidget {
  const EmailPasswordAuthView({
    super.key,
    required this.signIn,
    required this.register,
    required this.resetPassword,
    required this.onAuthenticated,
    this.requireEmailVerification = false,
    this.sendEmailVerification,
    this.refreshEmailVerification,
  });

  final EmailPasswordSignIn signIn;
  final EmailPasswordRegister register;
  final EmailPasswordReset resetPassword;
  final Future<void> Function() onAuthenticated;
  final bool requireEmailVerification;
  final EmailVerificationSend? sendEmailVerification;
  final EmailVerificationRefresh? refreshEmailVerification;

  @override
  State<EmailPasswordAuthView> createState() => _EmailPasswordAuthViewState();
}

class _EmailPasswordAuthViewState extends State<EmailPasswordAuthView> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _registering = false;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _awaitingVerification = false;
  bool _verificationSent = false;
  String? _error;

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
        ? null
        : 'Informe um e-mail válido.';
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Informe sua senha.';
    if (_registering && value.length < 6) {
      return 'Use pelo menos 6 caracteres.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_registering) {
        await widget.register(
          _name.text.trim(),
          _email.text.trim(),
          _password.text,
        );
      } else {
        await widget.signIn(_email.text.trim(), _password.text);
      }
      _password.clear();
      if (widget.requireEmailVerification &&
          widget.refreshEmailVerification != null &&
          !await widget.refreshEmailVerification!()) {
        if (mounted) setState(() => _awaitingVerification = true);
        return;
      }
      await widget.onAuthenticated();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = authErrorMessage(
            error,
            action: _registering
                ? AuthErrorAction.createAccount
                : AuthErrorAction.signIn,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendVerification() async {
    final send = widget.sendEmailVerification;
    if (_busy || send == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await send();
      if (mounted) {
        setState(() => _verificationSent = true);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = authErrorMessage(error, action: AuthErrorAction.signIn),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkVerification() async {
    final refresh = widget.refreshEmailVerification;
    if (_busy || refresh == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (await refresh()) {
        await widget.onAuthenticated();
      } else if (mounted) {
        setState(() {
          _error =
              'Ainda não confirmamos o e-mail. Abra o link recebido e tente novamente.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = authErrorMessage(error, action: AuthErrorAction.signIn),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendReset() async {
    if (_busy) return;
    final emailError = _validateEmail(_email.text);
    if (emailError != null) {
      setState(() => _error = emailError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.resetPassword(_email.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Se existir uma conta para esse e-mail, você receberá instruções para redefinir a senha.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = authErrorMessage(
            error,
            action: AuthErrorAction.resetPassword,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleMode() {
    if (_busy) return;
    setState(() {
      _registering = !_registering;
      _error = null;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Acesso à sua conta')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              color: Colors.white,
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.feature),
                side: const BorderSide(color: AppColors.mist),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AppBrand(compact: true, tagline: '')),
                    const SizedBox(height: AppSpacing.xl),
                    if (_awaitingVerification)
                      _buildVerificationPrompt(context)
                    else
                      Form(
                        key: _formKey,
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Icon(
                                _registering
                                    ? Icons.person_add_alt_1_rounded
                                    : Icons.lock_open_rounded,
                                size: 42,
                                color: AppColors.sky,
                                semanticLabel: _registering
                                    ? 'Criar conta'
                                    : 'Entrar na conta',
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                _registering
                                    ? 'Crie sua conta'
                                    : 'Que bom ter você aqui',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                _registering
                                    ? 'Use seus dados para salvar seus lugares favoritos.'
                                    : 'Entre para acessar seus favoritos e personalizar sua experiência.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppColors.muted),
                              ),
                              const SizedBox(height: AppSpacing.xl),
                              if (_registering) ...[
                                TextFormField(
                                  key: const Key('auth-name'),
                                  controller: _name,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.name],
                                  decoration: const InputDecoration(
                                    labelText: 'Seu nome',
                                    prefixIcon: Icon(
                                      Icons.person_outline_rounded,
                                    ),
                                  ),
                                  validator: (value) =>
                                      (value ?? '').trim().length >= 2
                                      ? null
                                      : 'Informe seu nome.',
                                ),
                                const SizedBox(height: AppSpacing.md),
                              ],
                              TextFormField(
                                key: const Key('auth-email'),
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.username],
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: 'E-mail',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                validator: _validateEmail,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              TextFormField(
                                key: const Key('auth-password'),
                                controller: _password,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                autofillHints: [
                                  _registering
                                      ? AutofillHints.newPassword
                                      : AutofillHints.password,
                                ],
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: 'Senha',
                                  prefixIcon: const Icon(Icons.key_outlined),
                                  suffixIcon: IconButton(
                                    tooltip: _obscurePassword
                                        ? 'Mostrar senha'
                                        : 'Ocultar senha',
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                validator: _validatePassword,
                              ),
                              if (!_registering)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    key: const Key('auth-reset-password'),
                                    onPressed: _busy ? null : _sendReset,
                                    child: const Text('Esqueci minha senha'),
                                  ),
                                ),
                              if (_error != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                Semantics(
                                  liveRegion: true,
                                  child: Container(
                                    key: const Key('email-auth-error'),
                                    padding: const EdgeInsets.all(
                                      AppSpacing.md,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.errorContainer,
                                      borderRadius: BorderRadius.circular(
                                        AppRadii.control,
                                      ),
                                    ),
                                    child: Text(
                                      _error!,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.md),
                              FilledButton.icon(
                                key: const Key('email-auth-submit'),
                                onPressed: _busy ? null : _submit,
                                icon: _busy
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        _registering
                                            ? Icons.person_add_alt_1_rounded
                                            : Icons.login_rounded,
                                      ),
                                label: Text(
                                  _busy
                                      ? 'Aguarde…'
                                      : _registering
                                      ? 'Criar conta'
                                      : 'Entrar',
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextButton(
                                key: const Key('email-auth-mode'),
                                onPressed: _toggleMode,
                                child: Text(
                                  _registering
                                      ? 'Já tenho uma conta — entrar'
                                      : 'Ainda não tenho conta — cadastrar',
                                ),
                              ),
                              const Divider(height: AppSpacing.section),
                              Text(
                                'Entrar é opcional. Você pode voltar e continuar explorando a cidade sem conta.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildVerificationPrompt(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(
        Icons.mark_email_unread_outlined,
        size: 44,
        color: AppColors.sky,
        semanticLabel: 'Verifique seu e-mail',
      ),
      const SizedBox(height: AppSpacing.md),
      Text(
        'Confirme seu e-mail',
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Enviaremos um link para ${_email.text.trim()}. Abra a mensagem e depois volte aqui para confirmar.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.muted),
      ),
      if (_verificationSent) ...[
        const SizedBox(height: AppSpacing.md),
        const Text(
          'Mensagem de verificação enviada. Confira também a pasta de spam.',
          key: Key('email-verification-sent'),
          textAlign: TextAlign.center,
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: AppSpacing.md),
        Text(
          _error!,
          key: const Key('email-verification-error'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const SizedBox(height: AppSpacing.xl),
      FilledButton.icon(
        key: const Key('send-email-verification'),
        onPressed: _busy ? null : _sendVerification,
        icon: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.mark_email_read_outlined),
        label: Text(
          _verificationSent ? 'Enviar novamente' : 'Enviar verificação',
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      OutlinedButton(
        key: const Key('refresh-email-verification'),
        onPressed: _busy ? null : _checkVerification,
        child: const Text('Já confirmei meu e-mail'),
      ),
      TextButton(
        key: const Key('email-verification-back'),
        onPressed: _busy
            ? null
            : () => setState(() {
                _awaitingVerification = false;
                _verificationSent = false;
                _error = null;
              }),
        child: const Text('Voltar ao login'),
      ),
    ],
  );
}
