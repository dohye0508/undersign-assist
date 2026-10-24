import 'package:flutter/foundation.dart';

import '../services/api_client.dart';
import 'document_photo.dart';
import 'judgement.dart';
import 'recognized_document.dart';

/// 네 단계. 코드에서는 읽기·판단·쓰기·서명으로 나누지만,
/// 사용자에게는 [label]처럼 하는 일을 쉬운 말로 보여준다.
enum WorkStep {
  read('문서 읽기', '찍으면 어떤 문서인지와 중요한 내용을 읽어드려요'),
  judge('검토하세요!', '빠지거나 확인할 내용을 근거와 함께 알려드려요'),
  write('쓴 글씨 확인', '칸을 고르고, 종이에 쓴 다음 확인을 누르면 무엇을 썼는지 읽어드려요'),
  sign('서명 위치', '어디에 서명하는지 알려드려요');

  const WorkStep(this.label, this.guide);

  final String label;

  /// 모드를 고를 때 들려주는 안내
  final String guide;
}

/// 한 화면 전체가 함께 보는 상태: 고른 모드, 찍은 사진, 읽기 결과, 결과 창 표시 여부.
class WorkspaceState extends ChangeNotifier {
  WorkStep _step = WorkStep.read;
  WorkStep get step => _step;

  DocumentPhoto? _photo;
  DocumentPhoto? get photo => _photo;

  RecognizedDocument? _recognized;
  RecognizedDocument? get recognized => _recognized;

  bool _reading = false;
  bool get reading => _reading;

  String? _readError;
  String? get readError => _readError;

  bool get hasPhoto => _photo != null;

  Judgement? _judgement;
  Judgement? get judgement => _judgement;

  bool _judging = false;
  bool get judging => _judging;

  String? _judgeError;
  String? get judgeError => _judgeError;

  /// 패드에 한 서명 (투명 배경 PNG). 다음 작업인 PDF 합성에서 쓴다
  Uint8List? _signaturePng;
  Uint8List? get signaturePng => _signaturePng;

  set signaturePng(Uint8List? value) {
    _signaturePng = value;
    notifyListeners();
  }

  void selectStep(WorkStep step) {
    _step = step;
    notifyListeners();
  }

  /// 새 문서 사진을 받으면 이전 결과를 지우고 바로 읽는다.
  /// 판단, 쓰기, 서명 모두 읽기 결과(글자와 위치)를 바탕으로 하기 때문이다.
  Future<RecognizedDocument?> setPhoto(DocumentPhoto photo) async {
    _photo = photo;
    _recognized = null;
    _judgement = null;
    _judgeError = null;
    _signaturePng = null;
    notifyListeners();
    return read();
  }

  /// 결과 창을 닫고 카메라로 돌아간다.
  void clearPhoto() {
    _photo = null;
    _readError = null;
    notifyListeners();
  }

  /// 읽기 결과를 규칙 엔진으로 판단한다. 같은 문서는 한 번만 판단한다
  Future<Judgement?> judge() async {
    final document = _recognized;
    if (document == null) return null;
    if (_judgement != null) return _judgement;
    _judging = true;
    _judgeError = null;
    notifyListeners();
    try {
      _judgement = await ApiClient.judge(document);
    } catch (_) {
      _judgeError = '판단하지 못했어요. 서버가 켜져 있는지 확인하고 다시 시도해 주세요.';
    }
    _judging = false;
    notifyListeners();
    return _judgement;
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
}
