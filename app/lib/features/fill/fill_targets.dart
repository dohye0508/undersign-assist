import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import '../../models/fill.dart';
import '../../models/recognized_document.dart';
import 'fill_kind.dart';

/// 사용자가 채울 칸 이름. 이 이름 뒤에 ':'가 있고 그 뒤가 비어 있으면 쓸 칸이다
const fillFieldNames = ['전화번호', '생년월일', '연락처', '접수번호', '성명', '이름', '주소', '날짜'];

/// 칸 이름이지만 채울 칸은 아닌 것. 앞 칸의 내용과 다음 칸 이름을 가르는 데만 쓴다.
/// 대표자: 보통 상대방(사업주)이 인쇄해 두는 칸이라 쓸 칸으로 묻지 않는다. 뒤의 (서명)은 서명 칸으로 따로 잡힌다.
/// 관리번호: 학교·기관이 쓰는 칸("기재하지 않음")이라 묻지 않는다
const _otherLabels = [
  '사업자등록번호', '주민등록번호', '관리번호', '회사명', '업체명', '사업장', '대표자', '대표', '상호', '직위', '직책', //
  '소속', '관계', '학년', '학교', '이메일', '휴대폰', '기간', '금액', '일자', '담당자', '서명',
];

/// 줄 맨 앞이나 칸 이름 앞에 오는 주체. "학생 성명", "보호자 서명"처럼 어느 사람의 칸인지 말할 때 쓴다.
/// "지원자 ： (인 또는 서명)"처럼 주체만 있고 칸 이름이 없으면 그 주체의 성명 칸으로 본다
const _owners = [
  '연대보증인', '법정대리인', '정보주체', '피보험자', '보호자', '학부모', '근로자', '사업주', '사용자', '고용주', //
  '임대인', '임차인', '매도인', '매수인', '신청인', '신청자', '지원자', '응시자', '참가자', '동의자', '수령인',
  '보증인', '대리인', '위임인', '수임인', '계약자', '세대주', '아버지', '어머니', '담임', '학생', '부모', '본인',
  '교사', '환자', '갑', '을',
];

final _knownNames = [...fillFieldNames, ..._otherLabels]..sort((a, b) => b.length.compareTo(a.length));
final _ownersLongFirst = [..._owners]..sort((a, b) => b.length.compareTo(a.length));

final _space = RegExp(r'\s');

/// 서명 표시. "(인 또는 서명)", "(서명/인)"처럼 괄호 안에 둘이 같이 있으면 한 표시로 본다
final _mark = RegExp(r'\((?:인|서명|날인)(?:또는|/|·|,)?(?:인|서명|날인)?\)|서명|날인');

/// 본문 문장 속 "서명합니다" 같은 말은 서명란이 아니다 (signature_spots와 같은 기준).
/// 괄호로 감싼 "(인 또는 서명)"은 문장 줄에 있어도 서명란이다
final _sentence = RegExp(r'(서명|날인)(하|합|함|을|이|한|할|해)');

/// 칸 안에 있어도 내용이 아닌 것: 밑줄, 점선, 괄호, 서명 표시
final _notContent = RegExp(r'\((?:인|서명|날인)(?:또는|/|·|,)?(?:인|서명|날인)?\)|서명|날인|[_\-–—.·…ㆍ()\[\]/~]');

/// 체크 상자로 읽히는 글자. OCR은 □를 ㅁ, 口, 디로 자주 읽는다
const _boxChars = 'ㅁ□口디■☐▢▣';

/// "동의하십니까" (OCR은 동→통으로 자주 읽는다)
final _consentQuestion = RegExp(r'[동통]의하(십니까|시겠습니까|시나요|세요|는지|십니|시는|십)');

