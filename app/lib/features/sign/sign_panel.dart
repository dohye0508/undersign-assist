import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/workspace_state.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_section.dart';
import 'signature_pad_screen.dart';
import 'signature_spots.dart';

/// 서명: 서명이 필요한 곳을 알려주고, 서명 전에 검토 결과를 한 번 더 들려주고, 패드에 서명하게 한다.
/// 여러 페이지 업로드와 서명을 합성한 PDF 출력은 다음 작업이다 (계획성.txt 4단계).
class SignPanel extends StatefulWidget {
  const SignPanel({super.key, required this.state});

  final WorkspaceState state;

  @override
  State<SignPanel> createState() => _SignPanelState();
}

class _SignPanelState extends State<SignPanel> {
  List<SignatureSpot> get _spots {
    final document = widget.state.recognized;
    return document == null ? [] : findSignatureSpots(document);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Speech.announce(context, '${_cautionReminder()}${describeSignatureSpots(_spots)}');
    });
  }

  /// 판단 결과에 확인이 필요한 곳이 있으면 서명 전에 먼저 알린다 (판단 없이 서명하지 않게)
  String _cautionReminder() {
    final judgement = widget.state.judgement;
    if (judgement == null) return '서명하기 전에 검토하세요를 먼저 들어 보세요. ';
    final caution = judgement.counts['caution'] ?? 0;
    return caution == 0 ? '' : '서명 전에 다시 알려드려요. 확인이 필요한 곳이 $caution개 있어요. ';
  }

  Future<void> _sign(SignatureSpot? spot) async {
    final png = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => SignaturePadScreen(spotLabel: spot?.label)),
    );
    if (png == null || !mounted) return;
    widget.state.signaturePng = png;
    Speech.announce(context, '서명을 저장했어요.');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final judgement = widget.state.judgement;
    final spots = _spots;
    final signature = widget.state.signaturePng;

    return PanelSection(
      title: WorkStep.sign.label,
      description: '서명할 곳을 알려드리고, 패드에 서명하면 칸을 벗어나거나 이상할 때 진동과 소리로 알려드려요.',
      children: [
        if (judgement != null)
          OutlinedButton.icon(
            onPressed: () => Speech.announce(context, judgement.speech),
            icon: const Icon(Icons.volume_up_outlined),
            label: const Text('검토 결과 다시 듣기'),
          ),
        const SizedBox(height: 16),
        Text('서명이 필요한 곳', style: text.labelLarge),
        const SizedBox(height: 8),
        if (spots.isEmpty)
          Text('서명란을 찾지 못했어요. 그래도 아래에서 서명할 수 있어요.', style: text.bodyMedium)
        else
          for (final spot in spots)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton.icon(
                onPressed: () => _sign(spot),
                icon: const Icon(Icons.draw_outlined),
                label: Text('${spot.label}에 서명하기'),
              ),
            ),
        if (spots.isEmpty) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => _sign(null),
            icon: const Icon(Icons.draw_outlined),
            label: const Text('패드에 서명하기'),
          ),
        ],
        if (signature != null) ...[
          const SizedBox(height: 16),
          Text('저장한 서명', style: text.labelLarge),
          const SizedBox(height: 8),
          Container(
            height: 110,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Semantics(image: true, label: '저장한 서명', child: Image.memory(signature, fit: BoxFit.contain)),
          ),
        ],
      ],
    );
  }
}
