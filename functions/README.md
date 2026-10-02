# Upload administrativo da logo da Home

Esta implementação não foi implantada. Nenhum segredo real é armazenado no
repositório. O proprietário deve configurar e implantar a Function para usar
o botão de envio em aparelhos.

## Transporte e assinatura

Flutter chama `uploadHomeImage` (Callable v2, `us-central1`) com somente
`purpose: home_logo` e `imageBase64`. O Firebase SDK transporta a autenticação.
A Function autoriza o usuário, valida os bytes, gera uma assinatura Cloudinary
SHA-256 e envia multipart para o endpoint **image/upload** por HTTPS. Somente
metadados validados retornam ao Flutter; assinatura e credenciais não retornam.

Esta é uma adaptação consciente do transporte inicialmente sugerido: uma
assinatura Cloudinary entregue ao cliente não assina `file` ou `resource_type`,
e presets não impõem limite por arquivo. Passar o arquivo pelo servidor permite
aplicar o limite real antes de chamar o provedor e impedir uploads raw/video.
Referências oficiais:

- https://cloudinary.com/documentation/authentication_signatures
- https://cloudinary.com/documentation/upload_presets
- https://firebase.google.com/docs/functions/callable
- https://firebase.google.com/docs/functions/config-env

Não existe endpoint público que devolva assinatura reutilizável. Não há upload
unsigned/preset, transformação de entrada, consulta a Firestore, publicação,
exclusão de asset ou registro de bytes em logs.

## Quem está autorizado

O ID token validado pelo Firebase deve conter um dos seguintes:

- `admin: true` (booleano);
- `role: admin`;
- e-mail `bru.mourris69@gmail.com` **e** `email_verified: true`.

O UID deve existir. O campo role de documentos Firestore e flags enviados pelo
cliente não são usados. O e-mail legado é o mesmo das Rules atuais, com a
verificação adicional de e-mail neste endpoint. UI e Rules não foram
refatoradas. Caso esse usuário use e-mail/senha sem e-mail confirmado, confirme
o e-mail e renove a sessão antes de usar o upload. Claims administrativas devem
ser atribuídas exclusivamente por uma ferramenta confiável do proprietário;
nunca por código cliente ou campo editável de usuário.

## Política de imagem

- JPEG, PNG e WebP; extensão/nome/MIME informados pelo cliente não autorizam tipo.
- Até **5 MiB (5.242.880 bytes)**, no cliente e novamente no servidor.
- O picker já limita a imagem a 1600 × 1600 e qualidade 90 quando suportado;
  5 MiB comporta fotos desse piloto sem transportar arquivos originais enormes.
- Assinaturas iniciais dos bytes são verificadas e Cloudinary decodifica a
  imagem com `allowed_formats=jpg,png,webp`; cabeçalho forjado não substitui essa
  validação do provedor. A resposta deve ser resource_type=image/type=upload.
- HEIC/HEIF não são enviados como tal. Se o picker fornecer JPEG convertido,
  pode ser enviado; caso contrário a UI solicita JPEG, PNG ou WebP. Sem novo
  conversor ou requisito nativo nesta etapa.
- IDs: `tudo-aqui-macacu/home/<UUID gerado no servidor>`, overwrite=false.
- Em modo dynamic, asset_folder usa `tudo-aqui-macacu/home`. Em modo fixed,
  o caminho do public_id organiza a pasta; não é enviado asset_folder.

Base64 acrescenta aproximadamente 33% ao transporte app→Function. Para uma
única imagem limitada é uma escolha simples, sem fila ou pacote HTTP Flutter.
O servidor usa fetch/FormData/Blob/crypto nativos de Node 20, o runtime já
declarado no projeto. A chamada ao provedor tem timeout de 45 s; a Function
tem timeout de 60 s e o cliente de 70 s. Indicador indeterminado: não simula
percentual de upload ou capacidade de cancelamento.

## Configuração externa pelo proprietário

1. No ambiente Cloudinary correto, consulte **Cloud name**, **API key** e o
   modo de pastas (dynamic ou fixed). Não copie o API secret para o Flutter,
   Firestore, GitHub, Codemagic ou arquivos do repositório.
2. Na raiz do app, configure o único segredo, pelo prompt seguro do Firebase:

   ```powershell
   firebase functions:secrets:set CLOUDINARY_API_SECRET --project tudo-aqui-macacu
   ```

   Informe o **API secret do mesmo ambiente Cloudinary** quando solicitado.
   Não use `secrets:access` para imprimir ou conferir seu valor em logs.
3. Os parâmetros públicos usados por defineString são:

   | Nome | Valor que o proprietário deve informar |
   | --- | --- |
   | CLOUDINARY_CLOUD_NAME | Cloud name do ambiente Cloudinary |
   | CLOUDINARY_API_KEY | API key daquele ambiente |
   | CLOUDINARY_FOLDER_MODE | dynamic (padrão) ou fixed para ambiente legado |

   O Firebase CLI solicita parâmetros sem valor durante a futura implantação;
   pode armazenar parâmetros públicos em arquivo .env do projeto Functions,
   ignorado pelo Git. O API secret usa Secret Manager, vinculado apenas a esta
   Function por `secrets`, e é lido somente durante a chamada.
4. **Somente quando o proprietário decidir implantar**, instale as dependências
   existentes e implante apenas a nova Function:

   ```powershell
   npm --prefix functions install
   firebase deploy --only functions:uploadHomeImage --project tudo-aqui-macacu
   ```

   A implantação requer o projeto Firebase habilitado para Functions/Secret
   Manager e as permissões apropriadas da conta do proprietário. Não é feita
   automaticamente nesta etapa. A função de push existente é preservada.
   Não há necessidade de novo upload preset ou biblioteca Cloudinary SDK.

## UX, persistência e auditoria

O piloto continua no HomeEditor, somente visual.logoUrl. LOCAL e UPLOADING
bloqueiam salvar/publicar; os bytes permanecem em memória. Envio concluído
produz REMOTE com a URL HTTPS original. Metadados publicId, width, height,
format e bytes ficam somente no resultado transitório do serviço.

Enviar não salva nem publica. O fluxo existente salva rascunho/publica após
ação explícita; publicação mantém `publish_home` no admin_audit_logs. Seleção e
upload isolados não criam logs extras. URL manual e otimização de entrega
continuam disponíveis. A imagem antiga nunca é excluída automaticamente.

Falha mantém a foto local e oferece retry explícito. Timeout/saída do editor
não garantem que um asset não tenha sido criado; retry pode criar outro asset
com UUID distinto. Nenhum cleanup automático é executado. Uma resposta que
chega depois do fechamento ou de substituição do estado não altera o editor.

## Validação offline e roteiro em aparelho

```powershell
node --check functions/index.js
node --check functions/home_image_upload.js
node --test functions/test/home_image_upload.test.js
flutter analyze --no-pub
flutter test --no-pub
```

Os testes não usam Firebase nem Cloudinary reais. Em aparelho, após configurar
e implantar: admin → Home → Editor completo → Logo da Home → Galeria → escolher
foto → Enviar imagem → conferir preview remoto → salvar somente rascunho.
Confira também falha de rede/retry, arquivo acima do limite e HEIC não convertido.
Usuário comum deve receber permission-denied no endpoint mesmo que tente
chamá-lo fora da interface. Nenhum dado real deve ser publicado para teste.
