import 'package:flutter/material.dart';

import '../models/document_photo.dart';
import '../theme/app_theme.dart';

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
  });

  final List<DocumentPhoto> pages;
  final bool open;
  final VoidCallback onToggle;

  /// 지울 페이지의 순번 (0부터)
  final ValueChanged<int> onRemove;

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
            // 버튼은 패널 아래 가장자리에 붙어 있어 패널과 함께 내려가고 올라간다
            _ToggleButton(count: pages.length, open: open, onToggle: onToggle),
          ],
        );
      },
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
    final radius = BorderRadius.circular(14);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        button: true,
        label: '업로드한 페이지 $count장, 목록 ${open ? '닫기' : '열기'}',
        excludeSemantics: true,
        child: Material(
          color: AppColors.surface.withValues(alpha: 0.96),
          elevation: 3,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: const BorderSide(color: AppColors.line),
          ),
          child: InkWell(
            onTap: onToggle,
            borderRadius: radius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 96),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(open ? Icons.expand_less : Icons.expand_more, color: AppColors.primary, size: 24),
                    const SizedBox(width: 6),
                    Text('$count장', style: const TextStyle(fontSize: 18, color: AppColors.text)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.pages, required this.maxHeight, required this.onRemove});

  final List<DocumentPhoto> pages;
  final double maxHeight;
  final ValueChanged<int> onRemove;

  static const _padding = 16.0;
  static const _gap = 10.0;
  static const _maxCardWidth = 170.0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        // 카메라 안내 글자가 비쳐 보이지 않게 불투명하게
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 18, offset: Offset(0, 6))],
      ),
      padding: const EdgeInsets.fromLTRB(_padding, _padding, _padding, _padding - 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(header: true, child: Text('업로드된 페이지', style: text.titleLarge)),
              ),
              _CountPill(count: pages.length),
            ],
          ),
          const SizedBox(height: 10),
          if (pages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '아직 찍은 페이지가 없어요. 문서를 한 장씩 찍어 주세요.',
                style: text.bodyLarge?.copyWith(color: AppColors.muted),
              ),
            )
          else
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 카드 높이 = 3:4 사진 + 아래 이름 줄. 너비가 바뀌어도 사진 비율이 유지되게 계산한다.
                  // 넓은 화면에서 카드가 패널보다 커지지 않게 너비 상한을 둔다
                  final cardWidth = ((constraints.maxWidth - _gap * 2) / 3).clamp(0.0, _maxCardWidth);
                  final photoHeight = (cardWidth - _PageCard.inset * 2) * 4 / 3;
                  final cardHeight = photoHeight + _PageCard.inset * 2 + _PageCard.footer;

                  // 카드가 적을 때 패널이 최대 높이까지 늘어나지 않고 카드 높이만큼만 차지하게 한다
                  return Align(
                    alignment: Alignment.topCenter,
                    heightFactor: 1,
                    child: SizedBox(
                      width: cardWidth * 3 + _gap * 2,
                      child: GridView.builder(
                        shrinkWrap: true,
                        itemCount: pages.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: _gap,
                          crossAxisSpacing: _gap,
                          mainAxisExtent: cardHeight,
                        ),
                        itemBuilder: (context, i) =>
                            _PageCard(page: pages[i], index: i, onRemove: () => onRemove(i)),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$count장', style: const TextStyle(fontSize: 17, color: AppColors.primary)),
    );
  }
}

/// 페이지 한 장. 사진, 순번, 지우기 버튼
class _PageCard extends StatelessWidget {
  const _PageCard({required this.page, required this.index, required this.onRemove});

  final DocumentPhoto page;
  final int index;
  final VoidCallback onRemove;

  static const inset = 8.0;
  static const footer = 40.0;

  @override
  Widget build(BuildContext context) {
    final label = '${index + 1}페이지';

    return Container(
      padding: const EdgeInsets.all(inset),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    page.bytes,
                    fit: BoxFit.cover,
                    semanticLabel: '$label 사진',
                    gaplessPlayback: true,
                  ),
                ),
                const Positioned(top: 6, right: 6, child: ExcludeSemantics(child: _CheckBadge())),
              ],
            ),
          ),
          SizedBox(
            height: footer,
            child: Row(
              children: [
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, color: AppColors.text),
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  tooltip: '$label 지우기',
                  icon: const Icon(Icons.delete_outline, size: 22),
                  color: AppColors.muted,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Icon(Icons.check, size: 14, color: Colors.white),
    );
  }
}
