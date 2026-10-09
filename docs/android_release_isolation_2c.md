# Segurança 2C — assinatura Android e isolamento de builds

## Resultado e limites

A configuração release não utiliza mais assinatura debug. A ausência de autorização, credenciais completas ou certificado aprovado impede a release, sem fallback. Debug normal e searchLocal mantêm assinatura debug e não carregam key.properties nem material de assinatura oficial.

Não foi gerado APK/AAB release, criado keystore, usado segredo real, executado workflow remoto, publicado artefato, realizado deploy, alterado Firebase, criado commit ou feito push. Foram preservados os testes da etapa 2B e as alterações locais anteriores. Um APK debug **já existente** foi inspecionado como teste negativo; nenhum APK foi gerado nesta etapa.

## Diagnóstico original

- `android/app/build.gradle.kts`: release atribuída a signingConfigs.debug.
- GitHub Actions: patch Python procurava `getByName("release") {`, mas o arquivo usava `release {`; a substituição não garantia o vínculo de assinatura.
- Codemagic: APK debug recebia certificado do grupo de assinatura Android por patch textual do Gradle, misturando teste com material de distribuição.
- GitHub: artefato debug era disponibilizado automaticamente a cada push.
- searchLocal já tinha ID próprio, remoção dos inicializadores Firebase de produção, VPN e restrição a debug; essas proteções não foram substituídas.

## Configuração preparada

O Gradle possui configurações explícitas:

| Ambiente | Identificador | Assinatura / comportamento |
|---|---|---|
| Desenvolvimento normal | br.com.tudoaquimacacu.tudo_aqui_macacu | Debug padrão, ferramentas locais/Hot Reload preservados; não consome credenciais release |
| Segurança local | br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal | Apenas debug; demo-universal-search, emuladores, inicializadores nativos bloqueados e VPN existentes |
| Distribuição oficial | br.com.tudoaquimacacu.tudo_aqui_macacu | authorizedRelease, debuggable=false, autorização explícita e certificado autorizado; sem flags LOCAL_SEARCH_* |

O identificador oficial não mudou. Nenhuma nova chave/certificado foi escolhido: a impressão do certificado existente autorizado precisa ser configurada futuramente pelo responsável. No caso de Play App Signing, distinguir certificado de upload do certificado de assinatura fornecido pela Play; usar a impressão apropriada ao artefato validado.

Variáveis exigidas pelo gate Gradle:

- ANDROID_RELEASE_AUTHORIZED=true.
- ANDROID_RELEASE_STORE_FILE: caminho do material já autorizado.
- ANDROID_RELEASE_STORE_PASSWORD e ANDROID_RELEASE_KEY_PASSWORD.
- ANDROID_RELEASE_KEY_ALIAS.
- ANDROID_RELEASE_CERT_SHA256: impressão pública SHA-256, não uma senha.

Não existem valores de senha, chave privada ou impressão de certificado real adicionados aos fontes. Debug não depende dessas variáveis. Release verifica existência do arquivo, entrada privada, senha da chave, validade do certificado, identidade debug convencional e correspondência exata da impressão autorizada. Falhas na leitura do keystore são sanitizadas; não se imprime exceção contendo material de assinatura.

`verifyReleaseAuthorization` também verifica:

- searchLocal não selecionado.
- Ausência de qualquer define LOCAL_SEARCH_ nos dart-defines compilados, inclusive quando fornecidos ao Flutter por arquivo de defines.
- google-services.json oficial com project_id=tudo-aqui-macacu e cliente Android correspondente ao ID oficial.

O gate é chamado ao preparar o grafo de tarefas de release, incluindo tarefas agregadas que levem à release. A tarefa `:app:verifyReleaseConfiguration` permite validar configuração sem compilar ou assinar artefatos. A configuração Kotlin foi efetivamente carregada pelo Gradle nesta etapa; isso é evidência mais forte que apenas procurar strings no arquivo.

## GitHub Actions e Codemagic

### GitHub

