import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/recognized_document.dart';
import '../../models/workspace_state.dart';
import '../../services/haptics.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import 'note_ink.dart';

/// 노트 화면. 분석할 때 올린 페이지 사진을 바탕에 깔고, 그 위에 펜(마우스·손가락·스타일러스)으로 쓴다.
///
/// 새로 찍지 않는다: 이미 올린 사진 위에 쓰므로 칸 위치가 읽기 결과와 그대로 맞는다.
/// 잉크는 페이지 사진 픽셀 좌표로 모아서, 저장하면 사진과 같은 크기의 투명 PNG가 된다 ([WorkspaceState.setNote]).
/// 뒤로 가기나 페이지 넘기기도 저장한 뒤에 움직여서, 화면을 못 보는 사용자가 쓴 글씨를 잃지 않게 한다.
class NotePadScreen extends StatefulWidget {
  const NotePadScreen({super.key, required this.state, required this.page});

  final WorkspaceState state;

  /// 처음 열 페이지 (0부터)
  final int page;

  @override
  State<NotePadScreen> createState() => _NotePadScreenState();
}

class _NotePadScreenState extends State<NotePadScreen> {
  late int _page = widget.page;
  ui.Image? _photo;

  /// 전에 저장한 노트. 이어서 쓴다
  ui.Image? _base;
  Size? _size;
  List<_Blank> _blanks = const [];
  String? _error;

  final List<NoteStroke> _strokes = [];

  /// 모두 지우기로 전에 저장한 노트까지 지웠는지
  bool _cleared = false;

  /// 모두 지우기 전 획. 되돌리기로 살린다
  List<NoteStroke>? _beforeClear;

  bool _busy = false;
  int? _pointer;
  int _lastWarnMs = 0;

  /// 화면에서 페이지가 놓인 자리
  Rect _rect = Rect.zero;

