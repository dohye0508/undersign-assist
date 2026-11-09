"""Groq 호출. 다른 AI로 바꿀 때는 이 파일만 고친다.

Groq는 OpenAI와 같은 형식의 API라서 별도 패키지 없이 표준 라이브러리로 부른다.
"""

import base64
import http.client
import json
import urllib.error
import urllib.request

from app import config

URL = "https://api.groq.com/openai/v1/chat/completions"
MAX_RESPONSE_BYTES = 1024 * 1024


class LlmError(RuntimeError):
    pass


def available() -> bool:
    return bool(config.GROQ_API_KEY)


def ask_json(prompt: str, model: str | None = None) -> dict:
    """글로 묻고 JSON으로 답을 받는다."""
    content = _chat(
        model or config.GROQ_TEXT_MODEL,
        [{"role": "user", "content": prompt}],
        response_format={"type": "json_object"},
    )
    try:
        answer = json.loads(content)
    except json.JSONDecodeError as error:
        raise LlmError("AI가 올바른 JSON을 반환하지 않았어요") from error
    if not isinstance(answer, dict):
        raise LlmError("AI의 JSON 응답이 객체가 아니에요")
    return answer


def ask_about_image(prompt: str, image_jpeg: bytes, model: str | None = None) -> str:
    """사진을 보여주고 짧은 답을 받는다."""
    data_url = "data:image/jpeg;base64," + base64.b64encode(image_jpeg).decode()
    return _chat(
        model or config.GROQ_VISION_MODEL,
        [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {"type": "image_url", "image_url": {"url": data_url}},
                ],
            }
        ],
    ).strip()


def _chat(model: str, messages: list[dict], **extra) -> str:
    if not available():
        raise LlmError("GROQ_API_KEY가 없어요")
    body = json.dumps({"model": model, "messages": messages, "temperature": 0, **extra}).encode()
    request = urllib.request.Request(
        URL,
        data=body,
        headers={
            "Authorization": f"Bearer {config.GROQ_API_KEY}",
            "Content-Type": "application/json",
            "User-Agent": "deullineun-gyeyakseo",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = response.read(MAX_RESPONSE_BYTES + 1)
        if len(payload) > MAX_RESPONSE_BYTES:
            raise LlmError("AI 응답의 크기가 너무 커요")
        content = json.loads(payload)["choices"][0]["message"]["content"]
        if not isinstance(content, str) or not content.strip():
            raise LlmError("AI가 읽을 수 있는 답을 반환하지 않았어요")
        return content
    except urllib.error.HTTPError as error:
        # Error bodies can contain the source document. Do not copy or log them.
        error.close()
        raise LlmError(f"AI 서비스를 이용할 수 없어요 (HTTP {error.code})") from error
    except (OSError, http.client.HTTPException) as error:
        raise LlmError("AI 서비스 연결이 끝나지 않았어요") from error
    except (ValueError, KeyError, IndexError, TypeError) as error:
        raise LlmError("AI 응답 형식이 올바르지 않아요") from error
