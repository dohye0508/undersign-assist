import { startCamera } from "./shared/camera.js";
import { announce } from "./shared/speech.js";
import * as read from "./tabs/read.js";
import * as write from "./tabs/write.js";
import * as sign from "./tabs/sign.js";
import * as judge from "./tabs/judge.js";

const TABS = { read, write, sign, judge };

for (const [name, tab] of Object.entries(TABS)) {
  tab.init(document.getElementById(`panel-${name}`));
}

const tabButtons = [...document.querySelectorAll('[role="tab"]')];

function selectTab(button) {
  for (const b of tabButtons) {
    const selected = b === button;
    b.setAttribute("aria-selected", String(selected));
    b.tabIndex = selected ? 0 : -1;
    document.getElementById(b.getAttribute("aria-controls")).hidden = !selected;
  }
  button.focus();
  announce(`${button.textContent} 탭`);
}

tabButtons.forEach((button, i) => {
  button.addEventListener("click", () => selectTab(button));
  // 좌우 화살표로 탭 이동 (스크린리더 탭 목록 관례)
  button.addEventListener("keydown", (e) => {
    const step = { ArrowRight: 1, ArrowLeft: -1 }[e.key];
    if (!step) return;
    e.preventDefault();
    selectTab(tabButtons[(i + step + tabButtons.length) % tabButtons.length]);
  });
});

document.getElementById("camera-start").addEventListener("click", startCamera);
