import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 웹에서는 스크린리더용 의미 정보가 기본으로 꺼져 있어서 처음부터 켠다.
  SemanticsBinding.instance.ensureSemantics();
  runApp(const UndersignApp());
}
