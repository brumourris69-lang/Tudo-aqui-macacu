import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../../../core/config/firestore_collections.dart';
import '../../../core/content/public_content_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../models/public_event.dart';
import '../services/event_reminder_service.dart';
import '../utils/city_calendar_date.dart';
import '../widgets/event_reminder_control.dart';

class MyAgendaView extends StatefulWidget {
  const MyAgendaView({
    super.key,
    required this.savedEventIds,
    required this.onRemove,
    this.uid,
    this.reminderService,
    this.onReminderChanged,
    this.eventsStreamFactory,
    this.onOpen,
    this.isAuthenticated = true,
  });

  final Set<String> savedEventIds;
  final Future<bool> Function(PublicEvent event) onRemove;
  final String? uid;
  final EventReminderService? reminderService;
  final VoidCallback? onReminderChanged;
  final Stream<PublicContentSnapshot> Function()? eventsStreamFactory;
  final ValueChanged<PublicEvent>? onOpen;
  final bool isAuthenticated;

  @override
  State<MyAgendaView> createState() => _MyAgendaViewState();
}

class _MyAgendaViewState extends State<MyAgendaView> {
  late Stream<PublicContentSnapshot> _events;
  late Set<String> _savedEventIds;
  final Set<String> _pendingRemovals = {};
  StreamSubscription<User?>? _authSubscription;
  String? _currentUid;
  bool _accountChanged = false;

  Stream<PublicContentSnapshot> _createStream() =>
      (widget.eventsStreamFactory?.call() ??
              watchPublicContent(FirestoreCollections.events))
          .map((snapshot) {
            final uid = _currentUid;
            if (uid != null && uid.isNotEmpty) {
              unawaited(_reconcileReminders(uid, snapshot));
            }
            return snapshot;
          });

