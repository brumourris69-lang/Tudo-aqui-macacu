import 'dart:async';
import '../../../core/config/local_search_environment.dart';
import '../../../core/config/local_network_isolation.dart';
import '../../../redesigned_app.dart' show App3DIcon, AppIcon;
import '../../businesses/models/business.dart';
import '../../businesses/repositories/business_repository.dart';
import '../../businesses/screens/business_profile.dart';
import '../models/search_result.dart';
import '../policies/business_search_policy.dart';
import '../repositories/universal_search_repository.dart';
import '../repositories/local_universal_search_repository.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Production stays interface-only; the isolated local variant uses the demo backend.
class UniversalSearchPage extends StatefulWidget {
  const UniversalSearchPage({
    super.key,
    this.repository,
    this.saved,
    this.onFavorite,
    this.resolveBusiness,
  });
  final UniversalSearchRepository? repository;
  final Set<String>? saved;
  final ValueChanged<Business>? onFavorite;
  final Future<Business?> Function(String id)? resolveBusiness;

  @override
  State<UniversalSearchPage> createState() => _UniversalSearchPageState();
}

class _UniversalSearchPageState extends State<UniversalSearchPage> {
  final _controller = TextEditingController();
  late final UniversalSearchRepository? _repository =
      widget.repository ??
      (LocalSearchEnvironment.enabled
          ? LocalUniversalSearchRepository()
          : null);
  Timer? _debounce;
  int _generation = 0;
  bool _loading = false;
  bool _searched = false;
  String? _error;
  final List<SearchResult> _results = [];
  BusinessSearchCursor? _cursor;
  BusinessSearchFilter get _filter => switch (_selectedFilter) {
    'Comércios' => BusinessSearchFilter.commerce,
    'Serviços' => BusinessSearchFilter.services,
    _ => BusinessSearchFilter.all,
  };

