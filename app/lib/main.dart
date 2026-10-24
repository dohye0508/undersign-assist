import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'app.dart';
import 'features/settings/device_settings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 웹에서는 스크린리더용 의미 정보가 기본으로 꺼져 있어서 처음부터 켠다.
  SemanticsBinding.instance.ensureSemantics();
  // 이 기기에 저장된 설정(말하기 속도, 소리 크기, 진동)을 음성과 효과음에 먼저 적용한다
  applyAppSettings();
  runApp(const UndersignApp());
}
