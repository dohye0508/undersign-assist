/// 읽기 결과. 백엔드 `app/models.py`의 `RecognizedDocument`와 모양을 맞춘다.
/// 판단, 쓰기, 서명 단계가 이 결과를 이어받아 쓴다.
class RecognizedDocument {
  const RecognizedDocument({
    required this.docType,
    required this.fields,
    required this.blocks,
    required this.speech,
  });

  /// contract(계약서) / notice(가정통신문) / consent(개인정보 동의서) / unknown
  final String docType;
  final Map<String, String> fields;

  /// 글자와 위치 박스. 쓰기(칸 위치)와 서명(서명란 위치)에 쓴다
  final List<Map<String, dynamic>> blocks;
  final String speech;

  factory RecognizedDocument.fromJson(Map<String, dynamic> json) => RecognizedDocument(
        docType: json['doc_type'] as String? ?? 'unknown',
        fields: Map<String, String>.from(json['fields'] as Map? ?? {}),
        blocks: List<Map<String, dynamic>>.from(json['blocks'] as List? ?? []),
        speech: json['speech'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'doc_type': docType,
        'fields': fields,
        'blocks': blocks,
        'speech': speech,
      };
}
