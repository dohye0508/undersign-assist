import 'dart:async';
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
///
/// 미리보기 하나마다 video 요소를 새로 만들고, 카메라 스트림 하나를 모두에 붙인다.
/// 예전에는 video 요소 하나를 모든 미리보기가 나눠 썼다. Flutter 웹은 미리보기를 만들 때
/// 그 요소를 새 틀로 옮기는데, 새 틀은 다음 프레임에야 페이지에 붙는다. 그 사이 요소가
/// 페이지에서 빠지면 브라우저가 재생을 멈추고, 다시 붙어도 스스로 다시 틀지 않아 화면이 멈춰 보였다.
/// 화면 전환(AnimatedSwitcher) 중이나 쓰기 단계의 작은 미리보기처럼 미리보기가 둘일 때는
/// 한쪽이 요소를 빼앗아 가 다른 쪽이 비거나 멈췄다.
class CameraService extends ChangeNotifier {
  static const _viewType = 'undersign-camera';
  static bool _registered = false;

  // 미리보기를 만드는 서비스. 서비스는 앱에 하나만 있다
  static CameraService? _instance;

  // 페이지에 붙어야 할 미리보기가 이만큼 프레임이 지나도 안 붙으면 버려진 것으로 본다
  static const _maxWaitFrames = 240;

  /// 사진을 찍을 때 쓰는 video. 페이지에 붙이지 않으므로 화면 전환과 상관없이 계속 재생된다.
  /// 화면에 보이는 미리보기가 있으면 그쪽을 먼저 쓰고, 없을 때만 이것을 쓴다.
  final web.HTMLVideoElement _capture = _newVideo(autoplay: false);

  /// 미리보기 video. 키는 Flutter가 정한 platform view id. 넣은 순서가 곧 만든 순서다
  final Map<int, web.HTMLVideoElement> _views = {};

  /// 재생을 이어 가려고 기다리는 중인 미리보기
  final Set<int> _waiting = {};

  late final JSFunction _onVisibilityChange = ((web.Event _) => _resumeAll()).toJS;

  web.MediaStream? _stream;

  String? _error;
  String? get error => _error;

  bool _ready = false;
  bool get ready => _ready;

