"""시연 영상 자동 녹화 (Playwright).

진짜 앱(app/build/web)과 진짜 백엔드(127.0.0.1:8000)를 켜 두고 실행하면,
가짜 카메라(samples 사진)로 촬영 → 읽기 → 검토 → 쓰고 서명하기 → PDF → 들리는 받아쓰기까지
키보드·마우스로 자동 조작하면서 화면을 영상(webm)과 장면별 캡처(png)로 남긴다.

준비 (한 번만):
    pip install playwright pillow
    playwright install chromium
    cd app && flutter build web          # API_BASE 기본값(localhost:8000)으로 빌드
백엔드 실행 (다른 터미널):
    cd backend && .venv\\Scripts\\activate && uvicorn app.main:app --host 127.0.0.1 --port 8000

실행:
    python scripts/record_demo.py                       # samples/contract.png, 결과는 demo_out/
    python scripts/record_demo.py --sample samples/consent_school.png
    python scripts/record_demo.py --headed              # 브라우저를 눈으로 보며 (디버깅)
    python scripts/record_demo.py --keys-only           # 서명 칸을 밀기 대신 Enter로 넘김
    python scripts/record_demo.py --no-practice         # 받아쓰기 장면 빼기

참고:
- 소리는 녹음되지 않는다. 앱이 말하는 문장(speechSynthesis)을 가로채 아래 자막으로 보여 주고
  demo_out/transcript.txt에도 적는다. 목소리까지 넣으려면 --headed로 띄우고 OBS 등으로 직접 녹화한다.
- 백엔드와 앱 화면은 실제 것이다. 가짜 카메라가 sample 사진을 비출 뿐이다.
- 서버는 127.0.0.1에만 묶는다.
"""
from __future__ import annotations

import argparse
import functools
import http.server
import io
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT / "app" / "build" / "web"

# 앱이 말하는 문장을 가로채 자막으로 보여 주고 기록한다. (말소리는 내지 않는다: 녹화용)
INIT_JS = r"""
(() => {
  window.__speech = [];
  const mk = () => {
    const bar = document.createElement('div');
    bar.id = '__caption';
    bar.style.cssText = 'position:fixed;left:50%;bottom:22px;transform:translateX(-50%);max-width:86%;' +
      'padding:12px 20px;border-radius:14px;background:rgba(11,59,102,.92);color:#fff;' +
      'font:600 20px/1.45 Pretendard,"Noto Sans KR",sans-serif;text-align:center;z-index:2147483647;' +
      'pointer-events:none;display:none;white-space:pre-wrap';
    const tag = document.createElement('div');
    tag.id = '__scene';
    tag.style.cssText = 'position:fixed;left:16px;top:14px;padding:8px 16px;border-radius:999px;' +
      'background:#CFE5FB;color:#0B3B66;font:700 18px Pretendard,"Noto Sans KR",sans-serif;' +
      'z-index:2147483647;pointer-events:none;display:none';
    document.documentElement.appendChild(bar);
    document.documentElement.appendChild(tag);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mk); else mk();
  let hideTimer = null;
  window.__say = (text) => {
    window.__speech.push({t: Date.now(), text});
    const bar = document.getElementById('__caption');
    if (bar) { bar.textContent = text.length > 140 ? text.slice(0, 138) + '…' : text; bar.style.display = 'block';
      clearTimeout(hideTimer); hideTimer = setTimeout(() => { bar.style.display = 'none'; }, 6500); }
  };
  window.__scene = (text) => {
    const tag = document.getElementById('__scene');
    if (tag) { tag.textContent = text; tag.style.display = text ? 'block' : 'none'; }
  };
  const fake = {
    speaking: false, pending: false, paused: false,
    speak(u) { window.__say(u.text || ''); setTimeout(() => { u.onend && u.onend({}); }, 50); },
    cancel() {}, pause() {}, resume() {},
    getVoices() { return []; }, addEventListener() {}, removeEventListener() {},
  };
  // 소리를 내지 않고 문장만 얻는다 (flutter_tts 웹이 speechSynthesis.speak를 부른다)
  try { Object.defineProperty(window, 'speechSynthesis', {value: fake, configurable: true}); } catch (e) {}
  if (!window.SpeechSynthesisUtterance) {
    window.SpeechSynthesisUtterance = function (t) { this.text = t; };
  }
})();
"""


