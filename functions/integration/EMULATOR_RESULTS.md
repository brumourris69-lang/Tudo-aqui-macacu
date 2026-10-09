# Busca Universal — Etapa 4D

Validação executada em 08/10/2026, exclusivamente em `demo-universal-search`.
Nenhum login, deploy, backfill, alteração de plano ou acesso a dados do projeto real.
A interface e o Admin não foram conectados aos emuladores.

## Ambiente

- Firebase CLI local 15.32.1, `../../work/firebase-tools.exe` (relativo a functions).
- Node 20.20.2 e Java 21.0.12.1 instalados somente em `../../work/search-emulator-tools`.
- Firestore Emulator 1.22.0, artefato oficial com checksum verificado.
- Dependências já declaradas de functions instaladas localmente, sem alterar versões declaradas ou gerar lockfile.
- Firestore `127.0.0.1:8087`, Functions `127.0.0.1:5007`, Auth `127.0.0.1:9097`.
- Configuração separada `firebase.search-emulator.json`; `firebase.json`, `.firebaserc` e `firestore.rules` preservados.
- Parâmetros Cloudinary e segredo temporários receberam apenas valores fictícios. Upload e notificações não foram chamados.

## Resultados reais

**19 grupos de integração passaram**, utilizando Firebase Admin SDK, REST e callable HTTP contra os serviços locais; sem mocks de armazenamento.

1. Conta e token reais do Auth Emulator, incluindo `verifyIdToken` local.
2. Gatilho automático de criação, ID original e projeção sem campos privados.
3. Callable com nome, acentos e múltiplos prefixos.
4. Edição automática de nome/categoria; filtros Comércios e Serviços.
5. Despublicação remove índice e resultado.
6. Desativação remove índice e resultado.
7. Expiração remove índice quando ocorre uma escrita.
8. Expiração sem nova escrita continua bloqueada por revalidação da origem.
9. Exclusão automática remove índice.
10. Escritas concorrentes e execução repetida do handler com payload antigo: estado final preservado; repetição não reescreve projeção idêntica.
11. Paginação sem duplicatas, limites e ausência de campos opcionais.
12. CloudEvents antigos duplicados enviados pela rota interna real do Functions Emulator; não sobrescrevem estado atual.
13. Índices obsoletos não expõem origem despublicada, inativa, expirada, excluída, renomeada ou com categoria alterada.
14. Instrumentação delegando todas as operações ao Firestore real local: página de 2 resultados lê **2 índices + 2 origens**, com `.limit(2)`; sem leitura da coleção inteira.
15. Consultas/cursor inválidos retornam `INVALID_ARGUMENT` sem stack/documentos privados.
16. 45 índices órfãos fictícios: uma busca para em **40 índices + 40 origens** e fornece cursor de continuação.
17. Visitante, token malformado, App Check ausente/malformado e Auth anônimo bloqueados.
18. Limites de intervalo (350 ms) e quota de minuto (30) com transações reais; estado do contador preparado localmente para testar fronteiras.
19. Regras atuais negam leitura de documento, consulta e escrita direta no índice privado, além de leitura do contador, com e sem usuário autenticado.

Também passaram **36 testes Node** e **33 testes Flutter** de base, infraestrutura e paridade. `flutter analyze --no-pub`: nenhum problema. Esses testes unitários são complementares, não substitutos dos 19 grupos reais.

## Falhas encontradas e corrigidas

- Falta inicial de espaço (`ENOSPC`) no download do emulador; ambiente preparado após liberar espaço.
- Discovery inicial excedeu 10 segundos: utilizado `FUNCTIONS_DISCOVERY_TIMEOUT=60` local.
- CLI não usa variáveis do processo para resolver todos os parâmetros declarados: usados `.env.local` e `.secret.local` temporários com valores fictícios.
- **Falha efetiva do backend:** o Functions Emulator encapsula `admin.firestore` e não preserva seus tipos estáticos. `FieldValue.serverTimestamp()` ficou indefinido no gatilho. Corrigido `business_search_functions.js` para importar `FieldValue`, `FieldPath` e `Timestamp` pela API modular oficial `firebase-admin/firestore`. Gatilhos e callable passaram após a correção.
- Ajustes do harness: limpeza exclusiva do banco demo entre execuções, status de rejeição do App Check malformado e rota/envelope completos para replay de CloudEvents. Não foram relaxadas regras ou políticas para passar testes.
- Execução final: **nenhum teste de integração falhou**.