  int get _pageCount => widget.state.pages.length;
  bool get _dirty => _strokes.isNotEmpty || _cleared;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _photo?.dispose();
    _base?.dispose();
    super.dispose();
  }

  /// [_page]의 사진과 저장된 노트를 연다. 화면 상태는 부르는 쪽이 미리 비워 둔다
  Future<void> _load() async {
    final page = _page;
    try {
      final photo = await NoteInk.decode(widget.state.pages[page].bytes);
      final note = widget.state.notes[page];
      final base = note == null ? null : await NoteInk.decode(note);
      if (!mounted || page != _page) {
        photo.dispose();
        base?.dispose();
        return;
      }
      final known = NoteInk.pageSize(widget.state.recognized, page);
      final size = known == null
          ? Size(photo.width.toDouble(), photo.height.toDouble())
          : Size(known.width.toDouble(), known.height.toDouble());
      final blanks = _findBlanks(widget.state.recognized, page, size);
      setState(() {
        _photo = photo;
        _base = base;
        _size = size;
        _blanks = blanks;
      });
      final names = {for (final b in blanks) b.field}.toList();
      final where = names.isEmpty ? '' : ' 이 페이지에서 쓸 칸은 ${names.join(', ')}이에요.';
      Speech.announce(context, '${page + 1}페이지를 노트에 올렸어요. 손가락이나 펜으로 칸에 쓰세요.$where 다 쓰면 저장을 누르세요.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '${page + 1}페이지 사진을 열지 못했어요.');
      Speech.announce(context, _error!);
    }
  }

  // --- 쓰기 ------------------------------------------------------------------

  void _down(PointerDownEvent event) {
    if (_busy || _photo == null || _size == null || _pointer != null) return;
    if (!_rect.contains(event.localPosition)) {
      _warnOutside(event);
      return;
    }
    _pointer = event.pointer;
    setState(() {
      _strokes.add(NoteStroke(_size!.width / _rect.width));
      _strokes.last.add(_toPage(event.localPosition), event.pressure);
      _beforeClear = null;
    });
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer || _strokes.isEmpty) return;
    if (!_rect.contains(event.localPosition)) _warnOutside(event);
    setState(() => _strokes.last.add(_toPage(event.localPosition), event.pressure));
  }

  void _up(PointerEvent event) {
    if (event.pointer == _pointer) _pointer = null;
  }

  /// 페이지 밖은 저장되지 않으므로 서명 패드처럼 진동·소리로 알린다 (1초에 한 번까지)
  void _warnOutside(PointerEvent event) {
    final now = event.timeStamp.inMilliseconds;
    if (now - _lastWarnMs < 1000) return;
    _lastWarnMs = now;
    Haptics.warn();
    Speech.announce(context, '페이지 밖이에요');
  }

  /// 화면 좌표 → 페이지 사진 픽셀 좌표
  Offset _toPage(Offset local) {
    final size = _size!;
    return Offset(
      (local.dx - _rect.left) * size.width / _rect.width,
      (local.dy - _rect.top) * size.height / _rect.height,
    );
  }

  void _undo() {
    if (_strokes.isNotEmpty) {
      setState(() => _strokes.removeLast());
      Speech.announce(context, '마지막 획을 지웠어요. 남은 획 ${_strokes.length}개.');
    } else if (_cleared) {
      setState(() {
        _cleared = false;
        _strokes.addAll(_beforeClear ?? const []);
        _beforeClear = null;
      });
      Speech.announce(context, '지운 글씨를 되살렸어요.');
    } else {
      Haptics.warn();
      Speech.announce(context, '되돌릴 획이 없어요.');
    }
  }

  void _clearAll() {
    if (_strokes.isEmpty && (_base == null || _cleared)) {
      Speech.announce(context, '지울 글씨가 없어요.');
      return;
    }
    setState(() {
      _beforeClear = List.of(_strokes);
      _strokes.clear();
      _cleared = true;
    });
    Speech.announce(context, '이 페이지에 쓴 글씨를 모두 지웠어요. 되돌리기를 누르면 되살아나요.');
  }

  // --- 저장 ------------------------------------------------------------------

  /// 바뀐 것이 있을 때만 그린다. 다 지웠으면 노트를 없앤다
  Future<void> _save() async {
    final size = _size;
    if (!_dirty || size == null) return;
    final base = _cleared ? null : _base;
    if (_strokes.isEmpty && base == null) {
      widget.state.clearNote(_page);
      return;
    }
    final png = await NoteInk.toPng(
      width: size.width.round(),
      height: size.height.round(),
      strokes: _strokes,
      base: base,
    );
    widget.state.setNote(_page, png);
  }

  Future<void> _saveAndClose() async {
    if (_busy) return;
    setState(() => _busy = true);
    final changed = _dirty;
    try {
      await _save();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      Haptics.warn();
      Speech.announce(context, '저장하지 못했어요. 다시 눌러 주세요.');
      return;
    }
    if (!mounted) return;
    final saved = widget.state.notes.containsKey(_page);
    if (changed) {
      Haptics.ok();
      Speech.announce(
        context,
        saved
            ? '${_page + 1}페이지에 쓴 글씨를 저장했어요. 쓴 글씨 읽어 주기를 누르면 읽어드려요.'
            : '${_page + 1}페이지 노트를 비웠어요.',
      );
    }
    Navigator.of(context).pop();
  }

  Future<void> _goTo(int page) async {
    if (_busy || page < 0 || page >= _pageCount) return;
    setState(() => _busy = true);
    try {
      await _save();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      Speech.announce(context, '저장하지 못해서 페이지를 넘기지 않았어요.');
      return;
    }
    if (!mounted) return;
    final oldPhoto = _photo, oldBase = _base;
    setState(() {
      _busy = false;
      _page = page;
      _photo = null;
      _base = null;
      _error = null;
      _strokes.clear();
      _cleared = false;
      _beforeClear = null;
    });
    oldPhoto?.dispose();
    oldBase?.dispose();
    await _load();
  }

  // --- 화면 ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final multiPage = _pageCount > 1;
    return PopScope(
      // 뒤로 가기도 저장한 뒤에 닫는다
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _saveAndClose();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(multiPage ? '${_page + 1}페이지 노트 ($_pageCount쪽 중)' : '${_page + 1}페이지 노트'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _pad(text)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _undo,
                            icon: const Icon(Icons.undo),
                            label: const Text('되돌리기'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _clearAll,
                            icon: const Icon(Icons.layers_clear_outlined),
                            label: const Text('모두 지우기'),
                          ),
                        ),
                      ],
                    ),
                    if (multiPage) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy || _page == 0 ? null : () => _goTo(_page - 1),
                              icon: const Icon(Icons.chevron_left),
                              label: const Text('이전 페이지'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy || _page == _pageCount - 1 ? null : () => _goTo(_page + 1),
                              icon: const Icon(Icons.chevron_right),
                              label: const Text('다음 페이지'),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _busy ? null : _saveAndClose,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_busy ? '저장하는 중…' : '저장'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pad(TextTheme text) {
    final photo = _photo;
    final size = _size;
    if (_error != null) {
      return Center(
        child: Semantics(liveRegion: true, child: Text(_error!, style: text.bodyLarge?.copyWith(fontSize: 22))),
      );
    }
    if (photo == null || size == null) {
      return Center(child: Text('페이지를 올리는 중…', style: text.bodyLarge?.copyWith(fontSize: 22)));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // 사진 비율 그대로 (contain) 가운데에 놓는다
        final area = Offset.zero & constraints.biggest;
        final fitted = applyBoxFit(BoxFit.contain, size, constraints.biggest).destination;
        _rect = Alignment.center.inscribe(fitted, area);
        return Semantics(
          label: '${_page + 1}페이지 문서 노트. 손가락이나 펜으로 칸에 쓰세요. 지금까지 ${_strokes.length}획.',
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _up,
            child: CustomPaint(
              size: constraints.biggest,
              painter: _NotePainter(
                photo: photo,
                base: _cleared ? null : _base,
                strokes: _strokes,
                blanks: _blanks,
                rect: _rect,
                page: size,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 써야 할 칸 이름. 이 글자가 있는 줄 오른쪽을 옅게 칠해 저시력 사용자가 쓸 곳을 보게 한다
const _blankFields = ['성명', '주소', '연락처', '생년월일', '날짜', '서명'];

/// 쓸 칸 하나 (페이지 좌표)
class _Blank {
  const _Blank(this.field, this.rect);

  final String field;
  final Rect rect;
}

/// OCR은 인쇄된 글자만 상자로 주므로, 칸 이름 줄의 오른쪽 빈 곳을 칸으로 어림한다
List<_Blank> _findBlanks(RecognizedDocument? document, int page, Size size) {
  if (document == null) return const [];
  final blanks = <_Blank>[];
  for (final block in document.blocks) {
    if (block.page != page) continue;
    // OCR 띄어쓰기는 믿기 어려워("성 명") 공백을 지우고 찾는다
    final compact = block.text.replaceAll(RegExp(r'\s+'), '');
    final field = _blankFields.where(compact.contains).firstOrNull;
    if (field == null) continue;
    final box = block.box;
    final left = box.x + box.width + box.height * 0.4;
    final width = math.min(size.width - left, box.height * 10.0);
    // 줄이 오른쪽 끝까지 차 있으면 (문장 속 "서명합니다" 등) 칸이 아니다
    if (width < box.height * 2) continue;
    final height = box.height * 1.6;
    blanks.add(_Blank(field, Rect.fromLTWH(left, box.y + box.height / 2 - height / 2, width, height)));
  }
  return blanks;
}

class _NotePainter extends CustomPainter {
  _NotePainter({
    required this.photo,
    required this.base,
    required this.strokes,
    required this.blanks,
    required this.rect,
    required this.page,
  });

  final ui.Image photo;
  final ui.Image? base;
  final List<NoteStroke> strokes;
  final List<_Blank> blanks;
  final Rect rect;
  final Size page;

  @override
  void paint(Canvas canvas, Size size) {
    // 사진도 페이지 상자에 꽉 채운다. 저장·합성(NoteInk)과 같은 방식이라 보이는 자리가 저장되는 자리다
    canvas.drawImageRect(
      photo,
      Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );

    canvas.save();
    canvas.clipRect(rect);
    canvas.translate(rect.left, rect.top);
    final sx = rect.width / page.width;
    final sy = rect.height / page.height;
    canvas.scale(sx, sy);

    final fill = Paint()..color = AppColors.primary.withValues(alpha: 0.10);
    final edge = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / sx;
    for (final blank in blanks) {
      final shape = RRect.fromRectAndRadius(blank.rect, Radius.circular(blank.rect.height * 0.2));
      canvas.drawRRect(shape, fill);
      canvas.drawRRect(shape, edge);
    }

    if (base != null) {
      canvas.drawImageRect(
        base!,
        Rect.fromLTWH(0, 0, base!.width.toDouble(), base!.height.toDouble()),
        Offset.zero & page,
        Paint(),
      );
    }
    NoteInk.paintStrokes(canvas, strokes);
    canvas.restore();

    canvas.drawRect(
      rect,
      Paint()
        ..color = AppColors.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  /// 획은 제자리에서 늘어나므로 매번 다시 그린다
  @override
  bool shouldRepaint(_NotePainter old) => true;
}
