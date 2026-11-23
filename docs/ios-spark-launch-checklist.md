# iOS Spark — checklist local de preparação

**Verificado em:** 15/11/2026
**Estado:** preparação local; nenhuma conta ou serviço hospedado foi alterado.

## O que já existe no repositório

- O Bundle ID do alvo iOS está configurado como
  `br.com.tudoaquimacacu.tudoaquimacacu`. É um candidato: ainda precisa ser
  confirmado como disponível e registrado pelo responsável.
- O deployment target é iOS 15.0.
- `Runner.entitlements` declara Sign in with Apple e App Attest para produção.
- O código da distribuição Spark agora só oferece Sign in with Apple em iOS
  quando a identidade Spark foi validada no início do app e a opção explícita
  `SPARK_DISTRIBUTION_IOS_APPLE_SIGN_IN_ENABLED` está habilitada.
- A exclusão de conta reconhece a reautenticação Apple somente nessa mesma
  configuração Spark validada.
- `.github/workflows/ios-testflight-distribution.yml` é exclusivamente Beta
  (`macacu-beta-261030-cf4a81`). Ele não deve ser usado para criar o app público.

## Bloqueios que dependem de cadastro externo

- A inscrição Apple Developer precisa estar ativa. A confirmação da conta,
  pagamento e situação do pedido não foram consultados nesta verificação.
- O Bundle ID candidato precisa ser confirmado e registrado em Apple Developer,
  App Store Connect e Firebase com o mesmo valor.
- O projeto Firebase candidato é `tudo-aqui-macacu`, mas não há configuração
  iOS `GoogleService-Info.plist` no checkout. O Firebase iOS App ID, sender ID,
  OAuth Client IDs e a configuração real de Auth/App Check ainda não foram
  comprovados.
- O projeto não contém certificado Apple Distribution nem perfil App Store.
  O Team ID também depende da inscrição ativa.
- Não existe workflow iOS Spark de assinatura. O workflow Beta é separado e
  não deve ter suas credenciais ou identidade reutilizadas.
- `pubspec.yaml` foi preparado localmente como `1.0.0+5`, avançando o build
  interno em relação ao `0.1.3+4` anterior. Antes do primeiro envio, confirme
  que o build 5 ainda não foi utilizado em nenhum cadastro das lojas.
- As páginas de privacidade e exclusão permanecem rascunhos locais. As URLs
  públicas de política, suporte e exclusão ainda não foram confirmadas.

## Ordem mais curta depois da aprovação da conta Apple

1. Confirmar a inscrição ativa e obter o Team ID.
2. Confirmar o Bundle ID candidato; registrar o App ID e habilitar Sign in with
   Apple e App Attest.
3. Registrar o mesmo Bundle ID no Firebase Spark candidato e obter o plist do
   app iOS. Configurar e validar Google Sign-In, Apple Sign-In e App Check no
   projeto correto.
4. Criar o registro do app no App Store Connect e preparar certificado de
   distribuição e perfil App Store. Guardar material privado somente em um
   ambiente seguro de CI, nunca no Git ou no Flutter.
5. Aprovar versão/build, conferir as URLs públicas de privacidade, suporte e
   exclusão, e revisar metadados e capturas finais.
6. Preparar um workflow iOS Spark separado, com validação fail-closed do
   projeto, App ID, Bundle ID, Team ID, plist e assinatura. Primeiro gerar e
   revisar o IPA; o envio ao TestFlight deve ser uma ação explícita posterior.
7. Validar a mesma identidade Spark e o fluxo essencial em um dispositivo
   Apple antes da submissão coordenada com Android.

**Regra de segurança:** não preencher os itens pendentes com valores Beta,
placeholders ou configuração Android. Não assinar nem enviar um build enquanto
Bundle ID, projeto Firebase e credenciais não forem confirmados.
