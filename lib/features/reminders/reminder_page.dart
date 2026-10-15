import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/page_frame.dart';
import '../../core/widgets/pressable_action.dart';
import 'reminder_platform.dart';

class ReminderPage extends ConsumerStatefulWidget {
  const ReminderPage({super.key});
  @override
  ConsumerState<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends ConsumerState<ReminderPage>
    with WidgetsBindingObserver {
  ReminderSettings? _settings;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _load();
  }

  Future<void> _load() async {
    try {
      final value = await ref.read(reminderPlatformProvider).read();
      if (mounted) {
        setState(() {
          _settings = value;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '提醒设置读取失败，请重试。');
    }
  }

  Future<void> _save(bool enabled, TimeOfDay time) async {
    if (_busy) return;
    setState(() => _busy = true);
    final platform = ref.read(reminderPlatformProvider);
    try {
      if (enabled && !await platform.requestPermission()) {
        throw StateError('通知未获允许，请在系统通知设置中开启。');
      }
      final value = await platform.save(
        enabled: enabled,
        hour: time.hour,
        minute: time.minute,
      );
      if (mounted) setState(() => _settings = value);
    } catch (error) {
      if (mounted) showActionError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final time = TimeOfDay(
      hour: settings?.hour ?? 20,
      minute: settings?.minute ?? 0,
    );
    return PopScope(
      canPop: !_busy,
      child: PageFrame(
        title: '学习提醒',
        subtitle: '在本机每天提醒一次，无需网络。',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              PressableAction(label: _error!, onPressed: _load)
            else if (settings == null)
              const LinearProgressIndicator()
            else ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('每日学习提醒'),
                value: settings.enabled,
                onChanged: _busy ? null : (v) => _save(v, time),
              ),
              const SizedBox(height: 16),
              PressableAction(
                label: '提醒时间 · ${time.format(context)}',
                onPressed: _busy
                    ? null
                    : () async {
                        final chosen = await showTimePicker(
                          context: context,
                          initialTime: time,
                        );
                        if (chosen != null && mounted) {
                          await _save(settings.enabled, chosen);
                        }
                      },
              ),
              const SizedBox(height: 16),
              Text(
                settings.allowed ? '系统通知已允许' : '系统通知未允许；已设置的提醒可能无法显示。',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              PressableAction(
                label: '发送测试通知',
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          if (!await ref
                              .read(reminderPlatformProvider)
                              .requestPermission()) {
                            throw StateError('请先允许通知。');
                          }
                          await ref.read(reminderPlatformProvider).test();
                          await _load();
                        } catch (error) {
                          if (context.mounted) showActionError(context, error);
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        try {
                          await ref
                              .read(reminderPlatformProvider)
                              .openSettings();
                        } catch (error) {
                          if (context.mounted) showActionError(context, error);
                        }
                      },
                child: const Text('打开系统通知设置'),
              ),
              const SizedBox(height: 24),
              const Text(
                '提醒时间受系统省电和后台管理影响，可能延后。强行停止应用后，需再次打开才能恢复提醒。提醒设置属于本机通知偏好，不随牌组备份迁移。',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
