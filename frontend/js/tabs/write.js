// 쓰기 탭: 써야 할 칸을 안내하고, 종이에 펜으로 쓴 글씨를 찍어 확인해 준다.
import { capturePhoto } from "../shared/camera.js";
import { postPhoto } from "../shared/api.js";
import { announce } from "../shared/speech.js";

export function init(panel) {
  panel.innerHTML = `
    <h2>쓰기</h2>
    <p>종이에 펜으로 쓴 다음 확인 버튼을 누르면, 무엇을 썼는지 읽어드려요.</p>
    <button type="button" data-action="check">쓴 글씨 확인</button>
  `;
  panel.querySelector('[data-action="check"]').addEventListener("click", checkWriting);
}

async function checkWriting() {
  const photo = await capturePhoto();
  if (!photo) return;
  // TODO: 읽기 결과에서 빈칸 목록을 받아 지금 쓸 칸을 고르게 하기
  const field = "성명";
  try {
    const result = await postPhoto("/api/write/check", photo, { field });
    announce(result.speech);
  } catch {
    announce("글씨를 확인하지 못했어요. 다시 시도해 주세요.");
  }
}
