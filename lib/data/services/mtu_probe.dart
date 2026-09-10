import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

enum MtuProbeMethod { dns, quic }

enum MtuProbeFailure { socket, dontFragment, unreachable }

class MtuProbeOutcome {
  const MtuProbeOutcome({
    required this.linkMtu,
    required this.pathMtu,
    required this.method,
    required this.anchor,
    required this.trace,
    required this.converged,
    this.failure,
  });

  const MtuProbeOutcome.failed(this.failure, this.trace)
    : linkMtu = 0,
      pathMtu = 0,
      method = null,
      anchor = '',
      converged = false;

  final int linkMtu;
  final int pathMtu;
  final MtuProbeMethod? method;
  final String anchor;
  final List<String> trace;
  final bool converged;
  final MtuProbeFailure? failure;

  bool get ok => failure == null && pathMtu > 0;
}

class MtuProbeTarget {
  const MtuProbeTarget({
    required this.address,
    required this.port,
    required this.method,
    required this.label,
  });

  final String address;
  final int port;
  final MtuProbeMethod method;
  final String label;
}

class MtuProbe {
  MtuProbe({
    this.ipv6 = false,
    this.onTrace,
    this.budget = const Duration(seconds: 60),
    this.targets,
  });

  final bool ipv6;
  final void Function(String line)? onTrace;
  final Duration budget;
  final List<MtuProbeTarget>? targets;

  static const int searchCeiling = 1500;
  static const int searchFloor = 576;

  Future<MtuProbeOutcome> run() async {
    final trace = <String>[];
    void log(String line) {
      trace.add(line);
      onTrace?.call(line);
    }

    final session = _Session(ipv6, log, targets);
    if (!await session.open()) {
      final failure = session.bound
          ? MtuProbeFailure.dontFragment
          : MtuProbeFailure.socket;
      return MtuProbeOutcome.failed(failure, trace);
    }

    try {
      return await session.discover(
        deadline: DateTime.now().add(budget),
        trace: trace,
      );
    } finally {
      session.dispose();
    }
  }
}

class _Session {
  _Session(this._ipv6, this._log, this._targets);

  final bool _ipv6;
  final void Function(String line) _log;
  final List<MtuProbeTarget>? _targets;

  RawDatagramSocket? _socket;
  Object? _lastError;
  InternetAddress? _peer;
  bool Function(Uint8List reply)? _matcher;
  Completer<bool>? _waiter;

  bool bound = false;
  Duration _wait = const Duration(milliseconds: 900);
  bool _muted = false;
  int _cursor = 0;

  static const int _poolTarget = 3;
  static const Duration _spacing = Duration(milliseconds: 120);

  int get _headerBytes => _ipv6 ? 48 : 28;

  Future<bool> open() async {
    final socket = await _bind();
    if (socket == null) return false;
    _socket = socket;
    return true;
  }

  void dispose() {
    _release();
    _socket?.close();
    _socket = null;
  }

  Future<RawDatagramSocket?> _bind() async {
    RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(
        _ipv6 ? InternetAddress.anyIPv6 : InternetAddress.anyIPv4,
        0,
      );
    } on Object catch (error) {
      _lastError = error;
      return null;
    }

    bound = true;
    if (!_armDontFragment(socket)) {
      socket.close();
      return null;
    }

