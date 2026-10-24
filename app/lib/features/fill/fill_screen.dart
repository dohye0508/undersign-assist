import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/fill.dart';
import '../../models/recognized_document.dart' show TextBlock;
import '../../models/workspace_state.dart';
import '../../services/download.dart';
import '../../services/haptics.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/tap_feedback.dart';
import '../output/signed_pdf.dart';
import '../sign/signature_check.dart';
import '../write/note_ink.dart';
import 'fill_kind.dart';
import 'fill_targets.dart';
import 'progress_dots.dart';

/// 쓰고 서명하기 화면. 칸 하나마다 화면 전체가 쓰기 칸이 된다.
///
/// 넘기기는 두 가지다:
///   1. 아래의 큰 "다음" 버튼 (마우스·키보드 Enter·스크린리더 사용자)
///   2. 쓰기 칸 오른쪽 끝에서 왼쪽으로 빠르고 길게 쓸기. 글씨 획과 헷갈리지 않게
///      오른쪽 35% 안에서 시작해 칸 너비의 35% 넘게, 거의 수평으로, 0.5초 안에 곧게 그은 것만 넘기기로 본다.
///      이렇게 그은 획은 글씨에 넣지 않는다. 밀기로 알아보는 순간 [Haptics.slide]를 낸다.
/// 넘기기 전에 [SignatureCheck]로 숫자 검사만 한다 (비었는지, 너무 작은지, 너무 빠른지. AI 판단 없음).
/// 통과하면 쓴 글씨가 문서 사진의 그 칸 자리로 줄어들며 들어가고(0.6초), 다음 칸이 나온다.
///
/// 고르는 칸([FillKind.check], "□예 □아니요")은 쓰는 대신 큰 "예"/"아니요" 버튼 둘을 보여 준다.
/// 고르면 그 상자 자리에 ✓를 그린 PNG를 만들어 글씨 칸과 똑같이 넣는다. PNG는 두 상자를 합친 칸과 같은 비율이고
/// 고른 상자 자리에만 ✓가 있어, 칸 자리만 아는 [FilledInk]로도 어느 쪽을 골랐는지 그대로 문서에 남는다.
///
/// ✓는 기계가 그리지 않고 **사용자가 딱 한 번 그린 것**([WorkspaceState.checkMark])을 쓴다.
/// 아직 없으면 처음 예/아니요를 고른 뒤 화면이 쓰기 칸으로 바뀌어 ✓를 한 번 그리게 하고, 그 뒤로는 저장해 둔 ✓를 그대로 넣는다.
class FillScreen extends StatefulWidget {
  const FillScreen({super.key, required this.state, required this.targets, this.start = 0, this.intro});

  final WorkspaceState state;
  final List<FillTarget> targets;

  /// 처음 쓸 칸 (targets 안의 순서)
  final int start;

  /// 열리자마자 첫 칸 안내 앞에 한 번 들려줄 말 (예: "써야 할 곳은 3곳이에요. …").
  /// 패널을 건너뛰고 바로 열릴 때 패널 대신 여기서 말한다
  final String? intro;

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

  /// 고르는 칸에서 이 화면에서 고른 답 (칸 순서 → 예면 true). 다시 돌아왔을 때 무엇을 골랐는지 말해 주려고 둔다
  final Map<int, bool> _choices = {};

  /// 다음 칸 안내 앞에 한 번 붙여 말할 것 (예: "예에 표시했어요.")
  String _pending = '';

  /// 고르는 칸에서 ✓를 처음 그리는 중인가. 이때는 고르는 칸도 쓰기 칸 모습이 된다
  bool _drawingCheck = false;

  /// ✓를 그리는 동안 기억해 둔 답 (그리기를 마치면 이 답의 상자에 넣는다)
  bool? _pendingChoice;

