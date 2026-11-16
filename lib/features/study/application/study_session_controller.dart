import 'package:flutter/foundation.dart';

import '../data/study_repository.dart';
import '../data/calendar_scheduler.dart';
import '../domain/scheduler.dart';
import '../domain/study_card.dart';
import '../../settings/domain/study_settings.dart';

/// Owns only presentation/session state. All persisted changes are delegated
/// to repository transactions, which also protect against other sessions.
class StudySessionController extends ChangeNotifier {
  StudySessionController(
    StudyRepository repository, {
    this.deckId,
    this.loadSettings,
  }) : _baseRepository = repository;
  final StudyRepository _baseRepository;
  final Future<StudySettings> Function()? loadSettings;
  StudyRepository? _sessionRepository;
  StudyRepository get repository => _sessionRepository ?? _baseRepository;
  final int? deckId;
  final _responseClock = Stopwatch();
  bool _disposed = false;
  bool _busy = false;
  bool _started = false;
  bool _answerVisible = false;
  int _completedReviews = 0;
  int _presentationRevision = 0;
  StudyCard? _current;
  ReviewReceipt? _lastReview;
  Map<ReviewRating, Duration> _previewIntervals = const {};
  Map<ReviewRating, String> _previewLabels = const {};
  DateTime? _previewCalendarDay;
  String? _error;

  bool get busy => _busy;
  StudyCard? get current => _current;
  bool get answerVisible => _answerVisible;
  bool get canUndo => _lastReview != null && !_busy;
  bool get isComplete =>
      _started && !_busy && _current == null && _error == null;
  int get completedReviews => _completedReviews;
  int get presentationRevision => _presentationRevision;
  Map<ReviewRating, Duration> get previewIntervals => _previewIntervals;
  Map<ReviewRating, String> get previewLabels => _previewLabels;
  String? get error => _error;

  Future<void> start() async {
    if (_busy || _disposed) return;
    _busy = true;
    _error = null;
    _notify();
    try {
      if (_sessionRepository == null) {
        final load = loadSettings;
        _sessionRepository = load == null
            ? _baseRepository
            : _baseRepository.withSettings(await load());
        if (_disposed) return;
      }
      await _loadNext();
      _started = true;
    } catch (error) {
      _error = _message(error, '学习队列载入失败，请重试。');
    } finally {
      _busy = false;
      _notify();
    }
  }

  void showAnswer() {
    if (_busy || _disposed || _current == null || _answerVisible) return;
    try {
      _updatePreview();
      _answerVisible = true;
      _error = null;
    } catch (error) {
      _error = _message(error, '排程预览失败，请检查卡片或系统时间。');
    }
    _notify();
  }

  void _updatePreview() {
    final now = repository.nowUtc;
    _previewIntervals = repository.scheduler.previewIntervals(
      _current!.card,
      reviewedAtUtc: now,
    );
    if (repository.scheduler case CalendarScheduler calendar) {
      _previewLabels = calendar.previewLabels(now);
      _previewCalendarDay = calendar.dayAt(now);
    }
  }

  void pauseForEditing() => _responseClock.stop();

  Future<void> refreshAfterEditing() async {
    final current = _current;
    if (_busy || _disposed || current == null) return;
    _busy = true;
    _error = null;
    _notify();
    try {
      final updated = await repository.getStudyCard(current.card.id);
      if (!_disposed) _setCurrent(updated);
    } on StateError catch (error) {
      if (error.message == '卡片不存在') {
        await _loadNext();
      } else {
        _error = error.message;
      }
    } catch (_) {
      _error = '修改后读取卡片失败，请重新载入。';
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> rate(ReviewRating rating) async {
    final item = _current;
    if (_busy || _disposed || !_answerVisible || item == null) return;
    _busy = true;
    _error = null;
    _notify();
    var committed = false;
    try {
      if (repository.scheduler case CalendarScheduler calendar) {
        if (_previewCalendarDay != calendar.dayAt(repository.nowUtc)) {
          _updatePreview();
          _error = '已跨过午夜，复习日期已更新，请查看后再次评分。';
          return;
        }
      }
      final receipt = await repository.rateCard(
        item.card,
        rating,
        elapsed: _responseClock.elapsed,
        expectedCalendarDay: _previewCalendarDay,
      );
      committed = true;
      _lastReview = receipt;
      _completedReviews++;
      _setCurrent(null);
      if (!_disposed) await _loadNext();
    } catch (error) {
      if (!committed) {
        if (repository.scheduler case CalendarScheduler calendar) {
          if (_previewCalendarDay != calendar.dayAt(repository.nowUtc)) {
            try {
              _updatePreview();
            } catch (_) {
              /* Preserve the scoring error. */
            }
          }
        }
      }
      _error = committed
          ? '评分已保存，但下一张卡片载入失败，请重新载入。'
          : _message(error, '评分未保存，请重试。');
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> undo() async {
    final receipt = _lastReview;
    if (_busy || _disposed || receipt == null) return;
    _busy = true;
    _error = null;
    _notify();
    var restored = false;
    try {
      final card = await repository.undoReview(receipt.logId);
      restored = true;
      _lastReview = null;
      _completedReviews--;
      _setCurrent(null);
      if (!_disposed) _setCurrent(await repository.getStudyCard(card.id));
    } catch (error) {
      _error = restored
          ? '评分已撤销，但卡片载入失败，请重新载入。'
          : _message(error, '撤销未完成，请重试。');
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> toggleFavorite() async {
    final item = _current;
    if (_busy || _disposed || item == null) return;
    _busy = true;
    _error = null;
    _notify();
    try {
      await repository.setFavorite(item.card.id, !item.card.isFavorite);
      if (!_disposed) _current = await repository.getStudyCard(item.card.id);
    } catch (error) {
      _error = _message(error, '收藏状态更新失败，请重新载入。');
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> _loadNext() async {
    final queue = await repository.loadQueue(deckId: deckId);
    if (_disposed) return;
    _setCurrent(
      queue.isEmpty ? null : await repository.getStudyCard(queue.first.id),
    );
  }

  void _setCurrent(StudyCard? item) {
    _presentationRevision++;
    _current = item;
    _answerVisible = false;
    _previewIntervals = const {};
    _previewLabels = const {};
    _previewCalendarDay = null;
    _responseClock.reset();
    if (item == null) {
      _responseClock.stop();
    } else {
      _responseClock.start();
    }
  }

  String _message(Object error, String fallback) => error is StateError
      ? error.message
      : error is ArgumentError
      ? '${error.message}'
      : fallback;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _responseClock.stop();
    super.dispose();
  }
}