  @override
  void initState() {
    super.initState();
    _events = _createStream();
    _savedEventIds = Set.of(widget.savedEventIds);
    _currentUid = widget.uid;
    if (widget.uid != null) {
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
        _handleAuthChange,
      );
    }
  }

  void _handleAuthChange(User? user) {
    final nextUid = user == null || user.isAnonymous ? null : user.uid;
    if (nextUid == _currentUid) return;
    final previousUid = _currentUid;
    setState(() {
      _currentUid = null;
      _accountChanged = true;
      _savedEventIds.clear();
    });
    if (previousUid != null) {
      unawaited(
        (widget.reminderService ?? EventReminderService.instance).pauseUser(
          previousUid,
        ),
      );
    }
  }

  void _retry() => setState(() => _events = _createStream());

  @override
  void didUpdateWidget(covariant MyAgendaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != null && oldWidget.uid != widget.uid) {
      unawaited(
        (oldWidget.reminderService ?? EventReminderService.instance).pauseUser(
          oldWidget.uid!,
        ),
      );
    }
    if (oldWidget.eventsStreamFactory != widget.eventsStreamFactory) {
      _events = _createStream();
    }
    if (!setEquals(oldWidget.savedEventIds, widget.savedEventIds)) {
      _savedEventIds = Set.of(widget.savedEventIds);
      if (widget.uid != null) {
        unawaited(
          (widget.reminderService ?? EventReminderService.instance)
              .cancelRemovedFromAgenda(widget.uid!, _savedEventIds),
        );
      }
    }
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }

  Future<void> _remove(PublicEvent event) async {
    if (!_pendingRemovals.add(event.id)) return;
    setState(() => _savedEventIds.remove(event.id));
    var success = false;
    try {
      success = await widget.onRemove(event);
    } catch (_) {
      success = false;
    }
    if (!mounted) return;
    setState(() {
      if (!success) _savedEventIds.add(event.id);
      _pendingRemovals.remove(event.id);
    });
    if (success && widget.uid != null) {
      await (widget.reminderService ?? EventReminderService.instance).cancel(
        widget.uid!,
        event.id,
      );
      widget.onReminderChanged?.call();
    }
  }

  Future<void> _reconcileReminders(
    String uid,
    PublicContentSnapshot snapshot,
  ) async {
    final visibleEvents = <PublicEvent>[];
    for (final document in snapshot.docs) {
      final data = document.data();
      if (!_isVisibleEvent(data)) continue;
      try {
        visibleEvents.add(PublicEvent.fromMap({...data, 'id': document.id}));
      } on FormatException {
        // Invalid public records are not eligible for a local reminder.
      }
    }
    await (widget.reminderService ?? EventReminderService.instance).reconcile(
      uid: uid,
      savedEventIds: Set.unmodifiable(_savedEventIds),
      publicEvents: visibleEvents,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Minha Agenda')),
    body: StreamBuilder<PublicContentSnapshot>(
      stream: _events,
      builder: (context, snapshot) {
        if (_accountChanged) {
          return _status(
            context,
            icon: Icons.lock_outline_rounded,
            message: 'Sua sessão mudou.',
            detail: 'Volte e abra Minha Agenda novamente com a conta atual.',
          );
        }
        if (snapshot.hasError) {
          return _status(
            context,
            icon: Icons.cloud_off_outlined,
            message: 'Não foi possível carregar sua agenda.',
            action: FilledButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final publicEvents = <PublicEvent>[];
        for (final document in snapshot.data!.docs) {
          final data = document.data();
          if (!_isVisibleEvent(data) || !_savedEventIds.contains(document.id)) {
            continue;
          }
          try {
            publicEvents.add(PublicEvent.fromMap({...data, 'id': document.id}));
          } on FormatException {
            // Invalid public records are not rendered in a personal agenda.
          }
        }
        publicEvents.sort((left, right) {
          final leftDate = dateInBrasilia(left.eventDate);
          final rightDate = dateInBrasilia(right.eventDate);
          if (leftDate == null) return rightDate == null ? 0 : 1;
          if (rightDate == null) return -1;
          return leftDate.compareTo(rightDate);
        });
        final visibleIds = publicEvents.map((event) => event.id).toSet();
        final unavailableCount = _savedEventIds.difference(visibleIds).length;
        if (publicEvents.isEmpty) {
          return _status(
            context,
            icon: Icons.event_note_outlined,
            message: widget.isAuthenticated
                ? 'Os eventos que você salvar aparecerão aqui.'
                : 'Sua agenda está vazia. Para salvar um evento, entre na sua conta.',
            detail: unavailableCount == 0
                ? null
                : 'Alguns eventos salvos não estão mais disponíveis. Seus registros foram preservados.',
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text(
              'Seus eventos salvos',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Datas e horários no horário de Brasília.',
              style: TextStyle(color: AppColors.muted),
            ),
            if (unavailableCount > 0) ...[
              const SizedBox(height: 12),
              Text(
                'Alguns eventos salvos não estão mais disponíveis. Seus registros foram preservados.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ],
            const SizedBox(height: 12),
            for (final event in publicEvents)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AgendaEventTile(
                  event: event,
                  uid: _currentUid,
                  reminderService: widget.reminderService,
                  onReminderChanged: widget.onReminderChanged,
                  onOpen: widget.onOpen == null
                      ? null
                      : () => widget.onOpen!(event),
                  onRemove: () => _remove(event),
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _status(
    BuildContext context, {
    required IconData icon,
    required String message,
    String? detail,
    Widget? action,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: AppColors.sky),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    ),
  );

  bool _isVisibleEvent(Map<String, dynamic> data) {
    if (data['published'] != true || data['active'] != true) return false;
    if (data.containsKey('deletedAt') ||
        (data.containsKey('deleted') && data['deleted'] != false)) {
      return false;
    }
    if (!data.containsKey('expiresAt')) return true;
    final expiry = data['expiresAt'];
    return expiry is Timestamp && expiry.toDate().isAfter(DateTime.now());
  }
}

class _AgendaEventTile extends StatelessWidget {
  const _AgendaEventTile({
    required this.event,
    required this.onRemove,
    required this.uid,
    required this.reminderService,
    required this.onReminderChanged,
    this.onOpen,
  });

  final PublicEvent event;
  final VoidCallback onRemove;
  final String? uid;
  final EventReminderService? reminderService;
  final VoidCallback? onReminderChanged;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final start = dateInBrasilia(event.eventDate);
    final end = eventEndDateInBrasilia({
      'endDate': event.endDate,
    }, start ?? currentBrasiliaDateTime());
    final ended =
        start != null &&
        hasEventEndedInBrasilia(
          start: start,
          end: end,
          endTime: event.endTime,
          now: currentBrasiliaDateTime(),
        );
    final time = [
      if (event.startTime.isNotEmpty) event.startTime,
      if (event.endTime.isNotEmpty) 'até ${event.endTime}',
    ].join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _eventCover(event.imageUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (event.eventDate.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${event.eventDate}${event.endDate.isEmpty || event.endDate == event.eventDate ? '' : ' – ${event.endDate}'}',
                        style: const TextStyle(color: AppColors.ocean),
                      ),
                    ],
                    if (time.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(time),
                    ],
                    if (event.category.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        event.category,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                    if (uid != null) ...[
                      const SizedBox(height: 2),
                      EventReminderControl(
                        uid: uid!,
                        event: event,
                        service: reminderService,
                        onChanged: onReminderChanged,
                      ),
                    ],
                    if (ended) ...[
                      const SizedBox(height: 6),
                      const Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text('Encerrado'),
                        avatar: Icon(Icons.history_rounded, size: 16),
                      ),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 4,
                        children: [
                          TextButton.icon(
                            onPressed: onRemove,
                            icon: const Icon(Icons.event_busy_outlined),
                            label: const Text('Remover'),
                          ),
                          if (onOpen != null)
                            TextButton.icon(
                              onPressed: onOpen,
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: const Text('Detalhes'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _eventCover(String url) {
    final parsed = Uri.tryParse(url);
    final safeUrl =
        parsed != null &&
            parsed.scheme == 'https' &&
            parsed.host.isNotEmpty &&
            parsed.userInfo.isEmpty
        ? url
        : '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 76,
        height: 76,
        child: safeUrl.isEmpty
            ? const ColoredBox(
                color: AppColors.mist,
                child: Icon(Icons.event_rounded, color: AppColors.ocean),
              )
            : Image.network(
                safeUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: AppColors.mist,
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
      ),
    );
  }
}
