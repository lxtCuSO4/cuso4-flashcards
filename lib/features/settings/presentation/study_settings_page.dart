import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/pressable_action.dart';
import '../domain/study_settings.dart';

class StudySettingsPage extends ConsumerStatefulWidget {
  const StudySettingsPage({super.key});

  @override
  ConsumerState<StudySettingsPage> createState() => _StudySettingsPageState();
}

class _StudySettingsPageState extends ConsumerState<StudySettingsPage> {
  final _form = GlobalKey<FormState>();
  final _fresh = TextEditingController();
  final _reviews = TextEditingController();
  final _retention = TextEditingController();
  final _freshFocus = FocusNode();
  final _reviewFocus = FocusNode();
  final _retentionFocus = FocusNode();
  final _advanced = ExpansibleController();
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _askingToLeave = false;
  bool _saved = false;
  String? _loadError;
  String? _saveError;
  StudySettings? _original;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final settings = await ref.read(studySettingsRepositoryProvider).load();
      if (!mounted) return;
      _original = settings;
      _fresh.text = '${settings.dailyNewLimit}';
      _reviews.text = '${settings.dailyReviewLimit}';
      _retention.text = '${settings.desiredRetentionPercent}';
    } catch (error) {
      if (!mounted) return;
      _loadError = error is StateError ? error.message : '学习设置读取失败，请重试。';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changed(String _) => setState(() {
    final original = _original!;
    _dirty =
        _fresh.text.trim() != '${original.dailyNewLimit}' ||
        _reviews.text.trim() != '${original.dailyReviewLimit}' ||
        _retention.text.trim() != '${original.desiredRetentionPercent}';
    _saved = false;
    _saveError = null;
  });

  String? _range(String? text, int min, int max) {
    final value = int.tryParse(text?.trim() ?? '');
    return value == null || value < min || value > max
        ? '请输入 $min–$max 的整数'
        : null;
  }

  Future<void> _save() async {
    if (_saving || _loading) return;
    if (!_form.currentState!.validate()) {
      if (_range(_fresh.text, 0, 9999) != null) {
        _freshFocus.requestFocus();
      } else if (_range(_reviews.text, 0, 99999) != null) {
        _reviewFocus.requestFocus();
      } else {
        _advanced.expand();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _retentionFocus.requestFocus();
        });
      }
      return;
    }
    final settings = StudySettings(
      dailyNewLimit: int.parse(_fresh.text.trim()),
      dailyReviewLimit: int.parse(_reviews.text.trim()),
      desiredRetentionPercent: int.parse(_retention.text.trim()),
    );
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _saveError = null;
      _saved = false;
    });
    try {
      await ref.read(studySettingsRepositoryProvider).save(settings);
      if (!mounted) return;
      setState(() {
        _original = settings;
        _fresh.text = '${settings.dailyNewLimit}';
        _reviews.text = '${settings.dailyReviewLimit}';
        _retention.text = '${settings.desiredRetentionPercent}';
        _dirty = false;
        _saved = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _saveError = '保存失败，输入已保留，请重试。');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discard() async {
    if (_saving || _askingToLeave) return;
    _askingToLeave = true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃修改？'),
        content: const Text('学习设置尚未保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    _askingToLeave = false;
    if (leave != true || !mounted) return;
    setState(() => _dirty = false);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _fresh.dispose();
    _reviews.dispose();
    _retention.dispose();
    _freshFocus.dispose();
    _reviewFocus.dispose();
    _retentionFocus.dispose();
    _advanced.dispose();
    super.dispose();
  }

  Widget _field({
    required TextEditingController controller,
    required FocusNode focus,
    required String label,
    required String help,
    required int min,
    required int max,
    String suffix = '张',
  }) => TextFormField(
    controller: controller,
    focusNode: focus,
    enabled: !_saving,
    keyboardType: TextInputType.number,
    textInputAction: TextInputAction.done,
    decoration: InputDecoration(
      labelText: label,
      helperText: help,
      helperMaxLines: 4,
      errorMaxLines: 3,
      suffixText: suffix,
    ),
    validator: (value) => _range(value, min, max),
    autovalidateMode: AutovalidateMode.onUserInteraction,
    onChanged: _changed,
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty && !_saving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_discard());
    },
    child: PageFrame(
      title: '学习设置',
      subtitle: '为每天留出合适的学习量。',
      child: _loading
          ? const LinearProgressIndicator(semanticsLabel: '正在读取学习设置')
          : _loadError != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_loadError!),
                const SizedBox(height: 16),
                PressableAction(label: '重新读取', onPressed: _load),
              ],
            )
          : Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '每日额度',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          const Text('每个牌组分别计算，章节之间不共用额度。'),
                          const SizedBox(height: 24),
                          _field(
                            controller: _fresh,
                            focus: _freshFocus,
                            label: '每日新卡数',
                            help: '0–9999，设为 0 暂停引入新卡。',
                            min: 0,
                            max: 9999,
                          ),
                          const SizedBox(height: 24),
                          _field(
                            controller: _reviews,
                            focus: _reviewFocus,
                            label: '每日复习上限',
                            help: '0–99999，设为 0 暂停到期复习卡。',
                            min: 0,
                            max: 99999,
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '学习中和重学中的卡片仍会按时出现。调低额度会计入今天已学的张数，撤销评分会归还额度。每天按首次学习时记录的时区，在零点更新额度。',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: ExpansionTile(
                      controller: _advanced,
                      title: const Text('FSRS 进阶设置'),
                      subtitle: Text(
                        '已保存的期望保持率：${_original!.desiredRetentionPercent}%',
                      ),
                      maintainState: true,
                      childrenPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      children: [
                        _field(
                          controller: _retention,
                          focus: _retentionFocus,
                          label: '期望保持率',
                          help: '70–99 的整数百分比。越高通常复习越频繁，建议从 90% 开始。',
                          min: 70,
                          max: 99,
                          suffix: '%',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '保存后，下次进入学习生效。不会重置进度，也不会立即改动已有卡片的到期日；新的保持率在之后的评分中使用。',
                  ),
                  const SizedBox(height: 24),
                  if (_saveError != null || _saved) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _saveError ?? '已保存，下次进入学习生效。',
                        style: TextStyle(
                          color: _saveError == null
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  PressableAction(
                    label: _saving ? '正在保存' : '保存学习设置',
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
    ),
  );
}