/// "□예 □아니요"도 "예 □ 아니요 □"도. 예(OCR은 에·여로도 읽는다)와 아니요 사이에 상자 글자가 낀다.
/// 상자는 OCR이 ㅁ, 口, 디는 물론 "[|", "더", "던" 같은 한글 한 글자로도 읽어서(배포 서버의 Tesseract가 그렇다)
/// 상자가 무슨 글자인지는 따지지 않고 예~아니요 사이를 최대 4글자로 본다. 그 안의 한글 글자는 [_matchYesNo]가 한 글자까지만 허락한다
final _yesNo = RegExp(r'([예에여])(.{0,4}?)(아니[요오])');

/// 상자 글자가 아닌 줄 끝맺음 문장부호 ("동의하십니까?" 바로 뒤의 예)
const _notBox = '?.,:;!·';

/// "2026년  월  일"처럼 월·일이 빈 날짜 (공백을 지운 글자 기준). "생년월일"은 뺀다.
/// 1번 그룹은 인쇄된 연도 숫자. 비어 있으면("년 월 일") 연도도 써야 한다
final _dateBlank = RegExp(r'(?<![가-힣])(\d{0,4})년월일(?![가-힣])');

/// 안내·목록 줄의 머리 글자. 이런 줄은 칸을 찾지 않는다 ("* 지원자 : 성명, 성별, …", "※ …")
final _bullet = RegExp(r'^[※*•○●▶►■□ㅁ口▪]');