  static const _drawPrompt = '체크 표시를 한 번만 그려 주세요. 다음부터는 이 표시를 그대로 써요. 다 그리면 왼쪽으로 밀거나 다음을 누르세요.';

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
      final before = widget.intro;
      // 패널이 건너뛰고 열었으면 써야 할 곳 목록을 먼저, 그다음 첫 칸 안내
      Speech.announce(context, before == null || before.isEmpty ? _intro(first: true) : '$before ${_intro(first: true)}');
    });
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  /// 칸에 들어설 때 들려줄 말. 열릴 때와 넘어갈 때 모두 이걸 말한다.
  ///
  /// - 서명: "3페이지 중 2페이지, 보호자 서명을 시작합니다. 손가락으로 크게 쓰고 왼쪽으로 미세요."
  /// - 글씨: "2번째, 지원자 성명을 쓰세요."
  /// - 날짜: 연도·월·일이 따로 칸이다. "날짜의 연도를 적으세요" → 월 → 일 ([FillTargetKind.datePart])
  /// - 동의 여부: 물음 + "예는 1, 아니요는 2를 누르거나 위아래 버튼을 누르세요."
  /// 이미 채운 칸이면 그 사실을 덧붙인다. [first]면 글씨 칸에 쓰는 법을 한 번 더 설명한다
  String _intro({bool first = false}) {
    final t = _target;
    final n = _index + 1;
    switch (t.kind) {
      case FillKind.check:
        final chosen = _choices[_index];
        final filled = !_filled
            ? ''
            : chosen == null
                ? '이미 고른 칸이에요. 다시 고르면 바뀌고, 그냥 다음을 누르면 그대로 둬요. '
                : '이미 ${chosen ? '예' : '아니요'}를 골랐어요. 다시 고르면 바뀌고, 그냥 다음을 누르면 그대로 둬요. ';
        return '$n번째, ${checkQuestion(t)} $filled예는 1, 아니요는 2를 누르거나 위아래 버튼을 누르세요.';
      case FillKind.signature:
        final pages = widget.state.pages.length;
        final where = pages <= 1 ? '1페이지' : '$pages페이지 중 ${t.page + 1}페이지';
        final filled = _filled ? '이미 서명한 칸이에요. 새로 쓰면 바뀌고, 그냥 다음을 누르면 그대로 둬요. ' : '';
        return '$where, ${josa(t.label, '을', '를')} 시작합니다. $filled손가락으로 크게 쓰고 왼쪽으로 미세요.';
      case FillKind.text:
        final filled = _filled ? ' 이미 채운 칸이에요. 새로 쓰면 바뀌고, 그냥 다음을 누르면 그대로 둬요.' : '';
        final how = first ? ' 화면 가득 크게 쓰고, 다 쓰면 왼쪽으로 밀거나 다음 버튼을 누르세요.' : '';
        if (t.datePart case final part?) {
          return '$n번째, 날짜의 ${josa(part, '을', '를')} 적으세요. 숫자만 쓰면 돼요.$filled$how';
        }
        return '$n번째, ${josa(t.label, '을', '를')} 쓰세요.$filled$how';
    }
  }

  /// 제목 위 작은 줄: "3페이지 중 1페이지 · 4번째 칸"
  String _where() {
    final pages = widget.state.pages.length;
    final n = '${_index + 1}번째 칸';
    return pages <= 1 ? '$n / 모두 ${_targets.length}칸' : '$pages페이지 중 ${_target.page + 1}페이지 · $n';
  }

  /// 제목 아래 무엇을 할지 한 줄
  String _hint() {
    final t = _target;
    if (_drawingCheck) return '한 번만 그리면 다음부터 그대로 써요';
    return switch (t.kind) {
      FillKind.check => '예 또는 아니요를 골라 주세요',
      FillKind.signature => '크게 서명해 주세요',
      FillKind.text when t.isDate => '${josa(t.datePart!, '을', '를')} 숫자로 적어 주세요',
      FillKind.text => '또박또박 써 주세요',
    };
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
    // 오른쪽 35% 안에서 시작해 너비의 35% 넘게 왼쪽으로, 거의 수평·빠르게·곧게
    final fling = _strokeStart.dx >= _area.width * 0.65 &&
        d.dx <= -_area.width * 0.35 &&
        d.dy.abs() <= d.dx.abs() * 0.35 &&
        ms <= 500 &&
        _pathLength <= d.distance * 1.3;
    if (fling) {
      setState(() => _strokes.removeLast());
      // 밀기 = 입력. 알아본 순간 바로 밀기 신호를 내고 넘긴다 (검사 결과는 _next가 따로 알린다)
      Haptics.slide();
      _next(bySlide: true);
    }
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer == _pointer) _pointer = null;
  }

  void _undo() {
    if (_phase != _Phase.writing || _busy) return;
    if (_target.kind == FillKind.check && !_drawingCheck) {
      Speech.announce(context, '고르는 칸이에요. 예나 아니요를 다시 누르면 바뀌어요.');
      return;
    }
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
    if (_target.kind == FillKind.check && !_drawingCheck) {
      Speech.announce(context, '고르는 칸이에요. 예나 아니요를 다시 누르면 바뀌어요.');
      return;
    }
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

  /// 넘기기. [bySlide]면 밀기 신호를 이미 냈으므로 통과 신호(ok)를 다시 내지 않는다
  Future<void> _next({bool bySlide = false}) async {
    if (_phase != _Phase.writing || _busy) return;
    final target = _target;
    if (target.kind == FillKind.check && _drawingCheck) {
      // 처음 그리는 ✓: 비었으면 다시, 있으면 저장하고 고른 상자에 넣는다
      if (_strokes.isEmpty) {
        const message = '아직 그리지 않았어요. 체크 표시를 그려 주세요.';
        setState(() => _message = message);
        Haptics.warn();
        Speech.announce(context, message);
        return;
      }
      widget.state.setCheckMark(_normalizeCheckMark(_strokes));
      final yes = _pendingChoice ?? true;
      setState(() {
        _drawingCheck = false;
        _pendingChoice = null;
        _strokes.clear();
      });
      if (!bySlide) Haptics.ok();
      await _placeCheck(yes, intro: '체크 표시를 저장했어요. ');
      return;
    }
    if (target.kind == FillKind.check) {
      if (_filled) {
        _advance();
        return;
      }
      const message = '아직 고르지 않았어요. 예 또는 아니요 버튼을 누르세요.';
      setState(() => _message = message);
      Haptics.warn();
      Speech.announce(context, message);
      return;
    }
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
    if (!bySlide) Haptics.ok();
    if (target.isSignature) _signatureBaseline ??= verdict.metrics;
    await _commit(target, List.of(_strokes), _FillInk.bounds(_strokes));
  }

  /// 예/아니요를 골랐다. 저장된 ✓가 있으면 바로 넣고, 없으면 먼저 ✓를 한 번 그리게 한다
  Future<void> _choose(bool yes) async {
    if (_phase != _Phase.writing || _busy) return;
    if (_drawingCheck) {
      // 그리는 중에 답을 바꿨다. 그린 획은 그대로 둔다
      setState(() => _pendingChoice = yes);
      Speech.announce(context, '${yes ? '예' : '아니요'}로 바꿨어요. 체크 표시를 마저 그리고 왼쪽으로 밀거나 다음을 누르세요.');
      return;
    }
    if (widget.state.checkMark == null) {
      setState(() {
        _drawingCheck = true;
        _pendingChoice = yes;
        _strokes.clear();
        _beforeClear = null;
        _message = null;
      });
      Haptics.ok();
      Speech.announce(context, '${yes ? '예' : '아니요'}를 골랐어요. $_drawPrompt');
      return;
    }
    Haptics.ok();
    await _placeCheck(yes, intro: '저장해 둔 체크 표시를 넣었어요. ');
  }

  /// 고르는 칸: 고른 상자 자리에 저장해 둔 ✓를 넣는다.
  /// 화면에는 두 상자를 합친 칸을 크게 놓고(가상 칸), 그 안의 고른 상자 자리에 ✓ 획을 놓은 뒤
  /// 글씨와 같은 길(PNG → 움직임 → 다음 칸)로 보낸다. PNG의 상자는 가상 칸 전체라 문서 칸에 꽉 들어가며 ✓가 제자리에 놓인다.
  /// [intro]는 다음 칸 안내 앞에 "예에 표시했어요" 뒤에 붙여 말한다
  Future<void> _placeCheck(bool yes, {String intro = ''}) async {
    final target = _target;
    final r = target.rect;
    final span = Rect.fromLTWH(r.x.toDouble(), r.y.toDouble(), r.width.toDouble(), r.height.toDouble());
    final blocks = widget.state.recognized?.blocks ?? const <TextBlock>[];
    final block = findCheckBlock(target, blocks);
    final boxes = block == null ? null : checkBoxRects(target, block);
    // 줄을 못 찾으면 왼쪽 절반이 예, 오른쪽 절반이 아니요
    final half = Size(span.width / 2, span.height);
    final chosen = boxes == null
        ? (yes ? span.topLeft & half : (span.topLeft + Offset(half.width, 0)) & half)
        : (yes ? boxes.yes : boxes.no);

    final s = math.min(_area.width * 0.9 / span.width, _area.height * 0.9 / span.height);
    final virtual = Rect.fromCenter(center: _area.center(Offset.zero), width: span.width * s, height: span.height * s);
    final boxOnScreen = Rect.fromLTWH(
      virtual.left + (chosen.left - span.left) * s,
      virtual.top + (chosen.top - span.top) * s,
      chosen.width * s,
      chosen.height * s,
    );
    final inner = boxOnScreen.deflate(boxOnScreen.shortestSide * 0.18);
    _choices[_index] = yes;
    _pending = '${yes ? '예' : '아니요'}에 표시했어요. $intro';
    final mark = widget.state.checkMark;
    if (mark == null) return; // 그 사이 지워졌으면 넣지 않는다 (다음 고르기에서 다시 그리게 된다)
    await _commit(target, _strokesFromCheckMark(mark, inner), virtual);
  }

  /// 그린 ✓를 저장용으로 정규화한다: 획마다 [x, y, 필압] 점 목록.
  /// 점을 감싸는 상자의 **긴 변**이 0~1이 되게 같은 배율로 줄여, 모든 값이 0~1 안에 있으면서도 가로세로 비율이 남는다
  /// (짧은 변은 0~비율). 그래서 [_strokesFromCheckMark]가 비율을 따로 저장하지 않고도 모양을 지킬 수 있다
  static List<List<List<double>>> _normalizeCheckMark(List<List<PenPoint>> strokes) {
    var left = double.infinity, top = double.infinity, right = -double.infinity, bottom = -double.infinity;
    for (final s in strokes) {
      for (final p in s) {
        left = math.min(left, p.position.dx);
        top = math.min(top, p.position.dy);
        right = math.max(right, p.position.dx);
        bottom = math.max(bottom, p.position.dy);
      }
    }
    final longest = math.max(math.max(right - left, bottom - top), 1e-6);
    return [
      for (final s in strokes)
        if (s.isNotEmpty)
          [
            for (final p in s) [(p.position.dx - left) / longest, (p.position.dy - top) / longest, p.pressure],
          ],
    ];
  }

  /// 저장된 ✓([_normalizeCheckMark] 모양)를 [box] 안에 비율을 지키며 가득(contain) 놓은 획으로 되돌린다
  static List<List<PenPoint>> _strokesFromCheckMark(List<List<List<double>>> mark, Rect box) {
    var right = 0.0, bottom = 0.0;
    for (final s in mark) {
      for (final p in s) {
        right = math.max(right, p[0]);
        bottom = math.max(bottom, p[1]);
      }
    }
    final size = Size(math.max(right, 1e-6), math.max(bottom, 1e-6));
    final dest = Alignment.center.inscribe(applyBoxFit(BoxFit.contain, size, box.size).destination, box);
    final scale = dest.width / size.width;
    var ms = 0;
    return [
      for (final s in mark)
        [
          for (final p in s)
            PenPoint(Offset(dest.left + p[0] * scale, dest.top + p[1] * scale), ms += 20, p.length > 2 ? p[2] : 0.5),
        ],
    ];
  }

  /// [strokes]를 [bounds] 상자의 PNG로 만들어 저장하고, 문서 사진의 칸 자리로 움직인 뒤 다음 칸으로
  Future<void> _commit(FillTarget target, List<List<PenPoint>> strokes, Rect bounds) async {
    setState(() => _busy = true);
    final Uint8List png;
    try {
      png = await _FillInk.toPng(strokes, bounds);
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
    // 다음 칸 안내 앞에 "넣었어요"를 붙인다 (고르는 칸은 _choose가 "예에 표시했어요"를 이미 넣었다)
    if (target.kind != FillKind.check) _pending = '${target.label} 넣었어요. ';

    final page = _pageSize(target.page);
    if (page != null) {
      _pageOnScreen = _fitPage(page, _area);
      _targetOnScreen = _mapBox(target, page, _pageOnScreen);
      _from = bounds;
      _to = _fitInk(bounds.size, _targetOnScreen, target.kind);
      setState(() {
        _flying = strokes;
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
      Speech.announce(context, '${_takePending()}모두 채웠어요. PDF로 받을 수 있어요.');
      return;
    }
    _goTo(next);
  }

  String _takePending() {
    final p = _pending;
    _pending = '';
    return p;
  }

  void _goTo(int index, {bool back = false}) {
    if (_phase == _Phase.writing && _strokes.isNotEmpty) _drafts[_index] = List.of(_strokes);
    setState(() {
      _index = index;
      _phase = _Phase.writing;
      _busy = false;
      _message = null;
      _beforeClear = null;
      _drawingCheck = false;
      _pendingChoice = null;
      _strokes
        ..clear()
        ..addAll(_drafts[index] ?? const []);
    });
    _precache();
    Speech.announce(context, '${_takePending()}${back ? '이전 칸이에요. ' : ''}${_intro()}');
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): done ? _export : _next,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(_exported),
        // 고르는 칸: 1 = 예, 2 = 아니요
        if (!done && _target.kind == FillKind.check) ...{
          const SingleActivator(LogicalKeyboardKey.digit1): () => _choose(true),
          const SingleActivator(LogicalKeyboardKey.digit2): () => _choose(false),
        },
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 맨 위 한 줄: 닫기 · 진행 동그라미 · 다시 듣기
                      Row(
                        children: [
                          IconButton(
                            tooltip: '닫기',
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                            onPressed: TapFeedback.wrap(() => Navigator.of(context).pop(_exported)),
                          ),
                          Expanded(
                            child: ProgressDots(
                              targets: _targets,
                              filledIds: widget.state.fills.keys.toSet(),
                              currentIndex: done ? -1 : _index,
                            ),
                          ),
                          IconButton(
                            tooltip: '다시 듣기',
                            icon: const Icon(Icons.volume_up_rounded),
                            onPressed: TapFeedback.wrap(() => Speech.announce(
                                  context,
                                  done
                                      ? '모두 채웠어요. PDF로 받을 수 있어요.'
                                      : _drawingCheck
                                          ? _drawPrompt
                                          : _intro(first: true),
                                )),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // 몇 페이지 몇 번째 칸 → 큰 칸 이름 → 무엇을 쓸지
                      if (!done)
                        Text(_where(), textAlign: TextAlign.center, style: text.labelLarge),
                      const SizedBox(height: 4),
                      Semantics(
                        header: true,
                        child: Text(
                          done ? '모두 채웠어요' : _drawingCheck ? '체크 표시' : _target.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.3),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        done ? '서명한 문서를 PDF로 받을 수 있어요' : _hint(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.muted),
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: done
                            ? _donePages()
                            : _target.kind == FillKind.check && !_drawingCheck
                                ? _checkArea(text)
                                : _writingArea(text),
                      ),
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
                      if (!done && !(_target.kind == FillKind.check && !_drawingCheck)) ...[
                        const SizedBox(height: 12),
                        const ExcludeSemantics(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.arrow_back_rounded, size: 18, color: AppColors.muted),
                              SizedBox(width: 6),
                              Text(
                                '다 쓰면 오른쪽에서 왼쪽으로 밀어 넘기세요',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
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
        final drawing = _drawingCheck;
        return Semantics(
          label: drawing
              ? '체크 표시 그리는 칸. 한 번만 그리면 다음부터 그대로 써요. 다 그리면 다음을 누르세요. 지금까지 ${_strokes.length}획.'
              : '${target.label} 쓰는 칸. 화면 가득 쓰세요. 다 쓰면 다음을 누르세요. 지금까지 ${_strokes.length}획.',
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _moveTo,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(AppRadius.card),
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
                          drawing
                              ? '여기에 체크 표시 ✓\n한 번만 그려요'
                              : _filled
                                  ? '${target.label}\n이미 채웠어요'
                                  : '여기에 ${target.label}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.grey300, height: 1.4),
                        ),
                      ),
                    ),
                  if (_phase == _Phase.placing) _placing(),
                  CustomPaint(painter: _InkPainter(_strokes, baseline: !target.isSignature && !drawing)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 고르는 칸: 위 "예", 아래 "아니요" 큰 버튼 둘. 고르면 같은 자리에서 ✓가 문서로 들어가는 움직임을 보여 준다
  Widget _checkArea(TextTheme text) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _area = constraints.biggest;
        final target = _target;
        final chosen = _choices[_index];
        final enabled = _phase == _Phase.writing && !_busy;
        if (_phase == _Phase.placing) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(fit: StackFit.expand, children: [_placing()]),
          );
        }
        final question = checkQuestion(target);
        return Semantics(
          label: '${target.label} 고르는 칸. $question 예 또는 아니요 버튼을 누르세요.'
              '${chosen == null ? '' : ' 지금은 ${chosen ? '예' : '아니요'}를 골랐어요.'}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                child: Text(question, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.4)),
              ),
              Expanded(
                child: _ChoiceButton(
                  label: '예',
                  icon: Icons.check_circle_outline,
                  selected: chosen == true,
                  filled: true,
                  onPressed: enabled ? () => _choose(true) : null,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _ChoiceButton(
                  label: '아니요',
                  icon: Icons.cancel_outlined,
                  selected: chosen == false,
                  filled: false,
                  onPressed: enabled ? () => _choose(false) : null,
                ),
              ),
              // 저장해 둔 ✓가 있을 때만: 지우면 다음에 예/아니요를 고를 때 다시 그린다
              if (widget.state.checkMark != null)
                TextButton.icon(
                  onPressed: TapFeedback.wrap(enabled ? _resetCheckMark : null),
                  icon: const Icon(Icons.draw_outlined, size: 18),
                  label: const Text('체크 표시 다시 그리기', style: TextStyle(fontSize: 13)),
                ),
            ],
          ),
        );
      },
    );
  }

  void _resetCheckMark() {
    widget.state.clearCheckMark();
    setState(() {});
    Speech.announce(context, '저장한 체크 표시를 지웠어요. 다음에 예나 아니요를 고르면 다시 그릴 수 있어요.');
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
        alignment: f.target.kind == FillKind.text ? Alignment.centerLeft : Alignment.center,
        gaplessPlayback: true,
      );

  Widget _writingButtons() {
    final enabled = _phase == _Phase.writing && !_busy;
    final isCheck = _target.kind == FillKind.check && !_drawingCheck;
    return SizedBox(
      height: 68,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 2, child: _ToolButton(label: '이전', onPressed: enabled && _index > 0 ? _previous : null)),
          const SizedBox(width: 8),
          if (!isCheck) ...[
            Expanded(flex: 2, child: _ToolButton(label: '다시 쓰기', onPressed: enabled ? _clear : null)),
            const SizedBox(width: 8),
          ],
          Expanded(
            flex: isCheck ? 5 : 3,
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 68), textStyle: _buttonText),
              onPressed: TapFeedback.wrap(enabled ? _next : null),
              child: const Text('다음'),
            ),
          ),
        ],
      ),
    );
  }

  static const _buttonText = TextStyle(fontFamily: AppFonts.body, fontSize: 18, fontWeight: FontWeight.w700);

  Widget _doneButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: TapFeedback.wrap(_busy ? null : _export),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(_busy ? 'PDF 만드는 중…' : '서명한 문서 PDF 받기'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: TapFeedback.wrap(_busy ? null : _previous),
                icon: const Icon(Icons.chevron_left),
                label: const Text('고치기'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: TapFeedback.wrap(() => Navigator.of(context).pop(_exported)),
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

/// 글씨 칸은 왼쪽에 붙이되 칸 높이의 15%만큼 안쪽에서 시작한다 (':' 바로 뒤에 붙지 않게).
/// 서명과 고르는 칸(✓ PNG는 칸과 같은 비율)은 가운데
Rect _fitInk(Size ink, Rect target, FillKind kind) {
  final isText = kind == FillKind.text;
  final area = isText ? fillTextInset(target) : target;
  return (isText ? Alignment.centerLeft : Alignment.center)
      .inscribe(applyBoxFit(BoxFit.contain, ink, area.size).destination, area);
}

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
      // 옅은 점선 밑줄
      final y = size.height * 0.7;
      final paint = Paint()
        ..color = AppColors.grey300
        ..strokeWidth = 2;
      for (var x = size.width * 0.06; x < size.width * 0.94; x += 10) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 5, size.width * 0.94), y), paint);
      }
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

