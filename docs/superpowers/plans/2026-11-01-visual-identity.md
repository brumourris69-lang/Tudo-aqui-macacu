# Identidade visual Tudo Aqui Macacu — plano de implementação

> **Para agentes de implementação:** executar checkpoint por checkpoint e parar para revisão humana entre os checkpoints.

**Objetivo:** unificar a identidade visual azul e laranja do aplicativo com Poppins, marca reutilizável e acabamento premium discreto, preservando o símbolo e os fluxos existentes.

**Arquitetura:** centralizar wordmark e moldura do logo em um widget `AppBrand`; centralizar cores e superfícies em `AppColors`/`AppTheme`; substituir as duas implementações de marca existentes por esse componente. Aplicar nas telas por checkpoints posteriores, sem alterar lógica de negócio.

**Stack:** Flutter/Dart, ThemeData Material 3, Poppins já disponível, testes de widget.

**Spec:** `docs/superpowers/specs/2026-11-01-visual-identity-design.md`.

## Restrições globais

- Preservar o logo atual, o nome e os acentos azul/laranja.
- Sem dependências novas, serviços hospedados, mudanças de dados, APK, commit ou push.
- Um checkpoint por vez; apresentar testes e resultado antes de avançar.

## Revisão de riscos

- Escala de fonte ampliada: testar que o wordmark cabe e respeita escala.
- Logo remoto inválido/lento: manter asset local como fallback.
- Cabeçalhos estreitos com ações: testar marca compacta sem overflow.
- Telas públicas versus fundo com foto: testar versões clara e inversa.
- Tema compartilhado alterando controles: cobrir botões, cards e formulários em `app_theme_test.dart`.

---

## Checkpoint 1 — Fundação da marca

**Arquivos:**
- Criar `lib/core/widgets/app_brand.dart`.
- Modificar `lib/core/theme/app_theme.dart` e, somente se necessário, `lib/core/theme/app_colors.dart`.
- Modificar `lib/redesigned_app.dart` para reutilizar a marca em `Brand` e `DynamicBrand`.
- Modificar `lib/features/businesses/screens/business_profile.dart` para usar a mesma marca no cabeçalho.
- Criar `test/app_brand_test.dart`; atualizar `test/app_theme_test.dart`.

**Interface produzida:** `AppBrand({String logoUrl = '', String tagline = 'A cidade na sua mão.', bool inverse = false, bool compact = false})`.

- [ ] Testar marca em modo claro/inverso, fallback local e ausência de overflow em 320 px.
- [ ] Implementar moldura elevada discreta e wordmark em Poppins, com `Macacu` destacado em laranja/azul conforme o fundo.
- [ ] Harmonizar `CardTheme`, botões e superfícies no tema global sem alterar callbacks ou navegação.
- [ ] Executar testes `app_brand_test.dart`, `app_theme_test.dart`, `business_profile_test.dart`, `flutter analyze --no-pub` e `git diff --check`.
- [ ] Parar e apresentar este checkpoint para revisão.

## Checkpoint 2 — Home e navegação

- Aplicar os tokens aprovados aos cabeçalhos, navegação e superfícies da Home, sem mexer em edição administrativa ou dados.
- Testar Home e caminhos de navegação afetados; parar para revisão.

## Checkpoint 3 — Áreas públicas

- Aplicar o sistema visual a Estabelecimentos, Explorar Macacu, Utilidades e Eventos.
- Preservar dados, regras, favoritos, agenda e rotas; testar telas estreitas/estados vazios; parar para revisão.

## Checkpoint 4 — Administração e Conta

- Aplicar os estilos a autenticação, Conta e editores administrativos preservando permissões, rascunhos e publicação.
- Testar controles de acesso e fluxos visuais afetados; parar para revisão.

## Checkpoint 5 — Acabamento e regressão

- Rever consistência, contraste, escala de texto e responsividade com testes Flutter direcionados e análise estática.
- Entregar resumo e aguardar pedido separado para compilar/instalar APK.
