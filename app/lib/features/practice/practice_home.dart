import 'package:flutter/material.dart';

import '../../services/haptics.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/tap_feedback.dart';
import 'browser_storage.dart';
import 'hangul.dart';
import 'practice_frame.dart';
import 'practice_items.dart';
import 'practice_screen.dart';
import '../read/read_panel.dart' show ListenButton;
import 'score_board.dart';
import 'score_store.dart';

enum _View { home, learnMenu, learn, wordMenu, word, board, name, settings }

/// 들리는 받아쓰기: 계약서 칸에 쓰기 전에 패드에서 글씨를 연습한다.
///
/// 홈 → 학습하기(자음·모음·글자) / 연습하기(낱말) / 나의 점수판 / 내 이름 등록, 설정.
/// 촬영 화면 위에 새 화면으로 열리고, 나가도 찍은 페이지와 분석 결과는 그대로 남는다.
class PracticeFlow extends StatefulWidget {
  const PracticeFlow({super.key, this.store});

  /// 시험에서 다른 저장소를 넣을 수 있다. 없으면 이 기기 저장소를 쓴다
  final ScoreStore? store;

  @override
  State<PracticeFlow> createState() => _PracticeFlowState();
}

class _PracticeFlowState extends State<PracticeFlow> {
  late final ScoreStore _store = widget.store ?? sharedScoreStore;

