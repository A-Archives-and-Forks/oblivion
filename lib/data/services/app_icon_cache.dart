import 'dart:typed_data';

import 'tunnel_channel.dart';

class AppIconCache {
  AppIconCache(this._channel);

  static const int _capacity = 400;

  final TunnelChannel _channel;
  final Map<String, Uint8List?> _resolved = <String, Uint8List?>{};
  final Map<String, Future<Uint8List?>> _inFlight =
      <String, Future<Uint8List?>>{};

  bool holds(String packageName) => _resolved.containsKey(packageName);

  Uint8List? peek(String packageName) => _resolved[packageName];

  Future<Uint8List?> load(String packageName) {
    if (_resolved.containsKey(packageName)) {
      return Future<Uint8List?>.value(_resolved[packageName]);
    }
    return _inFlight[packageName] ??= _fetch(packageName);
  }

  Future<Uint8List?> _fetch(String packageName) async {
    Uint8List? bytes;
    try {
      bytes = await _channel.appIcon(packageName);
    } catch (_) {
      bytes = null;
    }

    if (_resolved.length >= _capacity) _resolved.clear();
    _resolved[packageName] = bytes;
    _inFlight.remove(packageName);
    return bytes;
  }
}
