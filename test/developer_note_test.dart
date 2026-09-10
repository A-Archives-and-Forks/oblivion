import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oblivion/l10n/generated/app_localizations.dart';
import 'package:oblivion/presentation/widgets/developer_note.dart';

Widget _host(Locale locale) {
  return CupertinoApp(
    locale: locale,
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      L10n.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: Builder(
      builder: (context) => CupertinoButton(
        onPressed: () => showDeveloperNote(context),
        child: const Text('open'),
      ),
    ),
  );
}

Future<L10n> _openNote(WidgetTester tester, Locale locale) async {
  tester.view.physicalSize = const Size(1000, 3200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_host(locale));
  final l10n = await L10n.delegate.load(locale);

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return l10n;
}

void main() {
  group('developer note', () {
    for (final locale in const <Locale>[Locale('en'), Locale('fa')]) {
      testWidgets('${locale.languageCode} carries every section', (
        tester,
      ) async {
        final l10n = await _openNote(tester, locale);

        expect(find.text(l10n.devNoteTitle), findsOneWidget);
        expect(find.text(l10n.devNoteDismiss), findsOneWidget);

        for (final section in <String>[
          l10n.devNoteIntro,
          l10n.devNoteHttp2Title,
          l10n.devNoteHttp2Body,
          l10n.devNoteWireGuardTitle,
          l10n.devNoteWireGuardBody,
          l10n.devNoteGoolTitle,
          l10n.devNoteGoolBody,
        ]) {
          expect(find.text(section), findsOneWidget, reason: section);
        }
      });
    }

    testWidgets('the note stays put until the button is used', (tester) async {
      final l10n = await _openNote(tester, const Locale('en'));

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text(l10n.devNoteTitle), findsOneWidget);

      await tester.tap(find.text(l10n.devNoteDismiss));
      await tester.pumpAndSettle();
      expect(find.text(l10n.devNoteTitle), findsNothing);
    });

    testWidgets('the persian note is written in persian', (tester) async {
      final l10n = await _openNote(tester, const Locale('fa'));

      final persian = RegExp(r'[؀-ۿ]');
      for (final text in <String>[
        l10n.devNote,
        l10n.devNoteIntro,
        l10n.devNoteHttp2Body,
        l10n.devNoteWireGuardBody,
        l10n.devNoteGoolBody,
      ]) {
        expect(persian.hasMatch(text), isTrue, reason: text);
      }
    });
  });
}
