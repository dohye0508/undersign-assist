"""Type-specific reading checks, separate from statutory/contract judgement.

These are reading aids, not required-by-law findings. Values are re-extracted
from OCR blocks; client-supplied fields cannot make an unread field look checked.
"""

from app.services import doc_reader
from app.models import DocType
from app.services.doc_classifier import normalize


GUIDANCE = {
    "application": "신청인, 신청 분야, 연락처와 제출 기한을 확인해 주세요. 접수 완료나 신청 자격을 판정한 결과는 아니에요.",
    "summary": "작품명, 작성자, 요약 내용과 제출 조건을 확인해 주세요. 제출물의 심사 결과를 판단한 것은 아니에요.",
    "authorization": ("위임하는 사람·받는 사람, 위임할 업무와 기간을 원문에서 확인해 주세요. 위임 범위를 대신 결정하지 않아요."),
    "certificate": ("대상자, 증명 내용, 발급 기관과 발급일을 확인해 주세요. 문서의 진위나 발급 기관을 확인한 결과는 아니에요."),
    "invoice": ("청구 내역, 청구 금액, 납부 기한과 납부처를 확인해 주세요. 청구서를 읽은 것으로 납부 완료를 확인할 수는 없어요."),
    "receipt": ("받은 금액, 거래일, 내역과 발행처를 확인해 주세요. 영수증의 진위나 실제 결제 여부를 조회한 결과는 아니에요."),
    "pledge": ("서약 내용, 서약자, 적용 기간을 확인해 주세요. 서약의 효력이나 불이익을 판정한 결과는 아니에요."),
    "report": ("보고 대상, 작성자, 보고 기간과 결과 내용을 확인해 주세요. 보고 내용의 사실 여부를 검증한 결과는 아니에요."),
    "questionnaire": ("조사 목적, 응답 방법과 제출 기한을 확인해 주세요. 응답이나 동의 여부를 대신 선택하지 않아요."),
    "activity_consent": ("활동 내용, 일정, 장소, 참가자와 보호자 확인 항목을 읽어 주세요. 개인정보 동의와 활동 참가 동의는 따로 확인해 주세요."),
}


def unavailable():
    speech = "문서의 세부 종류에 맞는 판단 기준을 정하지 못했어요. 검토를 완료한 결과가 아니므로 문서 읽기에서 원문을 확인해 주세요."
    return {"findings": [{"level": "info", "item": "판단 범위 확인", "reason": speech,
                          "evidence": "", "rule_id": "unsupported_judgement", "severity": "info",
                          "line": -1, "speech": speech, "basis": []}],
            "speech": speech, "subtype": "", "counts": {"info": 1}, "questions": [],
            "disclaimer": "자동 판단 결과가 제공되지 않았어요."}


def run(document):
    kind = getattr(document.doc_type, "value", document.doc_type)
    if kind not in GUIDANCE:
        return None
    fields = doc_reader._extract_by_rules(document.blocks, DocType(kind))
    placeholders = {"", "서명", "인", "날인", "서명또는인", "서명또는날인", "서명날인"}
    labels = {field.label for field in fields if normalize(field.value) not in placeholders}
    unread = [spec["label"] for spec in doc_reader.RULES[kind]["fields"] if spec["label"] not in labels]
    guidance = GUIDANCE[kind]
    findings = [{
        "level": "info", "item": "문서 확인 안내", "reason": "종류별 원문 확인 항목",
        "evidence": "", "rule_id": f"form_{kind}_guide", "severity": "info",
        "line": -1, "speech": guidance, "basis": [],
    }]
    if unread:
        message = f"{', '.join(unread)} 값을 읽지 못했어요. 해당 항목이 필요한 서식인지, 빈칸인지, 사진에서 빠졌는지 원문을 확인해 주세요."
        findings.insert(0, {
            "level": "info", "item": "값을 읽지 못한 항목", "reason": message,
            "evidence": "", "rule_id": f"form_{kind}_unread", "severity": "info",
            "line": -1, "speech": message, "basis": [],
        })
    disclaimer = "문서 종류에 맞춘 읽기 확인이며 법적 적합성이나 진위 판정은 아니에요."
    return {"findings": findings, "speech": " ".join(f["speech"] for f in findings),
            "subtype": kind, "counts": {"info": len(findings)}, "questions": [],
            "disclaimer": disclaimer}
