/// 판단 결과. 백엔드 `app/routers/judge.py`의 `Judgement`와 모양을 맞춘다.
class Judgement {
  const Judgement({
    required this.findings,
    required this.speech,
    required this.subtype,
    required this.counts,
    required this.questions,
    required this.disclaimer,
  });

  final List<Finding> findings;

  /// 처음에 읽어줄 요약 (심각한 것부터 최대 3개)
  final String speech;

  /// 세부 문서 종류 (예: labor_part_time)
  final String subtype;

  /// 종류별 개수 (caution, missing, info)
  final Map<String, int> counts;

  /// 문서만으로 알 수 없어 사용자에게 물어야 할 것
  final List<String> questions;
  final String disclaimer;

  factory Judgement.fromJson(Map<String, dynamic> json) => Judgement(
        findings: [for (final f in json['findings'] as List? ?? []) Finding.fromJson(f)],
        speech: json['speech'] as String? ?? '',
        subtype: json['subtype'] as String? ?? '',
        counts: Map<String, int>.from(json['counts'] as Map? ?? {}),
        questions: [for (final q in json['questions'] as List? ?? []) (q as Map)['text'] as String],
        disclaimer: json['disclaimer'] as String? ?? '',
      );
}

class Finding {
  const Finding({
    required this.level,
    required this.item,
    required this.reason,
    required this.evidence,
    required this.severity,
    required this.line,
    required this.speech,
    required this.basis,
  });

  /// ok / missing / caution / info
  final String level;
  final String item;

  /// 비교한 기준 (예: "문서 값 9,000 / 2026년 기준 10,320")
  final String reason;

  /// 문서 원문 줄
  final String evidence;

  /// critical / high / medium / info
  final String severity;

  /// 읽기 결과 blocks에서 몇 번째 줄인지. 없으면 -1
  final int line;

  /// 이 결과 하나를 읽어줄 문장
  final String speech;

  /// 근거 법 조항
  final List<LawRef> basis;

  factory Finding.fromJson(Map<String, dynamic> json) => Finding(
        level: json['level'] as String? ?? 'info',
        item: json['item'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        evidence: json['evidence'] as String? ?? '',
        severity: json['severity'] as String? ?? 'info',
        line: json['line'] as int? ?? -1,
        speech: json['speech'] as String? ?? '',
        basis: [for (final b in json['basis'] as List? ?? []) LawRef.fromJson(b)],
      );
}

class LawRef {
  const LawRef({required this.lawName, required this.articleNo, required this.title, required this.excerpt});

  final String lawName;
  final String articleNo;
  final String title;

  /// 해당 항 원문 한 문단
  final String excerpt;

  String get label => '$lawName $articleNo'.trim();

  factory LawRef.fromJson(Map<String, dynamic> json) => LawRef(
        lawName: json['law_name'] as String? ?? '',
        articleNo: json['article_no'] as String? ?? '',
        title: json['title'] as String? ?? '',
        excerpt: json['excerpt'] as String? ?? '',
      );
}
