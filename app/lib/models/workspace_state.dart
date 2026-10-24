import 'package:flutter/foundation.dart';

import '../services/api_client.dart';
import 'document_photo.dart';
import 'fill.dart';
import 'judgement.dart';
import 'recognized_document.dart';

/// 네 단계. 코드에서는 읽기·판단·쓰기·서명으로 나누지만,
/// 사용자에게는 [label]처럼 하는 일을 쉬운 말로 보여준다.
enum WorkStep {
  read('문서 읽기', '어떤 문서인지와 중요한 내용을 읽어드려요'),
  judge('검토하세요!', '빠지거나 확인할 내용을 근거와 함께 알려드려요'),
  // 쓰기와 서명은 하는 일이 같아서(패드에 쓰면 문서 자리로 들어감) 한 단계로 합쳤다
  fill('쓰고 서명하기', '써야 할 칸을 하나씩 알려드려요. 화면 가득 쓰고 왼쪽으로 밀면 문서 자리로 들어가요');

  const WorkStep(this.label, this.guide);

  final String label;

  /// 단계를 고를 때 들려주는 안내
  final String guide;
}

/// 화면 전체가 함께 보는 상태.
///   1. 업로드: 페이지 사진을 차례로 모은다 ([pages])
///   2. 분석: 모든 페이지를 한 문서로 읽고([recognized]) 규칙으로 판단한다([judgement])
///   3. 쓰고 서명하기: 칸마다 패드에 쓴 글씨를 받는다 ([fills])
///   4. 출력: 페이지 사진에 글씨를 합성해 PDF로 (features/output)
class WorkspaceState extends ChangeNotifier {
  final List<DocumentPhoto> _pages = [];
  List<DocumentPhoto> get pages => List.unmodifiable(_pages);
  bool get hasPages => _pages.isNotEmpty;

  RecognizedDocument? _recognized;
  RecognizedDocument? get recognized => _recognized;

  bool _reading = false;
  bool get reading => _reading;

  String? _readError;
  String? get readError => _readError;

  Judgement? _judgement;
  Judgement? get judgement => _judgement;

  bool _judging = false;
  bool get judging => _judging;

  String? _judgeError;
  String? get judgeError => _judgeError;

  /// 칸(FillTarget.id)마다 패드에 쓴 글씨. 쓰기와 서명을 함께 담는다
  final Map<String, FilledInk> _fills = {};
  Map<String, FilledInk> get fills => Map.unmodifiable(_fills);

  void setFill(FilledInk ink) {
    _fills[ink.target.id] = ink;
    notifyListeners();
  }

  void removeFill(String id) {
    _fills.remove(id);
    notifyListeners();
  }

  /// (이전 방식, 정리 예정) 서명란 줄 번호마다 서명
  final Map<int, Uint8List> _signatures = {};
  Map<int, Uint8List> get signatures => Map.unmodifiable(_signatures);

  void setSignature(int line, Uint8List png) {
    _signatures[line] = png;
    notifyListeners();
  }

  /// 페이지(0부터)마다 패드에 쓴 글씨. 페이지 사진과 같은 크기의 투명 배경 PNG.
  /// 분석하면 페이지가 노트에 올라가고, 사용자가 그 위에 직접 쓴다 (features/write)
  final Map<int, Uint8List> _notes = {};
  Map<int, Uint8List> get notes => Map.unmodifiable(_notes);

  void setNote(int page, Uint8List png) {
    _notes[page] = png;
    notifyListeners();
  }

  void clearNote(int page) {
    _notes.remove(page);
    notifyListeners();
  }

  // --- 1. 업로드 -------------------------------------------------------------

  void addPage(DocumentPhoto photo) {
    _pages.add(photo);
    _resetAnalysis();
    notifyListeners();
  }

  void removePage(int index) {
    _pages.removeAt(index);
    _resetAnalysis();
    notifyListeners();
  }

  void clearPages() {
    _pages.clear();
    _resetAnalysis();
    notifyListeners();
  }

  /// 페이지가 바뀌면 이전 분석과 서명은 맞지 않으므로 지운다
  void _resetAnalysis() {
    _recognized = null;
    _readError = null;
    _judgement = null;
    _judgeError = null;
    _answers.clear();
    _signatures.clear();
    _notes.clear();
    _fills.clear();
  }

  // --- 2. 분석 ---------------------------------------------------------------

  /// 모든 페이지를 한 문서로 읽는다. 이미 읽었으면 다시 부르지 않는다
  Future<RecognizedDocument?> read() async {
    if (_pages.isEmpty) return null;
    if (_recognized != null) return _recognized;
    _reading = true;
    _readError = null;
    notifyListeners();
    try {
      _recognized = await ApiClient.read(_pages);
    } catch (_) {
      _readError = '문서를 읽지 못했어요. 서버가 켜져 있는지 확인하고 다시 시도해 주세요.';
    }
    _reading = false;
    notifyListeners();
    return _recognized;
  }

  /// 판단 질문(예: 사업장 인원)에 사용자가 고른 답. 질문 id → 답 코드
  final Map<String, String> _answers = {};
  Map<String, String> get answers => Map.unmodifiable(_answers);

  /// 질문에 답하고 그 답으로 다시 판단한다
  Future<Judgement?> answer(String questionId, String option) {
    _answers[questionId] = option;
    _judgement = null;
    return judge();
  }

  /// 읽기 결과를 규칙 엔진으로 판단한다. 같은 문서·같은 답이면 한 번만 판단한다
  Future<Judgement?> judge() async {
    final document = _recognized;
    if (document == null) return null;
    if (_judgement != null) return _judgement;
    _judging = true;
    _judgeError = null;
    notifyListeners();
    try {
      _judgement = await ApiClient.judge(document, answers: _answers);
    } catch (_) {
      _judgeError = '판단하지 못했어요. 서버가 켜져 있는지 확인하고 다시 시도해 주세요.';
    }
    _judging = false;
    notifyListeners();
    return _judgement;
  }
}
