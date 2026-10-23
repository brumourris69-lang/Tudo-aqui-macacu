# Simulação local do protocolo da outbox

Este módulo demonstra a coordenação de eventos `catalog_outbox` V1 e V2 sem conectar a Firebase ou Supabase. O protocolo aceita eventos V1 legados sem campos persistidos de lease/retry e valida o formato V2 completo antes de claim ou escrita. O adaptador Firestore REST server-only agora oferece consulta paginada e transições transacionais de lease; isto ainda não é um consumidor, Cron ou integração com o escritor SQL.

## Contrato persistido V2

Eventos novos preservam `operationId`, `entityType`, `entityId`, `authorUid`, `version`, `operation`, `state`, `attemptCount` e timestamps. `version` continua correspondendo ao `catalogVersion` canônico. O produtor grava `schemaVersion: 2`, `state: pending`, `attemptCount: 0`, `workerId: null`, `leaseToken: null`, `leaseExpiresAt: null`, `nextAttemptAt: null`, `lastErrorCode: null` e `syncedAt: null`; `createdAt` e `updatedAt` são timestamps definidos pelo servidor na mesma transação que grava a fonte canônica e o evento. `nextAttemptAt: null` significa elegível imediatamente. Ausência de um campo não equivale a `null`: leitores V2 devem exigir os campos de ciclo de vida; leitores legados V1 não podem presumir que eles existam. Datas de lease, retry e conclusão devem ser valores Timestamp do Firestore, não strings ISO.

O protocolo aceita eventos V1 existentes sem campos de ciclo de vida sem tratá-los como `null` nem presumir lease ou retry persistidos. Para V2, exige todos os campos, timestamps Firestore válidos, ausência de chaves desconhecidas e combinações coerentes entre estado, lease, tentativas, retry, erro e conclusão. Um V2 incompleto é recusado antes do claim, sem escrita no catálogo. Isso não migra nem reescreve documentos antigos. A candidata original de Rules continua sendo V1; uma candidata V2 separada valida apenas a criação inicial do novo formato e mantém leitura/alteração/exclusão da outbox negadas a clientes. As regras ainda não autorizam claims ou transições posteriores do trabalhador confiável.

## Máquina de estados

```text
pending ──claim válido──> processing ──gravação confirmada──> synced
   ▲                           │
   │                           ├──evento antigo──> superseded
   │                           ├──evento inconsistente/falha terminal──> dead_letter
   └──falha transitória + backoff┘
```

Um lease contém `workerId`, token único, versão esperada e prazo. O adaptador compara em transação estado esperado, versão, token, trabalhador e prazo; `updateTime` é usado como precondição da escrita. Um lease em `processing` cujo prazo expirou pode ser reclamado; o token anterior deixa de permitir leitura protegida, renovação ou confirmação. O protocolo interno recebe tempos em milissegundos; o adaptador converte-os para `Date`, serializado pelo REST como Timestamp Firestore, e normaliza timestamps REST de volta para `Date`. V1 sem lifecycle permanece sem esses campos até o primeiro claim, que os acrescenta sem mudar `schemaVersion`; leituras V1 continuam aceitando os campos ausentes.

`firebase_firestore_outbox_adapter.mjs` é exclusivamente para servidor confiável: recebe o store REST e uma identidade `workerId` injetados, não guarda credenciais e não deve ser incluído em Flutter nem exposto por endpoint cliente. A autenticação efetiva vem da identidade OAuth/IAM configurada no store. Falhas do Firestore são convertidas para códigos fixos; não há log de corpos nem mensagens brutas.

`listEligibleEvents` consulta apenas `pending` e `processing`, em páginas de até 100 documentos, ordenadas por `__name__`. Cada varredura usa um `readTime` fixo (relógio local menos cinco segundos) e um cursor opaco limitado a 55 minutos; cursor inválido, expirado, leitura fora de ordem ou mudança de snapshot falha fechada. A elegibilidade de `nextAttemptAt`/`leaseExpiresAt` e a compatibilidade com campos ausentes V1 são filtradas no servidor. Páginas podem conter menos eventos elegíveis que o limite e ainda retornar cursor.

