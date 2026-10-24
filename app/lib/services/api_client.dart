import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/document_photo.dart';
import '../models/judgement.dart';
import '../models/recognized_document.dart';

/// 백엔드(FastAPI) 호출. 주소는 `--dart-define=API_BASE=...`로 바꿀 수 있다.
class ApiClient {
  static const base = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8000');

  static Future<RecognizedDocument> read(DocumentPhoto photo) async {
    final json = await _postPhoto('/api/read', photo);
    return RecognizedDocument.fromJson(json);
  }

  /// 고른 칸에 무엇이 쓰였는지. 응답: field, found, written, box, speech
  static Future<Map<String, dynamic>> checkWriting(DocumentPhoto photo, String field) =>
      _postPhoto('/api/write/check', photo, fields: {'field': field});

  /// 판단: 규칙 엔진(backend/app/services/judge)이 빠진 항목과 확인할 내용을 근거와 함께 돌려준다
  static Future<Judgement> judge(RecognizedDocument document) async =>
      Judgement.fromJson(await _postJson('/api/judge', document.toJson()));

  // 서명란 찾기는 백엔드를 부르지 않고 앱에서 읽기 결과로 한다 (features/sign/signature_spots.dart).

  static Future<Map<String, dynamic>> _postPhoto(
    String path,
    DocumentPhoto photo, {
    Map<String, String> fields = const {},
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$base$path'))
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes('photo', photo.bytes, filename: photo.name));
    final response = await http.Response.fromStream(await request.send());
    return _decode(path, response);
  }

  static Future<Map<String, dynamic>> _postJson(String path, Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$base$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(path, response);
  }

  static Map<String, dynamic> _decode(String path, http.Response response) {
    if (response.statusCode != 200) {
      throw Exception('$path 요청 실패: ${response.statusCode}');
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }
}
