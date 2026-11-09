import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/widgets.dart';

/// 주변의 가로 여백만큼 배경을 넓히고, 세로 크기는 실제 내용 높이에 맞춘다.
class FullBleed extends StatelessWidget {
  const FullBleed({super.key, required this.inset, required this.child});

  final double inset;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) => OverflowBox(
      minWidth: constraints.maxWidth + inset * 2,
      maxWidth: constraints.maxWidth + inset * 2,
      fit: OverflowBoxFit.deferToChild,
      child: child,
    ),
  );
}
