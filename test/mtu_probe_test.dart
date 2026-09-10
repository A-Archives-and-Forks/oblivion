import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oblivion/data/services/mtu_probe.dart';

class _Responder {
  _Responder(this._socket, this._dropAbove) {
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      for (var d = _socket.receive(); d != null; d = _socket.receive()) {
        if (d.data.length < 12) continue;
        if (d.data.length + 28 > _dropAbove) continue;

        final reply = Uint8List(12);
        reply.setRange(0, 12, d.data);
        reply[2] = 0x81;
        reply[3] = 0x80;
        _socket.send(reply, d.address, d.port);
      }
    });
  }

  static Future<_Responder> bind(int dropAbove) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    return _Responder(socket, dropAbove);
  }

  final RawDatagramSocket _socket;
  final int _dropAbove;

  int get port => _socket.port;

  void close() => _socket.close();

  List<MtuProbeTarget> get targets => <MtuProbeTarget>[
    MtuProbeTarget(
      address: '127.0.0.1',
      port: port,
      method: MtuProbeMethod.dns,
      label: 'loopback responder',
    ),
  ];
}

void main() {
  group('mtu probe', () {
    test('a path that carries everything reports the search ceiling', () async {
      final responder = await _Responder.bind(65535);
      addTearDown(responder.close);

      final outcome = await MtuProbe(targets: responder.targets).run();

      expect(outcome.ok, isTrue);
      expect(outcome.failure, isNull);
      expect(outcome.pathMtu, MtuProbe.searchCeiling);
      expect(outcome.converged, isTrue);
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('a path that swallows big packets is measured, never guessed', () async {
      final responder = await _Responder.bind(1400);
      addTearDown(responder.close);

      final outcome = await MtuProbe(targets: responder.targets).run();

      expect(outcome.ok, isTrue);
      expect(outcome.pathMtu, 1400);
      expect(outcome.linkMtu, greaterThanOrEqualTo(outcome.pathMtu));
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('a measurement never claims more than the path really carries',
        () async {
      final responder = await _Responder.bind(1337);
      addTearDown(responder.close);

      final outcome = await MtuProbe(targets: responder.targets).run();

      expect(outcome.ok, isTrue);
      expect(outcome.pathMtu, lessThanOrEqualTo(1337));
      expect(outcome.pathMtu, greaterThanOrEqualTo(1280));
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('a target that never answers fails instead of inventing a number',
        () async {
      final outcome = await MtuProbe(
        budget: const Duration(seconds: 10),
        targets: const <MtuProbeTarget>[
          MtuProbeTarget(
            address: '127.0.0.1',
            port: 9,
            method: MtuProbeMethod.dns,
            label: 'nowhere',
          ),
        ],
      ).run();

      expect(outcome.ok, isFalse);
      expect(outcome.failure, MtuProbeFailure.unreachable);
      expect(outcome.pathMtu, 0);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