    socket.readEventsEnabled = true;
    socket.listen(
      (event) => _onEvent(socket, event),
      onError: (Object error) => _lastError = error,
      cancelOnError: false,
    );
    return socket;
  }

  Future<bool> _renew() async {
    _socket?.close();
    _socket = null;
    final socket = await _bind();
    if (socket == null) return false;
    _socket = socket;
    return true;
  }

  bool _armDontFragment(RawDatagramSocket socket) {
    for (final candidate in _dontFragmentOptions(_ipv6)) {
      try {
        socket.setRawOption(candidate);
      } on Object {
        continue;
      }
      return true;
    }
    _log('this device refused to send unfragmented probes');
    return false;
  }

  Future<MtuProbeOutcome> discover({
    required DateTime deadline,
    required List<String> trace,
  }) async {
    final pool = <_Anchor>[];
    var reach = const Duration(milliseconds: 250);

    for (final anchor in _anchors(_ipv6, _targets)) {
      if (DateTime.now().isAfter(deadline)) break;

      final floor = _floorFor(anchor);
      final rtt = await _timedAnswer(anchor, floor, attempts: 1);
      if (rtt == null) continue;

      pool.add(anchor);
      if (rtt > reach) reach = rtt;
      _log('${anchor.label} answered at $floor bytes in ${rtt.inMilliseconds} ms');
      if (pool.length >= _poolTarget) break;
    }

    if (pool.isEmpty) {
      if (_lastError != null) _log('last socket error: $_lastError');
      return MtuProbeOutcome.failed(MtuProbeFailure.unreachable, trace);
    }

    _wait = Duration(milliseconds: (reach.inMilliseconds * 4).clamp(700, 2200));

    final ladder = pool.reduce(
      (a, b) => b.minPayload < a.minPayload ? b : a,
    );
    final low = _floorFor(ladder);
    final link = await _localCeiling(ladder, low);
    _log('this device sends up to $link bytes unfragmented');

    final path = await _pathCeiling(pool, low, link, deadline);
    if (_muted && path <= low) {
      _log('the targets stopped answering before anything was measured');
      return MtuProbeOutcome.failed(MtuProbeFailure.unreachable, trace);
    }

    if (_muted) _log('the targets stopped answering part way through');
    _log('the internet path carries $path bytes whole');

    return MtuProbeOutcome(
      linkMtu: link,
      pathMtu: path,
      method: pool.first.method,
      anchor: pool.map((anchor) => anchor.label).join(', '),
      trace: trace,
      converged: !_muted && !DateTime.now().isAfter(deadline),
    );
  }

  int _floorFor(_Anchor anchor) =>
      max(MtuProbe.searchFloor, anchor.minPayload + _headerBytes);

  Future<int> _localCeiling(_Anchor anchor, int known) async {
    const ceiling = MtuProbe.searchCeiling;
    if (known >= ceiling || await _sendable(anchor, ceiling)) return ceiling;

    var low = known;
    var high = ceiling;
    while (high - low > 1) {
      final middle = low + (high - low) ~/ 2;
      if (await _sendable(anchor, middle)) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return low;
  }

  Future<int> _pathCeiling(
    List<_Anchor> pool,
    int known,
    int ceiling,
    DateTime deadline,
  ) async {
    final coarse = _ladder(known, ceiling, _coarseSteps);
    if (coarse.isEmpty) return known;

    var landed = -1;
    for (var rung = 0; rung < coarse.length; rung++) {
      if (DateTime.now().isAfter(deadline)) break;

      if (await _hits(pool, coarse[rung], 1)) {
        landed = rung;
        break;
      }
      if (!await _stillTalking(pool)) {
        _muted = true;
        return known;
      }
    }

    if (landed < 0) return known;

    var best = coarse[landed];
    final upper = landed == 0 ? ceiling : coarse[landed - 1];

    for (final rung in _ladder(best, upper, _fineSteps).reversed) {
      if (DateTime.now().isAfter(deadline)) break;
      if (!await _hits(pool, rung, 3)) break;
      best = rung;
    }
    return best;
  }

  Future<bool> _hits(List<_Anchor> pool, int total, int attempts) async {
    final usable = _rotate(pool, total);
    if (usable.isEmpty) return false;

    for (var attempt = 0; attempt < attempts; attempt++) {
      final anchor = usable[attempt % usable.length];
      if (await _answers(anchor, total, attempts: 1)) return true;
    }
    return false;
  }

  Future<bool> _stillTalking(List<_Anchor> pool) async {
    for (final anchor in _rotate(pool, 0)) {
      if (await _answers(anchor, _floorFor(anchor), attempts: 1)) return true;
    }
    return false;
  }

  List<_Anchor> _rotate(List<_Anchor> pool, int total) {
    final usable = <_Anchor>[
      for (final anchor in pool)
        if (total == 0 || total - _headerBytes >= anchor.minPayload) anchor,
    ];
    if (usable.length < 2) return usable;

    _cursor = (_cursor + 1) % usable.length;
    return <_Anchor>[...usable.skip(_cursor), ...usable.take(_cursor)];
  }

  Future<bool> _sendable(_Anchor anchor, int total) async {
    final payload = total - _headerBytes;
    if (payload < anchor.minPayload) return false;
    return _transmit(anchor, anchor.build(payload));
  }

  Future<bool> _answers(_Anchor anchor, int total, {int attempts = 2}) async {
    return await _timedAnswer(anchor, total, attempts: attempts) != null;
  }

  Future<Duration?> _timedAnswer(
    _Anchor anchor,
    int total, {
    int attempts = 2,
  }) async {
    final payload = total - _headerBytes;
    if (payload < anchor.minPayload) return null;

    for (var attempt = 0; attempt < attempts; attempt++) {
      final probe = anchor.build(payload);
      final waiter = Completer<bool>();
      _peer = anchor.address;
      _matcher = probe.matches;
      _waiter = waiter;

      final started = DateTime.now();
      if (!await _transmit(anchor, probe)) {
        _release();
        return null;
      }

      final answered = await waiter.future.timeout(
        _wait,
        onTimeout: () => false,
      );
      _release();
      if (answered) return DateTime.now().difference(started);
      await Future<void>.delayed(_spacing);
    }
    return null;
  }

  Future<bool> _transmit(_Anchor anchor, _Probe probe) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final socket = _socket;
      if (socket == null) return false;

      var sent = 0;
      try {
        sent = socket.send(probe.bytes, anchor.address, anchor.port);
      } on Object catch (error) {
        _lastError = error;
      }
      if (sent > 0) return true;

      await Future<void>.delayed(const Duration(milliseconds: 8));
      if (!await _renew()) return false;
    }
    return false;
  }

  void _release() {
    _peer = null;
    _matcher = null;
    _waiter = null;
  }

  void _onEvent(RawDatagramSocket socket, RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    for (
      var datagram = socket.receive();
      datagram != null;
      datagram = socket.receive()
    ) {
      final matcher = _matcher;
      final waiter = _waiter;
      if (matcher == null || waiter == null || waiter.isCompleted) continue;
      if (datagram.address.address != _peer?.address) continue;
      if (!matcher(datagram.data)) continue;

      _matcher = null;
      _waiter = null;
      waiter.complete(true);
    }
  }
}

