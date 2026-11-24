import 'package:flutter/material.dart';

import '../models/business.dart';
import '../repositories/business_repository.dart';

typedef PublicBusinessPreviewBuilder =
    Widget Function(BuildContext context, Business business);

/// Resolves only the public Premium complement for an already-loaded Basic
/// listing. It never reads the canonical establishment document.
class PublicBusinessPreview extends StatefulWidget {
  const PublicBusinessPreview({
    super.key,
    required this.business,
    required this.repository,
    required this.builder,
  });

  final Business business;
  final BusinessRepository repository;
  final PublicBusinessPreviewBuilder builder;

  @override
  State<PublicBusinessPreview> createState() => _PublicBusinessPreviewState();
}

class _PublicBusinessPreviewState extends State<PublicBusinessPreview> {
  late Future<Business> _preview;

  Future<Business> _resolve(Business basic) async {
    try {
      return await widget.repository.getPublicPreview(basic);
    } catch (_) {
      return basic;
    }
  }

  @override
  void initState() {
    super.initState();
    _preview = _resolve(widget.business);
  }

  @override
  void didUpdateWidget(covariant PublicBusinessPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.business, widget.business) ||
        oldWidget.repository != widget.repository) {
      _preview = _resolve(widget.business);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Business>(
    future: _preview,
    initialData: widget.business,
    builder: (context, snapshot) =>
        widget.builder(context, snapshot.data ?? widget.business),
  );
}
