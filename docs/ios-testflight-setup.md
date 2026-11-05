# Preparar o TestFlight do iOS

O fluxo manual está em `.github/workflows/ios-testflight-distribution.yml`. Ele aceita somente `codex/mvp-1.0-git-organizacao`, exige confirmações para custo macOS, arquivo assinado e configuração externa, e só envia ao App Store Connect quando `upload_to_testflight` estiver marcado. Esta execução não assina, envia nem publica nada.

## Identificador atual

O alvo Runner está configurado como `br.com.tudoaquimacacu.tudoaquimacacu`. É um **candidato**, não uma confirmação de disponibilidade ou registro. Antes de cadastrar, confirme que Tiago/Tudo Aqui Macacu controla esse domínio reverso e que o identificador está livre. Se decidir usar outro, altere o Bundle ID no Xcode e use exatamente o mesmo valor em Apple Developer, App Store Connect e Firebase Beta antes de habilitar o fluxo.

## Configurações reais necessárias

1. **Apple Developer:** em *Certificates, Identifiers & Profiles*, registre um App ID explícito com o Bundle ID definitivo e habilite **Sign in with Apple** e **App Attest**. Crie um certificado **Apple Distribution** e exporte o `.p12` com senha. Gere um perfil de provisionamento **App Store Connect** para esse App ID e certificado, incluindo os dois entitlements do arquivo `ios/Runner/Runner.entitlements`. A adesão ao Apple Developer Program é separada do backend e tem cobrança anual (valor em moeda local mostrado pela Apple no cadastro).
2. **App Store Connect:** crie o registro do app com o mesmo Bundle ID. Crie uma chave de API com a menor função que permita enviar builds, baixe o `.p8` uma única vez e guarde-o com segurança. O upload pelo fluxo só ocorre com a opção manual `upload_to_testflight` marcada.
3. **Firebase Beta:** no projeto isolado `macacu-beta-261030-cf4a81`, registre um app iOS com o Bundle ID definitivo e baixe o `GoogleService-Info.plist` desse app. Configure Google e Apple em Authentication. Registre o app iOS no App Check com App Attest e o Team ID. Não use a configuração Android como substituta. O arquivo plist é injetado temporariamente pelo workflow, validado contra o projeto, app e OAuth IDs e removido ao final; não o adicione ao Git.
4. **Google OAuth:** confira no plist o `CLIENT_ID` e `REVERSED_CLIENT_ID`; obtenha também o OAuth Web Client ID correto do Beta. O workflow verifica os IDs e acrescenta somente durante o build o callback reverso do Google ao `Info.plist`, preservando o esquema `tudoaqui`.
5. **GitHub Actions:** crie o environment `ios-testflight`, restrinja-o à branch `codex/mvp-1.0-git-organizacao` e, se o plano do repositório permitir, configure um revisor obrigatório. Adicione como *secrets* do environment:

   - `IOS_DISTRIBUTION_P12_BASE64`
   - `IOS_DISTRIBUTION_P12_PASSWORD`
   - `IOS_APP_STORE_PROFILE_BASE64`
   - `IOS_BETA_GOOGLE_SERVICE_INFO_PLIST_BASE64`
   - `APP_STORE_CONNECT_API_KEY_ID`
   - `APP_STORE_CONNECT_API_ISSUER_ID`
   - `APP_STORE_CONNECT_API_PRIVATE_KEY_P8`

   Adicione como *variables* do repositório: `IOS_TESTFLIGHT_ENABLED=true` (somente após concluir e conferir todos os cadastros acima), `IOS_BUNDLE_ID`, `IOS_TEAM_ID`, `BETA_IOS_FIREBASE_APP_ID`, `BETA_IOS_MESSAGING_SENDER_ID`, `BETA_IOS_GOOGLE_CLIENT_ID`, `BETA_IOS_GOOGLE_WEB_CLIENT_ID` e `BETA_IOS_APPLE_SIGN_IN_ENABLED=true` (somente após habilitar e testar o provedor Apple no Firebase Beta e no App ID). Os arquivos P12, perfil, plist e P8 devem ser codificados em Base64 apenas ao inseri-los nos secrets; não os imprima no terminal nem os salve no repositório.

## Executar quando estiver pronto

1. Integre este workflow à branch padrão do GitHub para que o GitHub o disponibilize em **Actions**; essa mudança não foi enviada nesta execução. Selecione o workflow e a branch de trabalho.
2. Para um arquivo local temporário, marque as confirmações de custo, assinatura e configuração externa e deixe `upload_to_testflight` desmarcado. O runner apaga o IPA ao terminar e não publica artefato.
3. Para enviar ao TestFlight, faça uma execução manual com `upload_to_testflight` marcado. Isso envia o IPA ao App Store Connect; não publica automaticamente na App Store nem seleciona testadores. Depois do processamento da Apple, conclua as informações de conformidade e escolha os grupos de teste no App Store Connect.

Confira a franquia/preço atual de minutos macOS do GitHub antes de cada execução. O workflow não cria cobrança mensal de backend, mas o runner macOS pode consumir minutos pagos conforme o plano. O TestFlight não usa o backend pago do Firebase; a app continuará apontando somente para o Firebase Beta configurado.

## Estado conhecido e pendências

- O Bundle ID acima ainda não foi confirmado em Apple Developer, App Store Connect ou Firebase.
- O repositório atualmente não contém `GoogleService-Info.plist`, certificado, perfil ou chave ASC. O job para antes de compilar se os secrets estiverem ausentes ou incoerentes.
- Apple Sign-In e App Attest precisam estar habilitados nos cadastros externos correspondentes; os entitlements do projeto não provam que esses registros externos existem.
- A regra da App Store 4.8 requer uma opção equivalente de login com proteção de privacidade quando Google Sign-In autentica a conta principal; Sign in with Apple deve estar realmente disponível no Beta. O workflow pede confirmação, mas não consegue verificar configurações hospedadas.
- O workflow iOS Simulator aprovado e os fluxos Android/MEmu não foram alterados. A presença do workflow manual no GitHub depende de integrá-lo à branch padrão; não houve push ou merge.
- A aprovação de compilação nativa, assinatura, upload e instalação no iPhone ainda depende de uma execução macOS autorizada. Nenhum desses passos foi realizado aqui.
