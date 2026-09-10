import 'package:flutter/cupertino.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';

Future<void> showDeveloperNote(BuildContext context) {
  return showCupertinoModalPopup<void>(
    context: context,
    barrierDismissible: false,
    builder: (sheetContext) => const _DeveloperNoteSheet(),
  );
}

class _DeveloperNoteSheet extends StatelessWidget {
  const _DeveloperNoteSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final media = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.82),
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        CupertinoIcons.info_circle_fill,
                        size: 22,
                        color: palette.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.devNoteTitle,
                          style: AppText.title(palette.label),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    children: <Widget>[
                      Text(
                        l10n.devNoteIntro,
                        style: AppText.rowValue(palette.label),
                      ),
                      _Section(
                        title: l10n.devNoteHttp2Title,
                        body: l10n.devNoteHttp2Body,
                      ),
                      _Section(
                        title: l10n.devNoteWireGuardTitle,
                        body: l10n.devNoteWireGuardBody,
                      ),
                      _Section(
                        title: l10n.devNoteGoolTitle,
                        body: l10n.devNoteGoolBody,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: CupertinoButton(
                    color: palette.primary,
                    borderRadius: BorderRadius.circular(10),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      l10n.devNoteDismiss,
                      style: AppText.rowTitle(const Color(0xFFFFFFFF)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: AppText.rowTitle(palette.primary).copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(body, style: AppText.rowValue(palette.label)),
        ],
      ),
    );
  }
}