- Mantidos job security-tests, dependência do build, suites Flutter normal/local e testes Node/Worker/Emulator da Segurança 2B.
- Acrescentados testes Python e verificação estática da configuração de assinatura ao job obrigatório.
- Removidos patches de texto e regeneração Android pelo workflow: usa-se a configuração Android versionada.
- APK debug pode continuar sendo compilado no CI, mas o upload do artefato de teste exige workflow_dispatch com debug-apk. Push não disponibiliza automaticamente esse artefato.
- Release fica em job separado: somente workflow_dispatch, branch main, opção release-aab, dependência dos testes/build e environment android-release.
- Preflight exige autorização explícita e impressão aprovada antes da etapa que recebe os secrets de assinatura. Não há trigger de pull_request/pull_request_target; job release também os rejeita pela política.
- Secrets existentes são recebidos apenas na etapa de assinatura do job confiável. Keystore é decodificado em runner.temp com umask 077; senhas ficam no ambiente, sem key.properties. Limpeza roda com always().
- AAB só é disponibilizado após o verificador do artefato aprovar. Isso é upload de artefato do workflow, não publicação na Play Store; não foi adicionado deploy/publicação em loja.

O environment android-release precisa ser configurado futuramente com revisores, restrição à branch confiável e secrets/vars de escopo apropriado. O arquivo YAML sozinho não cria uma política de aprovação humana. Nenhuma configuração do GitHub foi alterada nesta etapa.

Variáveis adicionais desse environment: ANDROID_RELEASE_AUTHORIZED, ANDROID_RELEASE_CERT_SHA256, BUNDLETOOL_VERSION e BUNDLETOOL_SHA256. O bundletool é baixado do repositório Google por versão explícita e seu hash é conferido antes de executar. A impressão e hashes são identificadores públicos. Secrets de keystore mantêm os nomes já utilizados; não foram solicitados nem alterados.

### Codemagic

O workflow Android passa a se identificar como APK debug para testes, sem android_signing, CM_KEYSTORE ou patches Gradle. Usa a assinatura debug padrão e mantém os testes Flutter já existentes. Workflows iOS foram preservados.

Não existe configuração de publicação em loja ou triggering automático no YAML atual; artifacts permanece para baixar o APK de teste gerado por solicitação. Configuração adicional feita na interface do Codemagic não foi consultada/alterada, portanto é necessário confirmar futuramente que não existem triggers/publicações externas ao YAML.

Compatibilidade: APKs debug antigos assinados pelo certificado customizado do Codemagic podem não aceitar atualização por um novo APK debug padrão, apesar do mesmo applicationId. Isso não muda a identidade da release oficial e não afeta o debug local que já usa sua própria chave, mas exige planejar o teste em instância separada se houver esse conflito. Não desinstalar automaticamente nem apagar dados do MEmu. Nenhum aplicativo foi instalado/removido agora.

## Verificações automatizadas

`scripts/android_release.py` possui três modos, sem construir, assinar ou publicar:

1. `--static`: configuração Gradle, identidade oficial, Firebase público, guardas CI, ausência de patches, segredos privados nos caminhos fonte/configuração inspecionados e arquivos de assinatura rastreados.
2. `--preflight`: autorização explícita; no CI, solicitação manual/main e versão/hash aprovados do bundletool.
3. `--artifact`: inspeção futura de APK ou AAB. APK usa apksigner verify --print-certs e apkanalyzer manifest print. AAB usa jarsigner, keytool e bundletool dump manifest. Certificado deve corresponder à impressão autorizada; identidade debug convencional, debuggable, instrumentation e componentes searchLocal são recusados. Também verifica recursos empacotados Firebase e presença de materiais privados dentro do ZIP.

Não são aceitas ferramentas AAB não aprovadas por hash. Saídas de ferramentas são capturadas, não despejadas nos logs; falhas recebem mensagem sanitizada. Identificadores públicos Firebase não são classificados como segredo privado.

Os oito testes Python incluem regressões artificiais: release apontando para debug, debuggable=true, retirada do gate Gradle, environment/branch indevidos, projeto Firebase demo, falta de autorização, evento pull_request, certificado divergente/debug, material privado e recursos demo. Usam somente fixtures sintéticas e cópias temporárias de configuração; não geram keystore.

