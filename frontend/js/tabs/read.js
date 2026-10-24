// 읽기 탭: 종이 문서를 찍어 문서 종류와 핵심 항목을 음성으로 읽어준다.
import { capturePhoto } from "../shared/camera.js";
import { postPhoto } from "../shared/api.js";
import { announce } from "../shared/speech.js";

export function init(panel) {
  panel.innerHTML = `
    <h2>읽기</h2>
    <p>종이 문서를 카메라 아래에 놓고 읽기 버튼을 누르세요.</p>
    <button type="button" data-action="read">문서 읽기</button>
  `;
  panel.querySelector('[data-action="read"]').addEventListener("click", readDocument);
}

async function readDocument() {
  const photo = await capturePhoto();
  if (!photo) return;
  announce("문서를 읽고 있어요.");
  try {
    const doc = await postPhoto("/api/read", photo);
    // TODO: 다른 탭(판단, 쓰기, 서명)이 쓸 수 있게 인식 결과를 공유 상태에 저장
    announce(doc.speech);
  } catch {
    announce("문서를 읽지 못했어요. 다시 시도해 주세요.");
  }
}
