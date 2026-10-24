// 종이 문서를 찍는 공통 카메라. 모든 탭이 이 모듈로 사진을 얻는다.
import { announce } from "./speech.js";

const video = () => document.getElementById("camera-video");

export async function startCamera() {
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: "environment", width: { ideal: 1920 } },
    });
    video().srcObject = stream;
    announce("카메라를 켰어요. 종이 문서를 카메라 아래에 놓아 주세요.");
  } catch {
    announce("카메라를 켤 수 없어요. 브라우저의 카메라 권한을 확인해 주세요.");
  }
}

// TODO: 문서가 화면 안에 다 들어왔는지 확인하고 방향을 음성으로 안내하기

export async function capturePhoto() {
  const v = video();
  if (!v.srcObject) {
    announce("먼저 카메라를 켜 주세요.");
    return null;
  }
  const canvas = document.createElement("canvas");
  canvas.width = v.videoWidth;
  canvas.height = v.videoHeight;
  canvas.getContext("2d").drawImage(v, 0, 0);
  return new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.92));
}
