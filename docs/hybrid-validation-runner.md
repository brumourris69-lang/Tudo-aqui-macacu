# Validador local da integração híbrida

O runner `tools/hybrid-validation-runner.mjs` executa, em ordem e sem instalar
dependências, as verificações locais já presentes no repositório:

```powershell
node tools/hybrid-validation-runner.mjs
```

Para incluir a verificação de tipos Deno do entrypoint Edge sem baixar módulos:

```powershell
node tools/hybrid-validation-runner.mjs --deno-bin 'C:\caminho\temporario\deno.exe'
```

O probe opt-in do Supabase Edge Runtime exige Docker Engine já ativo e a imagem
`public.ecr.aws/supabase/edge-runtime:v1.77.4` já em cache. Ele não inicia Docker,
não faz pull, cria um único container sem rede/portas/credenciais, valida sua
configuração por `docker inspect` e remove apenas esse container e a pasta temporária
que criou:

```powershell
node tools/hybrid-validation-runner.mjs --edge-runtime-probe
```

O probe carrega o entrypoint real `consume-catalog-outbox` e os módulos compartilhados
no user worker do runtime oficial. Sem secrets de servidor, confirma `GET` (405),
`POST` desabilitado (503), assinatura ausente/inválida (401), payload inválido (400) e
HMAC sintética válida (200) contra um processador falso, além da sanitização da resposta.
Isso não valida credenciais reais, Firestore, PostgreSQL, sincronização nem serviço
hospedado. A suíte offline do harness é executada por padrão na etapa
`orchestrator-harness-tests`.

O caminho deve ser absoluto e apontar para `deno.exe`/`deno`; as etapas executam
`deno check --cached-only` no entrypoint e `deno test --cached-only` nos testes offline
do handler.

Ele roda testes/sintaxe de Functions, scripts e módulos compartilhados, regressões
Python, análise Flutter, a matriz Flutter normal, a matriz de desenvolvimento
`searchLocal`, App Check local e `git diff --check`. O relatório JSON ao final lista
código de saída, duração e contagem TAP quando disponível. Testes condicionais pulados
continuam visíveis como `skipped`; um exit code zero não é descrito como prova de
integração se essas condições não foram executadas.

Por padrão, o runner não inicia Firebase Emulator, Docker, Edge Runtime ou serviços
hospedados. Ele também não instala ferramentas, publica alterações, faz deploy nem
altera configurações. Variáveis comuns de credenciais, seleção Firebase/Supabase e
injeção Node (`NODE_OPTIONS`/`NODE_PATH`) são removidas do ambiente dos subprocessos.

## Integração Firestore + PostgreSQL já preparada

Para executar somente quando os serviços descartáveis já tiverem sido iniciados e
inspecionados separadamente:

```powershell
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:18087'
$env:CATALOG_POSTGRES_TEST_CONTAINER = 'macacu-0755-pg-<sufixo-local>'
node tools/hybrid-validation-runner.mjs --include-local-integration
```

O preflight exige o host loopback e o padrão de nome do container descartável; o teste
também confere imagem, label de tarefa, rede, portas e mounts antes de processar dados.
O runner não cria, para ou remove esses recursos. Para o caminho PostgREST HTTP local,
podem ser informados também `CATALOG_POSTGREST_URL` (somente `http://127.0.0.1:25432/`),
`CATALOG_POSTGREST_API_KEY` sintética de teste e
`CATALOG_POSTGREST_TEST_CONTAINER` com o prefixo `macacu-0755-rest-`. A chave nunca é
impressa pelo runner e só é encaminhada se todos os controles de destino local passarem.

Não forneça credenciais reais. O nome do container, a URL e a configuração do PostgREST
continuam sujeitos à inspeção feita pela suíte de integração. O uso da opção não prova
IAM, índices, runtime Edge, agendamento ou comportamento hospedado.

## Cancelamento

Cada etapa tem timeout máximo de 20 minutos. Ao receber Ctrl+C ou timeout, o runner
encerra a árvore do processo que ele iniciou (`taskkill /T` no Windows), marca a etapa
como interrompida/falha e não tenta novamente. Recursos externos preexistentes nunca
são encerrados pelo runner.

## Gates que continuam fora da automação local

O runner não realiza login, lê segredos do disco, configura Vault/IAM, modifica Rules
hospedadas, cria Cron, faz deploy, executa backfill ou publica clientes. Essas ações
dependem de decisões e evidência de homologação próprias; passar na suíte local não as
aprova automaticamente.
