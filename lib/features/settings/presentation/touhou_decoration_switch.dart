import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/feedback/feedback_controller.dart';
import '../../../core/widgets/page_frame.dart';

class TouhouDecorationSwitch extends ConsumerStatefulWidget {
  const TouhouDecorationSwitch({super.key});

  @override
  ConsumerState<TouhouDecorationSwitch> createState() =>
      _TouhouDecorationSwitchState();
}

class _TouhouDecorationSwitchState
    extends ConsumerState<TouhouDecorationSwitch> {
  bool _saving = false;

  Future<void> _save(bool enabled) async {
    if (_saving) return;
    setState(() => _saving = true);
    unawaited(FeedbackScope.of(context).tap());
    try {
      await saveSetting(ref, 'touhouDecorations', '$enabled');
    } catch (error) {
      if (mounted) showActionError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    return SwitchListTile.adaptive(
      title: const Text('东方主题装饰'),
      subtitle: const Text('寺子屋、迷途竹林与永远亭等小题签'),
      value: settings?['touhouDecorations'] != 'false',
      onChanged: settings == null || _saving ? null : _save,
    );
  }
}
