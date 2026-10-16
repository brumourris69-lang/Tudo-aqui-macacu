import 'package:flutter/material.dart';

import '../models/business.dart';
import '../repositories/business_repository.dart';

typedef PublishedBusinessStripCardBuilder =
    Widget Function(
      BuildContext context,
      Business business,
      bool saved,
      VoidCallback onFavorite,
    );

class PublishedBusinessStrip extends StatefulWidget {
  const PublishedBusinessStrip({
    super.key,
    required this.saved,
    required this.favorite,
    required this.cardBuilder,
    this.repository,
    this.businessesStreamFactory,
    this.limit = 6,
  }) : assert(repository != null || businessesStreamFactory != null);

  final BusinessRepository? repository;
  final Stream<List<Business>> Function()? businessesStreamFactory;
  final Set<String> saved;
  final ValueChanged<Business> favorite;
  final PublishedBusinessStripCardBuilder cardBuilder;
  final int limit;

  @override
  State<PublishedBusinessStrip> createState() => _PublishedBusinessStripState();
}

class _PublishedBusinessStripState extends State<PublishedBusinessStrip> {
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
      final source = snapshot.data ?? _lastItems;
      final items = source == null
          ? const <Business>[]
          : BusinessRepository.featuredBusinesses(source).take(widget.limit).toList();
      Widget status(String message, {bool retry = false}) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!retry) const CircularProgressIndicator(),
            if (!retry) const SizedBox(height: 8),
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
      if (source == null) {
        return SizedBox(
          height: 230,
          child: status(
            snapshot.hasError
                ? 'Não foi possível carregar os destaques.'
                : 'Carregando destaques…',
            retry: snapshot.hasError,
          ),
        );
      }
      if (items.isEmpty && !snapshot.hasError) {
        return const SizedBox(
          height: 96,
          child: Center(child: Text('Nenhum estabelecimento em destaque.')),
        );
      }
      return Column(
        children: [
          if (snapshot.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: status('Não foi possível atualizar os destaques.', retry: true),
            ),
          SizedBox(
            height: 230,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, index) => SizedBox(
                width: 292,
                child: widget.cardBuilder(
                  context,
                  items[index],
                  _isBusinessSaved(widget.saved, items[index]),
                  () => widget.favorite(items[index]),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

bool _isBusinessSaved(Set<String> saved, Business business) =>
    saved.contains(business.favoriteKey) || saved.contains(business.name);
