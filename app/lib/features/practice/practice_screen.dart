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
/// 연습하기: 낱말을 한 줄로, 줄을 벗어나면 톡톡. 점수를 말해 주고 다음 낱말로 넘어간다.
enum PracticeMode { learn, word }

/// 글씨를 쓰는 화면. 다 쓰고 왼쪽으로 밀거나 "다 썼어요"(Enter)를 누르면 판정한다.
///
/// 밀면 쓰기 칸이 손가락을 따라 왼쪽으로 움직이고 다음 작성란이 오른쪽에서 같이 딸려 온다.
/// 손을 떼면 쓴 글씨가 입력되어(점수 저장) 위쪽 동그라미가 채워지고, 다음 칸이 자리를 잡는다.
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

class _PracticeScreenState extends State<PracticeScreen> with SingleTickerProviderStateMixin {
  /// 판정에 쓰는 펜 색과 글씨 굵기
  static const _inkColor = Color(0xFF1A2A80);
  static const _guideColor = Color(0xFFC3CAE0);

  /// 칸과 칸 사이 간격 (밀 때 두 칸이 나란히 보인다)
  static const _gap = 12.0;

  late final HapticGuide _haptic = HapticGuide(widget.store.settings);

  /// 쓰기 칸이 옆으로 움직이는 값: 밀 때는 손가락을 따라가고, 넘길 때는 나가고, 못 넘길 때는 제자리로 돌아온다
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 240))
    ..addListener(_onAnim);
  double _cardDx = 0;
  double _animFrom = 0;
  double _animTo = 0;

  /// 칸이 나가는 중이라 새 입력을 받지 않는다
  bool _transitioning = false;

  /// 지금 긋는 획이 "밀기"로 보여서 칸이 손을 따라가는 중이다 (이 획은 글씨로 그리지 않는다)
  bool _dragging = false;

  int _index = 0;
  final List<List<Offset>> _strokes = [];

  /// 입력이 끝난 칸 (위쪽 동그라미가 채워진다)
  final Set<int> _done = {};

  Size _area = Size.zero;
  Size _guideSize = Size.zero;

  /// 글자별 보조선 지도. 지금 칸과 이웃 칸(앞뒤)을 미리 만들어 둔다 (밀 때 딸려 오는 칸에도 보조선이 보이게)
  final Map<String, GuideMap> _guides = {};
  final Set<String> _building = {};

  int? _pointer;
  Offset _strokeStart = Offset.zero;
  int _strokeStartMs = 0;
  double _pathLength = 0;

  int _failStreak = 0;
  PracticeVerdict? _verdict;

  PracticeItem get _item => widget.items[_index];
  bool get _learn => widget.mode == PracticeMode.learn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _announceItem(0, first: true);
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _haptic.dispose();
    super.dispose();
  }

  // --- 말하기 ----------------------------------------------------------------

  void _announceItem(int index, {bool first = false, String prefix = ''}) {
    final n = widget.items.length;
    final how = first ? ' 다 쓰면 화면 오른쪽에서 왼쪽으로 밀어 주세요. 다 썼어요 버튼도 있어요.' : '';
    Speech.announce(
      context,
      '$prefix${widget.title}, $n개 중 ${index + 1}번째. ${widget.items[index].speech}$how',
    );
  }

  // --- 보조선 지도 -----------------------------------------------------------

  String _keyOf(int i) => '${widget.items[i].text}|${_guideSize.width.round()}x${_guideSize.height.round()}';

  GuideMap? _guideAt(int i) => i < 0 || i >= widget.items.length ? null : _guides[_keyOf(i)];

  GuideMap? get _guide => _guideAt(_index);

  /// 칸 크기나 글자가 바뀌면 지도를 다시 만든다 (수십 ms). 지금 칸을 먼저, 이웃 칸은 이어서
  void _ensureGuides(Size size) {
    if (size.isEmpty) return;
    if (size != _guideSize) {
      _guideSize = size;
      _guides.clear();
      _building.clear();
    }
    for (final i in [_index, _index + 1, _index - 1]) {
      if (i < 0 || i >= widget.items.length) continue;
      final key = _keyOf(i);
      if (_guides.containsKey(key) || !_building.add(key)) continue;
      final text = widget.items[i].text;
      GlyphGuide.build(text: text, area: size, fontSize: GlyphGuide.fontSizeFor(text, size)).then(
        (guide) {
          _building.remove(key);
          if (!mounted || size != _guideSize) return;
          setState(() => _guides[key] = guide);
        },
        onError: (_) => _building.remove(key),
      );
    }
  }

  // --- 칸 움직임 -------------------------------------------------------------

  void _onAnim() {
    if (!mounted) return;
    final t = Curves.easeOutCubic.transform(_anim.value);
    setState(() => _cardDx = _animFrom + (_animTo - _animFrom) * t);
  }

  Future<void> _animateCard(double from, double to) {
    _animFrom = from;
    _animTo = to;
    return _anim.forward(from: 0).orCancel.then((_) {}, onError: (_) {});
  }

  /// 칸이 손을 놓은 자리에서 제자리로 돌아온다
  void _springBack() {
    if (_cardDx != 0) _animateCard(_cardDx, 0);
  }

  /// 칸이 [dir]쪽(1이면 왼쪽으로 나가며 다음 칸이 들어옴, -1이면 반대)으로 나간 뒤 [commit]으로 칸을 바꾼다.
  /// 이웃 칸이 이미 옆에 딸려 와 있어서, 바뀐 뒤의 모습이 끊김 없이 이어진다
  Future<void> _slideTo(int dir, VoidCallback commit) async {
    if (_transitioning) return;
    _transitioning = true;
    _haptic.stop();
    await _animateCard(_cardDx, -dir * (_area.width + _gap));
    if (!mounted) return;
    commit();
    _transitioning = false;
  }

  // --- 쓰기 ------------------------------------------------------------------

  Offset _clamp(Offset p) => Offset(
        p.dx.clamp(0, _area.width).toDouble(),
        p.dy.clamp(0, _area.height).toDouble(),
      );

  void _down(PointerDownEvent e) {
    if (_pointer != null || _transitioning || _guide == null) return;
    _anim.stop();
    _pointer = e.pointer;
    _strokeStart = e.localPosition;
    _strokeStartMs = e.timeStamp.inMilliseconds;
    _pathLength = 0;
    setState(() {
      _cardDx = 0;
      _dragging = false;
      _strokes.add([_clamp(e.localPosition)]);
      _verdict = null;
    });
    final guide = _guide!;
    if (_learn) _haptic.start(guide.distanceAt(_clamp(e.localPosition)) / guide.glyphSize);
  }

  void _moveTo(PointerMoveEvent e) {
    if (e.pointer != _pointer || _strokes.isEmpty) return;
    _pathLength += e.delta.distance;
    final d = e.localPosition - _strokeStart;
    // 오른쪽에서 시작해 왼쪽으로 거의 수평으로 끌면 "밀기"로 본다: 칸이 손을 따라가고 이 획은 글씨로 그리지 않는다
    final sliding = _strokeStart.dx >= _area.width * 0.65 && d.dx < -24 && d.dy.abs() <= d.dx.abs() * 0.5;
    setState(() {
      _strokes.last.add(_clamp(e.localPosition));
      _dragging = sliding;
      _cardDx = sliding ? math.max(d.dx, -_area.width) : 0;
    });
    if (sliding) {
      _haptic.stop();
    } else {
      _feel(e.localPosition);
    }
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
    // 오른쪽 35% 안에서 시작해 너비의 35% 넘게 왼쪽으로, 거의 수평으로 곧게 = 밀어서 넘기기.
    // 칸을 손가락으로 끄는 동작이라 천천히 밀어도 된다 (0.9초까지)
    final fling = _strokeStart.dx >= _area.width * 0.65 &&
        d.dx <= -_area.width * 0.35 &&
        d.dy.abs() <= d.dx.abs() * 0.35 &&
        ms <= 900 &&
        _pathLength <= d.distance * 1.3;
    setState(() {
      _dragging = false;
      if (fling) _strokes.removeLast();
    });
    if (fling) {
      Haptics.slide();
      _submit();
    } else {
      _springBack();
    }
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _haptic.stop();
    setState(() => _dragging = false);
    _springBack();
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

  // --- 판정과 입력 -----------------------------------------------------------

  /// 쓴 글씨를 판정한다. 넘어갈 수 있으면 글씨가 입력되고(점수 저장, 동그라미 채움) 다음 칸으로 나간다.
  /// 다시 써야 하면 칸이 제자리로 돌아온다
  void _submit() {
    if (_transitioning) return;
    if (_strokes.isEmpty) {
      Haptics.warn();
      Speech.announce(context, '아직 쓰지 않았어요. 보조선을 따라 써 주세요.');
      _springBack();
      return;
    }
    final guide = _guide;
    if (guide == null) {
      Speech.announce(context, '보조선을 준비하고 있어요. 잠시 뒤에 다시 해 주세요.');
      _springBack();
      return;
    }

    final report = StrokeMetrics.measure(_strokes, guide);
    final verdict = PracticeJudge.judge(report, label: _item.spokenName, lenient: !_learn);
    widget.store.record(_item, verdict.score);
    final message = '${PracticeJudge.scoreSentence(verdict.score)} ${verdict.message}';
    final last = _index == widget.items.length - 1;

    // 학습하기는 통과해야 넘어가고, 연습하기는 점수만 주고 늘 넘어간다
    final advance = _learn ? verdict.passed : true;
    var giveUp = false;
    if (_learn) {
      if (advance) {
        Haptics.ok();
        _failStreak = 0;
      } else {
        Haptics.warn();
        _failStreak++;
        giveUp = _failStreak >= 3 && !last;
      }
    } else if (verdict.score >= 60) {
      Haptics.ok();
    } else {
      Haptics.warn();
    }

    if (advance) setState(() => _done.add(_index));

    if ((advance || giveUp) && !last) {
      _announceItem(_index + 1, prefix: '$message ${giveUp ? '이번 글자는 넘어갈게요. ' : ''}');
      _slideTo(1, () => _moveIndex(1, keep: verdict));
      return;
    }

    // 못 넘어가는 경우: 마지막 칸이거나 다시 써야 한다. 글씨는 입력(또는 지움)하고 칸은 제자리로
    setState(() {
      _verdict = verdict;
      _strokes.clear();
    });
    _springBack();
    if (advance && last) {
      Speech.announce(context, '$message ${widget.title}을 모두 마쳤어요. 나의 점수판에서 확인해 보세요.');
    } else {
      Speech.announce(context, '$message 다시 써 보세요.');
    }
  }

  // --- 넘기기 ----------------------------------------------------------------

  /// 이전/다음 버튼: 판정 없이 칸만 넘긴다
  void _step(int delta) {
    if (_transitioning) return;
    final next = _index + delta;
    if (next < 0) {
      Speech.announce(context, '첫 번째예요.');
      return;
    }
    if (next >= widget.items.length) {
      Speech.announce(context, '마지막이에요. 뒤로 가서 다른 것을 골라 보세요.');
      return;
    }
    _announceItem(next);
    _slideTo(delta, () => _moveIndex(delta));
  }

  void _moveIndex(int delta, {PracticeVerdict? keep}) {
    _haptic.stop();
    _failStreak = 0;
    setState(() {
      _index += delta;
      _strokes.clear();
      _dragging = false;
      _verdict = keep;
      _cardDx = 0;
    });
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
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Text(
                '${_index + 1} / ${widget.items.length}  ·  ${_item.spokenName}',
                style: text.titleMedium,
              ),
            ),
            _dots(),
            const SizedBox(height: 8),
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

  /// 칸 수만큼의 동그라미. 입력이 끝난 칸은 채워지고, 지금 칸은 테두리가 진하다
  Widget _dots() {
    return Semantics(
      label: '${widget.items.length}개 중 ${_done.length}개 입력했어요',
      excludeSemantics: true,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < widget.items.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _done.contains(i) ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: i == _index || _done.contains(i) ? AppColors.primary : AppColors.line,
                  width: i == _index ? 2.5 : 1.5,
                ),
              ),
            ),
        ],
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

  /// 쓰기 칸. 지금 칸이 [_cardDx]만큼 움직이고, 그 옆에 이웃 칸(밀면 다음 칸, 반대로 끌면 앞 칸)이 딸려 온다
  Widget _writingArea(TextTheme text) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _area = constraints.biggest;
        _ensureGuides(_area);
        final dir = _cardDx < 0 ? 1 : (_cardDx > 0 ? -1 : 0);
        final neighbor = _index + dir;
        final showNeighbor = dir != 0 && neighbor >= 0 && neighbor < widget.items.length;
        return Semantics(
          label: '${_item.spokenName} 쓰는 칸. 지금까지 ${_strokes.length}획.',
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _moveTo,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (showNeighbor)
                    Transform.translate(
                      offset: Offset(_cardDx + dir * (_area.width + _gap), 0),
                      child: _card(text, neighbor, strokes: const []),
                    ),
                  Transform.translate(
                    offset: Offset(_cardDx, 0),
                    child: _card(text, _index, strokes: _strokes, hideLast: _dragging),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _card(TextTheme text, int index, {required List<List<Offset>> strokes, bool hideLast = false}) {
    final item = widget.items[index];
    final guide = _guideAt(index);
    return Container(
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
              strokes: strokes,
              hideLast: hideLast,
              guide: guide,
              text: item.text,
              fontSize: GlyphGuide.fontSizeFor(item.text, _area),
              showGuide: !widget.store.settings.hideGuide,
              line: !_learn,
            ),
          ),
          if (guide == null) Center(child: Text('보조선을 준비하고 있어요', style: text.bodyMedium)),
        ],
      ),
    );
  }
}

class _PracticePainter extends CustomPainter {
  _PracticePainter({
    required this.strokes,
    required this.hideLast,
    required this.guide,
    required this.text,
    required this.fontSize,
    required this.showGuide,
    required this.line,
  });

  final List<List<Offset>> strokes;

  /// 밀기로 보이는 마지막 획은 그리지 않는다
  final bool hideLast;
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
    final count = hideLast ? strokes.length - 1 : strokes.length;
    for (var s = 0; s < count; s++) {
      final stroke = strokes[s];
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
