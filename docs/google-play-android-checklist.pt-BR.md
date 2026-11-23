# Google Play — checklist Android 1.0

**Estado:** checklist local; nenhum app/AAB foi enviado ao Play Console nem submetido à análise.

## Cadastro e acesso à produção

- [ ] Confirmar no Play Console o tipo de conta do desenvolvedor e a data de criação.
- [ ] Na tela “Criar app”, usar: **Tudo Aqui Macacu**, pacote `br.com.tudoaquimacacu.tudo_aqui_macacu`, idioma **Português (Brasil)**, tipo **App** e distribuição **Grátis**.
- [ ] O titular deve ler e aceitar pessoalmente as declarações de políticas, assinatura do app e exportação. Não delegar essa confirmação.
- [ ] Se a conta for pessoal e tiver sido criada após 13/11/2023, concluir teste fechado com ao menos 12 participantes inscritos continuamente por 14 dias e solicitar acesso à produção.

## Política, segurança e ficha

- [x] Política de Privacidade publicada em `https://tudoaquiprivacidade.htmly.com.br/`; verificada com HTTP 200, título correto, sem `noindex` e com o canal oficial em 17/11/2026.
- [x] Página externa de solicitação de exclusão publicada em `https://whimsical-douhua-86c4c3.netlify.app`; verificada com HTTP 200, título do app, canal oficial, prazo informado e sem `noindex` ou marcação de rascunho em 17/11/2026.
- [ ] Conferir a política com o APK/AAB final, as bases legais e retenções descritas, os fornecedores efetivamente usados e os formulários de privacidade das lojas. Revisão jurídica recomendada; não declarada como concluída.
- [ ] Cadastrar a URL da política e a URL externa de exclusão nos campos correspondentes do Play Console. Ainda não foram inseridas no Console.
- [x] O workflow `release-aab` agora passa `PRIVACY_POLICY_URL=https://tudoaquiprivacidade.htmly.com.br/`; confirmar a exibição do link no AAB final.
- [ ] Preencher Segurança dos dados a partir do APK final: conta/autenticação, favoritos, mensagens de contato, dados locais e serviços externos. Confirmar conteúdo com a configuração real dos serviços.
- [ ] Completar classificação etária, público-alvo, declarações de anúncios, categoria, suporte e informações de contato.
- [ ] Preparar ícone, artes e capturas reais do build candidato; não usar dados sintéticos.

## AAB assinado e distribuição

- [ ] Consolidar e revisar o candidato em `main` sem descartar as alterações locais.
- [ ] Configurar no ambiente GitHub `android-release` a autorização e o fingerprint do certificado; guardar keystore, senhas e alias somente nos secrets protegidos; fixar versão e SHA-256 do Bundletool.
- [x] Antes de cada AAB, validar no `google-services.json` os três SHA-1 da assinatura Play: `b133098c37ddb064f922d3b963e233b620211963` (chave observada no APK entregue pela Play), `76c9cb09de708f9243e00bf3da69b22dd8e4cafd` (híbrida clássica) e `5a848a249c8eaf71d88e272501d7b1c9b4be6a73` (híbrida pós-quântica). O preflight Android bloqueia o AAB se algum faltar. Repetir a conferência no Play Console somente quando houver rotação de chave.
- [x] Cadastrar no Firebase os três fingerprints SHA-1 da assinatura Android híbrida, incluindo o PQC, e baixar uma configuração atualizada para a identidade de distribuição.
- [ ] Disparar manualmente o workflow `Gerar Android` na `main`, opção `release-aab`.
- [ ] Conferir o artefato `app-release-verified.aab`. O workflow verifica e disponibiliza o AAB; **não faz upload ao Google Play**.
- [ ] Fazer upload no track permitido pelo Play Console e revisar todas as declarações antes de enviar para análise.

## Referências oficiais

- [Preparar o app para revisão](https://support.google.com/googleplay/android-developer/answer/9859455)
- [Requisito de exclusão de conta](https://support.google.com/googleplay/android-developer/answer/13327111)
- [Teste exigido para novas contas pessoais](https://support.google.com/googleplay/android-developer/answer/14151465)
- [Preparar e lançar uma versão](https://support.google.com/googleplay/android-developer/answer/9859348)
