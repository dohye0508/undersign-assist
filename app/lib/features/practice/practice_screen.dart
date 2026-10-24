import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/haptic_guide.dart';
import '../../services/haptics.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/tap_feedback.dart';
import 'feedback.dart';
import 'glyph_guide.dart';
import 'practice_frame.dart';
import 'practice_items.dart';
import 'score_store.dart';
import 'stroke_metrics.dart';

/// 학습하기: 한 글자씩, 보조선에 가까울수록 촘촘한 거리 진동. 통과해야 다음으로.
/// 연습하기: 낱말을 한 줄로, 줄을 벗어나면 톡톡. 점수만 주고 언제든 다음으로.
enum PracticeMode { learn, word }

/// 글씨를 쓰는 화면. 다 쓰고 왼쪽으로 밀거나 "다 썼어요"(Enter)를 누르면 판정한다
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({
    super.key,
    required this.title,
    required this.items,
    required this.mode,
    required this.store,
    required this.onExit,
  });

  final String title;
  final List<PracticeItem> items;
  final PracticeMode mode;
  final ScoreStore store;
  final VoidCallback onExit;

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  /// 판정에 쓰는 펜 색과 글씨 굵기
  static const _inkColor = Color(0xFF1A2A80);
  static const _guideColor = Color(0xFFC3CAE0);

  late final HapticGuide _haptic = HapticGuide(widget.store.settings);

  int _index = 0;
  final List<List<Offset>> _strokes = [];

  Size _area = Size.zero;
  GuideMap? _guide;
  String _guideKey = '';
  int _guideToken = 0;

  int? _pointer;
  Offset _strokeStart = Offset.zero;
  int _strokeStartMs = 0;
  double _pathLength = 0;

  /// 연습하기: 방금 점수를 말해 줬다. 이때 쓴 글씨는 지워 두고, 아무것도 안 쓴 채 밀면 다음 낱말로 간다
  bool _judged = false;
  int _failStreak = 0;
  PracticeVerdict? _verdict;

  PracticeItem get _item => widget.items[_index];
  bool get _learn => widget.mode == PracticeMode.learn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _announceItem(first: true);
    });
  }

  @override
  void dispose() {
    _haptic.dispose();
    super.dispose();
  }

  // --- 말하기 ----------------------------------------------------------------

  void _announceItem({bool first = false, String prefix = ''}) {
    final n = widget.items.length;
    final how = first ? ' 다 쓰면 화면 오른쪽에서 왼쪽으로 밀어 주세요. 다 썼어요 버튼도 있어요.' : '';
    Speech.announce(
      context,
      '$prefix${widget.title}, $n개 중 ${_index + 1}번째. ${_item.speech}$how',
    );
  }

  // --- 보조선 지도 -----------------------------------------------------------

  /// 칸 크기나 글자가 바뀌면 지도를 다시 만든다. 만드는 동안(수십 ms)은 쓸 수 없다
  void _ensureGuide(Size size) {
    if (size.isEmpty) return;
    final key = '${_item.text}|${size.width.round()}x${size.height.round()}';
    if (key == _guideKey) return;
    _guideKey = key;
    _guide = null;
    final token = ++_guideToken;
    final text = _item.text;
    GlyphGuide.build(text: text, area: size, fontSize: GlyphGuide.fontSizeFor(text, size)).then((guide) {
      if (!mounted || token != _guideToken) return;
      setState(() => _guide = guide);
    });
  }

  // --- 쓰기 ------------------------------------------------------------------

  Offset _clamp(Offset p) => Offset(
        p.dx.clamp(0, _area.width).toDouble(),
        p.dy.clamp(0, _area.height).toDouble(),
      );

  void _down(PointerDownEvent e) {
    if (_pointer != null || _guide == null) return;
    _pointer = e.pointer;
    _strokeStart = e.localPosition;
    _strokeStartMs = e.timeStamp.inMilliseconds;
    _pathLength = 0;
    setState(() {
      _strokes.add([_clamp(e.localPosition)]);
      _judged = false;
      _verdict = null;
    });
    final guide = _guide!;
    if (_learn) _haptic.start(guide.distanceAt(_clamp(e.localPosition)) / guide.glyphSize);
  }

  void _moveTo(PointerMoveEvent e) {
    if (e.pointer != _pointer || _strokes.isEmpty) return;
    _pathLength += e.delta.distance;
    setState(() => _strokes.last.add(_clamp(e.localPosition)));
    _feel(e.localPosition);
  }

  /// 쓰는 동안의 진동 안내
  void _feel(Offset raw) {
    final guide = _guide;
    if (guide == null) return;
    final outside = raw.dx < 0 || raw.dy < 0 || raw.dx > _area.width || raw.dy > _area.height;
    if (outside) _haptic.outside();
    if (_learn) {
      _haptic.update(guide.distanceAt(_clamp(raw)) / guide.glyphSize);
    } else if (!outside) {
      final band = _lineBand(guide);
      if (raw.dy < band.top || raw.dy > band.bottom) _haptic.offLine();
    }
  }

  /// 연습하기의 "줄": 보조 낱말이 놓인 가로 띠 (글씨 높이의 25%만큼 여유)
  Rect _lineBand(GuideMap guide) {
    final ink = guide.inkBounds;
    return Rect.fromLTRB(0, ink.top - ink.height * 0.25, _area.width, ink.bottom + ink.height * 0.25);
  }

  void _up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _haptic.stop();
    final d = e.localPosition - _strokeStart;
    final ms = e.timeStamp.inMilliseconds - _strokeStartMs;
    // 오른쪽 35% 안에서 시작해 너비의 35% 넘게 왼쪽으로, 거의 수평·빠르게·곧게 = 밀어서 넘기기
    final fling = _strokeStart.dx >= _area.width * 0.65 &&
        d.dx <= -_area.width * 0.35 &&
        d.dy.abs() <= d.dx.abs() * 0.35 &&
        ms <= 500 &&
        _pathLength <= d.distance * 1.3;
    if (fling) {
      setState(() => _strokes.removeLast());
      Haptics.slide();
      _submit();
    }
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _haptic.stop();
  }

  void _undoStroke() {
    if (_strokes.isEmpty) {
      Speech.announce(context, '지울 획이 없어요.');
      return;
    }
    setState(() => _strokes.removeLast());
    Speech.announce(context, '마지막 획을 지웠어요. 남은 획 ${_strokes.length}개.');
  }

  void _clearAll() {
    if (_strokes.isEmpty) return;
    setState(_strokes.clear);
    Speech.announce(context, '모두 지웠어요. 처음부터 다시 써 보세요.');
  }

  // --- 판정 ------------------------------------------------------------------

  void _submit() {
    if (_strokes.isEmpty) {
      if (!_learn && _judged) {
        _step(1);
        return;
      }
      Haptics.warn();
      Speech.announce(context, '아직 쓰지 않았어요. 보조선을 따라 써 주세요.');
      return;
    }
    final guide = _guide;
    if (guide == null) {
      Speech.announce(context, '보조선을 준비하고 있어요. 잠시 뒤에 다시 해 주세요.');
      return;
    }

    final report = StrokeMetrics.measure(_strokes, guide);
    final verdict = PracticeJudge.judge(report, label: _item.spokenName, lenient: !_learn);
    widget.store.record(_item, verdict.score);
    final score = PracticeJudge.scoreSentence(verdict.score);

    if (_learn) {
      if (verdict.passed) {
        Haptics.ok();
        _failStreak = 0;
        final last = _index == widget.items.length - 1;
        setState(() {
          _verdict = verdict;
          _strokes.clear();
        });
        if (last) {
          Speech.announce(context, '$score ${verdict.message} ${widget.title}을 모두 마쳤어요. 나의 점수판에서 확인해 보세요.');
        } else {
          _moveIndex(1, prefix: '$score ${verdict.message} ');
        }
      } else {
        Haptics.warn();
        _failStreak++;
        setState(() {
          _verdict = verdict;
          _strokes.clear();
        });
        if (_failStreak >= 3 && _index < widget.items.length - 1) {
          _failStreak = 0;
          _moveIndex(1, prefix: '$score ${verdict.message} 이번 글자는 넘어갈게요. ');
        } else {
          Speech.announce(context, '$score ${verdict.message} 다시 써 보세요.');
        }
      }
      return;
    }

    // 연습하기: 점수만 주고, 같은 낱말을 다시 쓰거나 밀어서 다음으로 갈 수 있다
    if (verdict.score >= 60) {
      Haptics.ok();
    } else {
      Haptics.warn();
    }
    setState(() {
      _verdict = verdict;
      _judged = true;
      _strokes.clear();
    });
    Speech.announce(context, '$score ${verdict.message} 같은 낱말을 다시 쓰거나, 왼쪽으로 밀어 다음 낱말로 가세요.');
  }

  // --- 넘기기 ----------------------------------------------------------------

  void _step(int delta) {
    final next = _index + delta;
    if (next < 0) {
      Speech.announce(context, '첫 번째예요.');
      return;
    }
    if (next >= widget.items.length) {
      Speech.announce(context, '마지막이에요. 뒤로 가서 다른 것을 골라 보세요.');
      return;
    }
    _moveIndex(delta);
  }

  void _moveIndex(int delta, {String prefix = ''}) {
    _haptic.stop();
    setState(() {
      _index += delta;
      _strokes.clear();
      _judged = false;
      _verdict = null;
      _guide = null;
      _guideKey = '';
    });
    _announceItem(prefix: prefix);
  }

  // --- 화면 ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PracticeFrame(
      title: widget.title,
      onBack: widget.onExit,
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.enter): _submit,
        const SingleActivator(LogicalKeyboardKey.backspace): _undoStroke,
        const SingleActivator(LogicalKeyboardKey.delete): _clearAll,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(1),
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                '${_index + 1} / ${widget.items.length}  ·  ${_item.spokenName}',
                style: text.titleMedium,
              ),
            ),
            Expanded(child: _writingArea(text)),
            const SizedBox(height: 8),
            _resultStrip(text),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _button('이전 글자', Icons.chevron_left, () => _step(-1))),
                const SizedBox(width: 8),
                Expanded(child: _button('다음 글자', Icons.chevron_right, () => _step(1))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _button('지우기', Icons.backspace_outlined, _undoStroke)),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: TapFeedback.wrap(_submit),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 64)),
                    icon: const Icon(Icons.check),
                    label: const Text('다 썼어요'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(String label, IconData icon, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: TapFeedback.wrap(onPressed),
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 64), padding: const EdgeInsets.symmetric(horizontal: 8)),
      icon: Icon(icon),
      label: Text(label),
    );
  }

  Widget _resultStrip(TextTheme text) {
    final verdict = _verdict;
    return Semantics(
      liveRegion: true,
      child: Container(
        height: 56,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: verdict == null
              ? AppColors.primarySoft
              : (verdict.passed ? AppColors.okSoft : AppColors.missingSoft),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          verdict == null
              ? (_learn ? '보조선을 따라 쓰세요' : '보조선 줄에 맞춰 한 줄로 쓰세요')
              : '${verdict.score}점  ${verdict.message}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: text.bodyLarge,
        ),
      ),
    );
  }

  Widget _writingArea(TextTheme text) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _area = constraints.biggest;
        _ensureGuide(_area);
        final guide = _guide;
        return Semantics(
          label: '${_item.spokenName} 쓰는 칸. 지금까지 ${_strokes.length}획.',
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _moveTo,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.line, width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _PracticePainter(
                      strokes: _strokes,
                      guide: guide,
                      text: _item.text,
                      fontSize: GlyphGuide.fontSizeFor(_item.text, _area),
                      showGuide: !widget.store.settings.hideGuide,
                      line: !_learn,
                    ),
                  ),
                  if (guide == null)
                    Center(child: Text('보조선을 준비하고 있어요', style: text.bodyMedium)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PracticePainter extends CustomPainter {
  _PracticePainter({
    required this.strokes,
    required this.guide,
    required this.text,
    required this.fontSize,
    required this.showGuide,
    required this.line,
  });

  final List<List<Offset>> strokes;
  final GuideMap? guide;
  final String text;
  final double fontSize;
  final bool showGuide;

  /// 낱말 연습: 글씨 아래에 가로 줄을 긋는다
  final bool line;

  @override
  void paint(Canvas canvas, Size size) {
    final g = guide;
    if (g != null && showGuide) {
      GlyphGuide.paint(canvas, size, text, fontSize, _PracticeScreenState._guideColor);
    }
    if (g != null && line && showGuide) {
      final y = g.inkBounds.bottom + g.inkBounds.height * 0.08;
      canvas.drawLine(
        Offset(size.width * 0.06, y),
        Offset(size.width * 0.94, y),
        Paint()
          ..color = _PracticeScreenState._guideColor
          ..strokeWidth = 2,
      );
    }

    final paint = Paint()
      ..color = _PracticeScreenState._inkColor
      ..strokeWidth = math.max(4.0, size.shortestSide * 0.012)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PracticePainter oldDelegate) => true;
}
