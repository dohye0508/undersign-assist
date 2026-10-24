"""Groq 호출. 다른 AI로 바꿀 때는 이 파일만 고친다.

Groq는 OpenAI와 같은 형식의 API라서 별도 패키지 없이 표준 라이브러리로 부른다.
"""

import base64
import json
import urllib.error
import urllib.request

from app import config

URL = "https://api.groq.com/openai/v1/chat/completions"


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
        return json.loads(content)
    except json.JSONDecodeError as error:
        raise LlmError(f"JSON이 아닌 답: {content[:200]}") from error


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
            return json.load(response)["choices"][0]["message"]["content"]
    except urllib.error.HTTPError as error:
        raise LlmError(f"Groq {error.code}: {error.read().decode()[:200]}") from error
    except (urllib.error.URLError, TimeoutError, KeyError) as error:
        raise LlmError(f"Groq 호출 실패: {error}") from error
