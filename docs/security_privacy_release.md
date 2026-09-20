# Tudo Aqui Macacu — Segurança, Privacidade e Release

## Métricas

O app grava métricas agregadas na coleção `metrics` somente para ações permitidas pelo cliente e pelas Firestore Rules. O documento de métrica contém:

- `action`: tipo do evento;
- `target`: identificador do item, como id do estabelecimento ou título público;
- `targetType`: tipo do alvo, como `business`, `offer`, `coupon`, `ad`;
- `createdAt`: timestamp do servidor.

O app não grava `userId`, email, nome, localização precisa ou outro dado pessoal na métrica. As métricas são para administração comercial agregada.

Eventos preparados:

- estabelecimento: visualização, WhatsApp, telefone, mapa, Instagram, favorito e compartilhamento;
- ofertas/cupons: abertura;
- banners/anúncios: abertura por toque;
- utilidades/notificações: abertura;
- classificados e adoção: ações reservadas para módulos futuros.

## Perfil de usuário

`syncUserProfile()` atualiza `displayName`, `email`, `photoUrl` e `updatedAt`. `createdAt` é gravado somente quando o documento ainda não existe. Usuário comum não deve alterar `role`, `createdAt` ou dados administrativos pelas regras.

## Administrador e Custom Claims

O app ainda mantém compatibilidade com o email administrador atual para não quebrar o acesso. As Firestore Rules já aceitam também:

- `request.auth.token.admin == true`; ou
- `request.auth.token.role == 'admin'`.

Para migração segura, configure Custom Claims em ambiente administrativo externo, por exemplo com Firebase Admin SDK em máquina confiável ou Cloud Function protegida. Nunca coloque service account, chave privada ou credenciais administrativas dentro do Flutter.

Exemplo conceitual com Admin SDK:

```js
await admin.auth().setCustomUserClaims(uid, { admin: true, role: 'admin' });
```

Depois disso, o usuário deve sair e entrar novamente para o token carregar as claims.

## Firestore Rules

As regras protegem:

- leitura/escrita de perfil por proprietário;
- `role` contra alteração por usuário comum;
- dispositivos FCM por proprietário;
- métricas com campos permitidos e sem `userId`;
- conteúdo público com escrita administrativa;
- fluxo de moderação para avaliações e propostas;
- logs administrativos somente para admin.

A interface visual não é considerada segurança. Operações administrativas dependem de Rules.

## FCM

No logout, o app remove o token do usuário atual e apaga o token local do Firebase Messaging. A Cloud Function de envio remove tokens inválidos ou marca erro em tokens problemáticos, evitando acúmulo indefinido de tokens expirados.

## Firebase App Check

Recomendado para Android antes de publicação:

1. No Firebase Console, abrir App Check.
2. Registrar o app Android.
3. Usar Play Integrity para produção.
4. Durante testes internos, manter modo de debug conforme documentação Firebase.
5. Ativar enforcement gradualmente para Firestore, Functions e Storage quando os testes estiverem estáveis.

Não há segredo privado a inserir no código Flutter para App Check.

## Dados usados pelo app

Para futura Política de Privacidade e Google Play Data Safety, mapear como uso real:

- autenticação Google: email, nome e foto do perfil;
- favoritos do usuário;
- token FCM para notificações;
- mensagens enviadas em formulários públicos;
- avaliações/propostas enviadas pelo usuário;
- métricas agregadas de uso sem identificação pessoal;
- imagens/links cadastrados pelo administrador via Cloudinary/Firestore.

Não documentar coleta de localização precisa se ela não for implementada. Links de mapa apenas abrem rotas externas quando o usuário toca.

## Android e publicação

Teste interno:

- artefato: `app-debug.apk`;
- gerado automaticamente no push pelo GitHub Actions.

Produção:

- artefato: `app-release.aab`;
- gerar manualmente pelo workflow `Gerar Android` selecionando `release-aab`;
- exige GitHub Secrets:
  - `ANDROID_KEYSTORE_BASE64`;
  - `ANDROID_KEYSTORE_PASSWORD`;
  - `ANDROID_KEY_ALIAS`;
  - `ANDROID_KEY_PASSWORD`.

Não publicar automaticamente na Google Play. A publicação deve ser feita manualmente depois de revisar login Google, App Check, Data Safety, política de privacidade e assinatura release.

## Segredos

Nunca versionar:

- service account JSON;
- private keys;
- keystore;
- senhas;
- tokens;
- arquivos `.env` privados.

`google-services.json` é configuração cliente do Firebase, não uma credencial administrativa, mas deve pertencer ao projeto correto.
