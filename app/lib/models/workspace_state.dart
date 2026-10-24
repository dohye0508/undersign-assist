import 'package:flutter/foundation.dart';

import '../services/api_client.dart';
import 'document_photo.dart';
import 'recognized_document.dart';

/// 네 단계. 순서가 실제 사용 순서다 (판단 없이 서명하지 않도록 판단이 서명보다 앞).
enum WorkStep {
  read('읽기', '문서를 읽어드려요'),
  judge('판단', '빠진 것, 확인할 것'),
  write('쓰기', '쓴 글씨 확인'),
  sign('서명', '서명란 안내');

  const WorkStep(this.label, this.summary);

  final String label;
  final String summary;
}

/// 한 화면 전체가 함께 보는 상태: 지금 다루는 문서 사진, 읽기 결과, 선택한 단계.
class WorkspaceState extends ChangeNotifier {
  DocumentPhoto? _photo;
  DocumentPhoto? get photo => _photo;

  RecognizedDocument? _recognized;
  RecognizedDocument? get recognized => _recognized;

  WorkStep _step = WorkStep.read;
  WorkStep get step => _step;

  bool _reading = false;
  bool get reading => _reading;

  String? _readError;
  String? get readError => _readError;

  bool get hasPhoto => _photo != null;

  /// 새 사진을 받으면 이전 결과를 지우고 바로 읽는다.
  /// 화면을 보지 않는 사용자가 "읽기"를 따로 찾아 누르지 않아도 되게 하기 위해서다.
  Future<RecognizedDocument?> setPhoto(DocumentPhoto photo) async {
    _photo = photo;
    _recognized = null;
    _step = WorkStep.read;
    notifyListeners();
    return read();
  }

  /// 사진을 버리고 카메라로 돌아간다.
  void clearPhoto() {
    _photo = null;
    _recognized = null;
    _readError = null;
    _step = WorkStep.read;
    notifyListeners();
  }

  Future<RecognizedDocument?> read() async {
    final photo = _photo;
    if (photo == null) return null;
    _reading = true;
    _readError = null;
    notifyListeners();
    try {
      _recognized = await ApiClient.read(photo);
    } catch (_) {
      _readError = '문서를 읽지 못했어요. 서버가 켜져 있는지 확인하고 다시 시도해 주세요.';
    }
    _reading = false;
    notifyListeners();
    return _recognized;
  }

  void selectStep(WorkStep step) {
    _step = step;
    notifyListeners();
  }
}