## Segurança e limitações

- O Functions Emulator da CLI utiliza `skipTokenVerification`. O teste positivo de App Check usa JWT fictício local para fornecer contexto; **não valida assinatura, atestação, revogação ou provedor real de App Check**. A ausência do cabeçalho foi negada pelo SDK; o token malformado também foi negado pela política do backend. Token Auth malformado e visitante foram negados; Auth anônimo é proibido explicitamente.
- Tokens emitidos pelo Auth Emulator são exclusivos dos testes. A autenticação/atestação de produção precisa de validação separada autorizada.
- Nenhum campo administrativo foi copiado ou retornado. Imagens seguem bloqueadas até definir autorização pública explícita.
- Não apareceu vazamento no caminho de pesquisa. As regras existentes de `establishments` baseiam leitura pública em `published`; não aplicam `active`/`expiresAt`. A busca revalida esses campos no servidor. Isso não equivale a restringir acesso direto à origem: essa política existente precisa de decisão separada, sem alteração nesta etapa.
- Sanitização de erros inesperados do SDK foi coberta pelo teste unitário do wrapper; não foi induzida indisponibilidade do Firestore local para alegar uma validação equivalente ponta a ponta. Os erros de consulta e acesso foram verificados por HTTP real.
- Limites são por UID; proteção distribuída contra abuso e contas múltiplas permanece necessária antes de produção.
- Índices expirados sem escrita podem permanecer armazenados, embora nunca retornados; limpeza periódica/TTL requer decisão posterior.

## Índices

`firestore.search-local.indexes.json` prepara índice composto de `business_search_index`: `prefixes ARRAY_CONTAINS` + `group ASC`, com ordem implícita de ID ascendente. Consulta sem filtro usa índice automático de array; ambas paginam por ID.

Nenhum índice foi implantado. O Firestore Emulator **não exige nem valida índices compostos**, logo a aprovação das consultas locais não confirma disponibilidade/adequação dos índices de produção. Também não mede faturamento real. Referência: https://firebase.google.com/docs/emulator-suite/connect_firestore#how_the_cloud_firestore_emulator_differs_from_production

## Reexecutar

Na raiz `app`, usar Node 20 e Java 21 no PATH. Criar temporariamente `functions/.env.local` com `CLOUDINARY_CLOUD_NAME=local-demo`, `CLOUDINARY_API_KEY=local-demo`, `CLOUDINARY_FOLDER_MODE=dynamic`, e `functions/.secret.local` com `CLOUDINARY_API_SECRET=LOCAL_TEST_ONLY`. **Não sobrescrever arquivos locais existentes.** Remover somente os arquivos fictícios criados para a execução ao terminar.

No primeiro terminal:

```powershell
$env:FUNCTIONS_DISCOVERY_TIMEOUT='60'
& '..\work\firebase-tools.exe' emulators:start --only firestore,functions,auth --project demo-universal-search --config firebase.search-emulator.json --non-interactive
```

Após os serviços e as quatro funções serem carregados, no segundo terminal:

```powershell
$env:GCLOUD_PROJECT='demo-universal-search'
$env:FUNCTIONS_EMULATOR='true'
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8087'
$env:FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9097'
node functions/integration/search_emulator.js
```

O harness elimina somente os dados do banco local demo no início. Usar instância exclusiva para esta suíte; não compartilhar com outros testes. A rota de replay usa o identificador interno `southamerica-east1-syncBusinessSearchIndex-0` da CLI 15.32.1 e pode precisar de atualização em outra versão.

## Arquivos desta etapa

- Criado `firebase.search-emulator.json`.
- Criado `firestore.search-local.indexes.json`.
- Criado `functions/integration/search_emulator.js`.
- Criado este relatório.
- Corrigido `functions/business_search_functions.js` (tipos oficiais do SDK).

Ferramentas/dependências locais e cache do emulador não são alterações de produção. Arquivos temporários de parâmetros foram removidos ao encerrar. Logs desta execução ficaram fora de `app`, em `../work/search-emulator-results`.

## Antes de conectar a interface

Autorizar próxima etapa; definir experiência de visitantes, autorização de imagens, App Check real, política de abuso e plano/custos. Preparar ativação controlada, índices e sincronização inicial, com autorização específica antes de qualquer operação real. A busca continua desabilitada fora do projeto demo em loopback; nenhuma interface foi conectada e nenhum recurso foi implantado.
