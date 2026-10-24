// 하드웨어 진동 대신 쓰는 소리 신호. 휴대폰이면 진동도 함께 준다.
// ok: 짧은 높은음 1번 / warn: 낮은음 2번 (이전 프로젝트의 진동 s, w 패턴과 같은 의미)

const PATTERNS = {
  ok: { tones: [880], vibrate: [150] },
  warn: { tones: [330, 330], vibrate: [200, 100, 200] },
};

let audioCtx;

export function signal(kind) {
  const pattern = PATTERNS[kind];
  if (!pattern) return;
  navigator.vibrate?.(pattern.vibrate);

  audioCtx ??= new AudioContext();
  pattern.tones.forEach((freq, i) => {
    const osc = audioCtx.createOscillator();
    osc.frequency.value = freq;
    osc.connect(audioCtx.destination);
    const start = audioCtx.currentTime + i * 0.3;
    osc.start(start);
    osc.stop(start + 0.18);
  });
}
