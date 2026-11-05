import 'package:flutter/material.dart';

import '../../../core/config/local_network_isolation.dart';
import '../../../core/config/local_search_environment.dart';
import '../../../core/content/public_content_detail_repository.dart';
import '../../../core/services/external_link_service.dart';
import '../../../core/share/public_share_content.dart';
import '../../../core/share/public_share_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../models/public_event.dart';
import '../utils/city_calendar_date.dart';

/// Public event details are loaded from the authenticated, allowlisted backend.
class EventDetailPage extends StatefulWidget {
  const EventDetailPage({
    super.key,
    required this.eventId,
    this.resolveEvent,
    this.onShare,
    this.agendaSaved = false,
    this.onToggleAgenda,
  });

  final String eventId;
  final Future<PublicEvent?> Function(String id)? resolveEvent;
  final Future<void> Function(PublicShareContent content)? onShare;
  final bool agendaSaved;
  final Future<bool> Function(PublicEvent event)? onToggleAgenda;

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  late Future<PublicEvent?> _event;
  late bool _agendaSaved;
  bool _agendaPending = false;

  @override
  void initState() {
    super.initState();
    _agendaSaved = widget.agendaSaved;
    _event = _load();
  }

  Future<void> _toggleAgenda(PublicEvent event) async {
    final action = widget.onToggleAgenda;
    if (action == null || _agendaPending) return;
    setState(() => _agendaPending = true);
    try {
      if (await action(event) && mounted) {
        setState(() => _agendaSaved = !_agendaSaved);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível atualizar sua agenda.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _agendaPending = false);
    }
  }

  Future<PublicEvent?> _load() {
    if (widget.resolveEvent != null) {
      return widget.resolveEvent!(widget.eventId);
    }
    return PublicContentDetailRepository()
        .resolve(collection: 'events', id: widget.eventId)
        .then(
          (data) => data == null
              ? null
              : PublicEvent.fromMap({...data, 'id': widget.eventId}),
        );
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
    final images = {
      for (final value in [event.imageUrl, ...event.galleryUrls])
        if (_canLoadImage(value)) value,
    }.toList();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.section,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (images.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.cardLarge),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: PageView(
                        children: [
                          for (final image in images)
                            Image.network(
                              image,
                              fit: BoxFit.cover,
                              frameBuilder:
                                  (context, child, frame, syncLoaded) =>
                                      frame != null || syncLoaded
                                      ? child
                                      : const ColoredBox(
                                          color: AppColors.skyTint,
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              color: AppColors.sky,
                                            ),
                                          ),
                                        ),
                              errorBuilder: (_, _, _) => const ColoredBox(
                                color: AppColors.skyTint,
                                child: Center(
                                  child: Icon(
                                    Icons.event_rounded,
                                    size: 42,
                                    color: AppColors.sky,
                                  ),
                                ),
                              ),
                            ),
                        ],
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
                      borderRadius: BorderRadius.circular(AppRadii.cardLarge),
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
                      color: AppColors.skyTint,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
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
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                if (widget.onToggleAgenda != null) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('event-agenda-toggle'),
                      onPressed: _agendaPending
                          ? null
                          : () => _toggleAgenda(event),
                      icon: _agendaPending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _agendaSaved
                                  ? Icons.event_available_rounded
                                  : Icons.event_available_outlined,
                            ),
                      label: Text(
                        _agendaSaved
                            ? 'Remover da Minha Agenda'
                            : 'Adicionar à Minha Agenda',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: PublicShareButton(
                    content: PublicShareContent(
                      title: event.title,
                      description: event.description,
                    ),
                    onShare: widget.onShare == null
                        ? null
                        : () => widget.onShare!(
                            PublicShareContent(
                              title: event.title,
                              description: event.description,
                            ),
                          ),
                    tooltip: 'Compartilhar evento',
                  ),
                ),
                if (event.eventDate.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _eventDateCard(event),
                ],
                if (event.location.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _metadata(Icons.location_on_outlined, event.location),
                ],
                if (event.address.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _metadata(Icons.directions_outlined, event.address),
                ],
                if (event.organizer.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _metadata(Icons.groups_2_outlined, event.organizer),
                ],
                if (_canOpenMaps(event.maps) ||
                    _canOpenUrl(event.registrationUrl) ||
                    _canOpenUrl(event.contactUrl)) ...[
                  const SizedBox(height: AppSpacing.xl),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      if (_canOpenMaps(event.maps))
                        OutlinedButton.icon(
                          onPressed: () =>
                              openUrl(context, event.maps, 'localização'),
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Ver localização'),
                        ),
                      if (_canOpenUrl(event.registrationUrl))
                        FilledButton.icon(
                          onPressed: () => openUrl(
                            context,
                            event.registrationUrl,
                            'inscrição',
                          ),
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('Inscreva-se'),
                        ),
                      if (_canOpenUrl(event.contactUrl))
                        OutlinedButton.icon(
                          onPressed: () =>
                              openUrl(context, event.contactUrl, 'contato'),
                          icon: const Icon(Icons.chat_outlined),
                          label: const Text('Falar com organizador'),
                        ),
                    ],
                  ),
                ],
                if (event.description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.section),
                  Text(
                    event.description,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.ink,
                      height: 1.6,
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

  String _eventDateRangeLabel(PublicEvent event) {
    final startLabel = event.startTime.isEmpty
        ? formatEventDateTimeInBrasilia(event.eventDate)
        : formatEventDateInBrasilia(event.eventDate);
    if (event.endDate.isEmpty) return startLabel;
    final start = dateInBrasilia(event.eventDate);
    final end = dateInBrasilia(event.endDate);
    if (start == null ||
        end == null ||
        (start.year == end.year &&
            start.month == end.month &&
            start.day == end.day)) {
      return startLabel;
    }
    return '$startLabel até ${formatEventDateInBrasilia(event.endDate)}';
  }

  Widget _eventDateCard(PublicEvent event) {
    final details = [
      _eventDateRangeLabel(event),
      if (event.startTime.isNotEmpty) event.startTime,
      if (event.endTime.isNotEmpty) 'até ${event.endTime}',
    ].join(' · ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.skyTint,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.sky.withValues(alpha: .12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              color: AppColors.ocean,
              size: 21,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Data e horário',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  details,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _canOpenUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        uri.scheme.toLowerCase() == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  bool _canOpenMaps(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        uri.userInfo.isEmpty &&
        ((uri.scheme.toLowerCase() == 'https' && uri.host.isNotEmpty) ||
            (uri.scheme.toLowerCase() == 'geo' && uri.path.isNotEmpty));
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
