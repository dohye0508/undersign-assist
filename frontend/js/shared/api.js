// 백엔드 호출. 프론트엔드와 같은 서버에서 서빙되므로 상대 경로를 쓴다.

export async function postPhoto(path, photo, fields = {}) {
  const form = new FormData();
  form.append("photo", photo, "document.jpg");
  for (const [key, value] of Object.entries(fields)) form.append(key, value);
  return request(path, { method: "POST", body: form });
}

export async function postJson(path, data) {
  return request(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
}

async function request(path, options) {
  const res = await fetch(path, options);
  if (!res.ok) throw new Error(`${path} 요청 실패: ${res.status}`);
  return res.json();
}
