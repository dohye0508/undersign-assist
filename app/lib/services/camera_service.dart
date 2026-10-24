import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../models/document_photo.dart';

/// 앱을 켜자마자 여는 카메라. 문서 사진을 찍을 때와 쓰기 확인용으로 다시 찍을 때 함께 쓴다.
///
/// camera 패키지를 쓰지 않고 브라우저 카메라(getUserMedia)를 직접 연다.
/// camera 패키지는 연결된 카메라를 전부 열어 보며 목록을 만드는데, 이 노트북에서는 그중 하나가
/// 읽히지 않아(cameraNotReadable) 목록 단계에서 통째로 실패했다. 여기서는 기본 카메라 하나만 연다.
class CameraService extends ChangeNotifier {
  static const _viewType = 'undersign-camera';
  static bool _registered = false;

  final web.HTMLVideoElement _video = web.HTMLVideoElement()
    ..autoplay = true
    ..muted = true
    ..setAttribute('playsinline', 'true')
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.objectFit = 'cover';

  web.MediaStream? _stream;

  String? _error;
  String? get error => _error;

  bool _ready = false;
  bool get ready => _ready;

  CameraService() {
    if (!_registered) {
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _currentVideo!);
      _registered = true;
    }
    _currentVideo = _video;
  }

  // 화면에 붙일 video 요소. 서비스는 앱에 하나만 있다
  static web.HTMLVideoElement? _currentVideo;

  /// 카메라 미리보기
  Widget preview() => const HtmlElementView(viewType: _viewType);

  /// 카메라를 연다. 실패하면 [error]에 이유를 남긴다. 다시 부르면 다시 시도한다.
  Future<void> start() async {
    _stop();
    _error = null;
    notifyListeners();

    // 뒷면 카메라를 먼저 바라고, 안 되면 아무 카메라나 연다
    final attempts = [
      {'facingMode': 'environment', 'width': {'ideal': 1920}, 'height': {'ideal': 1080}},
      {'width': {'ideal': 1280}},
      true,
    ];
    Object? lastError;
    for (final video in attempts) {
      try {
        final constraints = {'video': video, 'audio': false}.jsify() as web.MediaStreamConstraints;
        final stream = await web.window.navigator.mediaDevices.getUserMedia(constraints).toDart;
        _stream = stream;
        _video.srcObject = stream;
        await _video.play().toDart;
        _ready = true;
        notifyListeners();
        return;
      } catch (e) {
        lastError = e;
        debugPrint('카메라 열기 실패 ($video): $e');
      }
    }
    _fail(lastError);
  }

  void _fail(Object? cause) {
    // 브라우저 오류는 "NotReadableError: ..." 같은 글로 온다. 앞의 이름만 쓴다
    final name = RegExp(r'\b(\w+Error)\b').firstMatch('$cause')?.group(1) ?? '$cause';
    final hint = switch (name) {
      'NotAllowedError' => '브라우저 주소창 왼쪽의 카메라 권한을 허용해 주세요.',
      'NotFoundError' => '연결된 카메라를 찾지 못했어요.',
      'NotReadableError' => '카메라를 읽을 수 없어요. 다른 프로그램이나 다른 탭이 카메라를 쓰고 있지 않은지 확인해 주세요.',
      _ => '다시 켜 보세요.',
    };
    _error = '카메라를 켤 수 없어요. $hint ($name)';
    _ready = false;
    notifyListeners();
  }

  /// 지금 화면을 JPEG 사진으로 찍는다
  Future<DocumentPhoto?> snapshot() async {
    if (!_ready || _video.videoWidth == 0) return null;
    final canvas = web.HTMLCanvasElement()
      ..width = _video.videoWidth
      ..height = _video.videoHeight;
    (canvas.getContext('2d') as web.CanvasRenderingContext2D).drawImage(_video, 0, 0);
    final dataUrl = canvas.toDataURL('image/jpeg', 0.92.toJS);
    final bytes = base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
    return DocumentPhoto(bytes: bytes, name: 'document.jpg');
  }

  void _stop() {
    final tracks = _stream?.getTracks().toDart ?? [];
    for (final track in tracks) {
      track.stop();
    }
    _stream = null;
    _ready = false;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
