import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/workspace_state.dart';
import '../../services/download.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_section.dart';
import '../output/signed_pdf.dart';
import 'signature_pad_screen.dart';
import 'signature_spots.dart';

/// 서명: 서명이 필요한 곳을 알려주고, 서명 전에 검토 결과를 한 번 더 들려주고,
/// 서명란마다 패드 서명을 받은 뒤, 페이지 사진에 서명을 합성한 PDF를 내려받게 한다 (계획서 3, 4단계).
class SignPanel extends StatefulWidget {
  const SignPanel({super.key, required this.state});

  final WorkspaceState state;

  @override
  State<SignPanel> createState() => _SignPanelState();
}

class _SignPanelState extends State<SignPanel> {
  bool _exporting = false;

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

  Future<void> _sign(SignatureSpot spot) async {
    final png = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => SignaturePadScreen(spotLabel: spot.label)),
    );
    if (png == null || !mounted) return;
    widget.state.setSignature(spot.line, png);
    final left = _spots.where((s) => !widget.state.signatures.containsKey(s.line)).length;
    Speech.announce(
      context,
      left == 0 ? '서명을 모두 마쳤어요. 서명한 계약서 PDF 받기를 누르세요.' : '${spot.label}에 서명했어요. 남은 서명란은 $left곳이에요.',
    );
  }

  Future<void> _export() async {
    final document = widget.state.recognized;
    if (document == null) return;
    setState(() => _exporting = true);
    try {
      final signatures = widget.state.signatures;
      final pdf = await buildSignedPdf(pages: widget.state.pages, document: document, signatures: signatures);
      downloadBytes(pdf, '들리는계약서_서명본.pdf');
      if (mounted) Speech.announce(context, describeSignedPdf(document, signatures));
    } catch (_) {
      if (mounted) Speech.announce(context, 'PDF를 만들지 못했어요. 다시 시도해 주세요.');
    }
    if (mounted) setState(() => _exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final judgement = widget.state.judgement;
    final spots = _spots;
    final signatures = widget.state.signatures;

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
          Text('서명란을 찾지 못했어요. 서명할 곳이 사진에 들어오게 다시 찍어 주세요.', style: text.bodyMedium)
        else
          for (final spot in spots) _SpotRow(spot: spot, signature: signatures[spot.line], onSign: () => _sign(spot)),
        if (signatures.isNotEmpty) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _exporting ? null : _export,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_exporting ? 'PDF 만드는 중…' : '서명한 계약서 PDF 받기'),
          ),
        ],
      ],
    );
  }
}

/// 서명란 하나: 아직이면 "서명하기" 버튼, 했으면 서명 미리보기와 "다시 서명"
class _SpotRow extends StatelessWidget {
  const _SpotRow({required this.spot, required this.signature, required this.onSign});

  final SignatureSpot spot;
  final Uint8List? signature;
  final VoidCallback onSign;

  @override
  Widget build(BuildContext context) {
    final signature = this.signature;
    if (signature == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: OutlinedButton.icon(
          onPressed: onSign,
          icon: const Icon(Icons.draw_outlined),
          label: Text('${spot.label}에 서명하기'),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.okSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.ok),
          const SizedBox(width: 10),
          Expanded(child: Text('${spot.label} 서명함', style: Theme.of(context).textTheme.titleMedium)),
          SizedBox(
            width: 96,
            height: 40,
            child: Semantics(
              image: true,
              label: '${spot.label} 서명',
              child: Image.memory(signature, fit: BoxFit.contain),
            ),
          ),
          TextButton(onPressed: onSign, child: const Text('다시 서명')),
        ],
      ),
    );
  }
}
