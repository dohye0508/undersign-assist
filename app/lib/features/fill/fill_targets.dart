import 'dart:math' as math;

import '../../models/fill.dart';
import '../../models/recognized_document.dart';

/// 사용자가 채울 칸 이름. 이 이름 뒤에 ':'가 있고 그 뒤가 비어 있으면 쓸 칸이다
const fillFieldNames = ['전화번호', '생년월일', '연락처', '성명', '이름', '주소', '날짜'];

/// 칸 이름이지만 채울 칸은 아닌 것. 앞 칸의 내용과 다음 칸 이름을 가르는 데만 쓴다.
/// 대표자: 보통 상대방(사업주)이 인쇄해 두는 칸이라 쓸 칸으로 묻지 않는다. 뒤의 (서명)은 서명 칸으로 따로 잡힌다
const _otherLabels = [
  '사업자등록번호', '주민등록번호', '회사명', '업체명', '사업장', '대표자', '대표', '상호', '직위', '직책', //
  '소속', '관계', '학년', '학교', '이메일', '휴대폰', '기간', '금액', '일자', '담당자', '서명',
];

/// 줄 맨 앞이나 칸 이름 앞에 오는 주체. "학생 성명", "보호자 서명"처럼 어느 사람의 칸인지 말할 때 쓴다
const _owners = [
  '연대보증인', '법정대리인', '정보주체', '보호자', '학부모', '근로자', '사업주', '사용자', '고용주', '임대인', //
  '임차인', '매도인', '매수인', '신청인', '동의자', '수령인', '보증인', '대리인', '위임인', '수임인', '계약자',
  '세대주', '아버지', '어머니', '담임', '학생', '부모', '본인', '교사', '갑', '을',
];

final _knownNames = [...fillFieldNames, ..._otherLabels]..sort((a, b) => b.length.compareTo(a.length));
final _ownersLongFirst = [..._owners]..sort((a, b) => b.length.compareTo(a.length));

final _space = RegExp(r'\s');
final _mark = RegExp(r'서명|날인|\(인\)');

/// 본문 문장 속 "서명합니다" 같은 말은 서명란이 아니다 (signature_spots와 같은 기준)
final _sentence = RegExp(r'(서명|날인)(하|합|함|을|이|한|할|해)');

/// 칸 안에 있어도 내용이 아닌 것: 밑줄, 점선, 괄호, 서명 표시
final _notContent = RegExp(r'\((서명|날인|인|서명또는날인|서명또는인)\)|서명|날인|[_\-–—.·…ㆍ()\[\]/~]');

/// 읽기 결과에서 사용자가 채울 칸(이름, 주소, 서명 …)을 찾는다. 백엔드를 부르지 않는다.
///
/// - "성명:"처럼 칸 이름 + ':' 뒤가 비어 있으면 글씨 칸. 이미 인쇄된 내용("상호: 행복편의점")이 있으면 뺀다
/// - "서명", "(인)", "날인"은 서명 칸. 문장 속 "서명합니다"는 뺀다
/// - 이름은 칸 이름 앞의 주체 + 칸 이름 ("보호자 성명", "보호자 서명"). 주체를 모르면 줄 맨 앞 주체를 쓴다
/// 순서는 페이지, 위에서 아래, 왼쪽에서 오른쪽.
List<FillTarget> findFillTargets(RecognizedDocument doc) {
  final found = <_Found>[];
  for (final (i, block) in doc.blocks.indexed) {
    found.addAll(_scanLine(block, i, _pageSize(doc, block.page)));
  }
  found.sort((a, b) {
    if (a.page != b.page) return a.page.compareTo(b.page);
    final tolerance = math.min(a.lineHeight, b.lineHeight) * 0.5;
    if ((a.lineCenter - b.lineCenter).abs() > tolerance) return a.lineCenter.compareTo(b.lineCenter);
    return a.x.compareTo(b.x);
  });

  // 같은 페이지에 같은 이름이 또 있으면 "둘째 성명"처럼 구분한다
  const ordinals = ['둘째', '셋째', '넷째', '다섯째'];
  final seen = <String, int>{};
  final multiPage = doc.pages.length > 1;
  return [
    for (final f in found)
      () {
        final key = '${f.page}|${f.label}';
        final n = seen[key] = (seen[key] ?? 0) + 1;
        final name = n == 1 ? f.label : '${n - 2 < ordinals.length ? ordinals[n - 2] : '$n번째'} ${f.label}';
        return FillTarget(
          id: f.id,
          label: multiPage ? '${f.page + 1}페이지 $name' : name,
          page: f.page,
          rect: f.rect,
          isSignature: f.isSignature,
        );
      }(),
  ];
}

