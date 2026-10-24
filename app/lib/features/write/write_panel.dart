import 'package:flutter/material.dart';

import '../../models/workspace_state.dart';
import '../../services/api_client.dart';
import '../../services/camera_service.dart';
import '../../services/speech.dart';
import '../../widgets/panel_section.dart';

/// 쓰기: 칸을 고르고 종이에 펜으로 쓴 뒤, 카메라로 다시 찍어 무엇을 썼는지 읽어준다.
class WritePanel extends StatefulWidget {
  const WritePanel({super.key, required this.state, required this.camera});

  final WorkspaceState state;
  final CameraService camera;

  @override
  State<WritePanel> createState() => _WritePanelState();
}

class _WritePanelState extends State<WritePanel> {
  /// 서식에 흔한 칸 이름. 읽은 문서에 있는 것만 보여준다
  static const _commonFields = ['성명', '이름', '주소', '연락처', '전화번호', '생년월일', '날짜'];

  String? _field;
  bool _busy = false;
  String? _result;

  List<String> get _fields {
    final text = (widget.state.recognized?.fullText ?? '').replaceAll(RegExp(r'\s'), '');
    final found = _commonFields.where(text.contains).toList();
    return found.isEmpty ? _commonFields : found;
  }

  Future<void> _check() async {
    final field = _field;
    if (field == null) return;
    setState(() => _busy = true);
    // 쓴 뒤의 종이를 새로 찍는다. 카메라가 없으면 처음 받은 사진으로 확인한다.
    final photo = await widget.camera.snapshot() ?? widget.state.photo!;
    try {
      final check = await ApiClient.checkWriting(photo, field);
      _result = check['speech'] as String?;
    } catch (_) {
      _result = '글씨를 확인하지 못했어요. 다시 시도해 주세요.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    Speech.announce(context, _result ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return PanelSection(
      title: '쓰기',
      description: '칸을 고르고 종이에 펜으로 쓴 다음, 확인을 누르면 무엇을 썼는지 읽어드려요.',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final field in _fields)
              ChoiceChip(
                label: Text(field),
                selected: _field == field,
                onSelected: (_) {
                  setState(() => _field = field);
                  Speech.announce(context, '$field 칸을 골랐어요. 종이에 쓰고 확인을 누르세요.');
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _field == null || _busy ? null : _check,
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(_busy ? '확인하는 중…' : '쓴 글씨 확인'),
        ),
        if (_result != null) ...[
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: Text(_result!, style: Theme.of(context).textTheme.bodyLarge)),
        ],
      ],
    );
  }
}
