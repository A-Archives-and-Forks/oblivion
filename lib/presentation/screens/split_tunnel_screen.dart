import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/tunnel_settings.dart';
import '../../data/services/app_icon_cache.dart';
import '../../data/services/tunnel_channel.dart';
import '../../l10n/generated/app_localizations.dart';
import '../providers/app_providers.dart';
import '../providers/tunnel_providers.dart';
import '../widgets/pickers.dart';
import '../widgets/screen_header.dart';
import '../widgets/settings_list.dart';

String splitModeTitle(L10n l10n, SplitTunnelMode value) => switch (value) {
  SplitTunnelMode.disabled => l10n.splitTunnelDisabled,
  SplitTunnelMode.bypassSelected => l10n.splitTunnelBlacklist,
  SplitTunnelMode.onlySelected => l10n.splitTunnelWhitelist,
};

String splitModeDesc(L10n l10n, SplitTunnelMode value) => switch (value) {
  SplitTunnelMode.disabled => l10n.splitTunnelDisabledDesc,
  SplitTunnelMode.bypassSelected => l10n.splitTunnelBlacklistDesc,
  SplitTunnelMode.onlySelected => l10n.splitTunnelWhitelistDesc,
};

final _showSystemAppsProvider = StateProvider<bool>((ref) => false);

final _appIconCacheProvider = Provider.autoDispose<AppIconCache>((ref) {
  return AppIconCache(ref.watch(tunnelChannelProvider));
});

class _AppEntry {
  const _AppEntry(this.app, this.searchKey);

  final InstalledApp app;
  final String searchKey;
}

final _installedAppsProvider = FutureProvider<List<_AppEntry>>((ref) async {
  final includeSystem = ref.watch(_showSystemAppsProvider);

  try {
    final apps = await ref
        .watch(tunnelChannelProvider)
        .installedApps(includeSystem: includeSystem);

    final entries = <_AppEntry>[
      for (final app in apps)
        _AppEntry(
          app,
          '${app.label.toLowerCase()} ${app.packageName.toLowerCase()}',
        ),
    ];
    entries.sort((a, b) => a.searchKey.compareTo(b.searchKey));
    return entries;
  } catch (_) {
    return const <_AppEntry>[];
  }
});

class SplitTunnelScreen extends ConsumerStatefulWidget {
  const SplitTunnelScreen({super.key});

  @override
  ConsumerState<SplitTunnelScreen> createState() => _SplitTunnelScreenState();
}

class _SplitTunnelScreenState extends ConsumerState<SplitTunnelScreen> {
  final ValueNotifier<String> _query = ValueNotifier<String>('');

