// Opt-in real loopback API contract check. No user photos or cloud APIs.
// Start the local backend with OCR_PROVIDER=tesseract and no GROQ_API_KEY, then:
// flutter test --dart-define=RUN_LOCAL_API=true --dart-define=API_BASE=http://127.0.0.1:8016 test/api_integration_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:undersign_assist/models/document_photo.dart';
import 'package:undersign_assist/models/recognized_document.dart';
import 'package:undersign_assist/services/api_client.dart';

void main() {
  test(
    'real read, judge, writing and validation contract',
    () async {
      final bytes = await File(
        '../samples/boundaries/images/inline_certificate/clean-1.jpg',
      ).readAsBytes();
      final image = DocumentPhoto(
        bytes: bytes,
        name: 'synthetic-certificate.jpg',
      );
      final doc = await ApiClient.read([image]);
      expect(doc.docType, 'certificate');
      expect(doc.pages.length, 1);
      expect(doc.pages.first.width, greaterThan(0));
      expect(doc.blocks, isNotEmpty);
      final review = await ApiClient.judge(doc);
      expect(review.subtype, 'certificate');
      expect(review.findings, isNotEmpty);

      final repeated = await ApiClient.read([image, image]);
      expect(repeated.pages.length, 2);
      expect(repeated.blocks.map((b) => b.page).toSet(), {0, 1});

      final written = await ApiClient.checkWriting(image, '성명');
      expect(written['field'], '성명');
      expect(written['found'], isA<bool>());
      expect(written['speech'], isNotEmpty);

      await expectLater(
        ApiClient.read([
          DocumentPhoto(name: 'bad.jpg', bytes: Uint8List.fromList([1, 2])),
        ]),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'user guidance',
            contains('사진'),
          ),
        ),
      );
      final unread = RecognizedDocument.fromJson({
        ...doc.toJson(),
        'needs_review': true,
        'review_pages': [0],
      });
      await expectLater(
        ApiClient.judge(unread),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'retake guidance',
            contains('다시'),
          ),
        ),
      );
    },
    skip: !const bool.fromEnvironment('RUN_LOCAL_API'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
