# Auditoria de segurança — Tudo Aqui Macacu

Data: 22/09/2026

## CRÍTICO

Nenhum segredo administrativo privado foi encontrado versionado. A varredura local encontrou somente `firebase/android/google-services.json`, que é configuração cliente do Firebase. Ele não é uma service account, mas a chave Web/API do projeto precisa ficar restrita no Google Cloud.

## ALTO

### Autorização administrativa ainda mantém fallback por e-mail

- Risco: enquanto o fallback por e-mail existir, a segurança depende também da integridade do provedor de login e das regras atuais. O app Flutter sozinho não é barreira.
- Local: `firestore.rules`, `lib/redesigned_app.dart`.
- Correção aplicada: as regras já aceitam `request.auth.token.admin == true` e `request.auth.token.role == 'admin'`, preservando compatibilidade com o administrador atual.
- Ação manual: migrar o admin para Custom Claim e depois remover o fallback por e-mail em uma etapa controlada.

### Envio de push global dependia de fila sensível

- Risco: se a fila `push_queue` fosse escrita indevidamente, poderia disparar notificações para todos os dispositivos.
- Local: `firestore.rules`, `functions/index.js`.
- Correção aplicada: `push_queue` agora aceita somente payload esperado, exige `status == queued`, limita tamanhos de campos e a Function valida título, mensagem e link antes de enviar.
- Ação manual: publicar Firestore Rules e redeploy das Cloud Functions.

### Tokens FCM podiam ter documento inconsistente

- Risco: documento em `users/{uid}/devices/{deviceId}` poderia ter `token` diferente do ID, criando estado inconsistente para logout/limpeza.
- Local: `firestore.rules`, `functions/index.js`.
- Correção aplicada: rules exigem `request.resource.data.token == deviceId`; a Function usa o campo `token` com fallback para o ID e remove tokens inválidos.

## MÉDIO

### Perfil do usuário aceitava e-mail divergente do Auth

- Risco: usuário autenticado poderia gravar um e-mail diferente no próprio documento de perfil.
- Local: `firestore.rules`.
- Correção aplicada: create/update de perfil agora só aceita `email` igual ao `request.auth.token.email`, mantendo `role` e `createdAt` protegidos.

### Links externos aceitavam schemes perigosos

- Risco: conteúdo administrável poderia tentar abrir `javascript:`, `file:`, `data:` ou outro scheme não desejado.
- Local: `lib/redesigned_app.dart`.
- Correção aplicada: abertura externa agora permite somente `https`, `tel`, `mailto`, `whatsapp` e `geo`.

### Function de push não tratava lote acima de 500 tokens

- Risco: envio global com mais de 500 tokens poderia falhar por limite do Firebase Messaging.
- Local: `functions/index.js`.
- Correção aplicada: envio agora é feito em lotes de até 500 tokens.

## BAIXO

### GitHub Actions sem permissões explícitas

- Risco: o token padrão do GitHub poderia receber permissões maiores que o necessário.
- Local: `.github/workflows/main.yml`.
- Correção aplicada: adicionado `permissions: contents: read`.

### `.gitignore` não cobria todas as chaves iOS/APNs comuns

- Risco: chaves `.p8`, certificados e perfis Apple poderiam ser adicionados por engano.
- Local: `.gitignore`.
- Correção aplicada: adicionados padrões para `.p8`, certificados, provision profiles e `GoogleService-Info.plist`.

## INFORMATIVO

### `createdAt` do perfil

- Local: `lib/redesigned_app.dart`.
- Situação: já estava corrigido. `createdAt` só é gravado quando o documento ainda não existe; `updatedAt` é atualizado nos logins.

### Cloudinary

- Situação: não foi encontrado API Secret do Cloudinary no Flutter. O app trabalha com URLs e otimização de imagens.
- Pendência: upload assinado/credenciais administrativas, se vier a existir, deve ficar em backend confiável, nunca no Flutter.

### Android e iOS

- Situação: este repositório não mantém `android/` e `ios/` versionados; o workflow recria Android no CI. A revisão direta de manifests/plists não se aplica ao estado versionado atual.
- Pendência: quando iOS for adicionado ao repositório, revisar `Info.plist`, URL schemes, permissões, App Attest/DeviceCheck e configuração do Google Sign-In.

### App Check

- Situação: não foi ativado enforcement nesta etapa para evitar derrubar produção.
- Pendência: configurar App Check em etapas: integrar SDK, monitorar, validar e só depois ativar enforcement no Firebase Console.

## AÇÕES QUE BRUNO PRECISA FAZER

1. Firebase Console → Firestore Database → Regras: publicar o `firestore.rules` atualizado.
2. Firebase Console/CLI → Functions: fazer deploy da Function `deliverPushNotification`.
3. Firebase Auth → Custom Claims: conceder admin para sua conta em ambiente seguro com Firebase Admin SDK. Depois sair e entrar novamente no app.
4. Google Cloud Console → APIs e serviços → Credenciais: restringir a API key do `google-services.json` ao pacote Android correto, SHA correto e APIs Firebase/Google necessárias.
5. Firebase Console → App Check: cadastrar Android com Play Integrity e iOS com App Attest/DeviceCheck, monitorar primeiro e ativar enforcement só depois de confirmar que o app real está enviando tokens válidos.
6. Cloudinary: manter API Secret fora do app. Se algum dia precisar de upload assinado, criar assinatura em backend seguro.
7. GitHub → Settings → Secrets and variables: confirmar que keystore e senhas estão somente em GitHub Secrets/Codemagic, nunca no código.
8. Apple Developer/Google Play: antes do lançamento final, conferir Bundle ID, package name, SHA de assinatura final e permissões das lojas.

