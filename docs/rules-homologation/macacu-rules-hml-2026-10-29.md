# Homologação isolada das Firestore Rules — 2026-10-29

## Resultado

**GO para o candidato neste projeto Firebase descartável; NO-GO para Beta/produção.** A homologação hospedada foi executada somente em `macacu-rules-hml-29oct26-a71c` (projeto `158164993050`). Não houve acesso nem alteração a `macacu-staging-261022`, produção ou Supabase.

## Ambiente e integridade

- Firebase CLI: 15.32.1.
- Billing: desativado (Spark; `billingEnabled=false` verificado).
- Firestore: banco `(default)`, região `southamerica-east1`, Standard.
- Authentication: somente e-mail/senha; sem provedores anônimos, telefone ou Google.
- App Web de teste: `1:158164993050:web:f1993ab15a1c65c6597da3`.
- Rules candidatas `firestore.rules` e `firestore.claims-local.rules`: SHA-256 `ddc454413e66107a2087265c3bc9012f7343f90e67a491c353e64e49a75d13b8`.
- Rules deny-all final: SHA-256 `ecf30f940747dcc3c5ba4993093e9a11ac9fc5df7e14b2a1512d2446923d84eb`.

## Testes hospedados

O runner publicou temporariamente o candidato exclusivamente no projeto descartável e executou **27 asserções usando Firebase Client SDK**. Admin SDK/REST foi usado apenas para provisionar e limpar fixtures; as permissões foram avaliadas pelo SDK cliente autenticado.

Cobertura: Admin autorizado e revogado, usuário comum, visitante, eventos publicados/rascunho/inativos/excluídos, Home, isolamento entre duas contas em Favoritos e Minha Agenda, e negação de gravações diretas nessas coleções. As negativas esperadas retornaram `PERMISSION_DENIED`.

Resultado: **27/27 aprovadas**. Foram criadas 4 contas sintéticas e 12 documentos; a limpeza removeu tudo. Verificação independente confirmou zero contas e zero documentos remanescentes nas coleções usadas pelo teste.

## Estado final e limpeza

- Release ativo: `projects/macacu-rules-hml-29oct26-a71c/releases/cloud.firestore`.
- Ruleset ativo final: `projects/macacu-rules-hml-29oct26-a71c/rulesets/a83d14f2-3b9b-4880-a1b8-b34aec568aa1`.
- O Ruleset ativo final foi lido novamente e corresponde ao hash deny-all acima.
- As duas contas de serviço temporárias foram removidas; bindings temporários removidos; papéis personalizados marcados como excluídos e sem bindings. Nenhuma chave de conta de serviço foi criada.
- As APIs `iam.googleapis.com` e `iamcredentials.googleapis.com`, habilitadas apenas para a preparação da identidade temporária, foram desativadas novamente (GET confirmou `DISABLED`).
- Projeto, Firestore, Auth e App Web permanecem disponíveis; o projeto foi deixado com Rules deny-all, conforme solicitado. O Ruleset candidato permanece apenas no histórico de Rules e não está ativo.

## Verificações locais

- `node --check tools/disposable-firebase-rules-homologation.mjs`: aprovado.
- `node --check tools/staging-rules-client-homologation.mjs`: aprovado.
- `node --test tools/staging-rules-client-homologation.test.mjs`: **19/19** aprovados.
- `git diff --check`: aprovado.
- Git ao final: **128 caminhos locais, zero staged**. Nenhum commit ou push.

## Limite da conclusão

Esta evidência valida o candidato em um projeto descartável e não altera a decisão sobre publicar Rules no staging compartilhado ou liberar produção. O projeto descartável continua deny-all até decisão posterior; nenhum dado real foi utilizado.
