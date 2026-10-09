# Firebase — Tudo Aqui Macacu

O aplicativo pode ser explorado sem login Google. A autorização administrativa exige Custom Claims e estado válido em `admin_authorizations`; e-mails não concedem acesso. O login é usado para favoritos, preferências e recursos personalizados.

## Arquivo Android

Baixe `google-services.json` no Firebase Console e coloque-o em `android/app/google-services.json`. O arquivo é necessário para o login Google funcionar no APK Android.

## Regras do Firestore

Copie o conteúdo de `firestore.rules` para Firestore Database > Regras e publique. As mensagens de contato só podem ser lidas pelo administrador; qualquer pessoa conectada pode enviá-las.
