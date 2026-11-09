// Actual backend responses generated from synthetic unknown/receipt documents.
const incompleteJudgements = <String, Map<String, dynamic>>{
  "unknown": {
    "findings": [
      {
        "level": "info",
        "item": "판단 범위 확인",
        "reason":
            "문서의 세부 종류에 맞는 판단 기준을 정하지 못했어요. 검토를 완료한 결과가 아니므로 문서 읽기에서 원문을 확인해 주세요.",
        "evidence": "",
        "rule_id": "unsupported_judgement",
        "severity": "info",
        "line": -1,
        "speech":
            "문서의 세부 종류에 맞는 판단 기준을 정하지 못했어요. 검토를 완료한 결과가 아니므로 문서 읽기에서 원문을 확인해 주세요.",
        "basis": [],
      },
    ],
    "speech":
        "문서의 세부 종류에 맞는 판단 기준을 정하지 못했어요. 검토를 완료한 결과가 아니므로 문서 읽기에서 원문을 확인해 주세요.",
    "subtype": "",
    "counts": {"info": 1},
    "questions": [],
    "disclaimer": "자동 판단 결과가 제공되지 않았어요.",
  },
  "receipt": {
    "findings": [
      {
        "level": "info",
        "item": "값을 읽지 못한 항목",
        "reason":
            "상호, 거래일, 품목, 결제 금액, 결제 수단, 승인 번호 값을 읽지 못했어요. 해당 항목이 필요한 서식인지, 빈칸인지, 사진에서 빠졌는지 원문을 확인해 주세요.",
        "evidence": "",
        "rule_id": "form_receipt_unread",
        "severity": "info",
        "line": -1,
        "speech":
            "상호, 거래일, 품목, 결제 금액, 결제 수단, 승인 번호 값을 읽지 못했어요. 해당 항목이 필요한 서식인지, 빈칸인지, 사진에서 빠졌는지 원문을 확인해 주세요.",
        "basis": [],
      },
      {
        "level": "info",
        "item": "문서 확인 안내",
        "reason": "종류별 원문 확인 항목",
        "evidence": "",
        "rule_id": "form_receipt_guide",
        "severity": "info",
        "line": -1,
        "speech":
            "받은 금액, 거래일, 내역과 발행처를 확인해 주세요. 영수증의 진위나 실제 결제 여부를 조회한 결과는 아니에요.",
        "basis": [],
      },
    ],
    "speech":
        "상호, 거래일, 품목, 결제 금액, 결제 수단, 승인 번호 값을 읽지 못했어요. 해당 항목이 필요한 서식인지, 빈칸인지, 사진에서 빠졌는지 원문을 확인해 주세요. 받은 금액, 거래일, 내역과 발행처를 확인해 주세요. 영수증의 진위나 실제 결제 여부를 조회한 결과는 아니에요.",
    "subtype": "receipt",
    "counts": {"info": 2},
    "questions": [],
    "disclaimer": "문서 종류에 맞춘 읽기 확인이며 법적 적합성이나 진위 판정은 아니에요.",
  },
};
