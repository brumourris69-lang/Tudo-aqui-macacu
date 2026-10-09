# Notificações — correção local da exposição (Etapa 1A)

Nada deste documento autoriza deploy, migração, envio FCM real ou alteração de dados de produção.

## Causa e pontos afetados

`NotificationComposer` gravava `targetEmail` no mesmo documento público dos
comunicados. `NotificationsView` consultava todos os publicados e filtrava o e-mail
no dispositivo. O catch-all de `firestore.rules` autorizava a leitura antes desse
filtro. `deliverPushNotification` também usava e-mail para selecionar dispositivos.

## Contrato preparado

- `notifications/{id}`: comunicados públicos publicados com `targetEmail: ''`.
  Não aceita `targetUid` ou e-mail destinatário nas novas escritas.
- `private_notifications/{id}`: título, descrição, link, publicação, atualização e
  `targetUid`. Não aceita `targetEmail` ou campos adicionais. Somente conta
  cadastrada com UID correspondente e publicação ativa, ou Admin, pode ler.
  Aqui "publicação ativa" significa `published: true`; a política global de
  `active`/`expiresAt` não foi alterada nesta etapa.
- Visitantes autenticados anonimamente e visitantes sem sessão só leem públicos.
- Criação/edição/exclusão continuam administrativas; `admin()` não foi alterado.
- O Admin continua informando e-mail. O repositório procura no máximo dois perfis
  usando igualdade de e-mail. Exige exatamente um resultado; não encontrar ou
  encontrar ambiguidade interrompe o envio, sem transformá-lo em broadcast.
- Conteúdo privado e fila nova guardam somente UID, sem e-mail destinatário.
- Notificação e fila são gravadas no mesmo batch, com ID compartilhado. Falha de
  regras impede ambas as gravações. O registro de auditoria permanece separado.
- A tela combina a consulta pública (`published == true`, `targetEmail == ''`)
  com a consulta privada (`published == true`, `targetUid == current UID`).
  Troca de sessão recria o StreamBuilder por UID e cancela as assinaturas antigas.
  Não depende de filtragem por e-mail no Flutter para autorização.
- Push usa UID quando presente, mantendo resolução por e-mail apenas para filas
  antigas privadas. Destinatários inválidos ou ambíguos nunca viram broadcast.

## Compatibilidade e migração futura, NÃO executada

1. Públicos antigos com `targetEmail: ''` continuam nas mesmas coleção e consulta.
2. Documentos antigos com `targetEmail` não vazio ficam legíveis somente pelo
   Admin, mesmo com `published: true`. Não são apagados nem entregues ao
   destinatário pelo aplicativo até migração revisada.
3. Documentos sem `targetEmail`, nulos ou malformados também ficam somente para
   Admin. Não é possível manter a antiga consulta ampla com segurança: regras
   não filtram resultados. Revisar esses registros antes de classificá-los.
4. Numa futura migração autorizada, executar inventário administrativo/dry-run,
   determinar positivamente quais documentos são públicos e quais são privados.
   Para públicos aprovados, normalizar somente o marcador vazio. Para privados,
   resolver e confirmar UID em Auth/perfil; ambiguidade, conta ausente ou dados
   divergentes exigem revisão humana. Copiar apenas campos de conteúdo para
   `private_notifications`, preservando ID/publicação/validade aplicáveis conforme
   contrato aprovado. Se validade/estado exigir expansão do contrato, preparar e
   testar antes de copiar. Não copiar e-mail nem criar nova fila de push.
5. Manter originais privados bloqueados para leitura pública, sem remoção
   automática. Uma cópia jamais deve transformar conteúdo privado em público.
6. Apps antigos fazem consulta ampla e receberão permission-denied após regras
   seguras. A versão nova é necessária para a lista de notificações funcionar.
   Não reabrir as regras para contornar compatibilidade de versões antigas.

## Push e testes exclusivamente locais

FCM não tem emulador. `sendPushBatch` impede transporte FCM quando Functions
Emulator está ativo; exige também projeto `demo-*` e Firestore loopback. A fila
recebe `deliveryMode: emulator-simulated`. O teste passa por Auth, Firestore Rules,
batch e gatilho Functions reais do Emulator, mas a entrega ao provedor é simulada.
Não comprova entrega em dispositivos de produção.

O gatilho existente utilizava `admin.firestore.FieldValue`, indisponível no
wrapper do Emulator instalado. Os timestamps do fluxo de push passam a importar
`FieldValue` de `firebase-admin/firestore`, mantendo a semântica serverTimestamp.

Execução de integração (somente após iniciar o Emulator demo local):

```powershell
$env:GCLOUD_PROJECT='demo-universal-search'
$env:FUNCTIONS_EMULATOR='true'
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8087'
$env:FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9097'
node functions/integration/notifications_emulator.js
```

O script carrega regras apenas no projeto demo existente, cria fixtures fictícias
identificadas por execução e não limpa dados preexistentes. Não requer credenciais
de produção. Queries usam filtros de igualdade, sem ordenação adicional; testar
também a configuração de índices efetivamente implantada antes de liberar.

## Implantação futura e riscos restantes

Validação executada nesta etapa: Flutter Analyze sem problemas; 243 testes
Flutter da suíte normal; 42 testes unitários Node; 12 cenários de integração no
projeto `demo-universal-search` (Auth 9097, Firestore 8087, Functions 5007). Todos
passaram. Widgets de listagem, estado vazio e erro foram exercitados em testes;
não houve validação visual da tela no MEmu. Não havia sessão Flutter interativa
ativa para Hot Reload. Nenhum APK foi gerado.

- Revisar esta alteração e executar novamente testes de Rules/Flutter/Functions.
- Autorizar separadamente implantação de regras, backend compatível com UID e
  versão do app. Priorizar bloqueio da exposição; aceitar temporariamente erro
  de listagem nas versões antigas, sem ampliar permissões.
- Planejar migração revisada e comunicação de atualização do aplicativo.
- Verificar criação administrativa e entrega FCM com contas/dispositivos de teste
  somente em etapa explicitamente autorizada.
- Autorização administrativa legada por e-mail, App Check de produção,
  idempotência de push e retenção permanecem pendentes da auditoria; não foram
  corrigidos silenciosamente nesta etapa.
- O mapeamento e-mail → UID reutiliza perfis atuais. Integridade e sincronização
  desses perfis devem ser verificadas antes de eventual migração real.

## Atualização local — Segurança 1C

As listagens públicas na variante local agora usam o backend com revalidação
de publicação, ativação e expiração. Listagens diretas públicas são negadas
nas Rules locais; leitura individual elegível continua permitida. O fluxo
privado por UID e o transporte de push permanecem preservados. As etapas
1B/1B.1 prepararam claims e revogação localmente, sem ativação em produção.
Consulte [a matriz e os limites atuais](content_visibility_local.md).