/// 읽기 결과에서 사용자가 채울 칸(이름, 주소, 서명, 동의 여부 …)을 찾는다. 백엔드를 부르지 않는다.
///
/// 줄마다 이 순서로 본다:
/// 1. "기재하지 않음"이 있는 줄은 기관용이라 뺀다
/// 2. "동의하십니까? □예 □아니요" → 고르는 칸 하나 ("수집·이용 동의 여부", "제3자 제공 동의 여부"). 상자 둘을 합친 자리
/// 3. "2026년  월  일" → 빈 자리마다 날짜 칸 (연도·월·일 따로)
/// 4. "접수번호"만 있는 칸 → 오른쪽(자리가 없으면 아래)의 빈 칸
/// 5. ※ * □ 같은 글자로 시작하는 안내·목록 줄은 뺀다
/// 6. "성명:"처럼 칸 이름 + ':' 뒤가 비어 있으면 글씨 칸. 이미 인쇄된 내용("상호: 행복편의점", "지원자: 성명, 성별, …")이 있으면 뺀다.
///    "지원자 ：", "법정대리인(보호자) ："처럼 주체만 있으면 그 주체의 성명 칸 (법정대리인(보호자)는 보호자로 부른다)
/// 7. "서명", "(인)", "날인", "(인 또는 서명)"은 서명 칸. 문장 속 "서명합니다"는 뺀다
/// 이름은 칸 이름 앞의 주체 + 칸 이름 ("보호자 성명", "보호자 서명"). 주체를 모르면 줄 맨 앞 주체를 쓴다.
/// 순서는 페이지, 위에서 아래, 왼쪽에서 오른쪽.
List<FillTarget> findFillTargets(RecognizedDocument doc) {
  final found = <_Found>[];
  for (final (i, block) in doc.blocks.indexed) {
    found.addAll(_scanLine(block, i, _pageSize(doc, block.page), doc.blocks));
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
/// 고르는 칸이 있으면 "채울 곳은 …" 으로 말하고 예·아니요로 고른다고 덧붙인다
String describeFillTargets(List<FillTarget> targets) {
  if (targets.isEmpty) return '써야 할 칸을 찾지 못했어요. 이름이나 서명 칸이 사진에 들어오게 다시 찍어 주세요.';
  final checks = targets.where((t) => t.kind == FillKind.check).length;
  final list = targets.map((t) => t.label).join(', ');
  if (checks == 0) return '써야 할 곳은 ${targets.length}곳이에요. $list.';
  return '채울 곳은 ${targets.length}곳이에요. $list. 동의 여부는 예나 아니요 중에서 골라요.';
}

/// 고르는 칸에서 물어볼 말. 칸 이름에서 무엇에 대한 동의인지 끌어낸다
String checkQuestion(FillTarget target) {
  final label = target.label;
  if (label.contains('수집·이용')) return '개인정보를 수집하고 이용하는 데 동의하십니까?';
  if (label.contains('제3자 제공')) return '개인정보를 제3자에게 제공하는 데 동의하십니까?';
  return '동의하십니까?';
}

/// 고르는 칸이 나온 줄. 같은 페이지에서 칸 자리와 겹치는 "□예 □아니요" 줄을 찾는다. 없으면 null
TextBlock? findCheckBlock(FillTarget target, List<TextBlock> blocks) {
  final r = target.rect;
  final rect = Rect.fromLTWH(r.x.toDouble(), r.y.toDouble(), r.width.toDouble(), r.height.toDouble());
  for (final block in blocks) {
    if (block.page != target.page) continue;
    final b = block.box;
    final overlap = rect.intersect(Rect.fromLTWH(b.x.toDouble(), b.y.toDouble(), b.width.toDouble(), b.height.toDouble()));
    if (overlap.width <= 0 || overlap.height <= 0) continue;
    if (_isCheckLine(_Line(block).compact)) return block;
  }
  return null;
}

/// 고르는 칸의 예 상자와 아니요 상자 자리 (그 페이지 사진의 픽셀 좌표).
/// 칸 자리([FillTarget.rect])는 두 상자를 합친 것이라, 표시를 넣을 때 어느 쪽인지 여기서 다시 잰다.
/// [block]이 "□예 □아니요" 줄이 아니면 null
({Rect yes, Rect no})? checkBoxRects(FillTarget target, TextBlock block) {
  final boxes = _yesNoBoxes(_Line(block));
  if (boxes == null) return null;
  return (yes: boxes.yes, no: boxes.no);
}

/// 글씨 칸에 글씨를 넣을 때 쓰는 자리: 칸 높이의 15%만큼 왼쪽을 비운다 (':' 바로 뒤에 붙지 않게).
/// 화면의 넣기 움직임과 PDF가 같은 함수를 써서 자리가 어긋나지 않게 한다. 서명 칸과 고르는 칸에는 쓰지 않는다
Rect fillTextInset(Rect rect) {
  final inset = rect.height * 0.15;
  return Rect.fromLTRB(rect.left + inset, rect.top, rect.right, rect.bottom);
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
  // 같은 줄 안의 순서는 칸 가운데로 비교한다. 서명 칸은 넓어서 왼쪽 끝으로 비교하면 바로 앞 글씨 칸보다 먼저 올 수 있다
  _Found(this.id, this.label, this.page, this.rect, this.isSignature, this.lineCenter, this.lineHeight)
      : x = rect.x + rect.width / 2;

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
  _Mark(this.start, this.end);

  final int start, end;
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

/// "법정대리인(보호자)" → 보호자, "입학지원자" → 지원자. 주체가 아니면 null
String? _ownerOf(String name) {
  final paren = RegExp(r'^([가-힣]+)\(([가-힣]+)\)$').firstMatch(name);
  final candidates = paren == null ? [name] : [paren.group(2)!, paren.group(1)!];
  for (final c in candidates) {
    if (_owners.contains(c)) return c;
  }
  for (final c in candidates) {
    final suffix = _ownerSuffix(c);
    if (suffix != null && suffix.length > 1) return suffix;
  }
  return null;
}

/// 괄호를 뗀 이름 ("법정대리인(보호자)" → 법정대리인)
String _stripParen(String name) => name.replaceAll(RegExp(r'\([^)]*\)'), '');

/// 한 줄의 글자와 자리. OCR 띄어쓰기는 믿기 어려워("성 명") 이름 찾기는 공백을 지운 글자([compact])로 하고,
/// 위치는 원문 글자로 잰다
class _Line {
  _Line(TextBlock block)
      : text = block.text.trim(),
        box = block.box {
    final buf = StringBuffer();
    for (var k = 0; k < text.length; k++) {
      if (_space.hasMatch(text[k])) continue;
      buf.write(text[k]);
      orig.add(k);
    }
    compact = buf.toString();
    layout = _LineLayout(text, box);
  }

  final String text;
  final Box box;
  final List<int> orig = [];
  late final String compact;
  late final _LineLayout layout;

  double get h => box.height.toDouble();
  double get cy => box.y + h / 2;

  /// [compact]의 [c]번째 글자가 원문에서 몇 번째인지
  int origAt(int c) => c >= compact.length ? text.length : orig[c];

  /// [compact]의 [c]번째 글자 왼쪽 끝
  double xAt(int c) => c >= compact.length ? layout.xAt(text.length) : layout.xAt(orig[c]);

  /// [compact]의 [c]번째 글자 오른쪽 끝
  double xEnd(int c) => layout.xAt(orig[c] + 1);

  /// [start]..[end) 글자 가운데에 놓인 정사각형 (체크 상자 자리). 상자는 줄 높이보다 조금 크게 인쇄된다
  Rect square(int start, int end) {
    final cx = (xAt(start) + xEnd(end - 1)) / 2;
    final side = h * 1.2;
    return Rect.fromCenter(center: Offset(cx, cy), width: side, height: side);
  }
}

/// 예·아니요 줄의 정규식 짝. 예~아니요 사이의 한글이 한 글자를 넘으면 문장 속 우연이라 버린다 ("예 또는 아니요")
RegExpMatch? _matchYesNo(String compact) {
  for (final m in _yesNo.allMatches(compact)) {
    final gap = m.group(2)!;
    final letters = gap.runes.where((r) => r >= 0xAC00 && r <= 0xD7A3 && !_boxChars.contains(String.fromCharCode(r))).length;
    if (letters <= 1) return m;
  }
  return null;
}

/// 글자가 상자로 읽혔을 법한가: 한글이 아닌 글자(ㅁ □ [ | 같은 것)이거나 [_boxChars]
bool _boxish(String c) => !_space.hasMatch(c) && !_notBox.contains(c) && (!_isHangul(c) || _boxChars.contains(c));

/// 예 상자와 아니요 상자의 자리 (그 줄 사진의 픽셀 좌표). [start]는 "예" 글자의 위치(칸 id에 쓴다).
///
/// 서식은 두 가지다. 상자가 글자 앞이면 "□예 □아니요", 뒤면 "예 □ 아니요 □"(해커톤 참가신청서).
/// 앞에 상자로 읽힌 글자가 있으면 앞, 없으면 뒤로 본다. OCR이 상자를 놓치면 글자 옆에 어림해서 둔다
({int start, Rect yes, Rect no})? _yesNoBoxes(_Line line) {
  final compact = line.compact;
  final m = _matchYesNo(compact);
  if (m == null) return null;
  final yesIdx = m.start;
  final gap = m.group(2)!;
  final noIdx = m.start + 1 + gap.length;
  final noEnd = m.end;
  final h = line.h;

  final lead = yesIdx > 0 ? compact[yesIdx - 1] : null;
  final boxBefore = lead != null && _boxish(lead);
  // 상자 글자는 줄 끝의 몇 글자 (OCR이 상자를 "Ｌ|"처럼 두 글자로 읽기도 한다)
  final tail = compact.substring(noEnd);
  final tailBox = tail.isNotEmpty && tail.length <= 4;

  Rect near(double cx) => Rect.fromCenter(center: Offset(cx, line.cy), width: h * 1.2, height: h * 1.2);

  if (boxBefore) {
    return (
      start: yesIdx,
      yes: line.square(yesIdx - 1, yesIdx),
      no: gap.isNotEmpty ? line.square(yesIdx + 1, noIdx) : near(line.xAt(noIdx) - h * 0.8),
    );
  }
  return (
    start: yesIdx,
    yes: gap.isNotEmpty ? line.square(yesIdx + 1, noIdx) : near(line.xEnd(yesIdx) + h * 0.8),
    no: tailBox ? line.square(noEnd, noEnd + tail.length) : near(line.xEnd(noEnd - 1) + h * 0.8),
  );
}

/// "동의하십니까? □예 □아니요" 줄인가. 물음 없이 "□예 □아니요"만 있는 줄도 포함한다
bool _isCheckLine(String compact) {
  final m = _matchYesNo(compact);
  if (m == null) return false;
  if (_consentQuestion.hasMatch(compact)) return true;
  final rest = compact.replaceRange(m.start, m.end, '').replaceAll(RegExp('[^가-힣]'), '');
  return rest.length <= 2;
}

/// 무엇에 대한 동의인지 물음에서 끌어낸 칸 이름. 반드시 "동의 여부"로 끝난다 ([FillTargetKind.kind]가 이 꼬리로 구분한다).
/// [context]는 물음의 글자(공백 지움). 예·아니요가 물음 줄 아래 따로 있는 서식은 윗줄까지 합친 글자다.
/// [owner]는 그 동의를 하는 사람("보호자")이고, 본인이면 null
String _checkLabel(String context, {String? owner}) {
  final what = context.contains('수집')
      ? '수집·이용 동의 여부'
      : (context.contains('제3자') || context.contains('제삼자') || context.contains('제공'))
          ? '제3자 제공 동의 여부'
          : '동의 여부';
  return owner == null ? what : '$owner $what';
}

/// 예·아니요 줄([index]) 바로 위의 물음과 제목에서 물음 글자와 동의하는 사람을 찾는다.
///
/// - 같은 줄에 "동의하십니까"가 있으면 그 줄이 물음이다.
/// - 아니면 바로 윗줄이 물음이면(해커톤 참가신청서) 그 줄을 합친다.
/// - 동의하는 사람은 위로 거슬러 오르며 "보호자 개인정보 수집 및 이용에 대한 동의(필수)"처럼
///   주체로 시작하고 '개인정보'와 '동의'가 든 제목 줄에서 읽는다. 앞 칸의 예·아니요 줄을 만나면 거기서 멈춘다.
///   ("• 보호자: 성명, …" 같은 항목 목록이나 표 칸의 "참가자 보호자 동의"는 제목이 아니라 건너뛴다)
({String context, String? owner}) _checkContext(List<TextBlock> blocks, int index) {
  final block = blocks[index];
  final own = _Line(block).compact;
  var context = own;
  if (!_consentQuestion.hasMatch(own) && index > 0 && blocks[index - 1].page == block.page) {
    final prev = _Line(blocks[index - 1]).compact;
    if (_consentQuestion.hasMatch(prev)) context = '$prev$own';
  }
  String? owner;
  for (var k = index - 1; k >= 0 && k >= index - 14; k--) {
    if (blocks[k].page != block.page) break;
    final compact = _Line(blocks[k]).compact;
    if (_isCheckLine(compact)) break;
    final heading = compact.replaceFirst(RegExp(r'^[ㅁ□口디■☐▢▣\[\]|ㅣ]+'), '');
    // 제목은 '개인정보 …에 대한 동의'꼴이다. 표 칸의 "참가자 보호자 동의" 같은 글자는 제목이 아니다
    if (!heading.contains('개인정보') || !heading.contains('동의') || heading.contains('?')) continue;
    for (final o in _ownersLongFirst) {
      if (o.length > 1 && heading.startsWith(o)) {
        owner = o;
        break;
      }
    }
    if (owner != null) break;
  }
  return (context: context, owner: owner);
}

List<_Found> _scanLine(TextBlock block, int lineNo, PageSize? page, List<TextBlock> blocks) {
  final line = _Line(block);
  final compact = line.compact;
  if (compact.isEmpty) return const [];
  // "관리번호 (기재하지 않음)"처럼 기관이 쓰는 칸
  if (compact.contains('기재하지')) return const [];

  final box = block.box;
  final h = line.h;
  final cy = line.cy;
  final pageWidth = page?.width.toDouble() ?? double.infinity;
  final pageHeight = page?.height.toDouble() ?? double.infinity;

  Box toBox(double left, double top, double width, double height) {
    final l = left.clamp(0.0, math.max(0.0, pageWidth - width));
    final t = top.clamp(0.0, math.max(0.0, pageHeight - height));
    return Box(l.round(), t.round(), width.round(), height.round());
  }

  final found = <_Found>[];

  // --- 동의 여부: "□예 □아니요" 두 상자를 합친 자리 ---
  if (_isCheckLine(compact)) {
    final boxes = _yesNoBoxes(line)!;
    // 예 상자 왼쪽 끝부터 아니요 상자 오른쪽 끝까지 ([checkBoxRects]와 같은 상자로 재서 표시가 칸 안에 들어간다)
    final left = math.min(boxes.yes.left, boxes.no.left);
    final right = math.max(boxes.yes.right, boxes.no.right);
    final height = h * 1.5;
    final ctx = _checkContext(blocks, lineNo);
    found.add(_Found(
      'p${block.page}-l$lineNo-c${boxes.start}-동의',
      _checkLabel(ctx.context, owner: ctx.owner),
      block.page,
      toBox(left, cy - height / 2, right - left, height),
      false,
      cy,
      h,
    ));
    return found;
  }

  // --- 날짜: "2026년  월  일" → 빈 자리마다 칸 하나씩 (연도, 월, 일) ---
  // 한 칸에 "10 24"를 한꺼번에 쓰게 하면 년·월·일 사이 간격을 사용자가 알 수 없다.
  // 그래서 "연도를 적으세요", "월을 적으세요", "일을 적으세요"로 따로 받고 각 숫자를 제 자리에 넣는다.
  // id 꼬리 -연/-월/-일은 [FillTargetKind.datePart]가 읽는다. 연도가 인쇄돼 있으면 연도 칸은 없다
  for (final m in _dateBlank.allMatches(compact)) {
    final yearIdx = m.end - 3, monthIdx = m.end - 2, dayIdx = m.end - 1;
    final yearPrinted = (m.group(1) ?? '').isNotEmpty;
    final height = h * 1.3;
    // [before] 글자 앞의 빈 자리. 빈 자리가 좁게 잡히면(OCR이 공백을 지움) 줄 높이만큼은 확보한다.
    // 글씨는 칸 크기에 맞춰 줄어들어 들어가므로 칸이 좁아도 숫자는 들어간다
    void add(String part, double left, int before) {
      final right = line.xAt(before) - h * 0.1;
      final l = math.min(left, right - h);
      found.add(_Found('p${block.page}-l$lineNo-c${m.start}-날짜-$part', '날짜 $part', block.page,
          toBox(l, cy - height / 2, right - l, height), false, cy, h));
    }

    if (!yearPrinted) {
      final start = m.start > 0 ? line.xEnd(m.start - 1) + h * 0.2 : line.xAt(yearIdx) - h * 3;
      add('연도', start, yearIdx);
    }
    add('월', line.xEnd(yearIdx) + h * 0.2, monthIdx);
    add('일', line.xEnd(monthIdx) + h * 0.2, dayIdx);
  }

  // --- 접수번호: 제목만 있는 표 칸. 빈 칸은 오른쪽, 자리가 없으면 아래 ---
  if (compact == '접수번호') {
    final width = h * 6;
    final rightSide = box.x + box.width + h * 0.3;
    if (rightSide + width <= pageWidth) {
      found.add(_Found('p${block.page}-l$lineNo-접수번호', '접수번호', block.page,
          toBox(rightSide, cy - h * 0.65, width, h * 1.3), false, cy, h));
    } else {
      final w = math.max(box.width.toDouble(), h * 4);
      found.add(_Found('p${block.page}-l$lineNo-접수번호', '접수번호', block.page,
          toBox(box.x.toDouble(), box.y + h * 1.3, w, h * 1.5), false, cy + h * 1.5, h));
    }
    return found;
  }

  // --- 안내·목록 줄 ---
  if (_bullet.hasMatch(compact)) return found;

  // --- 서명 표시 ---
  final sentenceLine = _sentence.hasMatch(compact);
  final marks = <_Mark>[];
  for (final m in _mark.allMatches(compact)) {
    final parenthesized = compact[m.start] == '(';
    if (sentenceLine && !parenthesized) continue;
    // "서명:"은 칸 이름으로 다룬다
    if (m.end < compact.length && (compact[m.end] == ':' || compact[m.end] == '：')) continue;
    // "서명날인", "서명(인)"은 한 칸
    if (marks.isNotEmpty && m.start - marks.last.end <= 3) continue;
    marks.add(_Mark(m.start, m.end));
  }

  // --- 칸 이름 ---
  final labels = <_Label>[];
  for (var colon = 0; colon < compact.length; colon++) {
    if (compact[colon] != ':' && compact[colon] != '：') continue;
    var runStart = colon;
    while (runStart > 0 && (_isHangul(compact[runStart - 1]) || compact[runStart - 1] == '(' || compact[runStart - 1] == ')')) {
      runStart--;
    }
    if (runStart == colon) continue; // "12:30" 같은 시간
    final run = compact.substring(runStart, colon);
    final known = _knownNames.where(run.endsWith).firstOrNull;
    int nameStart;
    if (known != null) {
      nameStart = colon - known.length;
    } else if (run.length <= 10) {
      // 모르는 칸 이름은 ':' 앞의 한글 덩어리 전체 ("법정대리인(보 호자) ："처럼 OCR이 낱말 안에 공백을 넣어도 잡힌다)
      nameStart = runStart;
    } else {
      // 문장이 붙어 길면 원문에서 ':' 앞 낱말까지만
      var k = line.origAt(colon) - 1;
      while (k >= 0 && _space.hasMatch(line.text[k])) {
        k--;
      }
      while (k >= 0 && !_space.hasMatch(line.text[k])) {
        k--;
      }
      nameStart = math.max(runStart, line.orig.indexWhere((o) => o > k));
    }
    final prefix = compact.substring(runStart, nameStart);
    var name = compact.substring(nameStart, colon);
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
    if (known == null) {
      // "지원자 ：", "법정대리인(보호자) ："처럼 주체만 있는 칸은 그 주체의 성명 칸.
      // 주체 목록에 없는 낱말도 뒤에 서명 표시가 따라오면("담당교사 : (인)") 주체로 본다
      final asOwner = _ownerOf(name);
      final bare = _stripParen(name);
      final markFollows = marks.any((m) => m.start > colon);
      if (asOwner != null || (markFollows && RegExp(r'^[가-힣]{2,6}$').hasMatch(bare))) {
        owner = asOwner ?? bare;
        name = '성명';
      }
    }
    labels.add(_Label(start, colon, name, owner));
  }

  final lineOwner = (labels.isNotEmpty ? labels.first.owner : null) ??
      _ownersLongFirst.where((o) => o.length > 1 && compact.startsWith(o)).firstOrNull;

  for (final (j, label) in labels.indexed) {
    final isSignature = label.name == '서명';
    if (!isSignature && !fillFieldNames.contains(label.name)) continue;
    // 칸은 다음 칸 이름이나 서명 표시 앞에서 끝난다
    var end = compact.length;
    if (j + 1 < labels.length) end = labels[j + 1].start;
    for (final mark in marks) {
      if (mark.start > label.colon && mark.start < end) {
        end = mark.start;
        break;
      }
    }
    final content = compact.substring(label.colon + 1, end).replaceAll(_notContent, '');
    if (content.isNotEmpty) continue; // 이미 인쇄된 내용이 있다 ("상호: 행복편의점", "지원자: 성명, 성별, …")

    // 빈칸은 ':' 바로 뒤가 아니라 조금 떨어져 시작한다. 글자 폭 어림이 작게 나오면 글씨가 인쇄 글자 위로
    // 왼쪽에 겹쳐 보이므로 넉넉히 띄운다
    final left = line.xEnd(label.colon) + h * 0.35;
    final right = end < compact.length
        ? line.xAt(end) - h * 0.15
        : math.min(pageWidth, math.max((box.x + box.width).toDouble(), left + h * 6));
    final owner = label.owner ?? lineOwner;
    final name = owner == null ? label.name : '$owner ${label.name}';
    final id = 'p${block.page}-l$lineNo-c${label.colon}-${label.name}';
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
    // 서명 표시 바로 앞 칸의 주체 ("보호자 성명: (서명)" → 보호자 서명, "지원자 ： (인 또는 서명)" → 지원자 서명)
    final before = labels.where((l) => l.colon < mark.start).lastOrNull;
    final owner = before?.owner ?? (before != null && _owners.contains(before.name) ? before.name : null) ?? lineOwner;
    final cx = (line.xAt(mark.start) + line.xEnd(mark.end - 1)) / 2;
    final height = h * 2;
    final width = height * 2.6;
    found.add(_Found(
      'p${block.page}-l$lineNo-c${mark.start}-서명표시',
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
/// 한글은 줄 높이만큼, 숫자·영문·기호는 그보다 좁게 잡고, 남는 폭은 빈칸(공백)에 나눠 준다.
/// ':' 뒤 공백(없으면 ':' 자체)에 주고, ':'가 없는 줄("2026년  월  일")은 모든 공백에 나눠 준다.
class _LineLayout {
  _LineLayout(String text, Box box) : _x = box.x.toDouble() {
    final h = box.height.toDouble();
    final widths = <double>[];
    final spaces = <int>[];
    // ':'가 없는 줄("2026년  월  일")은 글자 폭을 실측(consent_school: 한글 0.75h, 숫자 0.37h)에 가깝게 좁게 잡는다.
    // 넓게 잡으면 "년" 끝이 실제보다 오른쪽으로 가서 월·일 빈칸이 글자에 겹친다
    final hasColon = text.contains(':') || text.contains('：');
    for (var k = 0; k < text.length; k++) {
      final c = text[k];
      if (_space.hasMatch(c)) {
        widths.add(h * 0.3);
        spaces.add(k);
      } else if (_isHangul(c) || c.codeUnitAt(0) >= 0x3000) {
        // 인쇄 양식의 한글은 대개 줄 높이만큼 넓다. 좁게 잡으면 빈칸이 실제보다 왼쪽에 잡힌다
        widths.add(h * (hasColon ? 1.0 : 0.8));
      } else if (RegExp(r'[0-9A-Za-z]').hasMatch(c)) {
        widths.add(h * (hasColon ? 0.55 : 0.45));
      } else {
        widths.add(h * 0.35);
      }
    }
    // 빈칸은 보통 ':' 바로 뒤에 있다. ':' 뒤 공백(없으면 ':' 자체)에만 남는 폭을 준다.
    // 낱말 사이 공백("학생 성명")까지 나눠 주면 빈칸 자리가 엉뚱하게 잡힌다
    final slots = <int>[
      for (final k in spaces)
        if (RegExp(r'[:：]$').hasMatch(text.substring(0, k).trimRight())) k,
    ];
    var fromColon = slots.isNotEmpty;
    if (!fromColon) {
      for (var k = 0; k < text.length; k++) {
        if (text[k] == ':' || text[k] == '：') slots.add(k);
      }
      fromColon = slots.isNotEmpty;
    }
    // ':'가 없는 줄은 공백이 곧 빈칸이다 ("2026년  월  일")
    if (!fromColon) slots.addAll(spaces);
    var total = widths.fold(0.0, (a, b) => a + b);
    // OCR이 빈칸 공백을 지워 글자만 남으면, 어림한 글자 폭만으로 상자가 꽉 차 빈칸이 0이 된다.
    // 인쇄 글자가 상자의 65%를 넘지 않게 줄여 빈칸 자리를 남긴다. 더 많이 줄이면(예: 55%) 글자가 실제보다
    // 좁게 잡혀 빈칸이 인쇄 글자 위로 왼쪽에 잡힌다 ("학생 성명: 보호자 성명: (서명)" 실측으로 맞춤).
    // ':'가 없는 줄은 빈칸이 있다고 볼 수 없어 줄이지 않는다
    if (fromColon && total > box.width * 0.8) {
      final shrink = box.width * 0.65 / total;
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
