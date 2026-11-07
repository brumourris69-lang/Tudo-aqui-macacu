# Fixtures locais de homologação do MVP 1.0

Escopo: somente Firebase Emulator local do projeto `demo-universal-search`, Firestore em `127.0.0.1:8087` e Auth em `127.0.0.1:9097`. Nunca usar Firebase hospedado. O preparador exige variáveis de Emulator e projeto exatas, recusa credenciais/fallback e não sobrescreve documentos. O Admin SDK é usado apenas para semear ou remover; a leitura da aplicação continua sujeita às Rules pelo SDK cliente.

Criado em 5 de novembro de 2026 pelo `tools/mvp1-homologation-fixtures.mjs`. Não limpar o Emulator durante a homologação.

## IDs exclusivos

| Coleção | IDs |
|---|---|
| `ads` | `mvp1-qa-20261105-banner` |
| `establishments` | `mvp1-qa-20261105-est-comercio`, `mvp1-qa-20261105-est-alimentacao`, `mvp1-qa-20261105-est-servicos` |
| `events` | `mvp1-qa-20261105-evento-feira`, `mvp1-qa-20261105-evento-musica` |
| `routes` | `mvp1-qa-20261105-ponto-praca`, `mvp1-qa-20261105-ponto-rio` |
| `utilities` | `mvp1-qa-20261105-util-transporte`, `mvp1-qa-20261105-util-coleta` |

Cada documento acima tem uma projeção espelhada em `beta_public_catalog/{coleção}/items/{id}`. Um estabelecimento (`mvp1-qa-20261105-est-comercio`) está destacado. Eventos ficam em 12 e 18 de novembro de 2026. Banner sem link e sem URL de imagem usa a arte local de fallback. Imagens, telefones, WhatsApp, Instagram, mapas, inscrições e contatos foram omitidos para evitar URLs, chamadas ou visitas externas a dados fictícios. Textos e nomes estão marcados `[TESTE]`; não usar como conteúdo real.

## Conferir, sem gravar

No PowerShell interativo autorizado, a partir da raiz do repositório:

```powershell
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8087'
$env:GCLOUD_PROJECT = 'demo-universal-search'
$env:GOOGLE_CLOUD_PROJECT = 'demo-universal-search'
node .\tools\mvp1-homologation-fixtures.mjs --inspect
```

## Remover exclusivamente as fixtures

Execute somente depois da homologação. O script remove as 10 fontes e as 10 projeções listadas acima em uma transação, e aborta se houver conjunto parcial ou se algum documento tiver sido alterado. Não remove `home_pages/published`, documentos de conta, dados de outros IDs ou qualquer outra coleção/documento.

```powershell
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8087'
$env:GCLOUD_PROJECT = 'demo-universal-search'
$env:GOOGLE_CLOUD_PROJECT = 'demo-universal-search'
node .\tools\mvp1-homologation-fixtures.mjs --remove
```

O script recusa execução caso o Firestore Emulator não responda no host local, o Hub não confirme Auth/Firestore em loopback, o projeto não seja o demo exato, as variáveis de credenciais/`FIREBASE_CONFIG` estejam definidas ou os dados deixem de corresponder às fixtures.
