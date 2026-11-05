import 'package:firebase_auth/firebase_auth.dart';

enum AuthErrorAction {
  signIn,
  createAccount,
  resetPassword,
  googleSignIn,
  appleSignIn,
  updateProfile,
  signOut,
}

/// Converts provider failures into messages safe to show without exposing
/// account details, tokens, or raw Firebase exception text.
String authErrorMessage(Object error, {required AuthErrorAction action}) {
  if (error is! FirebaseAuthException) {
    return 'Não foi possível concluir agora. Tente novamente em instantes.';
  }

  return switch (error.code.toLowerCase()) {
    'invalid-email' => 'Confira o formato do e-mail e tente novamente.',
    'user-disabled' =>
      'Esta conta está temporariamente desativada. Entre em contato com o suporte.',
    'user-not-found' || 'wrong-password' || 'invalid-credential' =>
      'E-mail ou senha incorretos. Confira os dados e tente novamente.',
    'email-already-in-use' =>
      'Este e-mail já possui uma conta. Entre ou use a recuperação de senha.',
    'weak-password' => 'Escolha uma senha com pelo menos 6 caracteres.',
    'operation-not-allowed' =>
      'Esta forma de acesso ainda não está habilitada neste ambiente.',
    'too-many-requests' =>
      'Muitas tentativas em pouco tempo. Aguarde um pouco e tente novamente.',
    'network-request-failed' =>
      'Sem conexão no momento. Verifique a internet e tente novamente.',
    'account-exists-with-different-credential' =>
      'Esta conta usa outra forma de acesso. Entre com o método já cadastrado.',
    'requires-recent-login' =>
      'Por segurança, entre novamente antes de continuar.',
    _ => switch (action) {
      AuthErrorAction.signIn =>
        'Não foi possível entrar agora. Tente novamente em instantes.',
      AuthErrorAction.createAccount =>
        'Não foi possível criar a conta agora. Confira os dados e tente novamente.',
      AuthErrorAction.resetPassword =>
        'Não foi possível enviar as instruções agora. Tente novamente em instantes.',
      AuthErrorAction.googleSignIn =>
        'Não foi possível entrar com o Google. Verifique a conexão e tente novamente.',
      AuthErrorAction.appleSignIn =>
        'Não foi possível entrar com a Apple. Verifique a conexão e tente novamente.',
      AuthErrorAction.updateProfile =>
        'Não foi possível atualizar seu perfil agora. Tente novamente.',
      AuthErrorAction.signOut =>
        'Não foi possível encerrar a sessão agora. Tente novamente.',
    },
  };
}