/// "써야 할 곳은 3곳이에요. 학생 성명, 보호자 성명, 보호자 서명."
String describeFillTargets(List<FillTarget> targets) {
  if (targets.isEmpty) return '써야 할 칸을 찾지 못했어요. 이름이나 서명 칸이 사진에 들어오게 다시 찍어 주세요.';
  return '써야 할 곳은 ${targets.length}곳이에요. ${targets.map((t) => t.label).join(', ')}.';
}

/// 받침이 있으면 [withBatchim], 없으면 [without] ("성명을" / "주소를", "성명이에요" / "주소예요")
String josa(String word, String withBatchim, String without) {
  if (word.isEmpty) return withBatchim;
  final code = word.codeUnitAt(word.length - 1);
  if (code < 0xAC00 || code > 0xD7A3) return withBatchim;
  return (code - 0xAC00) % 28 == 0 ? '$word$without' : '$word$withBatchim';
}

PageSize? _pageSize(RecognizedDocument doc, int page) {
  if (page < doc.pages.length) return doc.pages[page];
  if (page == 0 && doc.imageWidth > 0 && doc.imageHeight > 0) return PageSize(doc.imageWidth, doc.imageHeight);
  return null;
}

class _Found {
  _Found(this.id, this.label, this.page, this.rect, this.isSignature, this.lineCenter, this.lineHeight)
      : x = rect.x.toDouble();

  final String id, label;
  final int page;
  final Box rect;
  final bool isSignature;
  final double lineCenter, lineHeight, x;
}

/// 줄 안의 "칸 이름:" 하나 (공백을 지운 글자 기준 위치)
class _Label {
  _Label(this.start, this.colon, this.name, this.owner);

  /// 주체까지 포함한 시작 위치. 앞 칸 내용은 여기서 끝난다
  final int start;
  final int colon;
  final String name;
  final String? owner;
}

class _Mark {
  _Mark(this.start, this.end, this.thingStart);

  final int start, end;

  /// 앞 칸이 끝나는 곳. "(서명)"이면 여는 괄호
  final int thingStart;
}

bool _isHangul(String c) {
  final code = c.codeUnitAt(0);
  return code >= 0xAC00 && code <= 0xD7A3;
}

String? _ownerSuffix(String prefix) {
  for (final owner in _ownersLongFirst) {
    // 한 글자 주체(갑, 을)는 낱말 끝에 우연히 붙기 쉬워 통째로 같을 때만
    if (owner.length == 1 ? prefix == owner : prefix.endsWith(owner)) return owner;
  }
  return null;
}

