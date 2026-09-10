import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/mtu_plan.dart';
import '../../data/models/tunnel_settings.dart';
import '../../data/services/mtu_probe.dart';
import '../../l10n/generated/app_localizations.dart';

Future<MtuPlan?> showMtuOptimizerSheet({
  required BuildContext context,
  required TunnelSettings settings,
}) {
  return showCupertinoModalPopup<MtuPlan>(
    context: context,
    barrierDismissible: false,
    builder: (sheetContext) => _MtuOptimizerSheet(settings: settings),
  );
}

Future<MtuProbeOutcome>? _inFlight;

Future<MtuProbeOutcome> _measureOnce(MtuProbe probe) async {
  while (_inFlight != null) {
    await _inFlight;
  }

  final run = probe.run();
  _inFlight = run;
  try {
    return await run;
  } finally {
    _inFlight = null;
  }
}

class _MtuOptimizerSheet extends StatefulWidget {
  const _MtuOptimizerSheet({required this.settings});

  final TunnelSettings settings;

  @override
  State<_MtuOptimizerSheet> createState() => _MtuOptimizerSheetState();
}

class _MtuOptimizerSheetState extends State<_MtuOptimizerSheet> {
  bool _running = true;
  String _status = '';
  MtuProbeOutcome? _outcome;
  MtuPlan? _plan;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    setState(() {
      _running = true;
      _status = '';
      _outcome = null;
      _plan = null;
    });

    final probe = MtuProbe(
      ipv6: widget.settings.ipVersion == IpVersion.v6,
      onTrace: (line) {
        if (mounted) setState(() => _status = line);
      },
    );

    final outcome = await _measureOnce(probe);
    if (!mounted) return;

    setState(() {
      _running = false;
      _outcome = outcome;
      _plan = outcome.ok
          ? MtuPlan.resolve(
              settings: widget.settings,
              pathMtu: outcome.pathMtu,
            )
          : null;
    });
  }

  String _failureText(L10n l10n, MtuProbeFailure failure) => switch (failure) {
    MtuProbeFailure.socket => l10n.mtuOptimizeFailedSocket,
    MtuProbeFailure.dontFragment => l10n.mtuOptimizeFailedDf,
    MtuProbeFailure.unreachable => l10n.mtuOptimizeFailedUnreachable,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;

    return Container(
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(l10n.mtuOptimizeTitle, style: AppText.title(palette.label)),
              const SizedBox(height: 16),
              if (_running) ..._measuring(l10n, palette),
              if (!_running) ..._settled(l10n, palette),
              const SizedBox(height: 18),
              _actions(l10n, palette),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _measuring(L10n l10n, AppPalette palette) => <Widget>[
    Row(
      children: <Widget>[
        const CupertinoActivityIndicator(),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            l10n.mtuOptimizeMeasuring,
            style: AppText.rowTitle(palette.label),
          ),
        ),
      ],
    ),
    const SizedBox(height: 10),
    Text(
      _status.isEmpty ? l10n.mtuOptimizeHint : _status,
      style: AppText.caption(palette.labelSecondary),
    ),
  ];

  List<Widget> _settled(L10n l10n, AppPalette palette) {
    final outcome = _outcome;
    final plan = _plan;

    if (outcome == null) return const <Widget>[];

    final failure = outcome.failure;
    if (failure != null || plan == null) {
      return <Widget>[
        Text(l10n.mtuOptimizeFailed, style: AppText.rowTitle(palette.danger)),
        const SizedBox(height: 8),
        Text(
          failure == null
              ? l10n.mtuOptimizeFailedUnreachable
              : _failureText(l10n, failure),
          style: AppText.caption(palette.labelSecondary),
        ),
      ];
    }

    final notes = <String>[
      if (!outcome.converged) l10n.mtuOptimizePartial,
      if (plan.pathLimited) l10n.mtuOptimizeNarrow,
      if (plan.handshakeAtRisk) l10n.mtuOptimizeTight,
      if (plan.tunnelMtu == widget.settings.tunnelMtu &&
          plan.coreMtu == widget.settings.coreMtu)
        l10n.mtuOptimizeUnchanged,
    ];

    return <Widget>[
      _reading(palette, l10n.mtuOptimizeTransport, plan.profile.label),
      _reading(palette, l10n.mtuOptimizeLink, '${outcome.linkMtu}'),
      _reading(palette, l10n.mtuOptimizePath, '${outcome.pathMtu}'),
      _reading(palette, l10n.mtuOptimizeOverhead, '${plan.overhead}'),
      if (plan.coreMtu > 0)
        _reading(palette, l10n.mtuOptimizeCore, '${plan.coreMtu}'),
      const SizedBox(height: 6),
      _reading(
        palette,
        l10n.mtuOptimizeResult,
        '${plan.tunnelMtu}',
        emphasise: true,
      ),
      if (notes.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        Text(
          notes.join('\n'),
          style: AppText.caption(palette.labelSecondary),
        ),
      ],
    ];
  }

  Widget _reading(
    AppPalette palette,
    String label,
    String value, {
    bool emphasise = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: emphasise
                  ? AppText.rowTitle(palette.label)
                  : AppText.caption(palette.labelSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: emphasise
                ? AppText.rowTitle(palette.primary)
                : AppText.rowValue(palette.label),
          ),
        ],
      ),
    );
  }

  Widget _actions(L10n l10n, AppPalette palette) {
    final plan = _plan;

    return Row(
      children: <Widget>[
        Expanded(
          child: CupertinoButton(
            color: palette.cardPressed,
            borderRadius: BorderRadius.circular(10),
            padding: const EdgeInsets.symmetric(vertical: 13),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel, style: AppText.rowTitle(palette.label)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: CupertinoButton(
            color: palette.primary,
            borderRadius: BorderRadius.circular(10),
            padding: const EdgeInsets.symmetric(vertical: 13),
            onPressed: _running
                ? null
                : () {
                    if (plan == null) {
                      _measure();
                      return;
                    }
                    Navigator.of(context).pop(plan);
                  },
            child: Text(
              plan == null ? l10n.mtuOptimizeRetry : l10n.mtuOptimizeApply,
              style: AppText.rowTitle(const Color(0xFFFFFFFF)),
            ),
          ),
        ),
      ],
    );
  }
}
