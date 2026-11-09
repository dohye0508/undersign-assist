"""Saved multi-page/inline-field scenes: real OCR and separately labelled replay."""
import argparse
import hashlib
import html
import json
import subprocess
import sys
import types
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from unittest.mock import patch

from realistic_ocr_documents import ROOT, config, doc_reader, layout, llm, ocr, scene, edit_distance
from sample_corpus import extra_scene
from stress_ocr_documents import photograph
from app.models import TextBlock, RecognizedDocument
from app.services import judge
from app.services.doc_classifier import normalize

DEST = ROOT / 'samples/boundaries'
PROFILES = ('clean', 'desk', 'handheld', 'dark_screen', 'tiny_unreadable')
BASELINE = '9d2937aff9a4bb7718694fcd615e1207361668c7'


def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', 'utf-8')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def forms():
    from test_document_boundaries import BOUNDARY_CASES
    selected = ('cover_lists_titles', 'split_reference_appendix', 'unsupported_primary_with_privacy',
                'clinical_form_is_not_school_reply_appendix')
    cases = [dict(c, fields={}) for c in BOUNDARY_CASES if c['id'] in selected]
    additions = [
        ('inline_contract', 'contract', '근로계약서\n시급: 15000원    임금 지급일: 매월 25일\n소정근로시간: 주20시간    근무 장소: 예시도서관\n계약 기간: 2026년 1월부터 12월까지\n근로자: 김가상\n임금 지급 방법: 계좌이체', {'임금': '15000원', '임금 지급일': '매월 25일', '근로 시간': '주20시간', '근무 장소': '예시도서관'}),
        ('inline_application', 'application', '참가 신청서\n신청인 성명: 김가상    연락처: 010-1111-2222\n이메일: person@example.com    소속: 예시학교\n참가 부문: 역사 탐방\n접수 기간: 2026년 11월\n신청합니다.', {'성명': '김가상', '연락처': '010-1111-2222', '이메일': 'person@example.com', '소속': '예시학교'}),
        ('inline_receipt', 'receipt', '물품 구매 영수증\n결제 금액: 12000원    환불 금액: 2000원\n상호: 예시문구점    거래일: 2026년 11월 9일\n결제 방법: 카드\n구매 내역: 공책\n결제 완료', {'결제 금액': '12000원', '상호': '예시문구점'}),
        ('inline_certificate', 'certificate', '재직증명서\n대표자 성명: 박대표    대상자 성명: 김대상\n대상자 소속: 개발팀    발급 기관: 예시회사\n재직 기간: 2024년 3월부터 현재\n발급일: 2026년 11월 9일\n위 사실을 증명합니다.', {'성명': '김대상', '소속': '개발팀', '발급 기관': '예시회사'}),
        ('night_contract', 'contract', '근로계약서\n근로자: 김예시\n월급: 160만원\n근로시간: 22:00~06:00\n휴게시간: 1시간\n근무일: 주3일\n근무 장소: 예시관리실\n업무 내용: 야간 관리', {'임금': '160만원', '근로 시간': '22:00~06:00'}),
        ('weekday_contract', 'contract', '근로계약서\n근로자: 김예시\n월급: 160만원\n근로시간: 오전 9시~오후 6시\n휴게시간: 1시간\n근무일: 매주 월요일, 수요일\n근무 장소: 예시도서관\n업무 내용: 자료 정리', {'임금': '160만원', '근로 시간': '오전 9시~오후 6시'}),
        ('party_contacts', 'authorization', '물품 수령 위임장\n위임인 연락처: 010-1111-2222\n위임인 성명: 김가상    대리인 성명: 이새봄\n위임 업무: 보관 물품 수령\n위임 기간: 2026년 11월\n대리인 연락처: 010-3333-4444\n작성일: 2026년 11월 9일', {'위임인': '김가상', '대리인': '이새봄'}),
        ('signed_amount', 'receipt', '환불 영수증\n상호: 예시문구점\n거래일: 2026년 11월 9일\n결제 금액: -3000원\n거래 내역: 공책 반품\n결제 방법: 카드 취소\n승인 번호: 12345678', {'결제 금액': '-3000원', '승인 번호': '12345678'}),
    ]
    cases.extend({'id': ident, 'expected': kind, 'pages': [text], 'fields': fields}
                 for ident, kind, text, fields in additions)
    return cases


