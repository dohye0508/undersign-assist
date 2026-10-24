import 'package:flutter/material.dart';

import '../../models/document_photo.dart';
import '../../models/recognized_document.dart';
import '../../models/workspace_state.dart';
import '../../services/api_client.dart';
import '../../services/camera_service.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/panel_section.dart';
import 'note_ink.dart';
import 'note_pad_screen.dart';

/// 쓰기: 분석한 페이지를 노트에 올려 그 위에 패드로 쓰고, 고른 칸에 무엇을 썼는지 읽어준다.
class WriteMode {
  WriteMode._();

  /// 서식에 흔한 칸 이름. 읽은 문서가 있으면 그 문서에 있는 것만 보여준다
  static const commonFields = ['성명', '주소', '연락처', '생년월일', '날짜'];

  static final field = ValueNotifier<String>(commonFields.first);

  static List<String> fieldsFor(RecognizedDocument? document) {
    final text = (document?.fullText ?? '').replaceAll(RegExp(r'\s'), '');
    final found = commonFields.where(text.contains).toList();
    return found.isEmpty ? commonFields : found;
  }

  /// 사진에서 고른 칸을 확인하고, 들려줄 문장을 돌려준다
  static Future<String> check(DocumentPhoto photo) async {
    try {
      final result = await ApiClient.checkWriting(photo, field.value);
      return result['speech'] as String? ?? '';
    } catch (_) {
      return '글씨를 확인하지 못했어요. 서버가 켜져 있는지 확인하고 다시 시도해 주세요.';
    }
  }

  /// 칸 이름이 인쇄된 페이지. 노트가 있는 페이지의 칸을 먼저 고른다 (여러 쪽에 같은 칸 이름이 있을 수 있다).
  /// 못 찾으면 노트가 있는 첫 페이지, 그것도 없으면 첫 페이지
  static int pageFor(RecognizedDocument? document, Map<int, Object> notes, String field) {
    for (final block in document?.blocks ?? const <TextBlock>[]) {
      final compact = block.text.replaceAll(RegExp(r'\s+'), '');
      if (compact.contains(field) && notes.containsKey(block.page)) return block.page;
    }
    final noted = notes.keys.toList()..sort();
    return noted.isEmpty ? 0 : noted.first;
  }

  /// 확인 API에 보낼 한 장: 페이지 사진 + 그 위에 쓴 노트. 노트가 없으면 사진 그대로
  static Future<DocumentPhoto> notePhoto(WorkspaceState state, int page) async {
    final photo = state.pages[page];
    final note = state.notes[page];
    if (note == null) return photo;
    final bytes = await NoteInk.composite(
      photo: photo.bytes,
      note: note,
      size: NoteInk.pageSize(state.recognized, page),
    );
    return DocumentPhoto(bytes: bytes, name: 'page${page + 1}_note.png');
  }
}

/// 쓰기 단계 화면. 새로 찍지 않고, 분석할 때 올린 페이지를 노트에 올려 그 위에 쓴다.
/// [camera]는 화면 쪽 생성자를 바꾸지 않으려고 받기만 하고 쓰지 않는다.
class WritePanel extends StatefulWidget {
  const WritePanel({super.key, required this.state, required this.camera});

  final WorkspaceState state;
  final CameraService camera;

  @override
  State<WritePanel> createState() => _WritePanelState();
}

class _WritePanelState extends State<WritePanel> {
  bool _busy = false;
  String? _result;

  Future<void> _open(int page) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => NotePadScreen(state: widget.state, page: page)),
    );
  }

  Future<void> _check() async {
    final state = widget.state;
    final field = WriteMode.field.value;
    final page = WriteMode.pageFor(state.recognized, state.notes, field);
    setState(() => _busy = true);
    final multiPage = state.pages.length > 1;
    Speech.announce(context, '${multiPage ? '${page + 1}페이지 ' : ''}$field 칸을 확인하고 있어요.');
    String message;
    try {
      message = await WriteMode.check(await WriteMode.notePhoto(state, page));
    } catch (_) {
      message = '노트와 사진을 합치지 못했어요. 다시 시도해 주세요.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = message;
    });
    Speech.announce(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final state = widget.state;
        return PanelSection(
          title: WorkStep.write.label,
          description: '페이지를 노트에 올려 손가락이나 펜으로 칸에 쓰고, 쓴 글씨 읽어 주기를 누르세요.',
          children: [
            if (!state.hasPages)
              Text('먼저 문서 사진을 올리고 분석하세요.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 22))
            else ...[
              for (final (i, _) in state.pages.indexed) ...[
                _PageButton(page: i, hasNote: state.notes.containsKey(i), onPressed: _busy ? null : () => _open(i)),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
              WriteFieldPicker(document: state.recognized),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : _check,
                icon: const Icon(Icons.record_voice_over_outlined),
                label: Text(_busy ? '확인하는 중…' : '쓴 글씨 읽어 주기'),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              WriteResultView(message: _result!),
            ],
          ],
        );
      },
    );
  }
}

/// "1페이지에 쓰기" 버튼. 쓴 글씨가 있으면 ✓를 붙이고, 스크린리더에는 말로 알린다
class _PageButton extends StatelessWidget {
  const _PageButton({required this.page, required this.hasNote, required this.onPressed});

  final int page;
  final bool hasNote;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final label = '${page + 1}페이지에 쓰기';
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(hasNote ? Icons.check_circle : Icons.edit_outlined, color: hasNote ? AppColors.ok : null),
      label: Text(
        hasNote ? '$label ✓' : label,
        semanticsLabel: hasNote ? '$label, 쓴 글씨 있음' : label,
      ),
    );
  }
}

/// 칸 고르기 줄
class WriteFieldPicker extends StatelessWidget {
  const WriteFieldPicker({super.key, required this.document});

  final RecognizedDocument? document;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: WriteMode.field,
      builder: (context, selected, _) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final field in WriteMode.fieldsFor(document)) ...[
              ChoiceChip(
                label: Text(field, style: const TextStyle(fontSize: 20)),
                // 손가락으로 누르기 쉽게 버튼만큼(64) 키운다
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                selected: field == selected,
                onSelected: (_) {
                  WriteMode.field.value = field;
                  Speech.announce(context, '$field 칸. 노트에 쓰고, 쓴 글씨 읽어 주기를 누르세요.');
                },
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// 결과 창에 보이는 쓰기 결과
class WriteResultView extends StatelessWidget {
  const WriteResultView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(message, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 22)),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => Speech.announce(context, message),
          icon: const Icon(Icons.volume_up_outlined),
          label: const Text('다시 듣기'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
        ),
      ],
    );
  }
}
