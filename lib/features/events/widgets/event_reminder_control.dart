import 'package:flutter/material.dart';

import '../models/public_event.dart';
import '../services/event_reminder_service.dart';

class EventReminderControl extends StatefulWidget {
  const EventReminderControl({
    super.key,
    required this.uid,
    required this.event,
    this.service,
    this.now,
    this.onChanged,
  });

  final String uid;
  final PublicEvent event;
  final EventReminderService? service;
  final DateTime? now;
  final VoidCallback? onChanged;

  @override
  State<EventReminderControl> createState() => _EventReminderControlState();
}

class _EventReminderControlState extends State<EventReminderControl> {
  late EventReminderService _service;
  EventReminderLead? _lead;
  bool _loading = true;
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? EventReminderService.instance;
    _load();
  }

  @override
  void didUpdateWidget(covariant EventReminderControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.event.id != widget.event.id ||
        oldWidget.event.startTime != widget.event.startTime ||
        oldWidget.event.eventDate != widget.event.eventDate ||
        oldWidget.service != widget.service) {
      _service = widget.service ?? EventReminderService.instance;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final lead = await _service.leadFor(widget.uid, widget.event.id);
    if (!mounted) return;
    setState(() {
      _lead = lead;
      _loading = false;
    });
  }

  Future<void> _chooseReminder() async {
    final lead = await showDialog<EventReminderLead>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ativar lembrete'),
        content: const Text('Quando você quer receber o aviso?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Agora não'),
          ),
          for (final option in EventReminderLead.values)
            TextButton(
              onPressed:
                  eventReminderAtUtc(widget.event, option, now: widget.now) ==
                      null
                  ? null
                  : () => Navigator.pop(dialogContext, option),
              child: Text(option.label),
            ),
        ],
      ),
    );
    if (lead == null || !mounted) return;
    setState(() => _pending = true);
    final result = await _service.activate(
      uid: widget.uid,
      event: widget.event,
      lead: lead,
      now: widget.now,
    );
    if (!mounted) return;
    setState(() {
      _pending = false;
      if (result == EventReminderResult.scheduled ||
          result == EventReminderResult.disabledGlobally) {
        _lead = lead;
      }
    });
    // Also notify the owner after a failed native request: it may have left a
    // cancellation pending, which the public-event watcher can retry.
    widget.onChanged?.call();
    if (result != EventReminderResult.scheduled) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_messageFor(result))));
    }
  }

  Future<void> _cancel() async {
    setState(() => _pending = true);
    try {
      await _service.cancel(widget.uid, widget.event.id);
      if (mounted) {
        setState(() => _lead = null);
        widget.onChanged?.call();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível cancelar o lembrete.'),
          ),
        );
        widget.onChanged?.call();
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  String _messageFor(EventReminderResult result) => switch (result) {
    EventReminderResult.disabledGlobally =>
      'Lembretes pausados. Você pode reativá-los em Minha Conta → Notificações.',
    EventReminderResult.permissionDenied =>
      'Permita notificações nas configurações do Android para receber lembretes.',
    EventReminderResult.timePassed =>
      'O horário escolhido para o lembrete já passou.',
    EventReminderResult.invalidEventTime =>
      'Este evento ainda não tem um horário de início válido.',
    EventReminderResult.unsupportedPlatform =>
      'Lembretes locais estão disponíveis no Android.',
    EventReminderResult.failed =>
      'Não foi possível ativar o lembrete neste aparelho.',
    EventReminderResult.scheduled => '',
  };

  @override
  Widget build(BuildContext context) {
    if (!_service.supported || widget.uid.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    if (_loading || _pending) {
      return const SizedBox(
        height: 36,
        width: 36,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_lead == null) {
      return TextButton.icon(
        key: const Key('event-reminder-enable'),
        onPressed: _chooseReminder,
        icon: const Icon(Icons.notifications_active_outlined),
        label: const Text('Ativar lembrete'),
      );
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      children: [
        TextButton.icon(
          onPressed: _chooseReminder,
          icon: const Icon(Icons.notifications_active_rounded),
          label: Text('Lembrete: ${_lead!.label}'),
        ),
        IconButton(
          tooltip: 'Cancelar lembrete',
          onPressed: _cancel,
          icon: const Icon(Icons.notifications_off_outlined),
        ),
      ],
    );
  }
}