def generate():
    authored = forms()
    dump(DEST / 'authored.json', authored)
    cases = []
    for index, case in enumerate(authored):
        for profile in PROFILES:
            images = []
            for page, text in enumerate(case['pages']):
                if profile == 'tiny_unreadable':
                    payload = extra_scene(layout(text, 'clean'), profile)
                elif profile == 'clean':
                    payload = photograph(text, profile)
                else:
                    payload = scene(layout(text, 'clean'), profile, 20261110 + index * 10 + page)
                name = f"images/{case['id']}/{profile}-{page+1}.jpg"
                path = DEST / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(payload)
                images.append({'path': name, 'sha256': sha(path)})
            cases.append({**case, 'id': f"{case['id']}/{profile}", 'profile': profile,
                          'expected_review': profile == 'tiny_unreadable', 'images': images})
    dump(DEST / 'manifest.json', {'provenance': 'Authored synthetic regression scenes; not field photos.', 'cases': cases})
    print(f"Generated {len(cases)} documents / {sum(len(c['images']) for c in cases)} images", flush=True)


def recognize(case):
    lines, reviews, boxes, hashes = [], [], [], []
    for page, image in enumerate(case['images']):
        path = DEST / image['path']
        if sha(path) != image['sha256']:
            raise ValueError('Changed image: ' + image['path'])
        result = ocr.recognize(path.read_bytes())
        reviews.append(result.needs_review)
        boxes.append(all(0 <= b.box.x < result.width and 0 <= b.box.y < result.height
                         and b.box.width > 0 and b.box.height > 0
                         and b.box.x + b.box.width <= result.width and b.box.y + b.box.height <= result.height
                         for b in result.lines))
        lines.extend(b.model_copy(update={'page': page}).model_dump() for b in result.lines)
        hashes.append(image['sha256'])
    return {'id': case['id'], 'image_hashes': hashes, 'page_reviews': reviews,
            'needs_review': any(reviews), 'valid_boxes': all(boxes), 'blocks': lines}


def baseline_reader():
    def source(path):
        return subprocess.check_output(['git', 'show', BASELINE + ':' + path], cwd=ROOT).decode('utf-8')
    def module(name, path):
        result = types.ModuleType(name)
        result.__file__ = str(ROOT / path)
        sys.modules[name] = result
        exec(compile(source(path), path, 'exec'), result.__dict__)
        return result
    classifier = module('_boundary_before_classifier', 'backend/app/services/doc_classifier.py')
    reader = module('_boundary_before_reader', 'backend/app/services/doc_reader.py')
    reader.RULES = json.loads(source('backend/app/rules/doc_types.json'))
    reader.CLASSIFIER = classifier.DocumentClassifier(reader.RULES)
    return reader


