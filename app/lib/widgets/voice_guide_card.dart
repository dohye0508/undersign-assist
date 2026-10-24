import 'package:flutter/material.dart';

import '../services/speech.dart';
import '../theme/app_theme.dart';
import 'panel_section.dart';

/// 마지막으로 음성으로 말한 문장을 크게 보여준다 (디자인 시안의 "음성 안내" 카드).
class VoiceGuideCard extends StatelessWidget {
  const VoiceGuideCard({super.key, this.detail});

  /// 아래 작은 줄 (예: "근로계약서로 보입니다 · AI로 정리")
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: Speech.lastMessage,
      builder: (context, message, _) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.volume_up_rounded, size: 15, color: AppColors.muted),
                const SizedBox(width: 6),
                Text('음성 안내', style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 6),
            // 화면 읽기 프로그램에는 Speech가 따로 알리므로 여기서는 중복해 읽지 않는다
            ExcludeSemantics(
              child: Text(
                message.isEmpty ? '카메라를 준비하고 있어요' : message,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.45),
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(detail!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
