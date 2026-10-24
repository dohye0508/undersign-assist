// 서명 탭: 서명란 위치를 안내하고, 서명 전에 동의 여부를 마지막으로 확인한다.
import { capturePhoto } from "../shared/camera.js";
import { postPhoto } from "../shared/api.js";
import { announce } from "../shared/speech.js";

export function init(panel) {
  panel.innerHTML = `
    <h2>서명</h2>
    <p>서명하기 전에 판단 탭의 결과를 먼저 들어 보세요. 서명란을 찾으면 위치를 알려드려요.</p>
    <button type="button" data-action="locate">서명란 찾기</button>
  `;
  panel.querySelector('[data-action="locate"]').addEventListener("click", locateSignature);
}

async function locateSignature() {
  const photo = await capturePhoto();
  if (!photo) return;
  // TODO: 판단 결과에 주의 항목이 있으면 서명 전에 다시 알려주기
  try {
    const spot = await postPhoto("/api/sign/locate", photo);
    announce(spot.speech);
  } catch {
    announce("서명란을 찾지 못했어요. 다시 시도해 주세요.");
  }
}
