import 'package:flutter_test/flutter_test.dart';
import 'package:oblivion/data/models/tunnel_status.dart';

void main() {
  group('tunnel status', () {
    test('a failure keeps the reason it was given', () {
      const status = TunnelStatus(
        stage: TunnelStage.failed,
        message: 'conduit mode needs a key this build does not embed',
      );

      expect(status.stage, TunnelStage.failed);
      expect(status.message, isNotNull);
    });

    test('a plain copy carries the reason forward', () {
      const status = TunnelStatus(
        stage: TunnelStage.failed,
        message: 'no working tunnel',
      );

      expect(status.copyWith().message, 'no working tunnel');
    });

    test('reconnecting drops the reason from the last failure', () {
      const status = TunnelStatus(
        stage: TunnelStage.failed,
        message: 'no working tunnel',
      );

      final next = status.copyWith(
        stage: TunnelStage.connecting,
        clearMessage: true,
      );

      expect(next.stage, TunnelStage.connecting);
      expect(next.message, isNull);
    });

    test('capabilities default to a build without conduit', () {
      const capability = TunnelCapability(embedded: true, privileged: true);
      expect(capability.conduit, isFalse);

      final parsed = TunnelCapability.fromMap(<dynamic, dynamic>{
        'embedded': true,
        'privileged': true,
        'conduit': true,
      });
      expect(parsed.conduit, isTrue);
      expect(parsed.ready, isTrue);
    });

    test('a capability payload missing conduit is read as unavailable', () {
      final parsed = TunnelCapability.fromMap(<dynamic, dynamic>{});
      expect(parsed.conduit, isFalse);
      expect(parsed.embedded, isTrue);
    });
  });
}