def evaluate(cases, cache, output):
    if cache['ocr_source_hash'] != sha(ROOT / 'backend/app/services/ocr.py'):
        raise ValueError('OCR implementation changed; run ocr again')
    lookup = {r['id']: r for r in cache['results']}
    previous = baseline_reader()
    rows = []
    with patch.object(llm, 'available', return_value=False):
        for case in cases:
            recorded = lookup[case['id']]
            if any(sha(DEST / im['path']) != im['sha256'] for im in case['images']):
                raise ValueError('Saved image changed: ' + case['id'])
            if recorded['image_hashes'] != [im['sha256'] for im in case['images']]:
                raise ValueError('Cache input mismatch: ' + case['id'])
            lines = [TextBlock(**b) for b in recorded['blocks']]
            kind, _, fields, _ = doc_reader.read(lines)
            before_kind, _, before_fields, _ = previous.read(lines)
            if recorded['needs_review']:
                fields, before_fields = [], []  # The app blocks extraction on unreadable photos.
            values = {f.label: f.value for f in fields}
            before_values = {f.label: f.value for f in before_fields}
            expected_fields = {} if case['expected_review'] else case['fields']
            # Keep signs and digits significant; only OCR whitespace is ignored.
            equal = lambda a, b: ''.join(a.split()) == ''.join(b.split())
            checks = {k: equal(values.get(k, ''), v) for k, v in expected_fields.items()}
            old_checks = {k: equal(before_values.get(k, ''), v) for k, v in expected_fields.items()}
            status_ok = recorded['needs_review'] == case['expected_review'] and recorded['valid_boxes']
            class_ok = case['expected_review'] or kind.value == case['expected']
            schedule = None
            if case['id'].startswith(('night_contract/', 'weekday_contract/')) and not case['expected_review']:
                doc = RecognizedDocument(doc_type=kind, fields=fields, blocks=lines, full_text='\n'.join(b.text for b in lines))
                schedule = judge.E.extract(doc)
            reference = normalize('\n'.join(case['pages']))
            transcript = normalize('\n'.join(b.text for b in lines))
            rows.append({**recorded, 'profile': case['profile'], 'expected': case['expected'],
                         'expected_review': case['expected_review'], 'before': before_kind.value, 'actual': kind.value,
                         'checks_pass': status_ok and class_ok, 'fields': values, 'field_checks': checks,
                         'before_field_checks': old_checks, 'schedule_values': schedule,
                         'reference_characters': len(reference), 'character_edits': edit_distance(reference, transcript)})
    ordinary = [r for r in rows if not r['expected_review']]
    summary = {'documents': len(rows), 'images': sum(len(c['images']) for c in cases),
               'ordinary_before_correct': sum(r['before'] == r['expected'] for r in ordinary),
               'ordinary_correct': sum(r['actual'] == r['expected'] for r in ordinary), 'ordinary': len(ordinary),
               'negative_detected': sum(r['needs_review'] for r in rows if r['expected_review']),
               'negatives': sum(r['expected_review'] for r in rows), 'gate_failures': sum(not r['checks_pass'] for r in rows),
               'field_correct': sum(sum(r['field_checks'].values()) for r in rows),
               'before_field_correct': sum(sum(r['before_field_checks'].values()) for r in rows),
               'field_checks': sum(len(r['field_checks']) for r in rows)}
    summary['ordinary_character_edit_rate'] = round(sum(r['character_edits'] for r in ordinary) / sum(r['reference_characters'] for r in ordinary), 4)
    summary['by_profile'] = {profile: {
        'documents': len(group), 'class_correct': None if all(r['expected_review'] for r in group) else sum(r['actual'] == r['expected'] for r in group),
        'review_expected': sum(r['needs_review'] == r['expected_review'] for r in group),
        'field_correct': sum(sum(r['field_checks'].values()) for r in group),
        'field_checks': sum(len(r['field_checks']) for r in group),
    } for profile in dict.fromkeys(r['profile'] for r in rows) if (group := [r for r in rows if r['profile'] == profile])}
    result = {'baseline': BASELINE, 'engine': cache['engine'], 'mode': 'Replay of recorded real OCR; no OCR rerun in evaluate.',
              'source_hashes': {p: sha(ROOT / p) for p in ('backend/app/services/doc_reader.py', 'backend/app/services/doc_classifier.py', 'backend/app/rules/doc_types.json', 'backend/app/services/judge/parse.py')},
              'summary': summary, 'results': rows}
    dump(output, result)
    print(json.dumps(summary), flush=True)
    return result