def log(msg: str) -> None:
    print(f"[녹화] {msg}", flush=True)


def port_open(port: int) -> bool:
    with socket.socket() as s:
        s.settimeout(0.5)
        return s.connect_ex(("127.0.0.1", port)) == 0


def start_static(port: int, web: Path) -> None:
    if port_open(port):
        log(f"127.0.0.1:{port} 에 이미 서버가 있어요. 그대로 씁니다.")
        return
    class Quiet(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a, **k):
            pass

    handler = functools.partial(Quiet, directory=str(web))
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    log(f"앱을 127.0.0.1:{port} 에 띄웠어요 ({web})")


def make_fake_camera(sample: Path, dest: Path) -> Path:
    """사진 한 장을 MJPEG 영상으로 만들어 크롬 가짜 카메라 입력으로 쓴다."""
    from PIL import Image

    img = Image.open(sample).convert("RGB")
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=92)
    frame = buf.getvalue()
    dest.write_bytes(frame * 15)
    return dest


class Demo:
    def __init__(self, page, out: Path, args):
        self.page, self.out, self.args = page, out, args
        self.shots = out / "shots"
        self.shots.mkdir(parents=True, exist_ok=True)
        self.n = 0
        self.vw, self.vh = args.width, args.height

    # --- 도구 -----------------------------------------------------------------
    def speech(self) -> list[str]:
        return [e["text"] for e in self.page.evaluate("window.__speech || []")]

    def scene(self, text: str) -> None:
        log(f"장면: {text}")
        self.page.evaluate("t => window.__scene && window.__scene(t)", text)

    def shot(self, name: str) -> None:
        self.n += 1
        self.page.screenshot(path=str(self.shots / f"{self.n:02d}_{name}.png"))

    def wait_speech(self, pattern: str, timeout: float = 60, since: int = 0) -> str | None:
        """since 번째 이후 말한 문장 중 pattern(정규식)에 맞는 첫 문장을 기다린다."""
        rx = re.compile(pattern)
        end = time.time() + timeout
        while time.time() < end:
            for s in self.speech()[since:]:
                if rx.search(s):
                    return s
            self.page.wait_for_timeout(250)
        log(f"  (기다려도 안 나옴: {pattern})")
        return None

    def press(self, key: str, wait: int = 400) -> None:
        self.page.keyboard.press(key)
        self.page.wait_for_timeout(wait)

    def click_button(self, name_regex: str, timeout: int = 3000) -> bool:
        try:
            self.page.get_by_role("button", name=re.compile(name_regex)).first.click(timeout=timeout)
            return True
        except Exception:
            return False

    def write_scribble(self, seed: int = 0) -> None:
        """화면 가운데 쓰는 칸에 천천히 몇 획을 쓴다 (0.4초 넘게, 칸의 8% 넘는 크기)."""
        w, h = self.vw, self.vh
        cx, cy = w * 0.5, h * 0.52
        m = self.page.mouse
        shapes = [
            [(-0.18, -0.06), (-0.12, 0.08), (-0.06, -0.08), (0.0, 0.08), (0.06, -0.08), (0.12, 0.08), (0.18, -0.04)],
            [(-0.16, 0.10), (-0.05, 0.12), (0.08, 0.10), (0.17, 0.12)],
            [(-0.02, -0.12), (0.0, 0.0), (0.02, 0.14)],
        ]
        for si, pts in enumerate(shapes):
            pts = [(cx + (x + 0.01 * seed) * w, cy + y * h) for x, y in pts]
            m.move(*pts[0])
            m.down()
            for a, b in zip(pts, pts[1:]):
                for i in range(1, 13):
                    m.move(a[0] + (b[0] - a[0]) * i / 12, a[1] + (b[1] - a[1]) * i / 12)
                    self.page.wait_for_timeout(18)
            m.up()
            self.page.wait_for_timeout(180)

    def find_guide(self):
        """회색 보조 글자(#D7DCE2, practice_screen의 _guideColor) 픽셀의 바깥 상자를 캡처에서 찾는다."""
        try:
            from PIL import Image, ImageChops

            self.page.evaluate("document.getElementById('__caption').style.visibility='hidden'")
            full = Image.open(io.BytesIO(self.page.screenshot())).convert("RGB")
            self.page.evaluate("document.getElementById('__caption').style.visibility='visible'")
            top = 100  # 위쪽 줄(닫기·동그라미)과 아래 버튼·결과 띠는 빼고 쓰는 칸만 본다
            img = full.crop((0, top, full.width, int(full.height * 0.72)))
            r, g, b = ImageChops.difference(img, Image.new("RGB", img.size, (215, 220, 226))).split()
            worst = ImageChops.lighter(ImageChops.lighter(r, g), b)  # 세 색 모두 가까운 픽셀만
            # 글자 가장자리의 흐린 픽셀과 작은 글씨도 비슷한 회색이 되므로, 일치 픽셀이 많이 모인 줄·열만 쓴다
            mask = worst.point(lambda v: 255 if v < 4 else 0)
            w, h = mask.size
            px = mask.tobytes()
            rows = [y for y in range(h) if px[y * w:(y + 1) * w].count(255) >= 25]
            cols = [x for x in range(w) if px[x::w].count(255) >= 25]
            if rows and cols and (cols[-1] - cols[0]) > 40 and (rows[-1] - rows[0]) > 40:
                return (cols[0], rows[0] + top, cols[-1], rows[-1] + top)
        except Exception:
            pass
        log("  보조선 위치를 못 찾아 화면 가운데에 씁니다")
        return None

    def swipe_left(self) -> None:
        """오른쪽에서 왼쪽으로 빠르게 민다 (오른쪽 끝에서 시작해 너비의 절반 넘게)."""
        w, h = self.vw, self.vh
        y = h * 0.52
        m = self.page.mouse
        # 앱 화면은 가운데 폭 480 한 줄이다. 쓰는 칸 오른쪽 35% 안에서 시작해 너비의 35% 넘게 왼쪽으로 민다
        col = min(w, 480)
        x0, x1 = w * 0.5 + col * 0.36, w * 0.5 - col * 0.36
        m.move(x0, y)
        m.down()
        # 앱은 0.9초 안에 끝난 밀기만 알아본다. 대기 없이 점 몇 개만 찍어 빠르게 민다
        steps = 5
        for i in range(1, steps + 1):
            m.move(x0 + (x1 - x0) * i / steps, y)
        m.up()

    # --- 장면 -----------------------------------------------------------------
    def run(self) -> None:
        p = self.page
        p.goto(self.args.app_url)
        p.wait_for_timeout(4500)  # Flutter 첫 화면
        self.scene("1  촬영")
        self.shot("camera")
        p.wait_for_timeout(1800)
        self.press("Space", 1500)  # 찍기
        self.shot("captured")
        self.press("p", 1500)  # 찍은 페이지 목록
        self.shot("page_tray")
        self.press("p", 600)

        self.scene("2  읽기")
        before = len(self.speech())
        self.press("Enter", 500)  # 분석
        got = self.wait_speech(r"다음에 할 일", 150, before)
        if not got:
            log("분석이 끝나지 않았어요. 백엔드가 켜져 있는지, 사진이 읽혔는지 확인하세요.")
        p.wait_for_timeout(3200)
        self.shot("read_result")

        self.scene("3  검토하세요!")
        self.press("2", 500)
        end = time.time() + 120
        asked = False
        while time.time() < end:
            if p.get_by_role("button", name=re.compile("검토 결과 듣기")).count():
                break  # 결과가 나옴
            skip = p.get_by_role("button", name=re.compile("모름|건너"))
            if skip.count() and not asked:
                asked = True  # 질문 먼저 화면
                p.wait_for_timeout(2500)
                self.shot("judge_question")
                skip.first.click()
            p.wait_for_timeout(500)
        else:
            log("검토 결과가 안 나왔어요. 백엔드를 확인하세요.")
        p.wait_for_timeout(2500)
        self.shot("judge_result")
        if self.click_button(r"근거 듣기"):
            p.wait_for_timeout(5500)
            self.shot("judge_basis")

        self.scene("4  쓰고 서명하기")
        self.press("Escape", 700)  # 문서 읽기로
        before = len(self.speech())
        self.press("3", 800)
        self.wait_speech(r"칸|써|적", 20, before)
        p.wait_for_timeout(1500)
        self.shot("fill_first")
        n_cells = 0
        for i in range(14):
            texts = self.speech()
            last = texts[-1] if texts else ""
            if re.search(r"모두 채웠어요", last):
                break
            before = len(self.speech())
            if re.search(r"예나 아니요", last):
                self.press("1", 1200)  # 체크 칸: 예
                self.shot(f"fill_check_{i+1}")
                self.write_scribble(i)
            else:
                p.wait_for_timeout(2200)  # 칸이 자리잡고 안내를 듣는 시간
                self.write_scribble(i)
            if i == 0:
                self.shot("fill_written")
            if self.args.keys_only:
                self.press("Enter", 2200)
            else:
                self.swipe_left()
                if not self.wait_speech(r".", 6, before):
                    log("  밀기가 안 먹혀 Enter로 넘겨요")
                    self.press("Control+z", 400)  # 밀다 남은 가로줄 한 획을 지운다
                    self.press("Enter", 1500)
                p.wait_for_timeout(1800)
            n_cells += 1
            if i == 1:
                self.shot("fill_second")
        log(f"칸 {n_cells}개를 썼어요")
        p.wait_for_timeout(1500)
        self.shot("fill_done")

        self.scene("5  PDF 출력")
        try:
            with p.expect_download(timeout=20000) as dl:
                self.press("Enter", 300)
            target = self.out / "signed.pdf"
            dl.value.save_as(str(target))
            log(f"PDF 저장: {target}")
        except Exception:
            log("PDF 내려받기를 못 잡았어요 (화면에서 직접 확인).")
        p.wait_for_timeout(3000)
        self.shot("pdf_done")

        if not self.args.no_practice:
            self.practice()
        self.scene("")
        p.wait_for_timeout(1500)

    def practice(self) -> None:
        p = self.page
        self.scene("6  들리는 받아쓰기")
        # 카메라 화면으로 돌아가기: 쓰기 화면 닫기 → 읽기 → 카메라
        for _ in range(3):
            self.press("Escape", 900)
        before = len(self.speech())
        self.press("g", 900)
        self.press("g", 1200)
        self.wait_speech(r"받아쓰기예요|글씨 연습|받아쓰기", 10, before)
        p.wait_for_timeout(2000)
        self.shot("practice_home")
        before = len(self.speech())
        if not self.click_button(r"학습하기"):
            log("받아쓰기 홈에서 '학습하기'를 못 찾았어요.")
            return
        p.wait_for_timeout(1800)
        self.shot("practice_menu")
        if not self.click_button(r"자음"):
            log("'자음' 버튼을 못 찾았어요.")
            return
        self.wait_speech(r"기역", 10, before)
        p.wait_for_timeout(2500)  # 보조선 준비
        self.shot("practice_guide")
        # 보조선(회색 글자)이 화면 어디 있는지 캡처에서 찾아 그 위를 따라 쓴다 (ㄱ: 가로로 긋고 끝에서 아래로)
        box = self.find_guide()
        w, h = self.vw, self.vh
        if box:
            x0, y0, x1, y1 = box
            bw, bh = x1 - x0, y1 - y0
            a = (x0 + bw * 0.04, y0 + bh * 0.09)
            b = (x1 - bw * 0.06, y0 + bh * 0.09)
            c = (x1 - bw * 0.12, y1 - bh * 0.03)
        else:
            cx, cy = w * 0.5, h * 0.40
            a, b, c = (cx - 0.07 * w, cy - 0.11 * h), (cx + 0.07 * w, cy - 0.11 * h), (cx + 0.07 * w, cy + 0.11 * h)
        m = p.mouse
        m.move(*a)
        m.down()
        for pt0, pt1 in ((a, b), (b, c)):
            for i in range(1, 25):
                m.move(pt0[0] + (pt1[0] - pt0[0]) * i / 24, pt0[1] + (pt1[1] - pt0[1]) * i / 24)
                p.wait_for_timeout(30)
        m.up()
        p.wait_for_timeout(700)
        self.shot("practice_written")
        before = len(self.speech())
        self.press("Enter", 500)
        self.wait_speech(r"점", 10, before)
        p.wait_for_timeout(3500)
        self.shot("practice_result")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sample", default=str(ROOT / "samples" / "contract.png"), help="가짜 카메라가 비출 문서 사진")
    ap.add_argument("--out", default=str(ROOT / "demo_out"))
    ap.add_argument("--app-url", default="http://127.0.0.1:3000")
    ap.add_argument("--api", default="http://127.0.0.1:8000")
    ap.add_argument("--width", type=int, default=1280)
    ap.add_argument("--height", type=int, default=720)
    ap.add_argument("--web", default=str(WEB), help="빌드한 앱 폴더")
    ap.add_argument("--headed", action="store_true")
    ap.add_argument("--keys-only", action="store_true")
    ap.add_argument("--no-practice", action="store_true")
    args = ap.parse_args()

    out = Path(args.out)
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)

    web = Path(args.web)
    if not (web / "index.html").exists():
        log("app/build/web 이 없어요. 먼저 `cd app && flutter build web` 를 실행하세요.")
        return 1
    try:
        urllib.request.urlopen(args.api + "/api/health", timeout=3).read()
    except Exception:
        log(f"백엔드({args.api})가 응답하지 않아요. uvicorn을 먼저 켜 주세요.")
        return 1
    port = int(args.app_url.rsplit(":", 1)[1])
    start_static(port, web)

    from playwright.sync_api import sync_playwright

    cam = make_fake_camera(Path(args.sample), out / "fake_camera.mjpeg")
    with sync_playwright() as pw:
        browser = pw.chromium.launch(
            headless=not args.headed,
            args=[
                "--use-fake-device-for-media-stream",
                "--use-fake-ui-for-media-stream",
                f"--use-file-for-fake-video-capture={cam}",
                "--autoplay-policy=no-user-gesture-required",
            ],
        )
        ctx = browser.new_context(
            viewport={"width": args.width, "height": args.height},
            record_video_dir=str(out / "video_raw"),
            record_video_size={"width": args.width, "height": args.height},
            permissions=["camera"],
            accept_downloads=True,
            locale="ko-KR",
        )
        ctx.add_init_script(INIT_JS)

        # Flutter 웹은 CanvasKit을 구글 CDN에서 받는다. 빌드 폴더에 있는 같은 파일로 대신 줘서
        # 인터넷이 없어도, CDN이 막혀 있어도 뜨게 한다. 글꼴 CDN은 막는다 (Pretendard를 앱에 내장).
        def serve_canvaskit(route):
            rel = route.request.url.split("/flutter-canvaskit/", 1)[1].split("/", 1)[1].split("?")[0]
            f = web / "canvaskit" / rel
            if f.is_file():
                ctype = "application/wasm" if f.suffix == ".wasm" else "application/javascript"
                route.fulfill(status=200, body=f.read_bytes(), headers={"Content-Type": ctype, "Access-Control-Allow-Origin": "*"})
            else:
                route.abort()

        ctx.route(re.compile(r"https://www\.gstatic\.com/flutter-canvaskit/.*"), serve_canvaskit)
        ctx.route(re.compile(r"https://fonts\.(gstatic|googleapis)\.com/.*"), lambda r: r.abort())
        page = ctx.new_page()
        demo = Demo(page, out, args)
        try:
            demo.run()
        finally:
            (out / "transcript.txt").write_text("\n".join(demo.speech()), encoding="utf-8")
            video = page.video
            ctx.close()
            browser.close()
            if video:
                src = Path(video.path())
                dest = out / "demo.webm"
                shutil.move(str(src), dest)
                shutil.rmtree(out / "video_raw", ignore_errors=True)
                log(f"영상: {dest}")
                if shutil.which("ffmpeg"):
                    mp4 = out / "demo.mp4"
                    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(dest), "-c:v", "libx264",
                                    "-pix_fmt", "yuv420p", "-preset", "veryfast", "-crf", "20", str(mp4)])
                    log(f"mp4: {mp4}")
        (out / "fake_camera.mjpeg").unlink(missing_ok=True)
    log(f"끝. 캡처는 {out / 'shots'}, 말한 문장은 {out / 'transcript.txt'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