  @override
  void initState() {
    super.initState();
    ref.invalidate(_installedAppsProvider);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;

    final mode = ref.watch(
      tunnelSettingsProvider.select((s) => s.splitTunnelMode),
    );
    final bypassed = ref.watch(
      tunnelSettingsProvider.select((s) => s.bypassedApps),
    );
    final controller = ref.read(tunnelSettingsProvider.notifier);
    final showSystem = ref.watch(_showSystemAppsProvider);
    final apps = ref.watch(_installedAppsProvider);
    final icons = ref.watch(_appIconCacheProvider);

    final enabled = mode.picksApps;
    final starved = mode == SplitTunnelMode.onlySelected && bypassed.isEmpty;

    return CupertinoPageScaffold(
      backgroundColor: palette.canvas,
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: <Widget>[
                ScreenHeader(title: l10n.splitTunnel),
                SettingsGroup(
                  children: <Widget>[
                    SettingsRow(
                      title: l10n.splitTunnel,
                      subtitle: splitModeDesc(l10n, mode),
                      value: splitModeTitle(l10n, mode),
                      onTap: () => showChoiceSheet<SplitTunnelMode>(
                        context: context,
                        title: l10n.splitTunnel,
                        selected: mode,
                        options: SplitTunnelMode.values
                            .map(
                              (value) => PickerOption<SplitTunnelMode>(
                                value: value,
                                title: splitModeTitle(l10n, value),
                                subtitle: splitModeDesc(l10n, value),
                              ),
                            )
                            .toList(),
                        onSelected: (value) => controller.update(
                          (s) => s.copyWith(splitTunnelMode: value),
                        ),
                      ),
                    ),
                    if (enabled)
                      SettingsRow(
                        title: l10n.splitTunnelPick,
                        subtitle: starved
                            ? l10n.splitAllowEmpty
                            : (mode == SplitTunnelMode.onlySelected
                                  ? l10n.splitAllowCount('${bypassed.length}')
                                  : l10n.splitBypassCount(
                                      '${bypassed.length}',
                                    )),
                        destructive: starved,
                      ),
                    SettingsRow(
                      title: l10n.showSystemApps,
                      enabled: enabled,
                      trailing: AppSwitch(
                        value: showSystem,
                        onChanged: enabled
                            ? (value) =>
                                  ref
                                          .read(
                                            _showSystemAppsProvider.notifier,
                                          )
                                          .state =
                                      value
                            : null,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: CupertinoTextField(
                    enabled: enabled,
                    placeholder: l10n.searchApps,
                    prefix: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 10),
                      child: Icon(
                        CupertinoIcons.search,
                        size: 17,
                        color: palette.labelSecondary,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 11,
                    ),
                    style: AppText.rowTitle(palette.label),
                    placeholderStyle: AppText.rowTitle(palette.labelSecondary),
                    decoration: BoxDecoration(
                      color: palette.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: palette.separator),
                    ),
                    onChanged: (value) =>
                        _query.value = value.trim().toLowerCase(),
                  ),
                ),
                Expanded(
                  child: apps.when(
                    loading: () => const Center(
                      child: CupertinoActivityIndicator(radius: 10),
                    ),
                    error: (_, _) => Center(
                      child: Text(
                        l10n.logsEmpty,
                        style: AppText.caption(palette.labelSecondary),
                      ),
                    ),
                    data: (list) => ValueListenableBuilder<String>(
                      valueListenable: _query,
                      builder: (_, query, _) => _AppList(
                        entries: query.isEmpty
                            ? list
                            : <_AppEntry>[
                                for (final entry in list)
                                  if (entry.searchKey.contains(query)) entry,
                              ],
                        bypassed: bypassed,
                        enabled: enabled,
                        emptyLabel: l10n.logsFilterEmpty,
                        onToggle: controller.toggleBypassedApp,
                        icons: icons,
                      ),
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

class _AppList extends StatelessWidget {
  const _AppList({
    required this.entries,
    required this.bypassed,
    required this.enabled,
    required this.emptyLabel,
    required this.onToggle,
    required this.icons,
  });

  final List<_AppEntry> entries;
  final Set<String> bypassed;
  final bool enabled;
  final String emptyLabel;
  final ValueChanged<String> onToggle;
  final AppIconCache icons;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (entries.isEmpty) {
      return Center(
        child: Text(emptyLabel, style: AppText.caption(palette.labelSecondary)),
      );
    }

    return ListView.builder(
      primary: false,
      itemCount: entries.length,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemBuilder: (_, index) {
        final entry = entries[index];
        return _AppRow(
          app: entry.app,
          icons: icons,
          enabled: enabled,
          bypassed: bypassed.contains(entry.app.packageName),
          onChanged: () => onToggle(entry.app.packageName),
        );
      },
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.icons,
    required this.enabled,
    required this.bypassed,
    required this.onChanged,
  });

  final InstalledApp app;
  final AppIconCache icons;
  final bool enabled;
  final bool bypassed;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      color: palette.card,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 9, 16, 9),
      foregroundDecoration: BoxDecoration(
        border: BorderDirectional(
          bottom: BorderSide(color: palette.separator, width: 1),
        ),
      ),
      child: Row(
        children: <Widget>[
          _AppIcon(packageName: app.packageName, icons: icons),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  app.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.rowTitle(
                    enabled ? palette.label : palette.labelSecondary,
                  ),
                ),
                Text(
                  app.packageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: AppText.caption(palette.labelSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppSwitch(
            value: bypassed,
            onChanged: enabled ? (_) => onChanged() : null,
          ),
        ],
      ),
    );
  }
}

class _AppIcon extends StatefulWidget {
  const _AppIcon({required this.packageName, required this.icons});

  final String packageName;
  final AppIconCache icons;

  @override
  State<_AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<_AppIcon> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _AppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageName != widget.packageName) _resolve();
  }

  void _resolve() {
    final wanted = widget.packageName;

    if (widget.icons.holds(wanted)) {
      _bytes = widget.icons.peek(wanted);
      return;
    }

    _bytes = null;
    widget.icons.load(wanted).then((value) {
      if (!mounted || widget.packageName != wanted) return;
      setState(() => _bytes = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final data = _bytes;

    return SizedBox(
      width: 34,
      height: 34,
      child: data == null || data.isEmpty
          ? _placeholder(palette)
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                data,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => _placeholder(palette),
              ),
            ),
    );
  }

  Widget _placeholder(AppPalette palette) => DecoratedBox(
    decoration: BoxDecoration(
      color: palette.cardPressed,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(CupertinoIcons.app, size: 17, color: palette.labelSecondary),
  );
}
