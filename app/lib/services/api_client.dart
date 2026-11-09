import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/document_photo.dart';
import '../models/judgement.dart';
import '../models/recognized_document.dart';

/// A recoverable API failure with a message suitable for screen and speech.
class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 백엔드(FastAPI) 호출. 주소는 `--dart-define=API_BASE=...`로 바꿀 수 있다.
class ApiClient {
  static const base = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://localhost:8000',
  );
  static const requestTimeout = Duration(minutes: 3);
  static const _invalidResponse = ApiException(
    '서버 응답을 읽지 못했어요. 잠시 후 다시 시도해 주세요.',
  );

  /// 여러 페이지를 한 문서로 읽는다 (페이지 순서대로 photo 필드를 여러 번 보낸다)
  static Future<RecognizedDocument> read(List<DocumentPhoto> pages) async {
    if (pages.isEmpty) throw const ApiException('문서 사진을 한 장 이상 선택해 주세요.');
    final request = http.MultipartRequest('POST', Uri.parse('$base/api/read'))
      ..files.addAll([
        for (final page in pages)
          http.MultipartFile.fromBytes(
            'photo',
            page.bytes,
            filename: page.name,
          ),
      ]);
    final body = _decode(await _send(request));
    if (body['doc_type'] is! String ||
        body['blocks'] is! List ||
        body['fields'] is! List ||
        body['full_text'] is! String ||
        body['speech'] is! String) {
      throw _invalidResponse;
    }
    try {
      final document = RecognizedDocument.fromJson(body);
      final sizes = document.pages.isNotEmpty
          ? document.pages
          : [PageSize(document.imageWidth, document.imageHeight)];
      if (sizes.length != pages.length ||
          sizes.any((p) => p.width <= 0 || p.height <= 0)) {
        throw _invalidResponse;
      }
      if (document.blocks.any(
            (b) =>
                b.page < 0 ||
                b.page >= sizes.length ||
                b.box.x < 0 ||
                b.box.y < 0 ||
                b.box.width <= 0 ||
                b.box.height <= 0 ||
                b.box.x + b.box.width > sizes[b.page].width ||
                b.box.y + b.box.height > sizes[b.page].height,
          ) ||
          document.fields.any(
            (f) => f.line < -1 || f.line >= document.blocks.length,
          ) ||
          document.reviewPages.any((p) => p < 0 || p >= sizes.length) ||
          document.referencePages.any((p) => p < 0 || p >= sizes.length) ||
          (!document.needsReview && document.reviewPages.isNotEmpty)) {
        throw _invalidResponse;
      }
      return document;
    } on TypeError {
      throw _invalidResponse;
    } on FormatException {
      throw _invalidResponse;
    }
  }

  /// 고른 칸에 무엇이 쓰였는지. 응답: field, found, written, box, speech
  static Future<Map<String, dynamic>> checkWriting(
    DocumentPhoto photo,
    String field,
  ) async {
    final body = await _postPhoto(
      '/api/write/check',
      photo,
      fields: {'field': field},
    );
    if (body['field'] != field.trim() ||
        body['found'] is! bool ||
        body['written'] is! String ||
        body['speech'] is! String) {
      throw _invalidResponse;
    }
    return body;
  }

  /// 판단: 규칙 엔진(backend/app/services/judge)이 빠진 항목과 확인할 내용을 근거와 함께 돌려준다
  /// [answers]: 판단 질문(예: 사업장 인원)에 사용자가 고른 답. 질문 id → 답 코드
  static Future<Judgement> judge(
    RecognizedDocument document, {
    Map<String, String> answers = const {},
  }) async {
    final body = await _postJson('/api/judge', {
      ...document.toJson(),
      'answers': answers,
    });
    if (body['speech'] is! String ||
        body['findings'] is! List ||
        body['questions'] is! List ||
        body['counts'] is! Map) {
      throw _invalidResponse;
    }
    try {
      final result = Judgement.fromJson(body);
      const levels = {'ok', 'caution', 'missing', 'info'};
      final actualCounts = <String, int>{};
      for (final finding in result.findings) {
        if (!levels.contains(finding.level) ||
            finding.line < -1 ||
            finding.line >= document.blocks.length) {
          throw _invalidResponse;
        }
        actualCounts.update(
          finding.level,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      if (result.counts.entries.any(
            (entry) => !levels.contains(entry.key) || entry.value < 0,
          ) ||
          levels.any(
            (level) =>
                (result.counts[level] ?? 0) != (actualCounts[level] ?? 0),
          )) {
        throw _invalidResponse;
      }
      final questionIds = <String>{};
      for (final question in result.questions) {
        if (question.id.trim().isEmpty ||
            !questionIds.add(question.id) ||
            question.text.trim().isEmpty ||
            question.options.isEmpty ||
            question.options.entries.any(
              (option) =>
                  option.key.trim().isEmpty || option.value.trim().isEmpty,
            )) {
          throw _invalidResponse;
        }
      }
      return result;
    } on TypeError {
      throw _invalidResponse;
    } on FormatException {
      throw _invalidResponse;
    }
  }

  // 서명란 찾기는 백엔드를 부르지 않고 앱에서 읽기 결과로 한다 (features/sign/signature_spots.dart).

  static Future<Map<String, dynamic>> _postPhoto(
    String path,
    DocumentPhoto photo, {
    Map<String, String> fields = const {},
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$base$path'))
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes(
          'photo',
          photo.bytes,
          filename: photo.name,
        ),
      );
    return _decode(await _send(request));
  }

  static Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final request = http.Request('POST', Uri.parse('$base$path'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);
    return _decode(await _send(request));
  }

  static Future<http.Response> _send(http.BaseRequest request) async {
    final client = http.Client();
    try {
      // One deadline covers connecting, uploading, and receiving the whole body.
      return await (() async => http.Response.fromStream(
        await client.send(request),
      ))().timeout(requestTimeout);
    } on TimeoutException {
      throw const ApiException(
        '응답 시간이 길어 요청을 중단했어요. 잠시 후 다시 시도하거나 사진을 나누어 올려 주세요.',
      );
    } on http.ClientException {
      throw const ApiException('서버에 연결하지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.');
    } finally {
      client.close();
    }
  }

  static Map<String, dynamic> _decode(http.Response response) {
    Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      if (response.statusCode == 200) throw _invalidResponse;
    }
    if (response.statusCode != 200) {
      if ({400, 413, 422}.contains(response.statusCode) &&
          body is Map &&
          body['detail'] is String) {
        final message = (body['detail'] as String).trim();
        if (message.isNotEmpty && message.length <= 300) {
          throw ApiException(message);
        }
      }
      throw ApiException(switch (response.statusCode) {
        413 => '사진 용량이 너무 커요. 사진 크기나 장수를 줄여 주세요.',
        400 || 422 => '문서나 선택한 항목을 확인하고 다시 시도해 주세요.',
        429 => '요청이 많아 잠시 기다려야 해요. 조금 뒤 다시 시도해 주세요.',
        _ => '서버에서 요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.',
      });
    }
    if (body is! Map<String, dynamic>) throw _invalidResponse;
    return body;
  }
}