/// 고르는 칸의 큰 답 버튼 (예 / 아니요). 적어도 120px 높이, 글자 48px. 고른 쪽은 테두리를 굵게
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool filled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 30),
        const SizedBox(width: 14),
        Text(label, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
        if (selected) ...[
          const SizedBox(width: 12),
          const Text('(고름)', style: TextStyle(fontSize: 16)),
        ],
      ],
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card));
    return Semantics(
      button: true,
      selected: selected,
      label: '$label 버튼${selected ? ', 고른 답' : ''}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 120),
        child: filled
            ? FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 120),
                  shape: shape,
                  side: selected ? const BorderSide(color: AppColors.primary, width: 5) : null,
                ),
                onPressed: TapFeedback.wrap(onPressed),
                child: child,
              )
            : OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 120),
                  shape: shape,
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.text,
                  side: BorderSide(color: selected ? AppColors.primary : AppColors.grey200, width: selected ? 4 : 1.5),
                ),
                onPressed: TapFeedback.wrap(onPressed),
                child: child,
              ),
      ),
    );
  }
}

/// 회색 바탕의 약한 버튼 (이전, 다시 쓰기). 68px 높이
class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 68),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        textStyle: _FillScreenState._buttonText,
      ),
      onPressed: TapFeedback.wrap(onPressed),
      child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
    );
  }
}
