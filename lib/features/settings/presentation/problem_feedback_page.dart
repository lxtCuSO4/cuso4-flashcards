import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/pressable_action.dart';
import '../../../core/widgets/touhou_tag.dart';

class ProblemFeedbackPage extends StatefulWidget {
  const ProblemFeedbackPage({super.key});

  @override
  State<ProblemFeedbackPage> createState() => _ProblemFeedbackPageState();
}

class _ProblemFeedbackPageState extends State<ProblemFeedbackPage> {
  static const _recipient = 'lixingtong035@163.com';
  static const _channel = MethodChannel(
    'com.cuso4.flashcards/problem_feedback',
  );
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _details = TextEditingController();
  final _contact = TextEditingController();
  final _titleFocus = FocusNode();
  final _detailsFocus = FocusNode();
  String _category = '问题';
  String? _status;
  bool _busy = false;
  bool _leaving = false;
  bool _confirming = false;

  bool get _hasContent =>
      [_title, _details, _contact].any((c) => c.text.isNotEmpty);
  String get _subject => '[Lunar Memory · $_category] ${_title.text.trim()}';
  String get _body =>
      '反馈类型：$_category\n标题：${_title.text.trim()}\n\n${_details.text.trim()}\n\n联系方式：${_contact.text.trim().isEmpty ? '未填写' : _contact.text.trim()}\n\n来自 Lunar Memory 1.0.0+1';

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    _contact.dispose();
    _titleFocus.dispose();
    _detailsFocus.dispose();
    super.dispose();
  }

  bool _validate() {
    if (_form.currentState!.validate()) return true;
    final target = _title.text.trim().isEmpty ? _titleFocus : _detailsFocus;
    target.requestFocus();
    return false;
  }

  Future<void> _openEmail() async {
    if (_busy || !_validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    var opened = false;
    try {
      opened =
          await _channel.invokeMethod<bool>('openEmail', {
            'subject': _subject,
            'body': _body,
          }) ??
          false;
    } catch (_) {
      // A missing or unavailable mail app always leaves a copyable draft.
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = opened ? '请在邮件应用中确认发送，当前表单已保留。' : '未能打开邮件应用。可以复制反馈，稍后自行发送。';
        });
      }
    }
  }

  Future<void> _copy() async {
    if (!_validate()) return;
    try {
      await Clipboard.setData(
        ClipboardData(text: '收件人：$_recipient\n主题：$_subject\n\n$_body'),
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已复制反馈内容和收件邮箱')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _status = '复制失败，请重试，或手动复制表单文字。');
      }
    }
  }

  Future<void> _confirmLeave() async {
    if (_confirming || _busy) return;
    _confirming = true;
    final leave = await confirmRemoval(
      context,
      '离开后当前表单会清空。若尚未发送，请先复制保存。',
      title: '离开反馈页面？',
      confirmLabel: '离开',
    );
    _confirming = false;
    if (!leave || !mounted) return;
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && (!_hasContent || _leaving),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _confirmLeave();
    },
    child: PageFrame(
      title: '问题反馈',
      header: const TouhouTag(TouhouPlace.eientei),
      subtitle: '把遇到的问题或想法寄到永远亭。',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SelectableText('收件邮箱：$_recipient'),
            const SizedBox(height: 12),
            const Text(
              '填写可离线完成。提交会打开手机邮件应用，请在那里确认发送；邮件应用联网后才能投递。未安装邮件应用时，可复制内容自行发送。',
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: '反馈类型'),
              items: [
                for (final label in ['问题', '建议', '其他'])
                  DropdownMenuItem(value: label, child: Text(label)),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _category = value!),
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const ValueKey('feedback-title'),
              controller: _title,
              focusNode: _titleFocus,
              enabled: !_busy,
              maxLength: 120,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '标题',
                hintText: '用一句话描述',
                errorMaxLines: 3,
              ),
              onChanged: (_) => setState(() => _status = null),
              validator: (v) => v == null || v.trim().isEmpty ? '请填写标题' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('feedback-details'),
              controller: _details,
              focusNode: _detailsFocus,
              enabled: !_busy,
              minLines: 5,
              maxLines: 12,
              maxLength: 6000,
              decoration: const InputDecoration(
                labelText: '反馈详情',
                hintText: '问题如何出现？你期待什么结果？\n可主动补充手机型号、Android 版本。',
                alignLabelWithHint: true,
                errorMaxLines: 3,
              ),
              onChanged: (_) => setState(() => _status = null),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '请填写反馈详情' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _contact,
              enabled: !_busy,
              maxLength: 150,
              decoration: const InputDecoration(labelText: '联系方式（可选）'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            const Text('只发送你在表单里填写的文字，不会自动附带牌组、图片或学习记录。离开页面后表单会清空。'),
            const SizedBox(height: 24),
            PressableAction(
              label: '打开邮件应用',
              onPressed: _busy ? null : _openEmail,
            ),
            const SizedBox(height: 12),
            PressableAction(label: '复制反馈内容', onPressed: _busy ? null : _copy),
            if (_status != null) ...[
              const SizedBox(height: 16),
              Semantics(liveRegion: true, child: SelectableText(_status!)),
            ],
          ],
        ),
      ),
    ),
  );
}
