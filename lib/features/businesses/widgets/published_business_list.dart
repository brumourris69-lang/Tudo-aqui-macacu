import 'package:flutter/material.dart';

import '../models/business.dart';
import '../repositories/business_repository.dart';

typedef PublishedBusinessListCardBuilder =
    Widget Function(
      BuildContext context,
      Business business,
      bool saved,
      VoidCallback onFavorite,
    );

class PublishedBusinessList extends StatefulWidget {
  const PublishedBusinessList({
    super.key,
    required this.saved,
    required this.favorite,
    required this.cardBuilder,
    this.repository,
    this.businessesStreamFactory,
  }) : assert(repository != null || businessesStreamFactory != null);

  final BusinessRepository? repository;
  final Stream<List<Business>> Function()? businessesStreamFactory;
  final Set<String> saved;
  final ValueChanged<Business> favorite;
  final PublishedBusinessListCardBuilder cardBuilder;

  @override
  State<PublishedBusinessList> createState() => _PublishedBusinessListState();
}

class _PublishedBusinessListState extends State<PublishedBusinessList> {
  late Stream<List<Business>> _stream;
  List<Business>? _lastItems;
  int _generation = 0;

  Stream<List<Business>> _createStream() =>
      widget.businessesStreamFactory?.call() ??
      widget.repository!.watchPublishedBusinesses();

  @override
  void initState() {
    super.initState();
    _stream = _createStream();
  }

  void _retry() => setState(() {
    _stream = _createStream();
    _generation++;
  });

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Business>>(
    key: ValueKey(_generation),
    stream: _stream,
    builder: (context, snapshot) {
      if (snapshot.hasData) _lastItems = snapshot.data;
      final items = snapshot.data ?? _lastItems;
      if (items == null && snapshot.hasError) {
        return _status(
          'Não foi possível carregar os estabelecimentos.',
          retry: true,
        );
      }
      if (items == null) return _status('Carregando estabelecimentos…');
      if (items.isEmpty && !snapshot.hasError) {
        return _status('Nenhum estabelecimento publicado por enquanto.');
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
        child: Column(
          children: [
            if (snapshot.hasError)
              _status('Não foi possível atualizar os estabelecimentos.', retry: true),
            ...items.map(
              (business) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: widget.cardBuilder(
                  context,
                  business,
                  _isBusinessSaved(widget.saved, business),
                  () => widget.favorite(business),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _status(String message, {bool retry = false}) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!retry) const CircularProgressIndicator(),
        if (!retry) const SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center),
        if (retry)
          TextButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
          ),
      ],
    ),
  );
}

bool _isBusinessSaved(Set<String> saved, Business business) =>
    saved.contains(business.favoriteKey) || saved.contains(business.name);
