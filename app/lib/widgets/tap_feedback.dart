import 'package:flutter/widgets.dart';

import '../services/haptics.dart';

/// 모든 버튼의 onPressed를 이걸로 감싼다. 눌리면 짧은 진동과 딸깍 소리가 난 뒤 원래 동작을 한다.
/// 시각장애인은 화면 대신 이 반응으로 버튼이 눌렸는지 안다.
class TapFeedback {
  TapFeedback._();

  static VoidCallback? wrap(VoidCallback? onPressed) {
    if (onPressed == null) return null;
    return () {
      Haptics.tap();
      onPressed();
    };
  }

  /// 값 하나를 받는 콜백용 (예: 선택지 버튼)
  static ValueChanged<T>? wrapValue<T>(ValueChanged<T>? onChanged) {
    if (onChanged == null) return null;
    return (value) {
      Haptics.tap();
      onChanged(value);
    };
  }
}
