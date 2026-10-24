import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/fill.dart';
import '../../models/workspace_state.dart';
import '../../services/download.dart';
import '../../services/haptics.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../output/signed_pdf.dart';
import '../sign/signature_check.dart';
import '../write/note_ink.dart';
import 'fill_targets.dart';

/// 쓰고 서명하기 화면. 칸 하나마다 화면 전체가 쓰기 칸이 된다.
///
/// 넘기기는 두 가지다:
///   1. 아래의 큰 "다음" 버튼 (마우스·키보드 Enter·스크린리더 사용자)
///   2. 쓰기 칸 오른쪽 끝에서 왼쪽으로 빠르고 길게 쓸기. 글씨 획과 헷갈리지 않게
///      오른쪽 45% 안에서 시작해 칸 너비의 40% 넘게, 거의 수평으로, 0.5초 안에 곧게 그은 것만 넘기기로 본다.
///      이렇게 그은 획은 글씨에 넣지 않는다.
/// 넘기기 전에 [SignatureCheck]로 숫자 검사만 한다 (비었는지, 너무 작은지, 너무 빠른지. AI 판단 없음).
/// 통과하면 쓴 글씨가 문서 사진의 그 칸 자리로 줄어들며 들어가고(0.6초), 다음 칸이 나온다.
class FillScreen extends StatefulWidget {
  const FillScreen({super.key, required this.state, required this.targets, this.start = 0});

  final WorkspaceState state;
  final List<FillTarget> targets;

  /// 처음 쓸 칸 (targets 안의 순서)
  final int start;

  @override
  State<FillScreen> createState() => _FillScreenState();
}

enum _Phase { writing, placing, done }

class _FillScreenState extends State<FillScreen> with SingleTickerProviderStateMixin {
  late int _index = widget.start.clamp(0, widget.targets.length - 1);
  _Phase _phase = _Phase.writing;

  final List<List<PenPoint>> _strokes = [];
  List<List<PenPoint>>? _beforeClear;

  /// 넣지 않고 다른 칸으로 옮겨 간 글씨. 돌아오면 이어 쓴다 (화면을 못 봐도 쓴 것을 잃지 않게)
  final Map<int, List<List<PenPoint>>> _drafts = {};
  String? _message;
  bool _busy = false;
  bool _exported = false;

  Size _area = Size.zero;

  // 쓸기 판정
  int? _pointer;
  Offset _strokeStart = Offset.zero;
  int _strokeStartMs = 0;
  double _pathLength = 0;

  // 넣기 움직임
  late final AnimationController _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  List<List<PenPoint>> _flying = const [];
  Rect _flyingBounds = Rect.zero;
  Rect _from = Rect.zero, _to = Rect.zero, _targetOnScreen = Rect.zero, _pageOnScreen = Rect.zero;

  /// 이 화면에서 처음 통과한 서명. 다음 서명은 이것과 비교한다 (글씨 칸과는 비교하지 않는다)
  static SignatureMetrics? _signatureBaseline;

