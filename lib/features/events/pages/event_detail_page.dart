import 'package:flutter/material.dart';

import '../../../core/config/local_network_isolation.dart';
import '../../../core/config/local_search_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../search/repositories/local_universal_search_repository.dart';
import '../models/public_event.dart';

/// Secure, reusable event detail surface. Its default resolver is local-only.
class EventDetailPage extends StatefulWidget {
  const EventDetailPage({super.key, required this.eventId, this.resolveEvent});

  final String eventId;
  final Future<PublicEvent?> Function(String id)? resolveEvent;

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  late Future<PublicEvent?> _event;

  @override
  void initState() {
    super.initState();
    _event = _load();
  }

  Future<PublicEvent?> _load() {
    if (widget.resolveEvent != null) {
      return widget.resolveEvent!(widget.eventId);
    }
    return LocalUniversalSearchRepository.resolveEvent(widget.eventId);
  }

  void _retry() {
    setState(() {
      _event = _load();
    });
  }

  bool _canLoadImage(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    if (LocalSearchEnvironment.enabled) return isLocalEmulatorEndpoint(uri);
    return uri.scheme == 'https';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.soft,
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Voltar',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('Evento'),
    ),
    body: FutureBuilder<PublicEvent?>(
      future: _event,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.sky),
          );
        }
        if (snapshot.hasError) {
          return _status(
            icon: Icons.wifi_off_rounded,
            title: 'Não foi possível carregar este evento.',
            detail: 'Verifique a conexão local e tente novamente.',
            action: FilledButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          );
        }
        final event = snapshot.data;
        if (event == null) {
          return _status(
            icon: Icons.event_busy_rounded,
            title: 'Este evento não está mais disponível.',
          );
        }
        return _content(event);
      },
    ),
  );

  Widget _content(PublicEvent event) {
    final showImage = _canLoadImage(event.imageUrl);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showImage) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        event.imageUrl,
                        fit: BoxFit.cover,
                        frameBuilder: (context, child, frame, syncLoaded) =>
                            frame != null || syncLoaded
                            ? child
                            : const ColoredBox(
                                color: Color(0xFFEAF3FD),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.sky,
                                  ),
                                ),
                              ),
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: Color(0xFFEAF3FD),
                          child: Center(
                            child: Icon(
                              Icons.event_rounded,
                              size: 42,
                              color: AppColors.sky,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                ] else ...[
                  Container(
                    width: double.infinity,
                    height: 112,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0056D6), Color(0xFF007BFF)],
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(
                      Icons.event_rounded,
                      color: Colors.white,
                      size: 46,
                    ),
                  ),
                  const SizedBox(height: 22),
                ],
                if (event.category.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3FD),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      event.category,
                      style: const TextStyle(
                        color: AppColors.ocean,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  event.title,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                if (event.eventDate.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _metadata(Icons.calendar_month_rounded, event.eventDate),
                ],
                if (event.location.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _metadata(Icons.location_on_outlined, event.location),
                ],
                if (event.description.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    event.description,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 16,
                      height: 1.7,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _metadata(IconData icon, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: AppColors.orange),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );

  Widget _status({
    required IconData icon,
    required String title,
    String? detail,
    Widget? action,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.sky, size: 42),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              height: 1.4,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, height: 1.5),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    ),
  );
}
