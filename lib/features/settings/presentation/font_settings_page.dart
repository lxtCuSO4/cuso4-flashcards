import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/content/card_content.dart';
import '../../../core/feedback/feedback_controller.dart';
import '../../../core/media/local_audio_controller.dart';
import '../../../core/typography/font_scale_scope.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/pressable_action.dart';
import '../../../core/widgets/touhou_tag.dart';
import '../domain/font_settings.dart';

class FontSettingsPage extends ConsumerStatefulWidget {
  const FontSettingsPage({super.key});
  @override
  ConsumerState<FontSettingsPage> createState() => _FontSettingsPageState();
}

class _FontSettingsPageState extends ConsumerState<FontSettingsPage> {
  FontSettings? _draft;
  bool _saving = false;
  late final LocalAudioController _audio;

  @override
  void initState() {
    super.initState();
    _audio = LocalAudioController(ref.read(mediaRepositoryProvider));
  }

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  Future<void> _save(FontSettings value) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(fontSettingsRepositoryProvider).save(value);
      if (!mounted) return;
      setState(() => _draft = value);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('字号设置已保存')));
    } catch (error) {
      if (mounted) showActionError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return PageFrame(
      title: '字体大小',
      header: const TouhouTag(TouhouPlace.eientei),
      subtitle: '拖动滑块实时预览，点击保存后应用。100% 保持系统字号。',
      child: settings.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => Column(
          children: [
            const Text('字号设置暂时无法读取。'),
            TextButton(
              onPressed: () => ref.invalidate(settingsProvider),
              child: const Text('重新读取设置'),
            ),
          ],
        ),
        data: (values) {
          final value =
              _draft ?? FontSettings.decode(values[FontSettings.settingKey]);
          final system = FontScaleScope.systemOf(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '界面文字：${value.uiPercent}%',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('菜单、按钮和页面说明；80%–150%。'),
              Slider(
                key: const ValueKey('ui-font-slider'),
                min: FontSettings.minUi.toDouble(),
                max: FontSettings.maxUi.toDouble(),
                divisions: 14,
                value: value.uiPercent.toDouble(),
                label: '${value.uiPercent}%',
                semanticFormatterCallback: (percent) =>
                    '界面字号 ${percent.round()}%',
                onChangeEnd: (_) => unawaited(FeedbackScope.of(context).tap()),
                onChanged: _saving
                    ? null
                    : (percent) => setState(
                        () => _draft = FontSettings(
                          uiPercent: percent.round(),
                          cardPercent: value.cardPercent,
                        ),
                      ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    '界面预览：菜单、按钮与说明文字。',
                    textScaler: applyFontPercent(system, value.uiPercent),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                '卡片阅读：${value.cardPercent}%',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('题干、选项、答案和解析正文；80%–200%，与界面字号独立。'),
              Slider(
                key: const ValueKey('card-font-slider'),
                min: FontSettings.minCard.toDouble(),
                max: FontSettings.maxCard.toDouble(),
                divisions: 24,
                value: value.cardPercent.toDouble(),
                label: '${value.cardPercent}%',
                semanticFormatterCallback: (percent) =>
                    '阅读字号 ${percent.round()}%',
                onChangeEnd: (_) => unawaited(FeedbackScope.of(context).tap()),
                onChanged: _saving
                    ? null
                    : (percent) => setState(
                        () => _draft = FontSettings(
                          uiPercent: value.uiPercent,
                          cardPercent: percent.round(),
                        ),
                      ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: FontScaleScope(
                    system: system,
                    cardPercent: value.cardPercent,
                    child: CardContent(
                      source: '卡片预览：题干、选项与解析会使用这一字号。',
                      media: ref.read(mediaRepositoryProvider),
                      audio: _audio,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('图片及图片里的文字不受字号设置影响。设置保存在本机，并包含在本地完整备份中。'),
              const SizedBox(height: 24),
              PressableAction(
                label: '保存字号',
                onPressed: _saving ? null : () => _save(value),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _saving
                    ? null
                    : () {
                        unawaited(FeedbackScope.of(context).tap());
                        setState(() => _draft = FontSettings());
                      },
                child: const Text('恢复默认'),
              ),
              const SizedBox(height: 8),
              const Text('恢复默认会将两项预览调整为 100%，点击保存后生效。'),
            ],
          );
        },
      ),
    );
  }
}
