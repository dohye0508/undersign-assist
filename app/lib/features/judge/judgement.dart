/// 판단 결과 모양. 백엔드 `routers/judge.py`의 Judgement와 맞춘다.
/// 판단 단계에서만 쓰므로 공유 `models/`가 아니라 이 폴더에 둔다.
class LawRef {
  const LawRef({this.lawName = '', this.articleNo = '', this.title = '', this.excerpt = '', this.url = ''});

  final String lawName, articleNo, title, excerpt, url;

  factory LawRef.fromJson(Map<String, dynamic> j) => LawRef(
        lawName: j['law_name'] as String? ?? '',
        articleNo: j['article_no'] as String? ?? '',
        title: j['title'] as String? ?? '',
        excerpt: j['excerpt'] as String? ?? '',
        url: j['url'] as String? ?? '',
      );
}

class Finding {
  const Finding({
    required this.level,
    required this.item,
    this.reason = '',
    this.evidence = '',
    this.ruleId = '',
    this.severity = 'info',
    this.line = -1,
    this.speech = '',
    this.basis = const [],
  });

  final String level; // ok / missing / caution / info
  final String item, reason, evidence, ruleId, severity, speech;
  final int line;
  final List<LawRef> basis;

  factory Finding.fromJson(Map<String, dynamic> j) => Finding(
        level: j['level'] as String? ?? 'info',
        item: j['item'] as String? ?? '',
        reason: j['reason'] as String? ?? '',
        evidence: j['evidence'] as String? ?? '',
        ruleId: j['rule_id'] as String? ?? '',
        severity: j['severity'] as String? ?? 'info',
        line: j['line'] as int? ?? -1,
        speech: j['speech'] as String? ?? '',
        basis: [for (final b in (j['basis'] as List? ?? const [])) LawRef.fromJson(b as Map<String, dynamic>)],
      );
}

class Question {
  const Question({required this.id, required this.text, this.options = const {}});

  final String id, text;
  final Map<String, String> options;

  factory Question.fromJson(Map<String, dynamic> j) => Question(
        id: j['id'] as String,
        text: j['text'] as String? ?? '',
        options: {for (final e in (j['options'] as Map? ?? const {}).entries) e.key as String: e.value as String},
      );
}

class Judgement {
  const Judgement({
    required this.findings,
    required this.speech,
    this.subtype = '',
    this.questions = const [],
    this.disclaimer = '',
  });

  final List<Finding> findings;
  final String speech, subtype, disclaimer;
  final List<Question> questions;

  factory Judgement.fromJson(Map<String, dynamic> j) => Judgement(
        findings: [for (final f in (j['findings'] as List? ?? const [])) Finding.fromJson(f as Map<String, dynamic>)],
        speech: j['speech'] as String? ?? '',
        subtype: j['subtype'] as String? ?? '',
        questions: [for (final q in (j['questions'] as List? ?? const [])) Question.fromJson(q as Map<String, dynamic>)],
        disclaimer: j['disclaimer'] as String? ?? '',
      );
}