List<_Found> _scanLine(TextBlock block, int line, PageSize? page) {
  final text = block.text.trim();
  if (text.isEmpty) return const [];

  // OCR 띄어쓰기는 믿기 어려워("성 명") 이름 찾기는 공백을 지운 글자로 하고, 위치는 원문 글자로 잰다
  final buf = StringBuffer();
  final orig = <int>[];
  for (var k = 0; k < text.length; k++) {
    if (_space.hasMatch(text[k])) continue;
    buf.write(text[k]);
    orig.add(k);
  }
  final compact = buf.toString();
  if (compact.isEmpty) return const [];
  final layout = _LineLayout(text, block.box);
  double xAt(int c) => c >= compact.length ? layout.xAt(text.length) : layout.xAt(orig[c]);
  double xEnd(int c) => layout.xAt(orig[c] + 1);

  // --- 칸 이름 ---
  final labels = <_Label>[];
  for (var colon = 0; colon < compact.length; colon++) {
    if (compact[colon] != ':' && compact[colon] != '：') continue;
    var runStart = colon;
    while (runStart > 0 && _isHangul(compact[runStart - 1])) {
      runStart--;
    }
    if (runStart == colon) continue; // "12:30" 같은 시간
    final run = compact.substring(runStart, colon);
    final known = _knownNames.where(run.endsWith).firstOrNull;
    int nameStart;
    if (known != null) {
      nameStart = colon - known.length;
    } else {
      // 모르는 칸 이름은 원문에서 ':' 앞 낱말까지로 본다
      var k = orig[colon] - 1;
      while (k >= 0 && !_space.hasMatch(text[k])) {
        k--;
      }
      nameStart = math.max(runStart, orig.indexWhere((o) => o > k));
    }
    final prefix = compact.substring(runStart, nameStart);
    String? owner;
    var start = nameStart;
    if (prefix.isNotEmpty) {
      final suffix = _ownerSuffix(prefix);
      if (suffix != null) {
        owner = suffix;
        start = nameStart - suffix.length;
      } else if (labels.isEmpty && prefix.length <= 6) {
        // 줄 첫 칸 앞이면 내용일 수 없으니 주체로 본다
        owner = prefix;
        start = runStart;
      }
      // 그 밖에는 앞 칸의 내용 (예: "상호: 행복편의점 대표자:"의 "행복편의점")
    }
    labels.add(_Label(start, colon, compact.substring(nameStart, colon), owner));
  }

  // --- 서명 표시 ---
  final sentenceLine = _sentence.hasMatch(compact);
  final marks = <_Mark>[];
  for (final m in _mark.allMatches(compact)) {
    final parenthesized = m.group(0) == '(인)' || (m.start > 0 && compact[m.start - 1] == '(');
    if (sentenceLine && !parenthesized) continue;
    // "서명:"은 칸 이름으로 다룬다
    if (m.end < compact.length && (compact[m.end] == ':' || compact[m.end] == '：')) continue;
    // "서명날인", "서명(인)"은 한 칸
    if (marks.isNotEmpty && m.start - marks.last.end <= 3) continue;
    marks.add(_Mark(m.start, m.end, parenthesized && m.group(0) != '(인)' ? m.start - 1 : m.start));
  }

  final lineOwner = (labels.isNotEmpty ? labels.first.owner : null) ??
      _ownersLongFirst.where((o) => o.length > 1 && compact.startsWith(o)).firstOrNull;

  final box = block.box;
  final h = box.height.toDouble();
  final cy = box.y + h / 2;
  final pageWidth = page?.width.toDouble() ?? double.infinity;
  final pageHeight = page?.height.toDouble() ?? double.infinity;

  Box toBox(double left, double top, double width, double height) {
    final l = left.clamp(0.0, math.max(0.0, pageWidth - width));
    final t = top.clamp(0.0, math.max(0.0, pageHeight - height));
    return Box(l.round(), t.round(), width.round(), height.round());
  }

  final found = <_Found>[];
  for (final (j, label) in labels.indexed) {
    final isSignature = label.name == '서명';
    if (!isSignature && !fillFieldNames.contains(label.name)) continue;
    // 칸은 다음 칸 이름이나 서명 표시 앞에서 끝난다
    var end = compact.length;
    if (j + 1 < labels.length) end = labels[j + 1].start;
    for (final mark in marks) {
      if (mark.thingStart > label.colon && mark.thingStart < end) {
        end = mark.thingStart;
        break;
      }
    }
    final content = compact.substring(label.colon + 1, end).replaceAll(_notContent, '');
    if (content.isNotEmpty) continue; // 이미 인쇄된 내용이 있다

    final left = xEnd(label.colon) + h * 0.25;
    final right = end < compact.length
        ? xAt(end) - h * 0.25
        : math.min(pageWidth, math.max((box.x + box.width).toDouble(), left + h * 6));
    final owner = label.owner ?? lineOwner;
    final name = owner == null ? label.name : '$owner ${label.name}';
    final id = 'p${block.page}-l$line-c${label.colon}-${label.name}';
    if (isSignature) {
      final height = h * 2;
      final width = (right - left).clamp(height * 1.3, height * 2.6);
      found.add(_Found(id, name, block.page, toBox(left, cy - height / 2, width, height), true, cy, h));
    } else {
      if (right - left < h * 1.2) continue; // 쓸 자리가 없다
      final height = h * 1.3;
      found.add(_Found(id, name, block.page, toBox(left, cy - height / 2, right - left, height), false, cy, h));
    }
  }

  for (final mark in marks) {
    // 서명 표시 바로 앞 칸의 주체 ("보호자 성명: (서명)" → 보호자 서명)
    final before = labels.where((l) => l.colon < mark.start).lastOrNull;
    final owner = before?.owner ?? (before != null && _owners.contains(before.name) ? before.name : null) ?? lineOwner;
    final cx = (xAt(mark.start) + xEnd(mark.end - 1)) / 2;
    final height = h * 2;
    final width = height * 2.6;
    found.add(_Found(
      'p${block.page}-l$line-c${mark.start}-서명표시',
      owner == null ? '서명' : '$owner 서명',
      block.page,
      toBox(cx - width / 2, cy - height / 2, width, height),
      true,
      cy,
      h,
    ));
  }
  return found;
}

