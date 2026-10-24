import 'package:flutter/material.dart';

import '../../models/fill.dart';
import '../../models/workspace_state.dart';
import '../../services/speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/tap_feedback.dart';
import 'fill_screen.dart';
import 'fill_targets.dart';

/// 쓰고 서명하기: 써야 할 칸 목록을 들려주고, "쓰기 시작"으로 칸마다 화면 가득 쓰게 한다.
/// 쓰기와 서명은 하는 일이 같아서(패드에 쓴 글씨가 문서 자리로 들어감) 한 단계로 합쳤다.
class FillPanel extends StatelessWidget {
  const FillPanel({super.key, required this.state});

  final WorkspaceState state;

  // 열릴 때 한 번 말해야 해서 상태는 안쪽 위젯이 갖는다
  @override
  Widget build(BuildContext context) => _FillPanelBody(state: state);
}

class _FillPanelBody extends StatefulWidget {
  const _FillPanelBody({required this.state});

  final WorkspaceState state;

  @override
  State<_FillPanelBody> createState() => _FillPanelBodyState();
}

class _FillPanelBodyState extends State<_FillPanelBody> {
  bool _exporting = false;

  /// 아직 아무것도 안 채웠을 때 쓰기 화면을 바로 열었는지. 두 번 열리지 않게 한다
  bool _autoOpened = false;

  List<FillTarget> get _targets {
    final document = widget.state.recognized;
    return document == null ? const [] : findFillTargets(document);
  }

  int _left(List<FillTarget> targets) => targets.where((t) => !widget.state.fills.containsKey(t.id)).length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targets = _targets;
      // 아직 하나도 안 채웠으면 목록을 거치지 않고 첫 칸부터 바로 쓴다. 써야 할 곳 목록은 쓰기 화면이 말한다.
      // 하나라도 채웠으면 목록을 보여 줘서 확인하고 다시 쓸 수 있게 한다
      if (!_autoOpened && widget.state.fills.isEmpty && targets.isNotEmpty) {
        _autoOpened = true;
        _open(0, announceList: true);
        return;
      }
      Speech.announce(context, _summary());
    });
  }

  String _summary() {
    final targets = _targets;
    final list = describeFillTargets(targets);
    if (targets.isEmpty) return list;
    final left = _left(targets);
    final next = left == 0 ? ' 모두 채웠어요. 서명한 문서 PDF 받기를 누르세요.' : ' 쓰기 시작을 누르면 화면 가득 쓸 수 있어요.';
    return '${_cautionReminder()}$list$next';
  }

  /// 판단 결과에 확인이 필요한 곳이 있으면 쓰고 서명하기 전에 먼저 알린다 (판단 없이 서명하지 않게)
  String _cautionReminder() {
    final judgement = widget.state.judgement;
    if (judgement == null) return '서명하기 전에 검토하세요를 먼저 들어 보세요. ';
    final caution = judgement.counts['caution'] ?? 0;
    return caution == 0 ? '' : '서명 전에 다시 알려드려요. 확인이 필요한 곳이 $caution개 있어요. ';
  }

  Future<void> _open(int index, {bool announceList = false}) async {
    final targets = _targets;
    final exported = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FillScreen(
          state: widget.state,
          targets: targets,
          start: index,
          intro: announceList ? '${_cautionReminder()}${describeFillTargets(targets)}' : null,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {}); // 돌아오면 목록(채운 칸 표시)을 새로 그린다
    final left = _left(targets);
    final filled = targets.length - left;
    Speech.announce(
      context,
      exported == true
          ? '쓰고 서명하기를 닫았어요.'
          : left == 0
              ? '모두 채웠어요. 서명한 문서 PDF 받기를 누르면 내려받아요.'
              : '채운 칸은 $filled곳, 남은 칸은 $left곳이에요.',
    );
  }

  Future<void> _export(List<FillTarget> targets) async {
    setState(() => _exporting = true);
    await exportFilledPdf(context, widget.state, targets);
    if (mounted) setState(() => _exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final targets = _targets;
    final fills = widget.state.fills;
    final firstEmpty = targets.indexWhere((t) => !fills.containsKey(t.id));

    // 단계 이름은 위 막대가 이미 보여 주므로 여기서는 제목 없이 내용만 그린다
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (targets.isEmpty)
          Text(describeFillTargets(targets), style: text.bodyLarge)
        else ...[
          Row(
            children: [
              Expanded(child: Text('써야 할 곳 ${targets.length}곳', style: text.labelLarge)),
              IconButton(
                tooltip: '써야 할 칸 다시 듣기',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.volume_up_outlined),
                onPressed: TapFeedback.wrap(() => Speech.announce(context, _summary())),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final (i, target) in targets.indexed)
            _TargetRow(target: target, ink: fills[target.id], onTap: () => _open(i)),
          if (firstEmpty >= 0) ...[
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: TapFeedback.wrap(() => _open(firstEmpty)),
              icon: const Icon(Icons.draw_outlined),
              label: const Text('쓰기 시작'),
            ),
          ],
        ],
        if (fills.isNotEmpty) ...[
          const SizedBox(height: 8),
          // 다 채웠으면 PDF 받기가 가장 큰 버튼이 된다
          if (firstEmpty >= 0)
            OutlinedButton.icon(
              onPressed: TapFeedback.wrap(_exporting ? null : () => _export(targets)),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_exporting ? 'PDF 만드는 중…' : '서명한 문서 PDF 받기'),
            )
          else
            FilledButton.icon(
              onPressed: TapFeedback.wrap(_exporting ? null : () => _export(targets)),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_exporting ? 'PDF 만드는 중…' : '서명한 문서 PDF 받기'),
            ),
        ],
      ],
    );
  }
}

/// 칸 하나: 채웠으면 ✓와 글씨 미리보기. 누르면 그 칸부터 (다시) 쓴다
class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.target, required this.ink, required this.onTap});

  final FillTarget target;
  final FilledInk? ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = this.ink;
    final done = ink != null;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          backgroundColor: done ? AppColors.okSoft : AppColors.surface,
        ),
        onPressed: TapFeedback.wrap(onTap),
        child: Semantics(
          label: done ? '${target.label}, 채웠어요. 누르면 다시 써요.' : '${target.label}, 아직 비었어요. 누르면 써요.',
          child: ExcludeSemantics(
            child: Row(
              children: [
                Icon(done ? Icons.check_circle : Icons.edit_outlined,
                    size: 20, color: done ? AppColors.ok : AppColors.muted),
                const SizedBox(width: 8),
                // 이름은 한 줄로. "사업주 서명"처럼 긴 이름이 두 줄로 꺾이지 않게 작게, 넘치면 말줄임
                Expanded(
                  child: Text(
                    target.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(fontSize: 13),
                  ),
                ),
                if (done) ...[
                  SizedBox(width: 72, height: 32, child: Image.memory(ink.png, fit: BoxFit.contain)),
                  const SizedBox(width: 4),
                ],
                Text(done ? '다시 쓰기' : '쓰기', style: text.bodySmall?.copyWith(color: AppColors.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