  CameraService() {
    if (!_registered) {
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        return _instance?._createView(viewId) ?? _newVideo();
      });
      _registered = true;
    }
    _instance = this;
    web.document.addEventListener('visibilitychange', _onVisibilityChange);
  }

  static web.HTMLVideoElement _newVideo({bool autoplay = true}) => web.HTMLVideoElement()
    ..autoplay = autoplay
    ..muted = true
    ..setAttribute('playsinline', 'true')
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.objectFit = 'cover';

  /// 카메라 미리보기. 부를 때마다 새 화면 요소가 생기고, 같은 카메라 스트림을 보여준다.
  Widget preview() => _CameraPreview(camera: this);

  /// Flutter 웹이 미리보기를 만들 때 부른다. 이때 돌려준 요소는 아직 페이지에 없다.
  web.HTMLVideoElement _createView(int viewId) {
    final video = _newVideo();
    final stream = _stream;
    if (stream != null) video.srcObject = stream;
    _views[viewId] = video;
    // 페이지에서 잠깐 빠졌다 붙으면(틀이 옮겨지면) 브라우저가 재생을 멈춘다. 그때마다 다시 튼다
    // JS 콜백은 Future를 돌려줄 수 없어서 결과를 기다리지 않는 함수로 감싼다
    video.addEventListener('pause', ((web.Event _) {
      _keepPlaying(viewId);
    }).toJS);
    _keepPlaying(viewId);
    return video;
  }

  /// 미리보기가 페이지에 붙을 때까지 기다렸다가 재생한다.
  /// 페이지 밖에서 play()를 부르면 브라우저가 곧바로 다시 멈추므로 반드시 붙은 뒤에 튼다.
  Future<void> _keepPlaying(int viewId) async {
    if (!_waiting.add(viewId)) return;
    try {
      for (var frame = 0; frame < _maxWaitFrames; frame++) {
        final video = _views[viewId];
        if (video == null || _stream == null) return;
        if (video.isConnected) {
          if (!video.paused) return;
          await _play(video);
          if (!video.paused && video.isConnected) return;
        }
        await _nextFrame();
      }
      // 끝내 페이지에 붙지 않았다: 만들어지자마자 버려진 미리보기다
      if (_views[viewId]?.isConnected == false) _release(viewId);
    } finally {
      _waiting.remove(viewId);
    }
  }

  /// 미리보기 위젯이 사라질 때 그 video를 놓는다
  void _release(int viewId) {
    final video = _views.remove(viewId);
    if (video == null) return;
    video.pause();
    video.srcObject = null;
  }

  void _resumeAll() {
    if (web.document.visibilityState != 'visible' || _stream == null) return;
    for (final viewId in _views.keys.toList()) {
      _keepPlaying(viewId);
    }
    if (_capture.paused) _play(_capture);
  }

  static Future<void> _play(web.HTMLVideoElement video) async {
    try {
      await video.play().toDart;
    } catch (_) {
      // 재생을 이어 가지 못하면 다음 프레임이나 다음 찍기에서 다시 시도한다
    }
  }

  static Future<void> _nextFrame() {
    final done = Completer<void>();
    web.window.requestAnimationFrame(((double _) => done.complete()).toJS);
    return done.future;
  }

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
        _capture.srcObject = stream;
        try {
          await _capture.play().toDart;
        } catch (_) {
          _stop();
          rethrow;
        }
        for (final entry in _views.entries) {
          entry.value.srcObject = stream;
          _keepPlaying(entry.key);
        }
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
    if (!_ready) return null;
    final video = await _frameSource();
    if (video == null) return null;
    final canvas = web.HTMLCanvasElement()
      ..width = video.videoWidth
      ..height = video.videoHeight;
    (canvas.getContext('2d') as web.CanvasRenderingContext2D).drawImage(video, 0, 0);
    final dataUrl = canvas.toDataURL('image/jpeg', 0.92.toJS);
    final bytes = base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
    return DocumentPhoto(bytes: bytes, name: 'document.jpg');
  }

  /// 지금 재생 중인 video를 고른다. 사용자가 보고 있는 미리보기를 먼저, 가장 최근 것부터 본다
  Future<web.HTMLVideoElement?> _frameSource() async {
    for (final video in _views.values.toList().reversed) {
      if (!video.isConnected) continue;
      if (video.paused) await _play(video);
      if (!video.paused && video.videoWidth > 0) return video;
    }
    if (_capture.paused) await _play(_capture);
    return _capture.videoWidth > 0 ? _capture : null;
  }

  void _stop() {
    final tracks = _stream?.getTracks().toDart ?? [];
    for (final track in tracks) {
      track.stop();
    }
    _stream = null;
    _ready = false;
    _capture.srcObject = null;
    for (final video in _views.values) {
      video.srcObject = null;
    }
  }

  @override
  void dispose() {
    _stop();
    for (final viewId in _views.keys.toList()) {
      _release(viewId);
    }
    web.document.removeEventListener('visibilitychange', _onVisibilityChange);
    if (identical(_instance, this)) _instance = null;
    super.dispose();
  }
}

/// 미리보기 하나. 사라질 때 자기 video를 서비스에 돌려준다
class _CameraPreview extends StatefulWidget {
  const _CameraPreview({required this.camera});

  final CameraService camera;

  @override
  State<_CameraPreview> createState() => _CameraPreviewState();
}

class _CameraPreviewState extends State<_CameraPreview> {
  int? _viewId;

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(
      viewType: CameraService._viewType,
      onPlatformViewCreated: (viewId) => _viewId = viewId,
    );
  }

  @override
  void dispose() {
    final viewId = _viewId;
    if (viewId != null) widget.camera._release(viewId);
    super.dispose();
  }
}
