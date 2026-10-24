import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/tap_feedback.dart';

/// 들리는 받아쓰기 화면들의 공통 틀: 배경, 위쪽 줄(뒤로, 제목, 다시 듣기), 키보드.
/// 메인 화면과 같은 폭(480)으로 가운데에 세로로 둔다.
class PracticeFrame extends StatelessWidget {
  const PracticeFrame({
    super.key,
    required this.title,
    required this.onBack,
    required this.child,
    this.trailing,
    this.shortcuts = const {},
    this.letterKeys = true,
  });

  final String title;
  final VoidCallback onBack;
  final Widget child;
  final Widget? trailing;

  /// 이 화면만의 키 (Enter, 방향키 등)
  final Map<ShortcutActivator, VoidCallback> shortcuts;

  /// R(다시 듣기) 같은 글자 키를 쓸지. 글을 입력하는 화면에서는 끈다
  final bool letterKeys;

  void _repeat(BuildContext context) {
    final last = Speech.lastMessage.value;
    if (last.isNotEmpty) Speech.announce(context, last);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): onBack,
        if (letterKeys) SingleActivator(LogicalKeyboardKey.keyR): () => _repeat(context),
        ...shortcuts,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Stack(
            children: [
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 60,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4, right: 6),
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: '뒤로 가기',
                                  icon: const Icon(Icons.arrow_back),
                                  onPressed: TapFeedback.wrap(onBack),
                                ),
                                Expanded(
                                  child: Semantics(
                                    header: true,
                                    child: Text(
                                      title,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.titleLarge,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '다시 듣기',
                                  icon: const Icon(Icons.volume_up_outlined, color: AppColors.muted),
                                  onPressed: TapFeedback.wrap(() => _repeat(context)),
                                ),
                                ?trailing,
                              ],
                            ),
                          ),
                        ),
                        Expanded(child: child),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
