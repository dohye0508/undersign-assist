import 'dart:async';

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
  WorkspaceState({
    Future<RecognizedDocument> Function(List<DocumentPhoto>)? readDocument,
    Future<Judgement> Function(RecognizedDocument, Map<String, String>)?
    judgeDocument,
  }) : _readDocument = readDocument ?? ApiClient.read,
       _judgeDocument =
           judgeDocument ??
           ((document, answers) => ApiClient.judge(document, answers: answers));

  final Future<RecognizedDocument> Function(List<DocumentPhoto>) _readDocument;
  final Future<Judgement> Function(RecognizedDocument, Map<String, String>)
  _judgeDocument;

  // A request may finish after photos or answers change. Only the matching
  // revision may update state; duplicate calls share that revision's request.
  int _readRevision = 0;
  int _judgeRevision = 0;
  Future<RecognizedDocument?>? _pendingRead;
  Future<Judgement?>? _pendingJudge;
  bool _disposed = false;
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

  /// 사용자가 딱 한 번 그린 체크 표시(✓). 동의 칸마다 이걸 그대로 넣는다.
  /// 그린 획을 화면 좌표(0~1로 정규화)로 저장해 어떤 칸 크기에도 맞출 수 있게 한다.
  /// 문서가 바뀌어도 내 ✓는 같으므로 [_resetAnalysis]에서 지우지 않는다
  List<List<List<double>>>? _checkMark;
  List<List<List<double>>>? get checkMark => _checkMark;

  /// [strokes]: 획마다 [x, y, pressure] 점 목록. x, y는 0~1
  void setCheckMark(List<List<List<double>>> strokes) {
    _checkMark = strokes;
    notifyListeners();
  }

  void clearCheckMark() {
    _checkMark = null;
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
    _readRevision++;
    _judgeRevision++;
    _pendingRead = null;
    _pendingJudge = null;
    _reading = false;
    _judging = false;
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
  Future<RecognizedDocument?> read() {
    if (_disposed || _pages.isEmpty) return Future.value(null);
    if (_recognized != null) return Future.value(_recognized);
    if (_pendingRead != null) return _pendingRead!;
    final revision = _readRevision;
    final snapshot = List<DocumentPhoto>.unmodifiable(_pages);
    final completion = Completer<RecognizedDocument?>();
    _pendingRead = completion.future;
    _reading = true;
    _readError = null;
    notifyListeners();
    unawaited(_performRead(snapshot, revision, completion));
    return completion.future;
  }

  Future<void> _performRead(
    List<DocumentPhoto> snapshot,
    int revision,
    Completer<RecognizedDocument?> completion,
  ) async {
    RecognizedDocument? result;
    try {
      final document = await _readDocument(snapshot);
      if (!_disposed && revision == _readRevision) {
        _recognized = document;
        result = document;
      }
    } catch (error) {
      if (!_disposed && revision == _readRevision) {
        _readError = error is ApiException
            ? error.message
            : '문서를 읽지 못했어요. 잠시 후 다시 시도해 주세요.';
      }
    } finally {
      if (!_disposed && revision == _readRevision) {
        _reading = false;
        _pendingRead = null;
        notifyListeners();
      }
      completion.complete(result);
    }
  }

  /// 판단 질문(예: 사업장 인원)에 사용자가 고른 답. 질문 id → 답 코드
  final Map<String, String> _answers = {};
  Map<String, String> get answers => Map.unmodifiable(_answers);

  /// 질문에 답하고 그 답으로 다시 판단한다
  Future<Judgement?> answer(String questionId, String option) {
    if (_disposed || _recognized == null) return Future.value(null);
    if (_answers[questionId] == option) return judge();
    _answers[questionId] = option;
    _judgeRevision++;
    _pendingJudge = null;
    _judging = false;
    _judgement = null;
    _judgeError = null;
    return judge();
  }

  /// 읽기 결과를 규칙 엔진으로 판단한다. 같은 문서·같은 답이면 한 번만 판단한다
  Future<Judgement?> judge() {
    final document = _recognized;
    if (_disposed || document == null) return Future.value(null);
    if (document.needsReview) {
      _judgeError = document.speech;
      notifyListeners();
      return Future.value(null);
    }
    if (_judgement != null) return Future.value(_judgement);
    if (_pendingJudge != null) return _pendingJudge!;
    final revision = _judgeRevision;
    final snapshot = Map<String, String>.unmodifiable(_answers);
    final completion = Completer<Judgement?>();
    _pendingJudge = completion.future;
    _judging = true;
    _judgeError = null;
    notifyListeners();
    unawaited(_performJudge(document, snapshot, revision, completion));
    return completion.future;
  }

  Future<void> _performJudge(
    RecognizedDocument document,
    Map<String, String> answers,
    int revision,
    Completer<Judgement?> completion,
  ) async {
    Judgement? result;
    try {
      final judgement = await _judgeDocument(document, answers);
      if (!_disposed && revision == _judgeRevision) {
        _judgement = judgement;
        result = judgement;
      }
    } catch (error) {
      if (!_disposed && revision == _judgeRevision) {
        _judgeError = error is ApiException
            ? error.message
            : '판단하지 못했어요. 잠시 후 다시 시도해 주세요.';
      }
    } finally {
      if (!_disposed && revision == _judgeRevision) {
        _judging = false;
        _pendingJudge = null;
        notifyListeners();
      }
      completion.complete(result);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _resetAnalysis();
    super.dispose();
  }
}
