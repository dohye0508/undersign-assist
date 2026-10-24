// 판단 탭: 빠진 항목과 불리한 내용을 근거와 함께 알려준다. 최종 판단은 사용자가 한다.
import { postJson } from "../shared/api.js";
import { announce } from "../shared/speech.js";
import { signal } from "../shared/signal.js";

export function init(panel) {
  panel.innerHTML = `
    <h2>판단</h2>
    <p>읽은 문서에서 빠진 항목과 확인이 필요한 내용을 근거와 함께 알려드려요.</p>
    <button type="button" data-action="judge">판단 듣기</button>
  `;
  panel.querySelector('[data-action="judge"]').addEventListener("click", judgeDocument);
}

async function judgeDocument() {
  // TODO: 읽기 탭의 인식 결과를 공유 상태에서 가져오기
  const recognized = { doc_type: "unknown", blocks: [], fields: {} };
  try {
    const result = await postJson("/api/judge", recognized);
    signal(result.findings.some((f) => f.level !== "ok") ? "warn" : "ok");
    announce(result.speech);
  } catch {
    announce("판단하지 못했어요. 다시 시도해 주세요.");
  }
}