/// OCR은 줄 상자만 주므로 글자마다 폭을 어림한다.
/// 한글은 줄 높이쯤, 숫자·영문·기호는 그보다 좁게 잡고, 남는 폭은 빈칸(공백)에 나눠 준다.
/// 공백이 없으면 ':' 뒤에 준다 (양식에서 빈칸은 보통 ':' 뒤다).
class _LineLayout {
  _LineLayout(String text, Box box) : _x = box.x.toDouble() {
    final h = box.height.toDouble();
    final widths = <double>[];
    final slots = <int>[];
    for (var k = 0; k < text.length; k++) {
      final c = text[k];
      if (_space.hasMatch(c)) {
        widths.add(h * 0.3);
        slots.add(k);
      } else if (_isHangul(c) || c.codeUnitAt(0) >= 0x3000) {
        widths.add(h * 0.9);
      } else if (RegExp(r'[0-9A-Za-z]').hasMatch(c)) {
        widths.add(h * 0.55);
      } else {
        widths.add(h * 0.35);
      }
    }
    // 빈칸은 보통 ':' 바로 뒤에 있다. ':' 뒤 공백(없으면 ':' 자체)에만 남는 폭을 준다.
    // 낱말 사이 공백("학생 성명")까지 나눠 주면 빈칸 자리가 엉뚱하게 잡힌다
    final afterColon = [
      for (final k in slots)
        if (RegExp(r'[:：]$').hasMatch(text.substring(0, k).trimRight())) k,
    ];
    if (afterColon.isNotEmpty) {
      slots
        ..clear()
        ..addAll(afterColon);
    } else {
      slots.clear();
      for (var k = 0; k < text.length; k++) {
        if (text[k] == ':' || text[k] == '：') slots.add(k);
      }
    }
    var total = widths.fold(0.0, (a, b) => a + b);
    // OCR이 빈칸 공백을 지워 글자만 남으면, 어림한 글자 폭만으로 상자가 꽉 차 빈칸이 0이 된다.
    // 인쇄 글자가 상자의 55%를 넘지 않게 줄여 빈칸 자리를 남긴다 (양식은 빈칸이 넓다)
    if (slots.isNotEmpty && total > box.width * 0.8) {
      final shrink = box.width * 0.55 / total;
      for (var k = 0; k < widths.length; k++) {
        widths[k] *= shrink;
      }
      total *= shrink;
    }
    final leftover = box.width - total;
    if (leftover > 0 && slots.isNotEmpty) {
      for (final k in slots) {
        widths[k] += leftover / slots.length;
      }
    } else if (total > 0) {
      final scale = box.width / total;
      for (var k = 0; k < widths.length; k++) {
        widths[k] *= scale;
      }
    }
    _prefix = [0.0];
    for (final w in widths) {
      _prefix.add(_prefix.last + w);
    }
  }

  final double _x;
  late final List<double> _prefix;

  /// [i]번째 글자의 왼쪽 끝 (i == 길이면 줄 끝)
  double xAt(int i) => _x + _prefix[i.clamp(0, _prefix.length - 1)];
}
