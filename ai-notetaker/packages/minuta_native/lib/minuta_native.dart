import 'dart:async';

import 'package:flutter/services.dart';

/// Native helpers: screen capture, task control and a message bus between the
/// app's Flutter engines (main UI and floating overlay).
class MinutaNative {
  MinutaNative._();

  static const _channel = MethodChannel('minuta_native');
  static final _messages = StreamController<Map<String, dynamic>>.broadcast();
  static bool _listening = false;

  /// Messages sent with [broadcast] from the app's other Flutter engines.
  static Stream<Map<String, dynamic>> get messages {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onMessage' && call.arguments is Map) {
          _messages.add(Map<String, dynamic>.from(call.arguments as Map));
        }
      });
    }
    return _messages.stream;
  }

  static Future<void> broadcast(Map<String, dynamic> message) =>
      _channel.invokeMethod('broadcast', message);

  /// Shows the system consent dialog (once per session) and starts mirroring.
  static Future<bool> requestScreenCapture() async =>
      await _channel.invokeMethod<bool>('requestScreenCapture') ?? false;

  static Future<bool> isScreenCaptureActive() async =>
      await _channel.invokeMethod<bool>('isScreenCaptureActive') ?? false;

  /// JPEG of the current screen, or null when capture is not active.
  static Future<Uint8List?> captureScreen({int maxSide = 1280}) =>
      _channel.invokeMethod<Uint8List>('captureScreen', {'maxSide': maxSide});

  static Future<void> stopScreenCapture() => _channel.invokeMethod('stopScreenCapture');

  /// Sends the app to the background, keeping it alive.
  static Future<void> moveTaskToBack() => _channel.invokeMethod('moveTaskToBack');

  /// Brings the app's main screen back to the front.
  static Future<void> openApp() => _channel.invokeMethod('openApp');
}
