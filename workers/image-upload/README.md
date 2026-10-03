# Upload administrativo de imagens — Cloudflare Workers Free + Cloudinary

Os editores da Home, Turismo e conteúdos locais utilizam
`WorkerImageUploadService` e o seletor compartilhado `ImageUploadButton`.
O envio direto cobre logos, fundos, capas e fotos das galerias; adicionar por
URL continua disponível. Galerias recebem uma foto por envio e preservam
reordenação, escolha de capa e remoção. Firebase Authentication e
Firestore continuam no projeto existente; este caminho não chama Cloud Functions
nem Secret Manager e não exige habilitar Blaze. A Function anterior permanece
no repositório para compatibilidade, mas não é o serviço padrão do editor.

O endpoint `/v1/home-logo` e a pasta `tudo-aqui-macacu/home` mantêm os nomes
do piloto por compatibilidade com o Worker publicado. Não houve mudança de
contrato, autorização ou deploy para ampliar os editores. O limite de cinco
envios por minuto é compartilhado entre todos eles. Uma imagem enviada e não
salva no formulário permanece no Cloudinary; remover/substituir no editor não
exclui o arquivo no provedor.

## Fluxo

1. Administrador seleciona uma foto no fluxo existente e confere o preview.
2. Flutter obtém o ID token Firebase da sessão e envia bytes por HTTPS para
   `POST /v1/home-logo` com `Authorization: Bearer <ID token>`.
3. Worker verifica assinatura RS256 usando chaves públicas do Google, projeto,
   issuer, audience, expiração, iat, auth_time e UID. Aplica as mesmas claims
   administrativas confiáveis do servidor anterior (ou e-mail legado verificado).
4. Limite de 5 tentativas/minuto por UID por localidade Cloudflare. Vinculação
   ausente bloqueia o upload. Não é uma cota global exata ou garantia contra abuso.
5. Corpo é lido com limite incremental de 5 MiB, mesmo sem Content-Length.
   Bytes identificam JPEG/PNG/WebP; Cloudinary decodifica e valida o formato.
6. Worker assina e faz o upload para endpoint fixo Cloudinary; assinatura e
   segredo nunca são retornados ao cliente. Reutiliza a implementação server-side
   de `functions/home_image_upload.js`, IDs UUID e overwrite=false.
7. Flutter aceita somente a resposta validada e o editor salva a URL pelo fluxo
   existente. Não há publicação automática nem exclusão de mídia ao substituir.

Sem vídeo, upload unsigned, mudança nas Rules ou gravação de bytes no Firestore.
Endpoint nativo Android/iOS: origens de navegador são recusadas; CORS web não está
habilitado. Claims do cliente/campos editáveis Firestore não concedem acesso.
JWTs válidos podem durar até sua expiração; não há checagem imediata de revogação.

## Configuração e publicação

Na pasta `workers/image-upload`:

```powershell
npm ci
npx wrangler login --scopes account:read user:read workers:write workers_scripts:write
npm test
npm run check
npm run deploy
npx wrangler secret put CLOUDINARY_API_SECRET
```

Colar o segredo **somente no prompt protegido ou no campo Secret do painel**.
Nunca usar argumento de shell, `.env` versionado, token no chat ou logs.
O deploy sem segredo deixa o upload bloqueado. Publicar e configurar não
significa que um upload real já foi validado.

Parâmetros públicos em `wrangler.jsonc`: projeto Firebase `tudo-aqui-macacu`,
cloud name e API key do ambiente Cloudinary Root conferido no painel, modo de
pastas `dynamic`. Caso a conta tenha modo legado fixed, ajustar só esse parâmetro.
Não comprar domínio: `workers.dev` fornece HTTPS. Não ativar plano pago.

Usar a URL emitida pelo deploy com sufixo `/v1/home-logo` como variável pública
`IMAGE_UPLOAD_WORKER_URL` do build, por exemplo:

```powershell
flutter build apk --debug --dart-define=IMAGE_UPLOAD_WORKER_URL=https://NOME.SUBDOMINIO.workers.dev/v1/home-logo
```

O mesmo define funciona em `flutter run`, AAB e build iOS. GitHub Actions usa a
variável de repositório `IMAGE_UPLOAD_WORKER_URL`; Codemagic usa uma variável de
ambiente com esse nome. O código/CI já têm como padrão a URL publicada:
`https://tudo-aqui-macacu-image-upload.tudo-aqui-macacu-image-upload.workers.dev/v1/home-logo`.
Essa URL é pública, não é a API Secret. APKs antigos não
recebem essa alteração automaticamente. Ausência/URL insegura produz mensagem
de configuração sem enviar token/foto para outro servidor.

## Validação antes de liberar

```powershell
npm test
npm run check
flutter analyze --no-pub
flutter test --no-pub
```

Após deploy: POST sem token deve responder 401; rota desconhecida deve ser 404.
No novo APK, entrar como administrador e enviar uma foto pequena, confirmar
preview/URL, salvar e reabrir. Conferir rejeição para não administrador, arquivo
maior que 5 MiB, rede interrompida e novas tentativas. Validar em Android e iOS.

Workers Free tem limites de requisições, memória e CPU (10 ms de CPU/request).
Espera de rede não consome esse tempo, mas validação/cópia de imagens consome.
Bytes diretos evitam overhead de base64; testes locais/dry-run não comprovam que
todos os dispositivos/tamanhos passam na cota de CPU de produção. Medir imagens
representativas em produção antes de afirmar suporte irrestrito a 5 MiB.
Ao alcançar cotas gratuitas o upload pode ficar indisponível; este código não
contrata upgrade automático. Cloudinary também continua sujeito à cota da conta.

Referências:
- https://firebase.google.com/docs/auth/admin/verify-id-tokens
- https://developers.cloudflare.com/workers/configuration/secrets/
- https://developers.cloudflare.com/workers/platform/limits/
- https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/
- https://cloudinary.com/documentation/upload_images