  List<FillTarget> get _targets => widget.targets;
  FillTarget get _target => _targets[_index];
  bool get _filled => widget.state.fills.containsKey(_target.id);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _precache();
      Speech.announce(context, _intro(first: true));
    });
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  String _intro({bool first = false}) {
    final t = _target;
    final head = first ? '${josa(t.label, '을', '를')} 쓰세요. ' : '다음은 ${josa(t.label, '이에요', '예요')}. ';
    final filled = _filled ? '이미 채운 칸이에요. 새로 쓰면 바뀌고, 그냥 다음을 누르면 그대로 둬요. ' : '';
    final how = first ? '화면 가득 크게 쓰고, 다 쓰면 아래 다음 버튼을 누르거나 오른쪽 끝에서 왼쪽으로 빠르게 미세요.' : '';
    return '$head$filled$how';
  }

  /// 넣을 때 문서 사진이 바로 보이게 미리 읽어 둔다
  void _precache() {
    precacheImage(_photo(_target.page), context).ignore();
  }

  ImageProvider _photo(int page) => ResizeImage(MemoryImage(widget.state.pages[page].bytes), width: 1600);

  // --- 쓰기 ------------------------------------------------------------------

  PenPoint _point(PointerEvent e) {
    // 칸 밖으로 끌려 나간 점은 칸 가장자리로 (검사기의 "칸 벗어남"은 여기선 해당 없다)
    final p = Offset(e.localPosition.dx.clamp(0, _area.width), e.localPosition.dy.clamp(0, _area.height));
    return PenPoint(p, e.timeStamp.inMilliseconds, e.pressure);
  }

  void _down(PointerDownEvent e) {
    if (_phase != _Phase.writing || _busy || _pointer != null) return;
    _pointer = e.pointer;
    _strokeStart = e.localPosition;
    _strokeStartMs = e.timeStamp.inMilliseconds;
    _pathLength = 0;
    setState(() {
      _strokes.add([_point(e)]);
      _beforeClear = null;
      _message = null;
    });
  }

  void _moveTo(PointerMoveEvent e) {
    if (e.pointer != _pointer || _strokes.isEmpty) return;
    _pathLength += e.delta.distance;
    setState(() => _strokes.last.add(_point(e)));
  }

  void _up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final d = e.localPosition - _strokeStart;
    final ms = e.timeStamp.inMilliseconds - _strokeStartMs;
    final fling = _strokeStart.dx >= _area.width * 0.55 &&
        d.dx <= -_area.width * 0.4 &&
        d.dy.abs() <= d.dx.abs() * 0.35 &&
        ms <= 500 &&
        _pathLength <= d.distance * 1.3;
    if (fling) {
      setState(() => _strokes.removeLast());
      _next();
    }
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer == _pointer) _pointer = null;
  }

  void _undo() {
    if (_phase != _Phase.writing || _busy) return;
    if (_strokes.isNotEmpty) {
      setState(() => _strokes.removeLast());
      Speech.announce(context, '마지막 획을 지웠어요. 남은 획 ${_strokes.length}개.');
    } else if (_beforeClear != null) {
      setState(() {
        _strokes.addAll(_beforeClear!);
        _beforeClear = null;
      });
      Speech.announce(context, '지운 글씨를 되살렸어요.');
    } else {
      Haptics.warn();
      Speech.announce(context, '되돌릴 획이 없어요.');
    }
  }

  void _clear() {
    if (_phase != _Phase.writing || _busy) return;
    if (_strokes.isEmpty) {
      Speech.announce(context, '지울 글씨가 없어요.');
      return;
    }
    setState(() {
      _beforeClear = List.of(_strokes);
      _strokes.clear();
      _message = null;
    });
    Speech.announce(context, '지웠어요. 다시 쓰세요. 되돌리기를 누르면 되살아나요.');
  }

  // --- 넘기기 ----------------------------------------------------------------

  /// 숫자 검사. 칸 = 쓰기 칸 전체라 "칸 벗어남"은 일어나지 않는다
  SignatureVerdict _check() {
    final guide = Offset.zero & _area;
    final saved = SignatureCheck.baseline;
    SignatureCheck.baseline = _target.isSignature ? _signatureBaseline : null;
    try {
      return SignatureCheck.judge(_strokes, guide);
    } finally {
      SignatureCheck.baseline = saved;
    }
  }

  /// 검사기 문구는 서명용이라 글씨 칸이면 말을 바꾼다
  String _problem(SignatureVerdict v) {
    if (_target.isSignature) return v.message;
    final m = v.metrics;
    if (m.strokeCount == 0) return '아직 쓰지 않았어요. 화면 가득 크게 써 주세요.';
    if (m.areaRatio < SignatureCheck.minAreaRatio) return '글씨가 너무 작아요. 화면을 더 크게 채워서 다시 써 주세요.';
    if (m.durationMs < SignatureCheck.minDurationMs) return '너무 빨리 썼어요. 천천히 다시 써 주세요.';
    return v.message;
  }

  Future<void> _next() async {
    if (_phase != _Phase.writing || _busy) return;
    final target = _target;
    if (_strokes.isEmpty && _filled) {
      _advance();
      return;
    }
    final verdict = _check();
    if (!verdict.ok) {
      final message = _problem(verdict);
      setState(() => _message = message);
      Haptics.warn();
      Speech.announce(context, message);
      return;
    }
    Haptics.ok();
    if (target.isSignature) _signatureBaseline ??= verdict.metrics;

    final bounds = _FillInk.bounds(_strokes);
    setState(() => _busy = true);
    final Uint8List png;
    try {
      png = await _FillInk.toPng(_strokes, bounds);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      Haptics.warn();
      Speech.announce(context, '글씨를 저장하지 못했어요. 다시 눌러 주세요.');
      return;
    }
    if (!mounted) return;
    widget.state.setFill(FilledInk(target: target, png: png));
    _drafts.remove(_index);

    final page = _pageSize(target.page);
    if (page != null) {
      _pageOnScreen = _fitPage(page, _area);
      _targetOnScreen = _mapBox(target, page, _pageOnScreen);
      _from = bounds;
      _to = _fitInk(bounds.size, _targetOnScreen, target.isSignature);
      setState(() {
        _flying = List.of(_strokes);
        _flyingBounds = bounds;
        _strokes.clear();
        _phase = _Phase.placing;
      });
      await _move.forward(from: 0);
      // 들어간 자리를 잠깐 보여 준다 (저시력 사용자)
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
    }
    _advance();
  }

  /// 다음 빈 칸으로. 뒤에 없으면 앞쪽 빈 칸으로, 모두 찼으면 끝
  void _advance() {
    final filled = widget.state.fills.keys.toSet();
    final n = _targets.length;
    int? next;
    for (var k = 1; k < n; k++) {
      final i = (_index + k) % n;
      if (!filled.contains(_targets[i].id)) {
        next = i;
        break;
      }
    }
    if (next == null) {
      setState(() {
        _phase = _Phase.done;
        _busy = false;
        _strokes.clear();
      });
      Speech.announce(context, '모두 채웠어요. PDF로 받을 수 있어요.');
      return;
    }
    _goTo(next);
  }

  void _goTo(int index, {bool back = false}) {
    if (_phase == _Phase.writing && _strokes.isNotEmpty) _drafts[_index] = List.of(_strokes);
    setState(() {
      _index = index;
      _phase = _Phase.writing;
      _busy = false;
      _message = null;
      _beforeClear = null;
      _strokes
        ..clear()
        ..addAll(_drafts[index] ?? const []);
    });
    _precache();
    final filled = _filled ? ' 이미 채운 칸이에요. 새로 쓰면 바뀌어요.' : '';
    Speech.announce(context, back ? '이전 칸, ${josa(_target.label, '이에요', '예요')}.$filled' : _intro());
  }

  void _previous() {
    if (_busy) return;
    if (_phase == _Phase.done) {
      _goTo(_targets.length - 1, back: true);
      return;
    }
    if (_index == 0) {
      Speech.announce(context, '첫 번째 칸이에요.');
      return;
    }
    _goTo(_index - 1, back: true);
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await exportFilledPdf(context, widget.state, _targets);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _exported = _exported || ok;
    });
  }

  Size? _pageSize(int page) {
    final s = NoteInk.pageSize(widget.state.recognized, page);
    return s == null ? null : Size(s.width.toDouble(), s.height.toDouble());
  }

  // --- 화면 ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = _phase == _Phase.done;
    final title = done ? '모두 채웠어요' : '${_target.label} (${_index + 1}/${_targets.length})';
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): done ? _export : _next,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(_exported),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppColors.surface,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: '닫기',
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => Navigator.of(context).pop(_exported),
                          ),
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(title, style: text.titleLarge?.copyWith(fontSize: 30), maxLines: 2),
                            ),
                          ),
                          IconButton(
                            tooltip: '다시 듣기',
                            icon: const Icon(Icons.volume_up_outlined),
                            onPressed: () => Speech.announce(
                              context,
                              done ? '모두 채웠어요. PDF로 받을 수 있어요.' : _intro(first: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(child: done ? _donePages() : _writingArea(text)),
                      if (_message != null && !done) ...[
                        const SizedBox(height: 8),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _message!,
                            textAlign: TextAlign.center,
                            style: text.bodyLarge?.copyWith(color: AppColors.caution),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      done ? _doneButtons() : _writingButtons(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _writingArea(TextTheme text) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _area = constraints.biggest;
        final target = _target;
        return Semantics(
          label: '${target.label} 쓰는 칸. 화면 가득 쓰세요. 다 쓰면 다음을 누르세요. 지금까지 ${_strokes.length}획.',
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
                  // 빈 칸이면 무엇을 쓸지 옅게 (저시력 사용자)
                  if (_strokes.isEmpty && _phase == _Phase.writing)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _filled ? '${target.label}\n이미 채웠어요' : '여기에 ${target.label}',
                          textAlign: TextAlign.center,
                          style: text.headlineMedium?.copyWith(color: AppColors.line, fontSize: 40),
                        ),
                      ),
                    ),
                  if (_phase == _Phase.placing) _placing(),
                  CustomPaint(painter: _InkPainter(_strokes, baseline: !target.isSignature)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 쓴 글씨가 문서 사진의 칸 자리로 줄어들며 들어간다
  Widget _placing() {
    final target = _target;
    final others = [
      for (final f in widget.state.fills.values)
        if (f.target.page == target.page && f.target.id != target.id) f,
    ];
    final page = _pageSize(target.page)!;
    return AnimatedBuilder(
      animation: _move,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_move.value);
        final fade = Curves.easeOut.transform((_move.value / 0.35).clamp(0.0, 1.0));
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fromRect(
              rect: _pageOnScreen,
              child: Opacity(
                opacity: fade,
                child: Image(image: _photo(target.page), fit: BoxFit.fill, gaplessPlayback: true),
              ),
            ),
            for (final f in others)
              Positioned.fromRect(
                rect: _mapBox(f.target, page, _pageOnScreen),
                child: Opacity(opacity: fade, child: _inkImage(f)),
              ),
            Positioned.fromRect(
              rect: _targetOnScreen.inflate(3),
              child: Opacity(
                opacity: fade * (1 - t * 0.6),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    border: Border.all(color: AppColors.primary, width: 2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
            CustomPaint(painter: _FlyingInkPainter(_flying, _flyingBounds, Rect.lerp(_from, _to, t)!)),
          ],
        );
      },
    );
  }

  /// 채운 칸이 있는 페이지마다 사진 + 글씨
  Widget _donePages() {
    final pages = {for (final t in _targets) t.page}.toList()..sort();
    final fills = widget.state.fills.values.toList();
    return ListView(
      children: [
        for (final p in pages)
          if (_pageSize(p) case final size?)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(
                image: true,
                label: '${p + 1}페이지. 채운 칸: ${fills.where((f) => f.target.page == p).map((f) => f.target.label).join(', ')}',
                child: AspectRatio(
                  aspectRatio: size.width / size.height,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final rect = Offset.zero & c.biggest;
                      return Stack(
                        children: [
                          Positioned.fill(child: Image(image: _photo(p), fit: BoxFit.fill, gaplessPlayback: true)),
                          for (final f in fills)
                            if (f.target.page == p)
                              Positioned.fromRect(rect: _mapBox(f.target, size, rect), child: _inkImage(f)),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _inkImage(FilledInk f) => Image.memory(
        f.png,
        fit: BoxFit.contain,
        alignment: f.target.isSignature ? Alignment.center : Alignment.centerLeft,
        gaplessPlayback: true,
      );

  Widget _writingButtons() {
    final enabled = _phase == _Phase.writing && !_busy;
    return SizedBox(
      height: 72,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _ToolButton(icon: Icons.chevron_left, label: '이전', onPressed: enabled ? _previous : null)),
          const SizedBox(width: 6),
          Expanded(child: _ToolButton(icon: Icons.undo, label: '되돌리기', onPressed: enabled ? _undo : null)),
          const SizedBox(width: 6),
          Expanded(child: _ToolButton(icon: Icons.refresh, label: '다시 쓰기', onPressed: enabled ? _clear : null)),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 72)),
              onPressed: enabled ? _next : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('다음'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _doneButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : _export,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(_busy ? 'PDF 만드는 중…' : '서명한 문서 PDF 받기'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _previous,
                icon: const Icon(Icons.chevron_left),
                label: const Text('고치기'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(_exported),
                icon: const Icon(Icons.close),
                label: const Text('닫기'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 채운 칸을 모두 넣은 PDF를 만들어 내려받고 결과를 들려준다. 성공하면 true
Future<bool> exportFilledPdf(BuildContext context, WorkspaceState state, List<FillTarget> targets) async {
  final document = state.recognized;
  if (document == null) return false;
  final order = {for (final (i, t) in targets.indexed) t.id: i};
  final fills = state.fills.values.toList()
    ..sort((a, b) => (order[a.target.id] ?? 1 << 30).compareTo(order[b.target.id] ?? 1 << 30));
  try {
    final pdf = await buildSignedPdf(pages: state.pages, document: document, signatures: const {}, fills: fills);
    downloadBytes(pdf, '들리는계약서_서명본.pdf');
  } catch (_) {
    Haptics.warn();
    if (context.mounted) Speech.announce(context, 'PDF를 만들지 못했어요. 다시 시도해 주세요.');
    return false;
  }
  Haptics.ok();
  final left = targets.where((t) => !state.fills.containsKey(t.id)).length;
  final warn = left == 0 ? '' : '아직 비어 있는 칸이 $left곳 있어요. ';
  if (context.mounted) Speech.announce(context, '$warn${describeFills(fills, state.pages.length)}');
  return true;
}

// --- 자리 계산 (화면과 PDF가 같은 방식: 사진은 페이지 상자에 꽉, 글씨는 칸 안에 contain) ---

Rect _fitPage(Size page, Size area) =>
    Alignment.center.inscribe(applyBoxFit(BoxFit.contain, page, area).destination, Offset.zero & area);

Rect _mapBox(FillTarget t, Size page, Rect pageRect) {
  final s = pageRect.width / page.width;
  final b = t.rect;
  return Rect.fromLTWH(pageRect.left + b.x * s, pageRect.top + b.y * s, b.width * s, b.height * s);
}

Rect _fitInk(Size ink, Rect target, bool signature) =>
    (signature ? Alignment.center : Alignment.centerLeft).inscribe(applyBoxFit(BoxFit.contain, ink, target.size).destination, target);

/// 패드 글씨: 가는 짙은 파랑 (필압 0.5에서 약 2.5px). 문서 칸에 줄여 넣어도 인쇄 글자와 굵기가 비슷하게
class _FillInk {
  _FillInk._();

  static const _maxWidth = 3.4;

  static double widthAt(PenPoint p) {
    final pressure = p.pressure <= 0 ? 0.5 : p.pressure.clamp(0.0, 1.0);
    return 1.6 + pressure * 1.8;
  }

  static void paint(Canvas canvas, List<List<PenPoint>> strokes) {
    final paint = Paint()
      ..color = NoteInk.color
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first.position, widthAt(stroke.first) / 2, paint);
        continue;
      }
      for (var i = 1; i < stroke.length; i++) {
        canvas.drawLine(stroke[i - 1].position, stroke[i].position, paint..strokeWidth = widthAt(stroke[i]));
      }
    }
  }

  /// 획을 감싸는 상자 + 굵기와 조금의 여백. PNG와 움직임이 같은 상자를 쓴다
  static Rect bounds(List<List<PenPoint>> strokes) {
    var left = double.infinity, top = double.infinity, right = -double.infinity, bottom = -double.infinity;
    for (final s in strokes) {
      for (final p in s) {
        left = math.min(left, p.position.dx);
        top = math.min(top, p.position.dy);
        right = math.max(right, p.position.dx);
        bottom = math.max(bottom, p.position.dy);
      }
    }
    return Rect.fromLTRB(left, top, right, bottom).inflate(_maxWidth + 6);
  }

  /// 획만 잘라낸 투명 배경 PNG. 칸에 줄여 넣어도 흐리지 않게 2배로 그린다
  static Future<Uint8List> toPng(List<List<PenPoint>> strokes, Rect bounds, {double pixelRatio = 2}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(pixelRatio)
      ..translate(-bounds.left, -bounds.top);
    paint(canvas, strokes);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      math.max(1, (bounds.width * pixelRatio).round()),
      math.max(1, (bounds.height * pixelRatio).round()),
    );
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.strokes, {required this.baseline});

  final List<List<PenPoint>> strokes;

  /// 글씨 칸이면 옅은 밑줄을 그어 줄을 맞추기 쉽게
  final bool baseline;

  @override
  void paint(Canvas canvas, Size size) {
    if (baseline) {
      final y = size.height * 0.7;
      canvas.drawLine(
        Offset(size.width * 0.06, y),
        Offset(size.width * 0.94, y),
        Paint()
          ..color = AppColors.line
          ..strokeWidth = 2,
      );
    }
    _FillInk.paint(canvas, strokes);
  }

  @override
  bool shouldRepaint(_InkPainter old) => true;
}

/// 움직이는 글씨: [source] 상자의 획을 [dest] 상자로 옮겨 그린다. 줄어들면 굵기도 함께 줄어 자연스럽다
class _FlyingInkPainter extends CustomPainter {
  _FlyingInkPainter(this.strokes, this.source, this.dest);

  final List<List<PenPoint>> strokes;
  final Rect source, dest;

  @override
  void paint(Canvas canvas, Size size) {
    if (source.isEmpty) return;
    canvas.save();
    canvas.translate(dest.left, dest.top);
    canvas.scale(dest.width / source.width, dest.height / source.height);
    canvas.translate(-source.left, -source.top);
    _FillInk.paint(canvas, strokes);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlyingInkPainter old) => old.dest != dest || old.strokes != strokes;
}

/// 아이콘 위, 글자 아래의 작은 버튼. 네 개가 한 줄에 들어가도 72px 높이를 지킨다
class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 72), padding: const EdgeInsets.symmetric(horizontal: 4)),
      onPressed: onPressed,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon, size: 28), Text(label, style: const TextStyle(fontSize: 17))],
        ),
      ),
    );
  }
}