## Decisão de versão e ciclo de vida

O evento é válido somente quando sua identidade, tipo, versão, operação e ID da operação são coerentes. A implementação consulta novamente o documento canônico: versão maior supersede o evento; versão menor, mesmo número com `outboxOperationId` diferente, ausência do documento ou inconsistência entre os IDs termina em `dead_letter`, sem publicar.

Uma projeção explícita V2 inclui somente colunas do catálogo. Contatos só seguem quando `publicContactApproved` é verdadeiro. `published=false` ou `active=false` atualiza a linha para removê-la dos resultados públicos e não cria tombstone. `deletedAt` preenchido produz tombstone permanente com versão e operação. Eventos antigos não apagam nem substituem versões posteriores, e um tombstone impede ressurreição.

## Retry e falha parcial

Falhas transitórias recebem apenas um código sanitizado permitido e `nextAttemptAt`, com backoff exponencial limitado. `attemptCount` conta claims, inclusive leases recuperados após interrupção. Falha marcada terminalmente ou esgotamento de tentativas resulta em `dead_letter`. O evento só vira `synced` depois que o adaptador de catálogo confirma `applied` ou `duplicate` idempotente.

Se a escrita no catálogo for confirmada, mas a transição para `synced` falhar, o evento permanece sem confirmação. Após expirar o lease, outro worker repete a mesma versão e `outboxOperationId`; o escritor SQL precisa tratar essa repetição como idempotente. Falhas repetidas de confirmação consomem o limite de claims e terminam em `dead_letter` com `retry_exhausted`, sem declarar sincronização. O protocolo não registra mensagens brutas de erro ou payloads privados.

## Limite da evidência

Os testes deste adaptador usam stores simulados e respostas REST fictícias. Provam o formato das transações/cursor, as precondições e a lógica de concorrência no mock; não provam resolução de conflitos ou isolamento transacional de um Firestore Emulator/serviço real, regras IAM, nem a integração do escritor SQL V2. A validação local anterior do escritor SQL é independente e não significa que os dois componentes estejam conectados. Antes de um consumidor automático, ainda é necessária uma prova integrada com Firestore Emulator isolado e o escritor SQL em ambiente local descartável.

## Alterações futuras necessárias para um consumidor real

- Executar o adaptador Firestore em runtime de servidor confiável com identidade IAM de privilégio mínimo; definir retenção e reprocessamento de dead letters.
- Atualizar Rules candidatas para permitir claims e transições somente a uma identidade de serviço confiável, mantendo clientes incapazes de alterar estado; definir como autenticar essa identidade.
- O evento pode ser lido ou atualizado apenas por acesso confiável do servidor; Rules candidatas continuam bloqueando clientes. A candidata V2 desta etapa cobre criação pareada, não claims, leitura administrativa ou transições.
- A consulta atual filtra somente por `state IN (pending, processing)` e ordena por `__name__`; ela depende do índice single-field automático de `state`, sem índice composto previsto para esse formato. Não foi testada no Emulator nesta etapa. A filtragem local de retry/lease reduz complexidade e mantém compatibilidade V1, mas pode ler muitos eventos não elegíveis. Se volume justificar filtros remotos por `nextAttemptAt` e `leaseExpiresAt`, medir custos e criar índices compostos separados, incluindo um caminho para V1 com campos ausentes/null, antes de mudar a consulta.
- Implementar claims e transições em transações Firestore, reconsultando a autorização/identidade de serviço e validando a versão esperada.
- Implementar escritor SQL server-side com chave idempotente `(id, catalog_version, outbox_operation_id)` e operação de tombstone; nunca disponibilizar credencial privilegiada no Flutter.
- Validar limites de tamanho, timeout, retry, dead-letter, reconciliação e métricas sob falhas reais.

Não foi criado consumidor, trigger, Cron, índice ou regra de produção nesta etapa.