Fontes oficiais das ferramentas: [apksigner](https://developer.android.com/tools/apksigner), [bundletool](https://developer.android.com/tools/bundletool), [implementação Google do comando dump](https://github.com/google/bundletool/blob/master/src/main/java/com/android/tools/build/bundletool/commands/DumpCommand.java).

## Validação executada

| Verificação | Resultado |
|---|---|
| Flutter Analyze --no-pub | Sem problemas |
| Flutter normal | 252 testes aprovados |
| Flutter local com flags demo/loopback | 22 testes aprovados |
| Node/Worker e guardas do runner | 72 testes aprovados |
| Python release | 8 testes aprovados, incluindo cenários negativos |
| Script --static e parsing YAML dos dois workflows | Aprovados |
| Gradle help --offline --no-daemon | Configuração Kotlin carregada com sucesso |
| :app:assembleDebug --dry-run --offline | Grafo válido sem credenciais; nenhum APK gerado |
| :app:assembleSearchLocalDebug --dry-run --offline | Grafo local válido sem credenciais; nenhum APK gerado |
| :app:verifyReleaseConfiguration sem credenciais, com autorização fictícia de teste | Recusado como esperado; mensagem clara sem fallback debug |
| :app:verifyReleaseConfiguration com LOCAL_SEARCH_EMULATORS=true, sem credenciais reais | Recusado antes da assinatura, como esperado |
| APK debug já existente, fingerprint sintético | Assinatura inspecionada e fingerprint divergente recusado |
| Mesmo APK debug existente, fingerprint público correspondente | Recusado por debuggable=true, confirmando inspeção real do manifesto |
| Diff dos arquivos editados | Sem erros de whitespace |

O teste de flag local teve inicialmente falha no harness PowerShell ao comparar texto acentuado com encoding diferente. O Gradle havia rejeitado corretamente LOCAL_SEARCH_; a evidência foi confirmada pelo marcador ASCII no log. Não houve mudança de segurança para acomodar esse diagnóstico.

Para inspecionar o APK existente foi usado Python do runtime local, pois o alias Microsoft Store não enxergava o caminho do SDK no AppData. Isso é limitação da ferramenta de execução local, não aprovação de um artefato: o diagnóstico inicial genérico não foi contado como evidência de bloqueio correto; as duas verificações reais posteriores confirmaram certificado divergente e debuggable.

Logs em `C:/Users/tiago/Documents/Codex/2026-09-11/pr/work/security-2c/`. Nenhuma senha, token ou chave privada foi registrada. Emuladores/backend não foram modificados; as integrações Emulator da etapa 2B não foram reexecutadas, pois não houve alteração de seus módulos.

## Arquivos desta etapa

- android/app/build.gradle.kts.
- .github/workflows/main.yml.
- codemagic.yaml.
- .gitignore, somente caches Python de verificação.
- scripts/android_release.py, novo.
- scripts/test/android_release_test.py, novo.
- docs/android_release_isolation_2c.md, novo.

Não houve alteração nas classes Android de isolamento, VPN, manifests locais, configuração Firebase de produção, Rules, Functions, Worker ou telas Flutter.

## Limitações e pendências antes da distribuição

- Não houve geração nem inspeção de release real. A validação positiva da assinatura autorizada, do AAB final, de atualizações sobre instalação oficial e do job remoto continua pendente de autorização.
- Verificações estáticas são guardas contra regressões conhecidas, não prova formal do Gradle nem scanner completo de segredos. A inspeção de recursos binários Firebase é conservadora por strings; não comprova todo comportamento de rede do Flutter ou toda seleção de recursos em runtime.
- A verificação de AAB com jarsigner/bundletool foi preparada e coberta por validações unitárias de política; o percurso completo em AAB real ainda não foi executado. A rejeição real de APK debug não comprova esse percurso.
- Confirmar titularidade/continuidade da chave oficial existente, upload key versus Play App Signing, impressão aprovada, restrições do environment e branch protection antes de fornecer secrets. Não gerar uma chave nova como substituição automática.
- Configurar e revisar versão/hash de bundletool por canal confiável. Não aceitar hash obtido sem verificação junto com binário de origem desconhecida.
- Warnings preexistentes sobre DSL/Kotlin/SDK Android e Gradle 10 permanecem; não foram atualizadas dependências/plataformas nesta etapa. Node 20, lockfile Functions e advisories continuam pendentes conforme 2A/2B.
- App Check real, claims/revogação operacional, migrações e compatibilidade de clientes antigos continuam sendo bloqueios separados da auditoria 2A. Esta etapa não autoriza publicar as correções de backend nem considera a segurança de produção concluída.
- Hot Reload não foi necessário: nenhuma alteração de UI ou execução no MEmu. O fluxo debug permanece disponível e independente da assinatura release.

Segurança 2C preparada e validada localmente. Aguardando autorização para a próxima etapa.
