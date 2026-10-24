import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../theme/app_theme.dart';
import 'app_logo.dart';

/// 앱을 처음 켤 때의 시작 화면 (사용자 요청): 흰 화면 정중앙에 로고와 "들리는계약서"(제목과 같은 글꼴)가
/// 나타나고, 머문 뒤 위에서 아래로 부드러운 그라데이션 경계로 걷히며 메인 화면이 드러난다.
/// 메인 화면은 처음부터 뒤에서 만들어져(카메라도 같이 켜진다) 걷히는 만큼 바로 보이므로 기다리는 시간이 늘지 않는다.
///
/// 전체 [total] 3.5초: 나타남 0.6초 → 머묾 1.6초 → 걷힘 1.3초. 걷히는 동안에는 눌러도 아래 화면이 받는다.
/// 기기의 "움직임 줄이기"가 켜져 있으면 걷히지 않고 옅어지기만 한다.
/// 스크린리더에는 시작할 때 "들리는계약서"만 알린다(카메라 안내는 카메라가 켜진 뒤에 따로 나온다).
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child, this.total = const Duration(milliseconds: 3500)});

  final Widget child;
  final Duration total;

  /// 나타남이 끝나는 때와 걷힘이 시작하는 때 (전체를 1로 본 비율)
  static const fadeInEnd = 600 / 3500;
  static const wipeStart = 2200 / 3500;

  /// 전체 진행 [t](0~1)에서 걷힘 진행도 0~1 (부드럽게 시작하고 끝난다)
  static double wipeProgress(double t) {
    final a = ((t - wipeStart) / (1 - wipeStart)).clamp(0.0, 1.0);
    return Curves.easeInOut.transform(a);
  }

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.total);
  var _finished = false;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() => _finished = true);
    });
    _controller.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // ignore: deprecated_member_use
      SemanticsService.announce('들리는계약서', Directionality.of(context));
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return widget.child;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final wipe = SplashGate.wipeProgress(t);
            final logoOpacity = (t / SplashGate.fadeInEnd).clamp(0.0, 1.0);
            // 걷히는 동안(그리고 끝난 뒤)에는 눌림이 아래 화면으로 간다
            final overlay = IgnorePointer(
              ignoring: t >= SplashGate.wipeStart,
              child: AbsorbPointer(child: _SplashFace(logoOpacity: logoOpacity)),
            );
            if (reduceMotion) return Opacity(opacity: 1 - wipe, child: overlay);
            if (wipe == 0) return overlay;
            return ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) {
                // 위에서부터 투명이 번져 내려온다. 경계가 0.4만큼 부드럽게 이어진다
                final p = (-0.4 + 1.4 * wipe);
                final from = p.clamp(0.0, 1.0);
                final to = (p + 0.4).clamp(0.0, 1.0);
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: const [Color(0x00000000), Color(0x00000000), Color(0xFF000000), Color(0xFF000000)],
                  stops: [0, from, to, 1],
                ).createShader(bounds);
              },
              child: overlay,
            );
          },
        ),
      ],
    );
  }
}

/// 시작 화면의 얼굴: 흰 바탕, 정중앙의 로고와 이름
class _SplashFace extends StatelessWidget {
  const _SplashFace({required this.logoOpacity});

  final double logoOpacity;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Material(
        color: AppColors.background,
        child: Center(
          child: Opacity(
            opacity: logoOpacity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 88),
                const SizedBox(height: 18),
                Text(
                  '들리는계약서',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
