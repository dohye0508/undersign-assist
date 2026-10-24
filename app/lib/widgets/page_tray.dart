import 'package:flutter/material.dart';

import '../models/document_photo.dart';
import '../theme/app_theme.dart';
import 'tap_feedback.dart';

/// 카메라 영역 맨 위에 붙는 업로드한 페이지 목록.
/// 평소에는 장수만 적힌 버튼 하나라 카메라를 가리지 않고, 누르면 위에서 패널이 내려온다.
/// 열림 여부는 부모가 쥔다 (읽기 결과 안내 등에서 함께 열고 닫을 수 있게).
class PageTray extends StatelessWidget {
  const PageTray({
    super.key,
    required this.pages,
    required this.open,
    required this.onToggle,
    required this.onRemove,
    this.trailing,
  });

  final List<DocumentPhoto> pages;
  final bool open;
  final VoidCallback onToggle;

  /// 지울 페이지의 순번 (0부터)
  final ValueChanged<int> onRemove;

  /// 페이지 목록 손잡이 바로 오른쪽에 나란히 매달리는 탭 (촬영 화면: 들리는 받아쓰기).
  /// 같은 모양으로 맞추려면 [PageTrayTab]을 쓴다
  final Widget? trailing;

  static const _duration = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Stack 안에서 위쪽만 고정하면 높이 제한이 없으므로 화면 높이를 기준으로 삼는다
        final available =
            constraints.maxHeight.isFinite ? constraints.maxHeight : MediaQuery.sizeOf(context).height;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 패널은 아래쪽부터 드러나도록 잘라서, 위에서 미끄러져 내려오는 것처럼 보이게 한다.
            // 다 닫히면 아예 빼서 화면 읽기 프로그램이 숨은 카드를 읽지 않게 한다
            TweenAnimationBuilder<double>(
              tween: Tween(end: open ? 1 : 0),
              duration: _duration,
              curve: Curves.easeOutCubic,
              child: _Panel(pages: pages, maxHeight: available * 0.6, onRemove: onRemove),
              builder: (context, t, child) {
                if (t == 0) return const SizedBox(width: double.infinity);
                return ClipRect(
                  child: Align(alignment: Alignment.bottomCenter, heightFactor: t, child: child),
                );
              },
            ),
            // 버튼은 패널 아래 가장자리에 붙어 있어 패널과 함께 내려가고 올라간다.
            // 옆 탭(받아쓰기)도 같은 줄에 나란히 매달린다
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ToggleButton(count: pages.length, open: open, onToggle: onToggle),
                if (trailing case final trailing?) ...[const SizedBox(width: 6), trailing],
              ],
            ),
          ],
        );
      },
    );
  }
}

/// 카메라 윗변에 매달린 손잡이 탭: 위는 평평하게 붙고 아래만 둥근 회색 탭.
/// 페이지 목록 손잡이와 그 옆 탭(받아쓰기)이 같은 모양을 쓴다
class PageTrayTab extends StatelessWidget {
  const PageTrayTab({
    super.key,
    required this.label,
    required this.semanticsLabel,
    required this.onTap,
    this.leadingIcon,
    this.trailingIcon,
    this.color = AppColors.textStrong,
  });

  final String label;

  /// 스크린리더가 읽을 이름
  final String semanticsLabel;
  final VoidCallback onTap;

  /// 글자 앞 작은 아이콘 (크기 18)
  final IconData? leadingIcon;

  /// 글자 뒤 아이콘 (크기 20, 목록 열기·닫기 화살표)
  final IconData? trailingIcon;

  /// 글자와 아이콘 색
  final Color color;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.vertical(bottom: Radius.circular(14));
    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Material(
        color: AppColors.grey100,
        borderRadius: radius,
        child: InkWell(
          onTap: TapFeedback.wrap(onTap),
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 96),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (leadingIcon case final icon?) ...[
                    Icon(icon, color: color, size: 18),
                    const SizedBox(width: 4),
                  ],
                  Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
                  if (trailingIcon case final icon?) ...[
                    const SizedBox(width: 4),
                    Icon(icon, color: color, size: 20),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({required this.count, required this.open, required this.onToggle});

  final int count;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    // 카메라 윗변에 붙은 손잡이: 끌어내리는 느낌
    return PageTrayTab(
      label: '찍은 페이지 $count장',
      semanticsLabel: '업로드한 페이지 $count장, 목록 ${open ? '닫기' : '열기'}',
      trailingIcon: open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
      onTap: onToggle,
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.pages, required this.maxHeight, required this.onRemove});

  final List<DocumentPhoto> pages;
  final double maxHeight;
  final ValueChanged<int> onRemove;

  static const _padding = 16.0;
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        // 카메라 안내 글자가 비쳐 보이지 않게 불투명하게
        color: AppColors.surface,
        // 카메라 윗변에 붙어 내려오므로 위는 평평하고 아래만 둥글다
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.card)),
      ),
      padding: const EdgeInsets.all(_padding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Semantics(header: true, child: Text('찍은 페이지 ${pages.length}장', style: text.titleMedium)),
              const Spacer(),
              Text('사진을 누르면 지워져요', style: text.bodySmall),
            ],
          ),
          const SizedBox(height: 12),
          if (pages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('아직 찍은 페이지가 없어요. 문서를 한 장씩 찍어 주세요.', style: text.bodyMedium),
            )
          else
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                itemCount: pages.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: _gap,
                  crossAxisSpacing: _gap,
                  childAspectRatio: 3 / 4,
                ),
                itemBuilder: (context, i) => _PageThumb(page: pages[i], index: i, onRemove: () => onRemove(i)),
              ),
            ),
        ],
      ),
    );
  }
}

/// 페이지 사진 한 장. 카드 없이 사진만, 왼쪽 위에 순번. 누르면 지운다
class _PageThumb extends StatelessWidget {
  const _PageThumb({required this.page, required this.index, required this.onRemove});

  final DocumentPhoto page;
  final int index;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(10);
    return Semantics(
      button: true,
      label: '${index + 1}페이지 사진. 누르면 지워요',
      excludeSemantics: true,
      child: Material(
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        color: AppColors.grey100,
        child: Ink.image(
          image: MemoryImage(page.bytes),
          fit: BoxFit.cover,
          child: InkWell(
            onTap: TapFeedback.wrap(onRemove),
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                margin: const EdgeInsets.all(6),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xCC191F28), borderRadius: BorderRadius.circular(6)),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
