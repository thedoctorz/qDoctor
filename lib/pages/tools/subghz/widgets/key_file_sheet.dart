import 'package:flutter/material.dart';

import '../../../../components/clipboard.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../decode_raw/decode_raw_sub.dart';
import 'pulse_train.dart';

class KeyFileAction {
  const KeyFileAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;
  final bool enabled;
}

class KeyFileSheet {
  const KeyFileSheet._();

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String flipperFormat,
    String? subtitle,
    List<int> pulses = const [],
    List<KeyFileAction> actions = const [],
    bool pulsesAvailable = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _KeyFileSheetBody(
        title: title,
        subtitle: subtitle,
        flipperFormat: flipperFormat,
        pulses: pulses,
        actions: actions,
        pulsesAvailable: pulsesAvailable,
      ),
    );
  }
}

class _KeyFileSheetBody extends StatefulWidget {
  const _KeyFileSheetBody({
    required this.title,
    required this.subtitle,
    required this.flipperFormat,
    required this.pulses,
    required this.actions,
    required this.pulsesAvailable,
  });

  final String title;
  final String? subtitle;
  final String flipperFormat;
  final List<int> pulses;
  final List<KeyFileAction> actions;

  final bool pulsesAvailable;

  @override
  State<_KeyFileSheetBody> createState() => _KeyFileSheetBodyState();
}

class _KeyFileSheetBodyState extends State<_KeyFileSheetBody> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final s = context.l10n;
    final fields = DecodeRawSub.fields(widget.flipperFormat);
    final ordered = <String>[
      for (final key in const ['Frequency', 'Preset', 'Protocol'])
        if (fields.containsKey(key)) key,
      for (final key in fields.keys)
        if (!const {
          'Frequency',
          'Preset',
          'Protocol',
          'Filetype',
          'Version',
        }.contains(key))
          key,
    ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            _grabber(colors),
            _header(colors, s),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  if (widget.pulses.isNotEmpty) ...[
                    _sectionLabel(colors, s.subghzRxPulseTrain),
                    const SizedBox(height: 8),
                    PulseTrainView(pulses: widget.pulses),
                    const SizedBox(height: 20),
                  ] else if (widget.pulsesAvailable) ...[
                    _sectionLabel(colors, s.subghzRxPulseTrain),
                    const SizedBox(height: 8),
                    Text(
                      s.subghzRxNoPulses,
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
                    ),
                    const SizedBox(height: 20),
                  ],
                  for (final key in ordered)
                    _field(colors, key, _pretty(key, fields[key]!)),
                  const SizedBox(height: 20),
                  _sectionLabel(colors, s.decodeRawDetails),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.divider),
                    ),
                    child: SelectableText(
                      widget.flipperFormat.trim(),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.4,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.actions.isNotEmpty) _actionBar(colors),
          ],
        ),
      ),
    );
  }

  Widget _grabber(QAppColors colors) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: colors.divider,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _header(QAppColors colors, L10n s) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    widget.subtitle!,
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: s.decodeRawCopy,
          onPressed: () => copyTextToClipboard(
            context,
            widget.flipperFormat,
            message: s.decodeRawCopied,
          ),
          icon: Icon(Icons.copy_all_outlined, color: colors.textMuted),
        ),
      ],
    ),
  );

  Widget _sectionLabel(QAppColors colors, String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.8,
      color: colors.textMuted,
    ),
  );

  Widget _field(QAppColors colors, String key, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            key,
            style: TextStyle(fontSize: 13, color: colors.textMuted),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _actionBar(QAppColors colors) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          for (final action in widget.actions)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilledButton.icon(
                  onPressed: (!action.enabled || _busy)
                      ? null
                      : () => _run(action),
                  icon: Icon(action.icon, size: 18),
                  label: Text(
                    action.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.onAccent,
                    disabledBackgroundColor: colors.divider,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _run(KeyFileAction action) async {
    setState(() => _busy = true);
    try {
      await action.onTap();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _pretty(String key, String value) {
    if (key != 'Frequency') return value;
    final hz = int.tryParse(value.trim());
    if (hz == null) return value;
    return '${(hz / 1000000).toStringAsFixed(2)} MHz';
  }
}
