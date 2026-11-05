import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../models/public_event.dart';
import '../services/event_reminder_service.dart';
import '../widgets/event_reminder_control.dart';

typedef ReminderEventsStreamFactory = Stream<List<PublicEvent>> Function();

class EventReminderSettingsView extends StatefulWidget {
  const EventReminderSettingsView({
    super.key,
    required this.uid,
    this.savedEventIds = const {},
    this.savedEventIdsProvider,
    required this.eventsStreamFactory,
    this.service,
    this.onChanged,
    this.onOpenInbox,
    this.accountUidStreamFactory,
  });

  final String uid;
  final Set<String> savedEventIds;
  final Set<String> Function()? savedEventIdsProvider;
  final ReminderEventsStreamFactory eventsStreamFactory;
  final EventReminderService? service;
  final VoidCallback? onChanged;
  final VoidCallback? onOpenInbox;
  final Stream<String?> Function()? accountUidStreamFactory;

  @override
  State<EventReminderSettingsView> createState() =>
      _EventReminderSettingsViewState();
}

class _EventReminderSettingsViewState extends State<EventReminderSettingsView>
    with WidgetsBindingObserver {
  late final EventReminderService _service;
  StreamSubscription<List<PublicEvent>>? _eventsSubscription;
  StreamSubscription<String?>? _accountSubscription;
  Future<void>? _pendingReconcile;
  List<PublicEvent>? _events;
  List<EventReminderSetting> _settings = const [];
  bool _enabled = true;
  bool _permissionEnabled = false;
  bool _loading = true;
  bool _busy = false;
  bool _accountChanged = false;
  Object? _loadError;
  Object? _eventsError;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? EventReminderService.instance;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_reload());
    _eventsSubscription = widget.eventsStreamFactory().listen(
      _handleEvents,
      onError: (Object error) {
        if (mounted) setState(() => _eventsError = error);
      },
    );
    _accountSubscription = widget.accountUidStreamFactory?.call().listen((uid) {
      if (uid == widget.uid || !mounted) return;
      setState(() {
        _accountChanged = true;
        _settings = const [];
        _events = const [];
      });
      unawaited(() async {
        await _pendingReconcile;
        await _service.pauseUser(widget.uid);
      }());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reload());
      if (_events != null && _enabled) unawaited(_reconcile(_events!));
    }
  }

  Future<void> _handleEvents(List<PublicEvent> events) async {
    if (!mounted || _accountChanged) return;
    setState(() {
      _events = events;
      _eventsError = null;
    });
    await _reconcile(events);
    await _reload();
  }

  Future<void> _reconcile(List<PublicEvent> events) async {
    if (_accountChanged) return;
    final previous = _pendingReconcile?.catchError((Object _) {});
    final operation = (previous ?? Future<void>.value()).then((_) async {
      if (_accountChanged) return;
      await _service.reconcile(
        uid: widget.uid,
        savedEventIds:
            widget.savedEventIdsProvider?.call() ?? widget.savedEventIds,
        publicEvents: events,
      );
    });
    _pendingReconcile = operation;
    try {
      await operation;
    } catch (_) {
      if (mounted) setState(() => _eventsError = StateError('reconcile'));
    } finally {
      if (identical(_pendingReconcile, operation)) _pendingReconcile = null;
    }
  }

  Future<void> _reload() async {
    try {
      final values = await Future.wait<Object>([
        _service.remindersEnabled(widget.uid),
        _service.notificationsEnabled(),
        _service.reminderSettings(widget.uid),
      ]);
      if (!mounted) return;
      setState(() {
        _enabled = values[0] as bool;
        _permissionEnabled = values[1] as bool;
        _settings = values[2] as List<EventReminderSetting>;
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  Future<void> _toggle(bool enabled) async {
    if (_accountChanged) return;
    setState(() => _busy = true);
    try {
      await _service.setRemindersEnabled(widget.uid, enabled);
      if (enabled && _events != null) await _reconcile(_events!);
      await _reload();
      widget.onChanged?.call();
    } catch (_) {
      _message('Não foi possível atualizar sua preferência. Tente novamente.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSystemSettings() async {
    if (_accountChanged) return;
    setState(() => _busy = true);
    try {
      final opened = await _service.openNotificationSettings();
      if (!opened) {
        _message('Não foi possível abrir as configurações do aparelho.');
      }
    } catch (_) {
      _message('Não foi possível abrir as configurações do aparelho.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(String eventId) async {
    if (_accountChanged) return;
    setState(() => _busy = true);
    try {
      await _service.cancel(widget.uid, eventId);
      await _reload();
      widget.onChanged?.call();
    } catch (_) {
      await _reload();
      _message('O cancelamento ficará pendente até o aparelho confirmar.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  String _scheduledTime(DateTime utc) {
    final brasilia = utc.toUtc().subtract(const Duration(hours: 3));
    final day = brasilia.day.toString().padLeft(2, '0');
    final month = brasilia.month.toString().padLeft(2, '0');
    final hour = brasilia.hour.toString().padLeft(2, '0');
    final minute = brasilia.minute.toString().padLeft(2, '0');
    return '$day/$month/${brasilia.year} às $hour:$minute (Brasília)';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_eventsSubscription?.cancel());
    unawaited(_accountSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eventsById = {
      for (final event in _events ?? const <PublicEvent>[]) event.id: event,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Notificações')),
      body: SafeArea(
        child: _accountChanged
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xxl),
                  child: Text(
                    'Sua sessão mudou. Volte à Minha Conta para abrir as preferências da conta atual.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? _loadFailure()
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.md,
                  AppSpacing.page,
                  AppSpacing.xxl,
                ),
                children: [
                  Card(
                    child: SwitchListTile.adaptive(
                      key: const Key('event-reminders-global-toggle'),
                      value: _enabled,
                      onChanged: _busy || !_service.supported ? null : _toggle,
                      secondary: const Icon(
                        Icons.event_available_outlined,
                        color: AppColors.ocean,
                      ),
                      title: const Text('Lembretes de eventos'),
                      subtitle: const Text(
                        'Avisos locais dos eventos salvos em Minha Agenda. Desativar não remove seus eventos salvos.',
                      ),
                    ),
                  ),
                  if (!_service.supported)
                    _notice(
                      Icons.phone_android_rounded,
                      'Lembretes locais não estão disponíveis neste aparelho.',
                    )
                  else if (!_permissionEnabled)
                    Card(
                      key: const Key('event-reminder-permission-warning'),
                      color: AppColors.soft,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Permissão de notificações desativada',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            const Text(
                              'Ative as notificações nas configurações do aparelho para receber os avisos. O aplicativo continuará funcionando normalmente.',
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                key: const Key(
                                  'event-reminder-open-system-settings',
                                ),
                                onPressed: _busy ? null : _openSystemSettings,
                                icon: const Icon(Icons.settings_outlined),
                                label: const Text('Abrir configurações'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_eventsError != null)
                    _notice(
                      Icons.cloud_off_outlined,
                      'Não foi possível atualizar a disponibilidade dos eventos. As configurações locais foram preservadas.',
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Seus lembretes',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_settings.isEmpty)
                    _notice(
                      Icons.notifications_none_rounded,
                      'Você ainda não configurou lembretes. Adicione um evento à Minha Agenda para ativar um aviso.',
                    )
                  else
                    for (final setting in _settings)
                      _reminderCard(setting, eventsById[setting.eventId]),
                  if (widget.onOpenInbox != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    OutlinedButton.icon(
                      key: const Key('event-reminder-open-inbox'),
                      onPressed: widget.onOpenInbox,
                      icon: const Icon(Icons.inbox_outlined),
                      label: const Text('Avisos do aplicativo'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _reminderCard(EventReminderSetting setting, PublicEvent? event) {
    final title = event?.title ?? setting.title;
    final pendingText = setting.removalPending
        ? 'Cancelamento pendente'
        : setting.cancellationPending
        ? 'Reconciliação do alarme pendente'
        : !_enabled || setting.paused
        ? 'Pausado'
        : !_permissionEnabled
        ? 'Permissão de notificações desativada'
        : 'Aviso previsto para ${_scheduledTime(setting.triggerAtUtc)}';
    return Card(
      key: Key('event-reminder-${setting.eventId}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: AppColors.mist,
                child: Icon(Icons.event_rounded, color: AppColors.ocean),
              ),
              title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${setting.lead.label} · $pendingText'),
              trailing: event == null || setting.removalPending
                  ? IconButton(
                      tooltip: 'Cancelar lembrete',
                      onPressed: _busy ? null : () => _cancel(setting.eventId),
                      icon: const Icon(Icons.notifications_off_outlined),
                    )
                  : null,
            ),
            if (event != null && !setting.removalPending)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs),
                child: EventReminderControl(
                  uid: widget.uid,
                  event: event,
                  service: _service,
                  onChanged: () {
                    unawaited(_reload());
                    widget.onChanged?.call();
                  },
                ),
              ),
            if (event == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xs,
                  0,
                  AppSpacing.xs,
                  AppSpacing.sm,
                ),
                child: Text(
                  setting.removalPending
                      ? 'O aviso será removido assim que o aparelho confirmar o cancelamento.'
                      : 'Este evento não está mais disponível na agenda pública.',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _notice(IconData icon, String message) => Card(
    color: AppColors.soft,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.ocean),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );

  Widget _loadFailure() => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 42,
            color: AppColors.orange,
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('Não foi possível carregar suas preferências.'),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    ),
  );
}