const List<int> _coarseSteps = <int>[
  1500,
  1452,
  1400,
  1360,
  1320,
  1280,
  1240,
  1200,
  1100,
  900,
  768,
  640,
];

const List<int> _fineSteps = <int>[
  1500,
  1492,
  1480,
  1472,
  1464,
  1458,
  1452,
  1442,
  1436,
  1428,
  1420,
  1412,
  1400,
  1392,
  1380,
  1372,
  1360,
  1352,
  1340,
  1332,
  1320,
  1300,
  1280,
  1260,
  1240,
  1220,
  1200,
  1150,
  1100,
  1024,
  960,
  900,
  832,
  768,
  704,
  640,
];

List<int> _ladder(int floor, int ceiling, List<int> steps) {
  final rungs = <int>{
    if (ceiling > floor) ceiling,
    for (final rung in steps)
      if (rung <= ceiling && rung > floor) rung,
  }.toList();
  rungs.sort((a, b) => b.compareTo(a));
  return rungs;
}

List<RawSocketOption> _dontFragmentOptions(bool ipv6) {
  final level = ipv6 ? RawSocketOption.levelIPv6 : RawSocketOption.levelIPv4;

  if (Platform.isLinux || Platform.isAndroid) {
    final name = ipv6 ? 23 : 10;
    return <RawSocketOption>[
      RawSocketOption.fromInt(level, name, 3),
      RawSocketOption.fromInt(level, name, 2),
    ];
  }

  if (Platform.isWindows) {
    return <RawSocketOption>[RawSocketOption.fromInt(level, 14, 1)];
  }

  return <RawSocketOption>[
    RawSocketOption.fromInt(level, ipv6 ? 62 : 28, 1),
  ];
}

class _Probe {
  const _Probe(this.bytes, this.matches);

  final Uint8List bytes;
  final bool Function(Uint8List reply) matches;
}

abstract class _Anchor {
  const _Anchor(this.address, this.port, this.label);

  final InternetAddress address;
  final int port;
  final String label;

  MtuProbeMethod get method;

  int get minPayload;

  _Probe build(int payload);
}

final Random _entropy = Random.secure();

class _DnsAnchor extends _Anchor {
  const _DnsAnchor(super.address, super.port, super.label);