  void _changed() {
    _debounce?.cancel();
    _generation++;
    setState(() {
      _results.clear();
      _cursor = null;
      _error = null;
      _searched = false;
      _loading = false;
    });
    if (_repository == null || _controller.text.trim().length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 350), () => _search());
  }

  Future<void> _search({bool more = false}) async {
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repository!.search(
        BusinessSearchRequest(
          query: _controller.text,
          filter: _filter,
          limit: 10,
          cursor: more ? _cursor : null,
        ),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (!more) _results.clear();
        for (final result in page.results) {
          if (!_results.any((item) => item.id == result.id)) {
            _results.add(result);
          }
        }
        _cursor = page.nextCursor;
        _searched = true;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error =
            'Não foi possível pesquisar. Verifique a conexão local e tente novamente.';
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(SearchResult result) async {
    try {
      if (widget.resolveBusiness == null) {
        await LocalUniversalSearchRepository.verifyIsolation();
      }
      final business =
          await (widget.resolveBusiness?.call(result.id) ??
              BusinessRepository().getPublicBusiness(result.id));
      if (!mounted) return;
      if (business == null) throw StateError('unavailable');
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StatefulBuilder(
            builder: (context, update) => BusinessProfile(
              business: business,
              saved:
                  widget.saved?.contains(business.favoriteKey) == true ||
                  widget.saved?.contains(business.name) == true,
              onFavorite: () {
                widget.onFavorite?.call(business);
                update(() {});
              },
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este estabelecimento não está disponível.'),
          ),
        );
      }
    }
  }

  Widget _resultImage(SearchResult result) {
    final fallback = App3DIcon(
      icon: AppIcon.fromCategory(result.category),
      size: 52,
    );
    final uri = Uri.tryParse(result.imageUrl);
    final allowed =
        result.imageUrl.isNotEmpty &&
        uri != null &&
        (!LocalSearchEnvironment.enabled || isLocalEmulatorEndpoint(uri));
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFFEDF5FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: allowed
            ? Image.network(
                result.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => Center(child: fallback),
              )
            : Center(child: fallback),
      ),
    );
  }

  Widget _resultCard(SearchResult result) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE9F0F8)),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: .045),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: () => _open(result),
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _resultImage(result),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        [
                          result.category,
                          result.subcategory,
                        ].where((value) => value.trim().isNotEmpty).join(' · '),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.sky,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _status({
    required IconData icon,
    required String title,
    String? detail,
    Widget? action,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 30, 16, 24),
    child: Column(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: const Color(0xFFEDF5FF),
            borderRadius: BorderRadius.circular(21),
          ),
          child: Icon(icon, color: AppColors.sky, size: 28),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
        if (action != null) ...[const SizedBox(height: 14), action],
      ],
    ),
  );

  Widget _localBody() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
    children: [
      const Text(
        'Ambiente local · estabelecimentos fictícios de teste',
        style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.5),
      ),
      if (_results.isNotEmpty) ...[
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Resultados encontrados',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${_results.length} ${_results.length == 1 ? 'carregado' : 'carregados'}',
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      if (_loading) ...[
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: const LinearProgressIndicator(
            minHeight: 3,
            color: AppColors.sky,
            backgroundColor: Color(0xFFE2EEFF),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text(
            'Pesquisando…',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
      ],
      if (_error != null)
        _status(
          icon: Icons.wifi_off_rounded,
          title: 'Não foi possível pesquisar.',
          detail: 'Verifique a conexão local e tente novamente.',
          action: OutlinedButton.icon(
            onPressed: _loading
                ? null
                : () => _search(more: _results.isNotEmpty),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Tentar novamente'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.ocean,
              minimumSize: const Size(48, 48),
              side: const BorderSide(color: Color(0xFFD3E6FF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      if (!_loading && _error == null && _results.isEmpty)
        _status(
          icon: _searched ? Icons.search_off_rounded : Icons.search_rounded,
          title: _searched
              ? 'Nenhum resultado encontrado.'
              : 'Digite pelo menos dois caracteres.',
          detail: _searched
              ? 'Tente outro nome ou escolha outro filtro.'
              : null,
        ),
      for (final result in _results) _resultCard(result),
      if (_cursor != null)
        TextButton(
          onPressed: _loading ? null : () => _search(more: true),
          child: const Text('Carregar mais'),
        ),
    ],
  );

  String _selectedFilter = 'Todos';
  static const _filters = [
    'Todos',
    'Comércios',
    'Serviços',
    'Turismo',
    'Empregos',
    'Eventos',
    'Notícias',
    'Utilidades',
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _generation++;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.soft,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Voltar',
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.ink,
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => _changed(),
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        hintText: 'O que você procura em Macacu?',
                        hintStyle: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AppColors.sky,
                        ),
                        suffixIcon: _controller.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Limpar pesquisa',
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: AppColors.muted,
                                ),
                                onPressed: () {
                                  _controller.clear();
                                  _changed();
                                },
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2EAF3),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2EAF3),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppColors.sky),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final filter in _filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          _repository != null &&
                                  !_filters.take(3).contains(filter)
                              ? '$filter · em breve'
                              : filter,
                        ),
                        selected: filter == _selectedFilter,
                        onSelected:
                            _repository != null &&
                                !_filters.take(3).contains(filter)
                            ? null
                            : (_) {
                                setState(() => _selectedFilter = filter);
                                _changed();
                              },
                        showCheckmark: false,
                        visualDensity: VisualDensity.standard,
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        disabledColor: const Color(0xFFF1F5FA),
                        selectedColor: AppColors.sky,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: filter == _selectedFilter
                              ? Colors.white
                              : AppColors.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        side: BorderSide(
                          color: filter == _selectedFilter
                              ? AppColors.sky
                              : const Color(0xFFE2EAF3),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _repository != null
                  ? _localBody()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDF5FF),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Icon(
                              Icons.search_rounded,
                              color: AppColors.sky,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            hasText
                                ? 'Pesquisa em desenvolvimento'
                                : 'Encontre tudo em Cachoeiras de Macacu.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            hasText
                                ? 'Em breve você poderá encontrar tudo por aqui.'
                                : 'Pesquise comércios, serviços, lugares, eventos e muito mais.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
