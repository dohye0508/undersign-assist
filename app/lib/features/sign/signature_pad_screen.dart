import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/haptics.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import 'signature_check.dart';

/// 패드 서명 화면. 가운데 칸 안에 펜(마우스·손가락·스타일러스)으로 서명한다.
///
/// 위치 교정: 펜이 칸을 벗어나는 순간 진동, 경고음, "칸을 벗어났어요" (1초에 한 번까지).
/// 품질 교정: 다 쓴 뒤 [SignatureCheck]가 획 수·크기·시간으로만 판단한다.
/// 통과하면 서명을 투명 배경 PNG로 돌려준다 (다음 작업인 PDF 합성에서 쓴다).
class SignaturePadScreen extends StatefulWidget {
  const SignaturePadScreen({super.key, this.spotLabel});

  /// 지금 서명하는 곳 (예: "근로자 줄")
  final String? spotLabel;

  @override
  State<SignaturePadScreen> createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<SignaturePadScreen> {
  final List<List<PenPoint>> _strokes = [];
  Rect _guide = Rect.zero;
  bool _outside = false;
  int _lastWarnMs = 0;
  String? _message;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final where = widget.spotLabel == null ? '' : '${widget.spotLabel}에 할 서명이에요. ';
      Speech.announce(context, '$where가운데 칸 안에 서명하세요. 칸을 벗어나면 진동과 소리로 알려드려요. 다 쓰면 서명 완료를 누르세요.');
    });
  }

  void _add(PointerEvent event, {bool newStroke = false}) {
    final point = PenPoint(event.localPosition, event.timeStamp.inMilliseconds, event.pressure);
    setState(() {
      if (newStroke) _strokes.add([]);
      _strokes.last.add(point);
      _outside = !_guide.contains(point.position);
    });
    if (_outside && point.timeMs - _lastWarnMs > 1000) {
      _lastWarnMs = point.timeMs;
      Haptics.warn();
      Speech.announce(context, '칸을 벗어났어요');
    }
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _outside = false;
      _message = null;
    });
    Speech.announce(context, '지웠어요. 다시 서명하세요.');
  }

  Future<void> _finish() async {
    final verdict = SignatureCheck.judge(_strokes, _guide);
    setState(() => _message = verdict.message);
    if (!verdict.ok) {
      Haptics.warn();
      Speech.announce(context, verdict.message);
      return;
    }
    Haptics.ok();
    SignatureCheck.baseline ??= verdict.metrics;
    setState(() => _saving = true);
    final png = await _toPng();
    if (!mounted) return;
    Navigator.of(context).pop(png);
  }

  /// 서명 칸 크기의 투명 배경 PNG로 그린다
  Future<Uint8List> _toPng() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(-_guide.left, -_guide.top);
    _StrokePainter.paintStrokes(canvas, _strokes, Colors.black);
    final image = await recorder.endRecording().toImage(_guide.width.round(), _guide.height.round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.spotLabel == null ? '패드에 서명' : '${widget.spotLabel} 서명')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // 서명 칸: 가로로 긴 상자를 가운데에
                        final width = constraints.maxWidth * 0.86;
                        final height = (width * 0.38).clamp(120.0, constraints.maxHeight * 0.7);
                        _guide = Rect.fromCenter(
                          center: constraints.biggest.center(Offset.zero),
                          width: width,
                          height: height,
                        );
                        return Semantics(
                          label: '서명 칸. 이 안에 서명하세요.',
                          child: Listener(
                            onPointerDown: (e) => _add(e, newStroke: true),
                            onPointerMove: _add,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: AppColors.line, width: 1.5),
                              ),
                              child: CustomPaint(
                                size: constraints.biggest,
                                painter: _StrokePainter(_strokes, _guide, _outside),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_message != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(_message!, textAlign: TextAlign.center, style: text.bodyLarge),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _clear,
                          icon: const Icon(Icons.refresh),
                          label: const Text('다시 서명'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _finish,
                          icon: const Icon(Icons.check),
                          label: const Text('서명 완료'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.strokes, this.guide, this.outside);

  final List<List<PenPoint>> strokes;
  final Rect guide;
  final bool outside;

  @override
  void paint(Canvas canvas, Size size) {
    // 서명 칸 (벗어나면 빨갛게)
    final color = outside ? AppColors.caution : AppColors.primary;
    canvas.drawRRect(
      RRect.fromRectAndRadius(guide, const Radius.circular(12)),
      Paint()..color = color.withValues(alpha: 0.06),
    );
    _drawDashed(canvas, guide, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    paintStrokes(canvas, strokes, AppColors.text);
  }

  /// 필압이 있으면 굵기에 반영한다 (스타일러스)
  static void paintStrokes(Canvas canvas, List<List<PenPoint>> strokes, Color color) {
    for (final stroke in strokes) {
      for (var i = 1; i < stroke.length; i++) {
        final pressure = stroke[i].pressure <= 0 ? 0.5 : stroke[i].pressure;
        canvas.drawLine(
          stroke[i - 1].position,
          stroke[i].position,
          Paint()
            ..color = color
            ..strokeWidth = 2 + pressure * 5
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  static void _drawDashed(Canvas canvas, Rect rect, Paint paint) {
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)));
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 14) {
        canvas.drawPath(metric.extractPath(d, d + 8), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) => true;
}