def report(cases, result):
    rows = result['results']
    text = ['# 서식 경계와 복합 촬영 OCR 시험', '', '12개 직접 작성한 문서 묶음 × 5조건 = 60건/85장. 합성 시험 자료이며 실제 현장 사진이 아닙니다.',
            '정면, 책상, 손에 든 촬영의 기울기·그림자·축소·압축, 어두운 화면, 판독 불가 축소를 시험합니다.',
            '실제 OCR을 저장한 뒤 동일 원문으로 이전/현재 코드의 분류와 항목 추출을 비교합니다. OCR 엔진 자체는 바꾸지 않았습니다.', '',
            '```json', json.dumps(result['summary'], ensure_ascii=False, indent=2), '```', '',
            '항목값은 지정한 일부 값만 비교하며 부호·숫자는 그대로, 공백만 제거합니다. 누락/오인식도 모두 실패로 기록합니다.',
            '문자 편집률은 일반 조건의 원문/OCR에서 공백·문장부호를 제외한 편집 거리 ÷ 원문 글자 수입니다. 분류 정확도와 별도 지표입니다.', '',
            '|사례|정답|이전→현재|재촬영|분류·품질 검사|지정 값|', '|---|---|---|---|---|---|']
    cards = []
    for case, row in zip(cases, rows):
        text.append(f"|{row['id']}|{row['expected']}|{row['before']}→{row['actual']}|{row['needs_review']}|{row['checks_pass']}|{sum(row['field_checks'].values())}/{len(row['field_checks'])}|")
        pictures = ''.join(f'<a href="{im["path"]}"><img loading="lazy" src="{im["path"]}" alt="{html.escape(row["id"])} {i+1}페이지"></a>' for i, im in enumerate(case['images']))
        transcript = '\n'.join(f"[{b['page']+1}] {b['text']}" for b in row['blocks'])
        cards.append(f'<article><h2>{row["id"]}</h2><p>정답 {row["expected"]} · 이전 {row["before"]} → 현재 {row["actual"]} · 재촬영 {row["needs_review"]}</p><p>분류·품질 검사 {row["checks_pass"]} · 지정 항목값 {sum(row["field_checks"].values())}/{len(row["field_checks"])}</p><div>{pictures}</div><details><summary>문안·OCR·항목값</summary><pre>{html.escape(chr(10).join(case["pages"]))}</pre><hr><pre>{html.escape(transcript)}</pre><pre>{html.escape(json.dumps(row["fields"],ensure_ascii=False,indent=2))}</pre></details></article>')
    text += ['', '재현: `python backend/tests/boundary_ocr_samples.py ocr` → `evaluate` → `report`. 이미지 변경 시에만 `generate`.',
             '`evaluate --require-correct`는 종류·재촬영·좌표 오류가 하나라도 남으면 실패합니다. 기본 evaluate는 실패도 기록하는 측정입니다. 항목값 오류는 별도 수치이며 전체 인식 정확도가 아닙니다.',
             'CI에서는 기존 OCR 검증 조건을 유지하고, 새 60건을 실패 포함 측정하여 별도 artifact로 보존합니다. 이 측정 단계의 종료 코드 0이 모든 OCR 값의 성공을 뜻하지 않습니다.']
    (DEST / 'README.md').write_text('\n'.join(text) + '\n', 'utf-8')
    (DEST / 'index.html').write_text('<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>추가 경계 OCR 시험</title><style>body{font:16px/1.6 sans-serif;margin:24px auto;max-width:1100px;padding:0 16px;background:#f4f6f8}article{padding:20px;margin:20px 0;background:white;border:1px solid #ccc}img{width:260px;height:340px;object-fit:contain;border:1px solid #ddd;margin:5px}pre{white-space:pre-wrap;overflow-wrap:anywhere}</style><h1>서식 경계와 복합 촬영 OCR 시험</h1><p><a href="../index.html">전체 샘플</a> · <a href="results.json">전체 결과</a></p><p>12개 가상 문서 묶음 × 5조건. 손에 든 촬영도 합성이며 현장 사진이 아닙니다. 실패를 포함한 전체 결과입니다.</p><p>분류 ' + str(result['summary']['ordinary_before_correct']) + ' → ' + str(result['summary']['ordinary_correct']) + '/' + str(result['summary']['ordinary']) + ' · 판독 불가 재촬영 ' + str(result['summary']['negative_detected']) + '/' + str(result['summary']['negatives']) + ' · 지정 항목값 ' + str(result['summary']['before_field_correct']) + ' → ' + str(result['summary']['field_correct']) + '/' + str(result['summary']['field_checks']) + '</p><details><summary>조건별 상세 수치</summary><pre>' + html.escape(json.dumps(result['summary'],ensure_ascii=False,indent=2)) + '</pre></details>' + ''.join(cards) + '</html>', 'utf-8')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('command', choices=('generate', 'ocr', 'evaluate', 'report'))
    p.add_argument('--profiles', nargs='+', choices=PROFILES)
    p.add_argument('--cache', type=Path, default=DEST / 'ocr.json')
    p.add_argument('--output', type=Path, default=DEST / 'results.json')
    p.add_argument('--workers', type=int, default=3)
    p.add_argument('--require-correct', action='store_true')
    a = p.parse_args()
    if a.workers < 1:
        p.error('--workers must be positive')
    if a.command == 'generate':
        generate()
        return 0
    cases = json.loads((DEST / 'manifest.json').read_text('utf-8'))['cases']
    if a.profiles:
        cases = [c for c in cases if c['profile'] in a.profiles]
    if a.command == 'ocr':
        rows = []
        with patch.object(config, 'OCR_PROVIDER', 'tesseract'), patch.object(llm, 'available', return_value=False):
            with ThreadPoolExecutor(max_workers=a.workers) as pool:
                for future in as_completed([pool.submit(recognize, c) for c in cases]):
                    rows.append(future.result())
                    if len(rows) % 10 == 0:
                        print(f'OCR {len(rows)}/{len(cases)}', flush=True)
        dump(a.cache, {'engine': subprocess.check_output([config.TESSERACT_CMD, '--version'], text=True).splitlines()[0],
                       'ocr_source_hash': sha(ROOT / 'backend/app/services/ocr.py'), 'results': rows})
        return 0
    if a.command == 'report':
        report(cases, json.loads(a.output.read_text('utf-8')))
        return 0
    result = evaluate(cases, json.loads(a.cache.read_text('utf-8')), a.output)
    return int(a.require_correct and result['summary']['gate_failures'] > 0)


if __name__ == '__main__':
    sys.exit(main())
