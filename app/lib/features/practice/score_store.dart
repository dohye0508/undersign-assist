import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'hangul.dart';
import 'practice_items.dart';

/// 이 기기의 작은 저장소. 브라우저를 다시 열어도 이름과 점수가 남게 한다.
/// 이름은 이 기기 밖으로 보내지 않는다.
abstract class KeyValueStorage {
  String? read(String key);
  void write(String key, String value);
}

/// 시험용
class MemoryStorage implements KeyValueStorage {
  final Map<String, String> values = {};

  @override
  String? read(String key) => values[key];

  @override
  void write(String key, String value) => values[key] = value;
}

/// 받아쓰기 설정
class PracticeSettings {
  PracticeSettings({this.vibrate = true, this.distanceSound = true, this.hideGuide = false});

  /// 진동 (안드로이드 크롬에서만 난다). 켜고 끄기는 앱 설정의 "진동" 하나로 합쳐서 화면에서 바꾸지 않는다.
  /// 앱 설정에서 끄면 `Haptics` 자체가 진동을 내지 않으므로 받아쓰기 진동도 꺼진다
  bool vibrate;

  /// 학습하기에서 보조선에 가까울수록 높고 잦아지는 소리
  bool distanceSound;

  /// 보조선을 화면에서 숨기고 쓴다 (판정은 같다)
  bool hideGuide;

  Map<String, dynamic> toJson() => {'vibrate': vibrate, 'distanceSound': distanceSound, 'hideGuide': hideGuide};

  void load(Map<String, dynamic> json) {
    // 예전에 받아쓰기 설정에서 끈 값은 읽지 않는다 (진동은 앱 설정으로 옮겼다. 여기서 꺼진 채 남으면 다시 켤 곳이 없다)
    distanceSound = json['distanceSound'] is bool ? json['distanceSound'] as bool : distanceSound;
    hideGuide = json['hideGuide'] is bool ? json['hideGuide'] as bool : hideGuide;
  }
}

/// 내 이름, 설정, 글자별 최근 점수
class ScoreStore extends ChangeNotifier {
  ScoreStore(this._storage) {
    _load();
  }

  static const _storageKey = 'undersign.practice.v1';
  static const maxRecent = 10;

  final KeyValueStorage _storage;

  String name = '';

  /// 내 정보: 계약서 칸에 자주 쓰는 값. 받아쓰기 연습 낱말이 되고, 쓰고 서명하기에서 회색 보조 글씨로 보인다.
  /// 모두 이 기기 밖으로 보내지 않는다
  String address = '';

  /// 생년월일. "2008년 3월 15일"처럼 사람이 읽는 꼴 그대로 둔다
  String birth = '';
  String phone = '';

  /// 등록된 정보가 하나라도 있는지
  bool get hasProfile => name.isNotEmpty || address.isNotEmpty || birth.isNotEmpty || phone.isNotEmpty;

  /// 낱말 연습에 넘기는 내 정보 묶음
  ProfileInfo get profile => ProfileInfo(name: name, address: address, birth: birth, phone: phone);

  /// 등록된 항목 이름들 ("이름", "주소", "생년월일", "전화번호"). 홈 타일 설명과 저장 안내에 쓴다
  List<String> get profileLabels => [
        if (name.isNotEmpty) '이름',
        if (address.isNotEmpty) '주소',
        if (birth.isNotEmpty) '생년월일',
        if (phone.isNotEmpty) '전화번호',
      ];
  final settings = PracticeSettings();

  /// 이름표(`consonant:ㄱ`) → 최근 점수들 (오래된 것이 앞)
  final Map<String, List<int>> _scores = {};

