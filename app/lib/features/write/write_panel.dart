import 'package:flutter/material.dart';

import '../../models/document_photo.dart';
import '../../models/recognized_document.dart';
import '../../services/api_client.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';

/// 쓰기: 칸을 고르고 종이에 펜으로 쓴 뒤 찍으면, 그 칸에 무엇이 쓰였는지 읽어준다.
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
      return '글씨를 확인하지 못했어요. 다시 찍어 주세요.';
    }
  }
}

/// 쓰기 모드일 때 촬영 버튼 위에 나오는 칸 고르기 줄
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
                label: Text(field, style: const TextStyle(fontSize: 17)),
                selected: field == selected,
                onSelected: (_) {
                  WriteMode.field.value = field;
                  Speech.announce(context, '$field 칸. 종이에 쓰고 찍으세요.');
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
        Text('쓴 글씨 확인', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
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
