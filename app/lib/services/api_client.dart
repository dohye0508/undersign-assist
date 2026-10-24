import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/document_photo.dart';
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

  // 서명은 아직 화면만 있다. 기능을 만들 때 아래 호출을 쓴다.
  /// [answers]: 판단이 되물은 질문의 답 (질문 id -> yes/no/unknown)
  static Future<Map<String, dynamic>> judge(
    RecognizedDocument document, {
    Map<String, String> answers = const {},
  }) =>
      _postJson('/api/judge', {...document.toJson(), 'answers': answers});

  static Future<Map<String, dynamic>> locateSignature(DocumentPhoto photo) =>
      _postPhoto('/api/sign/locate', photo);

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