  void _load() {
    final raw = _storage.read(_storageKey);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return;
      if (json['name'] is String) name = json['name'] as String;
      if (json['address'] is String) address = json['address'] as String;
      if (json['birth'] is String) birth = json['birth'] as String;
      if (json['phone'] is String) phone = json['phone'] as String;
      if (json['settings'] is Map<String, dynamic>) settings.load(json['settings'] as Map<String, dynamic>);
      final scores = json['scores'];
      if (scores is Map<String, dynamic>) {
        scores.forEach((key, value) {
          if (value is List) _scores[key] = [for (final v in value) if (v is num) v.toInt().clamp(0, 100).toInt()];
        });
      }
    } catch (_) {
      // 깨진 저장값은 버리고 처음부터
    }
  }

  void _save() {
    _storage.write(
      _storageKey,
      jsonEncode({
        'name': name,
        'address': address,
        'birth': birth,
        'phone': phone,
        'settings': settings.toJson(),
        'scores': _scores,
      }),
    );
  }

  void setName(String value) {
    name = value;
    _save();
    notifyListeners();
  }

  /// 내 정보 저장. 넘기지 않은 값은 그대로 둔다
  void setProfile({String? name, String? address, String? birth, String? phone}) {
    if (name != null) this.name = name.trim();
    if (address != null) this.address = address.trim();
    if (birth != null) this.birth = birth.trim();
    if (phone != null) this.phone = phone.trim();
    _save();
    notifyListeners();
  }

  void updateSettings(void Function(PracticeSettings) change) {
    change(settings);
    _save();
    notifyListeners();
  }

  void record(PracticeItem item, int score) {
    final list = _scores.putIfAbsent(item.key, () => []);
    list.add(score.clamp(0, 100).toInt());
    if (list.length > maxRecent) list.removeRange(0, list.length - maxRecent);
    _save();
    notifyListeners();
  }

  List<int> recent(String key) => List.unmodifiable(_scores[key] ?? const <int>[]);

  /// 종류별 최근 점수의 평균. 연습한 적이 없으면 null
  int? average(PracticeKind kind) {
    final all = [for (final e in _scores.entries) if (_kindOf(e.key) == kind) ...e.value];
    if (all.isEmpty) return null;
    return (all.reduce((a, b) => a + b) / all.length).round();
  }

  /// 점수가 두 번 이상 쌓인 글자들의 (마지막 − 처음) 평균이 가장 큰 종류. 오른 것이 없으면 null
  PracticeKind? mostImproved() {
    PracticeKind? best;
    var bestDelta = 0.0;
    for (final kind in PracticeKind.values) {
      final deltas = [
        for (final e in _scores.entries)
          if (_kindOf(e.key) == kind && e.value.length >= 2) (e.value.last - e.value.first).toDouble(),
      ];
      if (deltas.isEmpty) continue;
      final mean = deltas.reduce((a, b) => a + b) / deltas.length;
      if (mean > bestDelta) {
        bestDelta = mean;
        best = kind;
      }
    }
    return best;
  }

  /// 연습한 글자들의 평균 점수, 낮은 것부터. [kinds]를 주면 그 종류만.
  /// 화면 아래 "어려웠던 글자", "글자별 점수" 목록에 쓴다
  List<({String text, String name, PracticeKind kind, int score})> itemScores({Set<PracticeKind>? kinds}) {
    final out = <({String text, String name, PracticeKind kind, int score})>[];
    _scores.forEach((key, list) {
      final kind = _kindOf(key);
      if (list.isEmpty || kind == null || (kinds != null && !kinds.contains(kind))) return;
      final text = key.substring(key.indexOf(':') + 1);
      final name = kind == PracticeKind.consonant || kind == PracticeKind.vowel ? jamoName(text) : text;
      out.add((text: text, name: name, kind: kind, score: (list.reduce((a, b) => a + b) / list.length).round()));
    });
    out.sort((a, b) => a.score.compareTo(b.score));
    return out;
  }

  /// 평균 점수가 가장 낮은 글자가 속한 종류. 아직 없으면 null (점수판의 "다시 써 보기"가 어느 묶음을 열지 정한다)
  PracticeKind? lowestItemKind() {
    String? lowestKey;
    var lowest = double.infinity;
    _scores.forEach((key, list) {
      if (list.isEmpty) return;
      final mean = list.reduce((a, b) => a + b) / list.length;
      if (mean < lowest) {
        lowest = mean;
        lowestKey = key;
      }
    });
    return lowestKey == null ? null : _kindOf(lowestKey!);
  }

  /// 평균 점수가 가장 낮은 글자(소리 내어 부르는 이름). 아직 없으면 null
  String? lowestItemName() {
    String? lowestKey;
    var lowest = double.infinity;
    _scores.forEach((key, list) {
      if (list.isEmpty) return;
      final mean = list.reduce((a, b) => a + b) / list.length;
      if (mean < lowest) {
        lowest = mean;
        lowestKey = key;
      }
    });
    final key = lowestKey;
    if (key == null) return null;
    final kind = _kindOf(key);
    final text = key.substring(key.indexOf(':') + 1);
    if (kind == PracticeKind.consonant || kind == PracticeKind.vowel) return jamoName(text);
    return text;
  }

  /// 점수판을 한 번에 읽어 주는 말
  String boardSpeech() {
    final parts = <String>[];
    var any = false;
    for (final kind in PracticeKind.values) {
      final avg = average(kind);
      if (avg == null) {
        parts.add('${kind.label}은 아직 연습하지 않았어요.');
      } else {
        any = true;
        parts.add('${kind.label} $avg점.');
      }
    }
    if (!any) return '아직 점수가 없어요. 학습하기나 연습하기에서 먼저 써 보세요.';
    final up = mostImproved();
    final low = lowestItemName();
    return '${parts.join(' ')}'
        '${up == null ? '' : ' 가장 많이 오른 건 ${up.label}${ieyo(up.label)}.'}'
        '${low == null ? '' : ' 가장 낮은 글자는 $low${ieyo(low)}.'}';
  }

  static PracticeKind? _kindOf(String key) {
    final prefix = key.contains(':') ? key.substring(0, key.indexOf(':')) : key;
    for (final kind in PracticeKind.values) {
      if (kind.name == prefix) return kind;
    }
    return null;
  }
}
