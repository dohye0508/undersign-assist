import 'package:flutter/material.dart';

import '../../models/fill.dart';
import 'fill_kind.dart';
import 'fill_targets.dart';

/// Keep completed/other-field previews in the same inset as placement and PDF.
class FilledInkPreview extends StatelessWidget {
  const FilledInkPreview({super.key, required this.fill});

  final FilledInk fill;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final isText = fill.target.kind == FillKind.text;
      final area = Rect.fromLTWH(
        0,
        0,
        constraints.maxWidth,
        constraints.maxHeight,
      );
      final inset = isText ? fillTextInset(area).left : 0.0;
      return Padding(
        padding: EdgeInsets.only(left: inset),
        child: Image.memory(
          fill.png,
          fit: BoxFit.contain,
          alignment: isText ? Alignment.centerLeft : Alignment.center,
          gaplessPlayback: true,
        ),
      );
    },
  );
}
