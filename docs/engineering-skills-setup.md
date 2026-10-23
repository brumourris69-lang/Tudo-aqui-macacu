# Skills e plugins de engenharia

Este repositório combina skills específicas existentes, skills oficiais de plugins Codex e skills locais em `.agents/skills/`. As skills locais são instruções sob demanda; não alteram o código nem concedem autorização para produção, credenciais, publicação ou mudança de permissões.

## Skills existentes preservadas

- `android-build-manager`, `firebase-emulator-manager`, `firebase-security-auditor`, `flutter-ui-builder` e `flutter-widget-tester`.
- Skills oficiais Flutter/Dart, Android e Firebase são instaladas pelo Codex Plugin Manager e permanecem no cache global do usuário.
- `supabase` e `supabase-postgres-best-practices` foram instaladas no escopo deste projeto por `skills` CLI 1.7.4.

## Skills locais adicionadas

`app-architecture`, `ios-native`, `mobile-ui-ux`, `mobile-security`, `lgpd-privacy`, `backend-engineering`, `automated-qa`, `safe-refactoring`, `mobile-release` e `app-performance`.

As skills complementam as instruções de `AGENTS.md`. Prefira a skill mais específica já existente e combine orientações somente quando a tarefa atravessar domínios. As recomendações sobre LGPD são técnicas e não constituem parecer jurídico.

## Plugins e ferramentas

- `dart-flutter` 1.0.7: skills oficiais e MCP Dart configurado para executar `dart mcp-server`.
- `android-skills` 1.0.16: skills oficiais do Android; o manifesto não configura MCP.
- `firebase` 1.1.0: skills oficiais e MCP Firebase configurado via `npx firebase-tools@15.32.1 mcp --dir .`.

Os plugins foram instalados no Codex do usuário, não no manifesto de dependências do app. O MCP Firebase pode expor operações contra projetos conforme autenticação/configuração disponível; com `--dir .`, pode ler o projeto padrão local, por isso instalação não é autorização para usá-lo em serviços hospedados. Antes de qualquer chamada, confirme ambiente e escopo. O processo `npx` pode baixar `firebase-tools@15.32.1` quando o MCP for iniciado, pois essa versão foi declarada pelo plugin. O MCP Dart também não foi iniciado nesta tarefa.

Na instalação Supabase, o relatório do `skills` CLI marcou o risco geral como `Safe`, zero alertas de socket e o indicador Snyk como `Med` para a skill Supabase e `Low` para Postgres Best Practices. Os dois `SKILL.md` foram lidos; não há scripts executáveis dentro das duas skills instaladas. Esses indicadores automatizados não são garantia de segurança.

O Codex desktop pode precisar ser reiniciado ou abrir uma nova conversa para descobrir plugins recém-instalados. A instalação não executou servidor MCP, login, inferência, emulador, build ou chamada hospedada.

## Validação e manutenção

Cada skill local deve ter `SKILL.md` com frontmatter `name` e `description`; valide com o `quick_validate.py` do `skill-creator` disponível no perfil Codex. Nesta instalação, esse script não pôde iniciar porque o Python disponível não tem o módulo PyYAML. Em substituição, o YAML dos 17 `SKILL.md` do projeto foi analisado pelo parser YAML já presente no cache do `skills` CLI e os metadados/nomes/descrições foram verificados. Não foi instalada dependência Python.

`codex plugin list --marketplace <nome> --json` confirmou cada plugin como `installed: true` e `enabled: true`. Os manifests foram inspecionados para identificar servidores MCP, mas nenhum servidor foi iniciado e nenhum tool call MCP foi feito. Portanto, o registro no marketplace foi validado; a inicialização operacional do MCP e a descoberta de skills em uma conversa nova ainda dependem de recarregar/reabrir o Codex.

As versões instaladas ficam registradas no Codex Plugin Manager; atualize conscientemente, sem substituir skills locais. O `git diff --check` foi executado após a configuração.

## Fontes oficiais consultadas

- Flutter: https://docs.flutter.dev/ai/get-started
- Flutter agent plugins: https://github.com/flutter/agent-plugins
- Android skills: https://developer.android.com/tools/agents/android-skills e https://github.com/android/skills
- Firebase Agent Skills: https://firebase.google.com/docs/ai-assistance/agent-skills e https://github.com/firebase/agent-skills
- Supabase Agent Skills: https://supabase.com/docs/guides/ai-tools/ai-skills
- Skills CLI: https://www.npmjs.com/package/skills
