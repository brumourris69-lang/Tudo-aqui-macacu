# App normal — preparação da ativação

## Decisão e alcance

O proprietário decidiu usar somente o app normal no MEmu e autorizou preparar
a ativação no Firebase real. A instalação de desenvolvimento usa o identificador
`br.com.tudoaquimacacu.tudo_aqui_macacu`, assinatura debug e nenhum `LOCAL_SEARCH_*`.
Não é uma release. O projeto normal configurado é `tudo-aqui-macacu`.

O flavor `searchLocal` permanece no repositório para testes automatizados de
segurança; não precisa ser usado como segundo aplicativo pelo proprietário.
Ocultar sua instalação preserva os dados locais. Não copiar fixtures do demo
para o Firebase real.

Autorização atual: preparar e verificar. Não inclui deploy, habilitar faturamento,
alterar contas/claims reais, enforcement App Check ou migrar dados.

## Estado confirmado no código

- Gradle já suporta debug normal sem flavor e exige autorização explícita para
  release; não precisa remover o isolamento nem modificar assinatura.
- `main.dart` inicializa o Firebase normal sem flags locais. Os serviços externos
  normais voltam ao comportamento existente; esse app não é um ambiente isolado.
- `UniversalSearchPage` seleciona repositório somente no modo local. No normal,
  a busca ainda não executa consultas.
- `business_search_functions.js` e seu registro em `functions/index.js` são
  exclusivos do demo; não existe export normal da busca preparado para deploy.
- `SecureBackend.productionAuthorized` permanece false. Listagens e operações
  protegidas não têm fallback inseguro de acesso direto.
- Os gateways Node possuem opt-in `SECURE_BACKEND_ENABLED=true` para o projeto
  oficial, mas isso não foi configurado remotamente.
- App Check real não está ativado pelo Flutter. O token sintético do transporte
  local nunca deve ser reutilizado pelo app normal.
- Admin exige claim, versão e estado `admin_authorizations`; não habilitar por
  e-mail para contornar falta de provisionamento.

## Sequência de preparação e ativação futura

| Ordem | Trabalho | Condição para avançar |
| --- | --- | --- |
| 1 | Inventariar, com acesso autorizado, plano Firebase, provedores Auth, funções/regras/índices implantados, App Check e configurações Worker | Registrar diferenças entre configuração remota e código; não presumir que estão sincronizados |
| 2 | Revisar dependências/advisories e runtime Functions conforme Segurança 2D; estimar custos e alertas | Aprovação financeira separada para qualquer mudança de plano |
| 3 | Preparar transporte normal de pesquisa com SDK callable, decodificação pública, erros, cursor e navegação existentes | Sem token sintético; sem baixar coleções inteiras; manter transporte demo nos testes |
| 4 | Preparar registro normal de busca e sincronização com opt-in explícito, Auth, App Check, quotas e revalidação | Testes demo de permissões, índice atrasado, expiração, paginação e falhas fechadas |
| 5 | Configurar Auth anônimo e App Check para builds autorizados | Autorização específica no Console; debug provider apenas para teste normal debug; Play Integrity para distribuição futura |
| 6 | Provisionar Admin por procedimento confiável | Autorização separada; confirmar UID, versão, estado, token atualizado e recuperação antes de mudar Rules |
| 7 | Coordenar implantação de gateways, busca, índices, Rules e Worker | Revisão e autorização de deploy; não implantar apenas Rules deixando cliente sem backend |
| 8 | Preparar índice inicial dos registros existentes | Autorização própria e prévia simulação; somente projeção pública de registros elegíveis; nenhuma cópia automática do demo |
| 9 | Liberar conexão normal Flutter e instalar debug atualizado | Validar no app normal visitante, login, busca, filtros, perfil, favoritos e Admin; mensagens de erro claras |

Os filtros Turismo/Notícias/Empregos/Eventos/Utilidades continuam pendentes de
implementação; a arquitetura multi-conteúdo não os torna funcionais por si só.

## Critérios de validação

- Executar Analyze, suítes Flutter normal/local, Node/Worker e segurança Emulator.
- Confirmar projeto normal, Auth válido e App Check real quando exigido; testes
  de emulator/mocks não comprovam atestação real.
- Garantir exclusão de privados, despublicados, desativados e expirados; preservar
  IDs e revalidar antes do perfil.
- Confirmar autorização administrativa e revogação com estado versionado; não
  alterar regras para permitir acesso indevido quando faltar configuração.
- Não imprimir credenciais/tokens ou colocar chaves administrativas no Flutter.
- Verificar que o app normal contém as alterações locais; não anunciar busca real
  funcionando antes de ter resposta validada do backend implantado.

## Interrupção e recuperação

Antes da implantação, registrar versões/configurações atuais e definir pontos de
retorno. Em falha, bloquear a nova conexão e investigar; não reabrir regras
permissivas nem restaurar fallback por e-mail. Retorno de backend/cliente deve
continuar compatível com as regras seguras. Não apagar dados ou desfazer
revogações administrativas como mecanismo de recuperação.

Nenhuma etapa remota desta sequência foi executada nesta preparação.
