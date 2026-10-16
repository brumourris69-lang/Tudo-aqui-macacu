# Integração local de `getPublicJob`

Este roteiro prepara uma validação integrada do contrato público da vaga. Ele é destinado exclusivamente ao Firebase Emulator do projeto `demo-universal-search`; exige autorização específica antes de executar o comando.

## Ambiente e serviços

Use Node.js 22, Java 21 e uma instalação existente do Firebase CLI. A configuração deve ser explicitamente `firebase.search-emulator.json`, que aponta para as Rules locais e define:

| Serviço | Endereço |
| --- | --- |
| Auth Emulator | `127.0.0.1:9097` |
| Firestore Emulator | `127.0.0.1:8087` |
| Functions Emulator | `127.0.0.1:5007` |
| Eventarc (auxiliar configurado) | `127.0.0.1:9297` |
| Emulator Hub (auxiliar) | `127.0.0.1:4407` |
| Logging (auxiliar) | `127.0.0.1:4507` |

Antes de executar, confirme que essas portas estão livres e que o CLI, Node e Java são as instalações esperadas. O comando abaixo não passa opções de importação nem exportação. Não use `firebase.json`, não troque o projeto e não aponte clientes para qualquer host fora de loopback.

## Execução futura

Na raiz do repositório, com o Firebase CLI já disponível no `PATH`, o comando previsto é:

```powershell
firebase emulators:exec --only auth,firestore,functions --config firebase.search-emulator.json --project demo-universal-search "node functions/integration/get_public_job_emulator.js"
```

`emulators:exec` inicia os serviços indicados, executa o harness e encerra os processos que iniciou. O harness também exige `GCLOUD_PROJECT=demo-universal-search`, `FUNCTIONS_EMULATOR=true`, Auth em `127.0.0.1:9097`, Firestore em `127.0.0.1:8087` e Functions na porta `5007`, antes de criar qualquer fixture. Se a instalação existente do Firebase CLI não puder ser localizada ou qualquer limite falhar, não substitua o comando por `npx` nem baixe ferramentas; pare e investigue separadamente.

## Fixtures, Auth e App Check

O harness cria IDs aleatórios por execução e grava apenas documentos correspondentes em `jobs/{id}`, `job_private/{id}`, o documento individual de quota e o índice `jobs__{id}` que o gatilho de busca local pode produzir. Também cria uma conta temporária pelo Auth Emulator. A limpeza apaga apenas essas referências e essa conta; não usa exclusões por coleção nem import/export.

O cenário positivo usa uma conta temporária do Auth Emulator e um token App Check de teste sem assinatura, aceito somente pelo Functions Emulator. Cenários separados omitem Auth ou App Check e enviam um token App Check inválido. Esse token fictício não é atestado real e nunca deve ser usado contra Firebase ou aplicativo normal. O teste unitário existente verifica, com um store instrumentado, que o resolvedor consulta somente `jobs` e não lê `job_private`.

O harness cobre vaga válida, inexistente, não publicada, inativa e expirada; ID inválido; Auth e App Check ausentes/inválidos; limite por usuário; projeção restrita aos campos de `PublicJob`; e ausência dos valores privados e campos não aprovados. A proteção contra exportação de `getPublicJob` no modo normal é verificada pelo teste unitário do entrypoint, carregado com o gate de backend normal permitido e o gate local desligado. Nenhum teste integrado chama projeto Firebase real.

## Limites da preparação

Nesta etapa o comando não foi executado. A execução integrada, qualquer download do Firebase CLI ou dos componentes de Emulator e qualquer alteração de dados persistentes exigem autorização específica. O teste integrado tampouco prova a ausência de leituras a `job_private`; essa propriedade é coberta pelo teste unitário instrumentado do backend.
