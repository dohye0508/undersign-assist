// 결과는 화면(aria-live 영역)과 음성으로 함께 알린다. 사용자는 화면을 볼 수 없다고 가정한다.

export function announce(text) {
  document.getElementById("announcer").textContent = text;
  speak(text);
}

export function speak(text) {
  if (!("speechSynthesis" in window)) return;
  speechSynthesis.cancel();
  const utterance = new SpeechSynthesisUtterance(text);
  utterance.lang = "ko-KR";
  speechSynthesis.speak(utterance);
}
