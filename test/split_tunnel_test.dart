import 'package:flutter_test/flutter_test.dart';
import 'package:oblivion/data/models/tunnel_settings.dart';

TunnelSettings _split(SplitTunnelMode mode, Set<String> apps) =>
    TunnelSettings(splitTunnelMode: mode, bypassedApps: apps);

void main() {
  group('split tunnelling', () {
    test('off by default, and nothing is picked', () {
      const settings = TunnelSettings();

      expect(settings.splitTunnelMode, SplitTunnelMode.disabled);
      expect(settings.splitTunnelActive, isFalse);
      expect(settings.bypassedApps, isEmpty);
    });

    test('both picking modes ask for an app list', () {
      expect(SplitTunnelMode.disabled.picksApps, isFalse);
      expect(SplitTunnelMode.bypassSelected.picksApps, isTrue);
      expect(SplitTunnelMode.onlySelected.picksApps, isTrue);
    });

    test('bypass keeps the chosen apps off the tunnel', () {
      final settings = _split(SplitTunnelMode.bypassSelected, <String>{
        'com.bank.app',
      });

      final payload = settings.toPlatformPayload();
      expect(payload['splitTunnelMode'], 'bypassSelected');
      expect(payload['bypassedApps'], <String>['com.bank.app']);
      expect(settings.splitTunnelStarved, isFalse);
    });

    test('only-selected sends the same list under its own mode', () {
      final settings = _split(SplitTunnelMode.onlySelected, <String>{
        'org.telegram.messenger',
        'com.instagram.android',
      });

      final payload = settings.toPlatformPayload();
      expect(payload['splitTunnelMode'], 'onlySelected');
      expect(
        payload['bypassedApps'],
        <String>['org.telegram.messenger', 'com.instagram.android'],
      );
      expect(settings.splitTunnelStarved, isFalse);
    });

    test('only-selected with nothing picked is called out', () {
      final settings = _split(SplitTunnelMode.onlySelected, const <String>{});

      expect(settings.splitTunnelActive, isTrue);
      expect(settings.splitTunnelStarved, isTrue);
    });

    test('an empty bypass list is harmless, unlike an empty allow list', () {
      final bypass = _split(SplitTunnelMode.bypassSelected, const <String>{});
      expect(bypass.splitTunnelStarved, isFalse);
    });

    test('an unknown stored mode falls back to off', () {
      expect(SplitTunnelMode.fromName('somethingElse'), SplitTunnelMode.disabled);
      expect(SplitTunnelMode.fromName(null), SplitTunnelMode.disabled);
      expect(
        SplitTunnelMode.fromName('onlySelected'),
        SplitTunnelMode.onlySelected,
      );
      expect(
        SplitTunnelMode.fromName('bypassSelected'),
        SplitTunnelMode.bypassSelected,
      );
    });

    test('toggling an app moves it in and out of the list', () {
      var settings = _split(SplitTunnelMode.onlySelected, const <String>{});

      final next = settings.bypassedApps.toSet()..add('com.example.one');
      settings = settings.copyWith(bypassedApps: next);
      expect(settings.splitTunnelStarved, isFalse);

      final removed = settings.bypassedApps.toSet()..remove('com.example.one');
      settings = settings.copyWith(bypassedApps: removed);
      expect(settings.splitTunnelStarved, isTrue);
    });
  });
}
