/// 읽기 결과. 백엔드 `app/models.py`의 `RecognizedDocument`와 모양을 맞춘다.
/// 판단, 쓰기, 서명 단계가 이 결과를 이어받아 쓴다.
class RecognizedDocument {
  const RecognizedDocument({
    required this.docType,
    required this.docTypeLabel,
    required this.blocks,
    required this.fields,
    required this.fullText,
    required this.imageWidth,
    required this.imageHeight,
    required this.pages,
    required this.reader,
    required this.speech,
  });

  /// contract(계약서) / notice(가정통신문) / consent(개인정보 동의서) / application(신청서) / summary(요약서) / unknown
  final String docType;
  final String docTypeLabel;
  final List<TextBlock> blocks;
  final List<DocField> fields;
  final String fullText;
  final int imageWidth;
  final int imageHeight;

  /// 페이지마다 사진 크기. 페이지 수는 pages.length
  final List<PageSize> pages;

  /// 항목을 정리한 방식: "ai"(Groq) 또는 "rules"(규칙 파일)
  final String reader;

  /// 사용자에게 읽어줄 요약
  final String speech;

  bool get isUnknown => docType == 'unknown';

  factory RecognizedDocument.fromJson(Map<String, dynamic> json) => RecognizedDocument(
        docType: json['doc_type'] as String? ?? 'unknown',
        docTypeLabel: json['doc_type_label'] as String? ?? '알 수 없는 문서',
        blocks: [for (final b in json['blocks'] as List? ?? []) TextBlock.fromJson(b)],
        fields: [for (final f in json['fields'] as List? ?? []) DocField.fromJson(f)],
        fullText: json['full_text'] as String? ?? '',
        imageWidth: json['image_width'] as int? ?? 0,
        imageHeight: json['image_height'] as int? ?? 0,
        pages: [for (final p in json['pages'] as List? ?? []) PageSize.fromJson(p)],
        reader: json['reader'] as String? ?? 'rules',
        speech: json['speech'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'doc_type': docType,
        'doc_type_label': docTypeLabel,
        'blocks': [for (final b in blocks) b.toJson()],
        'fields': [for (final f in fields) f.toJson()],
        'full_text': fullText,
        'image_width': imageWidth,
        'image_height': imageHeight,
        'pages': [for (final p in pages) p.toJson()],
        'reader': reader,
        'speech': speech,
      };
}

/// 사진 픽셀 좌표의 상자 (왼쪽 위가 0, 0)
class Box {
  const Box(this.x, this.y, this.width, this.height);

  final int x, y, width, height;

  factory Box.fromJson(Map<String, dynamic> json) =>
      Box(json['x'] as int, json['y'] as int, json['width'] as int, json['height'] as int);

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'width': width, 'height': height};
}

/// 한 줄의 글자와 위치
class TextBlock {
  const TextBlock(this.text, this.box, [this.page = 0]);

  final String text;

  /// [page]번째 페이지 사진의 좌표
  final Box box;

  /// 몇 번째 페이지의 줄인지 (0부터)
  final int page;

  factory TextBlock.fromJson(Map<String, dynamic> json) => TextBlock(
        json['text'] as String,
        Box.fromJson(json['box'] as Map<String, dynamic>),
        json['page'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {'text': text, 'box': box.toJson(), 'page': page};
}

/// 페이지 사진 크기 (백엔드가 방향을 바로잡은 뒤)
class PageSize {
  const PageSize(this.width, this.height);

  final int width, height;

  factory PageSize.fromJson(Map<String, dynamic> json) => PageSize(json['width'] as int, json['height'] as int);

  Map<String, dynamic> toJson() => {'width': width, 'height': height};
}

/// 문서에서 찾은 항목 (예: 임금 → 시간급 9,000원)
class DocField {
  const DocField(this.label, this.value, this.line);

  final String label;
  final String value;

  /// [RecognizedDocument.blocks]에서 몇 번째 줄인지
  final int line;

  factory DocField.fromJson(Map<String, dynamic> json) =>
      DocField(json['label'] as String, json['value'] as String, json['line'] as int);

  Map<String, dynamic> toJson() => {'label': label, 'value': value, 'line': line};
}