  static const int _fixedBytes = 32;
  static const int _paddingOption = 12;

  @override
  MtuProbeMethod get method => MtuProbeMethod.dns;

  @override
  int get minPayload => _fixedBytes;

  @override
  _Probe build(int payload) {
    final padding = payload - _fixedBytes;
    final id = _entropy.nextInt(0x10000);

    final out = Uint8List(payload);
    final view = ByteData.view(out.buffer);

    view.setUint16(0, id);
    view.setUint16(2, 0x0100);
    view.setUint16(4, 1);
    view.setUint16(10, 1);

    view.setUint16(13, 2);
    view.setUint16(15, 1);

    view.setUint16(18, 41);
    view.setUint16(20, 1232);
    view.setUint16(26, 4 + padding);
    view.setUint16(28, _paddingOption);
    view.setUint16(30, padding);

    return _Probe(out, (reply) {
      if (reply.length < 4) return false;
      if (reply[0] != (id >> 8) || reply[1] != (id & 0xff)) return false;
      return reply[2] & 0x80 != 0;
    });
  }
}

class _QuicAnchor extends _Anchor {
  const _QuicAnchor(super.address, super.port, super.label);

  static const int _connectionIdBytes = 8;

  @override
  MtuProbeMethod get method => MtuProbeMethod.quic;

  @override
  int get minPayload => 1200;

  @override
  _Probe build(int payload) {
    final out = Uint8List(payload);
    out[0] = 0xc0;
    out[1] = 0x1a;
    out[2] = 0x2a;
    out[3] = 0x3a;
    out[4] = 0x4a;

    out[5] = _connectionIdBytes;
    for (var i = 0; i < _connectionIdBytes; i++) {
      out[6 + i] = _entropy.nextInt(256);
    }

    final scidAt = 7 + _connectionIdBytes;
    out[scidAt - 1] = _connectionIdBytes;
    final source = Uint8List(_connectionIdBytes);
    for (var i = 0; i < _connectionIdBytes; i++) {
      source[i] = _entropy.nextInt(256);
      out[scidAt + i] = source[i];
    }

    return _Probe(out, (reply) {
      if (reply.length < 7) return false;
      if (reply[0] & 0x80 == 0) return false;
      if (reply[1] != 0 || reply[2] != 0 || reply[3] != 0 || reply[4] != 0) {
        return false;
      }

      final echoed = reply[5];
      if (echoed != source.length || reply.length < 6 + echoed) return false;
      for (var i = 0; i < echoed; i++) {
        if (reply[6 + i] != source[i]) return false;
      }
      return true;
    });
  }
}

List<_Anchor> _anchors(bool ipv6, List<MtuProbeTarget>? targets) {
  if (targets != null) {
    return <_Anchor>[
      for (final target in targets)
        if (target.method == MtuProbeMethod.dns)
          _DnsAnchor(
            InternetAddress(target.address),
            target.port,
            target.label,
          )
        else
          _QuicAnchor(
            InternetAddress(target.address),
            target.port,
            target.label,
          ),
    ];
  }

  if (ipv6) {
    return <_Anchor>[
      _DnsAnchor(InternetAddress('2606:4700:4700::1111'), 53, 'cloudflare dns'),
      _QuicAnchor(
        InternetAddress('2606:4700:4700::1111'),
        443,
        'cloudflare quic',
      ),
      _DnsAnchor(InternetAddress('2001:4860:4860::8888'), 53, 'google dns'),
      _DnsAnchor(InternetAddress('2620:fe::fe'), 53, 'quad9 dns'),
    ];
  }

  return <_Anchor>[
    _DnsAnchor(InternetAddress('1.1.1.1'), 53, 'cloudflare dns'),
    _QuicAnchor(InternetAddress('1.1.1.1'), 443, 'cloudflare quic'),
    _DnsAnchor(InternetAddress('8.8.8.8'), 53, 'google dns'),
    _QuicAnchor(InternetAddress('162.159.198.1'), 443, 'cloudflare edge quic'),
    _DnsAnchor(InternetAddress('9.9.9.9'), 53, 'quad9 dns'),
    _DnsAnchor(InternetAddress('1.0.0.1'), 53, 'cloudflare dns backup'),
  ];
}