  _View _view = _View.home;
  PracticeKind _kind = PracticeKind.consonant;
  WordGroup _group = WordGroup.contract;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Speech.announce(context, _intro(_View.home));
    });
  }

  String _intro(_View view) {
    switch (view) {
      case _View.home:
        return '들리는 받아쓰기예요. 학습하기, 연습하기, 나의 점수판, 내 이름 등록이 있어요.';
      case _View.learnMenu:
        return '학습하기예요. 자음, 모음, 글자 중에서 골라 주세요.';
      case _View.wordMenu:
        return '연습하기예요. 내 이름, 계약서 낱말, 일반 낱말 중에서 골라 주세요.';
      case _View.board:
        return '나의 점수판이에요. ${_store.boardSpeech()}';
      case _View.name:
        final name = _store.name;
        return '내 이름 등록이에요. 한글로 이름을 입력하고 저장을 눌러 주세요.'
            '${name.isEmpty ? '' : ' 지금 등록된 이름은 $name${ieyo(name)}.'}';
      case _View.settings:
        return '설정이에요. 진동, 거리 소리, 보조선 숨기기를 켜고 끌 수 있어요.';
      case _View.learn:
      case _View.word:
        return '';
    }
  }

  void _go(_View view, {String? say}) {
    setState(() => _view = view);
    final text = say ?? _intro(view);
    if (text.isNotEmpty) Speech.announce(context, text);
  }

  /// 한 단계씩 뒤로. 홈에서는 받아쓰기를 나간다
  void _back() {
    switch (_view) {
      case _View.home:
        Navigator.of(context).maybePop();
      case _View.learn:
        _go(_View.learnMenu);
      case _View.word:
        _go(_View.wordMenu);
      case _View.learnMenu:
      case _View.wordMenu:
      case _View.board:
      case _View.name:
      case _View.settings:
        _go(_View.home);
    }
  }

  /// 점수판에서: 가장 낮은 글자가 속한 묶음을 바로 연다
  void _retryLowest() {
    final kind = _store.lowestItemKind();
    if (kind == null) return;
    if (kind == PracticeKind.word) {
      _go(_View.wordMenu);
    } else {
      _openLearn(kind);
    }
  }

  void _openLearn(PracticeKind kind) {
    _kind = kind;
    setState(() => _view = _View.learn);
  }

  void _openWords(WordGroup group) {
    if (group == WordGroup.myName && _store.name.isEmpty) {
      _go(_View.name, say: '먼저 내 이름을 등록해 주세요. 한글로 이름을 입력하고 저장을 눌러 주세요.');
      return;
    }
    _group = group;
    setState(() => _view = _View.word);
  }

  String get _title {
    switch (_view) {
      case _View.home:
        return '들리는 받아쓰기';
      case _View.learnMenu:
        return '학습하기';
      case _View.wordMenu:
        return '연습하기';
      case _View.board:
        return '나의 점수판';
      case _View.name:
        return '내 이름 등록';
      case _View.settings:
        return '설정';
      case _View.learn:
        return '${_kind.label} 학습';
      case _View.word:
        return '낱말 연습, ${_group.label}';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_view == _View.learn) {
      return PracticeScreen(
        key: ValueKey('learn-${_kind.name}'),
        title: _title,
        items: itemsFor(_kind),
        mode: PracticeMode.learn,
        store: _store,
        onExit: _back,
      );
    }
    if (_view == _View.word) {
      return PracticeScreen(
        key: ValueKey('word-${_group.name}'),
        title: _title,
        items: wordItems(_group, name: _store.name),
        mode: PracticeMode.word,
        store: _store,
        onExit: _back,
      );
    }
    return PracticeFrame(
      title: _view == _View.home ? '' : _title,
      backLabel: _backLabel,
      onBack: _back,
      letterKeys: _view != _View.name,
      trailing: _view == _View.home
          ? IconButton(
              tooltip: '설정',
              icon: const Icon(Icons.settings_outlined),
              onPressed: TapFeedback.wrap(() => _go(_View.settings)),
            )
          : null,
      child: ListenableBuilder(
        listenable: _store,
        builder: (context, _) => _body(),
      ),
    );
  }

  /// 뒤로 버튼에 적는 곳 이름
  String get _backLabel {
    switch (_view) {
      case _View.home:
        return '카메라로';
      case _View.learn:
        return '학습하기';
      case _View.word:
        return '연습하기';
      default:
        return '받아쓰기';
    }
  }

  Widget _body() {
    final avg = _store.average(PracticeKind.consonant) ??
        _store.average(PracticeKind.vowel) ??
        _store.average(PracticeKind.syllable) ??
        _store.average(PracticeKind.word);
    switch (_view) {
      case _View.home:
        // 큰 타일 2×2 (사용자 선택 H2). 타일마다 큰 보기 글자로 무엇인지 짐작하게 한다
        return _home([
          _Choice('학습하기', '자음·모음·글자', 'ㄱ', () => _go(_View.learnMenu), primary: true),
          _Choice('연습하기', '낱말 한 줄', '서명', () => _go(_View.wordMenu)),
          _Choice('나의 점수판', avg == null ? '아직 없어요' : '최근 평균 $avg점', avg == null ? '점수' : '$avg', () => _go(_View.board)),
          _Choice('내 이름 등록', _store.name.isEmpty ? '아직 없어요' : _store.name, _store.name.isEmpty ? '이름' : _store.name,
              () => _go(_View.name)),
        ]);
      case _View.learnMenu:
        return _menu([
          _Choice('자음', 'ㄱ ㄴ ㄷ … 14개', 'ㄱ', () => _openLearn(PracticeKind.consonant), primary: true),
          _Choice('모음', 'ㅏ ㅑ ㅓ … 10개', 'ㅏ', () => _openLearn(PracticeKind.vowel)),
          _Choice('글자', '가 나 다 … 받침 있는 글자까지', '가', () => _openLearn(PracticeKind.syllable)),
        ]);
      case _View.wordMenu:
        return _menu([
          _Choice('내 이름', _store.name.isEmpty ? '먼저 이름을 등록해요' : _store.name, '名', () => _openWords(WordGroup.myName)),
          _Choice('계약서 낱말', '동의, 확인, 서명, 성명, 주소 …', '서명', () => _openWords(WordGroup.contract), primary: true),
          _Choice('일반 낱말', '하늘, 나무, 바다 …', '하늘', () => _openWords(WordGroup.general)),
        ]);
      case _View.board:
        return ScoreBoardView(store: _store, onRetryLowest: _retryLowest);
      case _View.name:
        return _NameForm(store: _store, onSaved: () => _go(_View.home, say: _savedSpeech()));
      case _View.settings:
        return _SettingsForm(store: _store);
      case _View.learn:
      case _View.word:
        return const SizedBox.shrink();
    }
  }

  String _savedSpeech() {
    final name = _store.name;
    return '$name, ${_countWord(name.runes.length)} 글자로 등록했어요. 낱말 연습의 내 이름에서 써 볼 수 있어요.';
  }

  static String _countWord(int n) {
    const words = ['', '한', '두', '세', '네', '다섯', '여섯'];
    return n >= 1 && n < words.length ? words[n] : '$n';
  }

  /// 홈: 작은 파란 줄 + 큰 제목 → 타일 2×2 → 사용법 듣기
  Widget _home(List<_Choice> choices) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const Text('글씨 연습', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accent)),
        const SizedBox(height: 6),
        Semantics(header: true, child: Text('들리는 받아쓰기', style: Theme.of(context).textTheme.headlineMedium)),
        const SizedBox(height: 18),
        for (var i = 0; i < choices.length; i += 2) ...[
          // ListView 안이라 세로 제약이 없어 stretch 대신 타일 높이를 고정한다
          Row(
            children: [
              Expanded(child: _Tile(choice: choices[i])),
              const SizedBox(width: 12),
              Expanded(child: i + 1 < choices.length ? _Tile(choice: choices[i + 1]) : const SizedBox.shrink()),
            ],
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
        ListenButton(
          label: '사용법 듣기',
          icon: Icons.volume_up_rounded,
          onPressed: () => Speech.announce(context, _intro(_View.home)),
        ),
      ],
    );
  }

  /// 아래 메뉴(학습하기·연습하기): "다음에 할 일"과 같은 줄 버튼, 왼쪽에 큰 보기 글자
  Widget _menu(List<_Choice> choices) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final c in choices) ...[
          _RowButton(choice: c),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _Choice {
  const _Choice(this.label, this.hint, this.glyph, this.onTap, {this.primary = false});

  final String label;
  final String hint;

  /// 큰 보기 글자 (ㄱ, 서명, 82 …)
  final String glyph;
  final VoidCallback onTap;

  /// 하늘색으로 강조 (한 화면에 하나)
  final bool primary;
}

/// 홈의 큰 타일: 큰 보기 글자 위, 이름과 한 줄 설명 아래
class _Tile extends StatelessWidget {
  const _Tile({required this.choice});

  final _Choice choice;

  @override
  Widget build(BuildContext context) {
    final c = choice;
    final fg = c.primary ? AppColors.onPrimary : AppColors.text;
    final sub = c.primary ? AppColors.onPrimary.withValues(alpha: 0.8) : AppColors.muted;
    final radius = BorderRadius.circular(AppRadius.card);
    return Semantics(
      button: true,
      label: '${c.label}. ${c.hint}',
      excludeSemantics: true,
      child: Material(
        color: c.primary ? AppColors.primary : AppColors.grey100,
        borderRadius: radius,
        child: InkWell(
          onTap: TapFeedback.wrap(c.onTap),
          borderRadius: radius,
          child: Container(
            height: 150,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    c.glyph,
                    style: TextStyle(
                      fontFamily: 'DoHyeon',
                      fontSize: c.glyph.length > 2 ? 34 : 50,
                      height: 1.1,
                      color: c.primary ? fg : AppColors.accent,
                    ),
                  ),
                ),
                const Spacer(),
                Text(c.label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: fg)),
                const SizedBox(height: 2),
                Text(
                  c.hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: sub),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 아래 메뉴의 줄 버튼
class _RowButton extends StatelessWidget {
  const _RowButton({required this.choice});

  final _Choice choice;

  @override
  Widget build(BuildContext context) {
    final c = choice;
    final fg = c.primary ? AppColors.onPrimary : AppColors.text;
    final sub = c.primary ? AppColors.onPrimary.withValues(alpha: 0.8) : AppColors.muted;
    final radius = BorderRadius.circular(AppRadius.button);
    return Semantics(
      button: true,
      label: '${c.label}. ${c.hint}',
      excludeSemantics: true,
      child: Material(
        color: c.primary ? AppColors.primary : AppColors.grey100,
        borderRadius: radius,
        child: InkWell(
          onTap: TapFeedback.wrap(c.onTap),
          borderRadius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      c.glyph,
                      style: TextStyle(fontFamily: 'DoHyeon', fontSize: 30, color: c.primary ? fg : AppColors.accent),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: fg)),
                      const SizedBox(height: 2),
                      Text(
                        c.hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: sub),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 26, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 내 이름 등록: 키보드로 입력한다 (스크린리더로도 입력할 수 있다)
class _NameForm extends StatefulWidget {
  const _NameForm({required this.store, required this.onSaved});

  final ScoreStore store;
  final VoidCallback onSaved;

  @override
  State<_NameForm> createState() => _NameFormState();
}

class _NameFormState extends State<_NameForm> {
  late final _controller = TextEditingController(text: widget.store.name);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (!isAllHangul(name) || name.runes.length > 6) {
      Haptics.warn();
      Speech.announce(context, '한글로 한 글자에서 여섯 글자까지만 입력할 수 있어요. 다시 입력해 주세요.');
      return;
    }
    Haptics.ok();
    widget.store.setName(name);
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 6,
          style: const TextStyle(fontSize: 28),
          decoration: const InputDecoration(labelText: '이름 (한글, 1~6글자)'),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: TapFeedback.wrap(_save),
          icon: const Icon(Icons.check),
          label: const Text('저장'),
        ),
        const SizedBox(height: 12),
        Text('이름은 이 기기 안에만 저장되고 밖으로 보내지 않아요.', style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

/// 설정: 진동, 거리 소리, 보조선 숨기기
class _SettingsForm extends StatelessWidget {
  const _SettingsForm({required this.store});

  final ScoreStore store;

  @override
  Widget build(BuildContext context) {
    final s = store.settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _toggle(context, '진동', '안드로이드 크롬에서만 나요', s.vibrate, (v) => s.vibrate = v),
        _toggle(context, '거리 소리', '보조선에 가까울수록 높고 잦은 소리', s.distanceSound, (v) => s.distanceSound = v),
        _toggle(context, '보조선 숨기기', '화면에서만 숨기고 판정은 같아요', s.hideGuide, (v) => s.hideGuide = v),
      ],
    );
  }

  Widget _toggle(BuildContext context, String label, String hint, bool value, void Function(bool) apply) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(color: AppColors.grey100, borderRadius: BorderRadius.circular(AppRadius.card)),
        child: SwitchListTile(
          activeThumbColor: AppColors.accent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          title: Text(label, style: text.titleMedium),
          subtitle: Text(hint, style: text.bodyMedium),
          value: value,
          onChanged: TapFeedback.wrapValue((v) {
            store.updateSettings((_) => apply(v));
            Speech.announce(context, '$label ${v ? '켰어요' : '껐어요'}.');
          }),
        ),
      ),
    );
  }
}
