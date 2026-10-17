import 'package:flutter/material.dart';

import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../action_row.dart';
import '../info_line.dart';

class DeviceInfoCard extends StatefulWidget {
  const DeviceInfoCard({
    super.key,
    required this.entries,
    required this.onOpenFullInfo,
    required this.onExport,
  });

  final List<MapEntry<String, String>> entries;
  final VoidCallback onOpenFullInfo;
  final VoidCallback onExport;

  @override
  State<DeviceInfoCard> createState() => _DeviceInfoCardState();
}

class _DeviceInfoCardState extends State<DeviceInfoCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 17, color: colors.accent),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      context.l10n.deviceInfoTitle,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            for (var i = 0; i < widget.entries.length; i++) ...[
              FlipperInfoLine(
                label: widget.entries[i].key,
                value: widget.entries[i].value,
              ),
              Divider(height: 1, color: colors.divider),
            ],
            FlipperActionRow(
              iconAsset: 'assets/ic/nav/navigate.svg',
              label: context.l10n.deviceFullInfo,
              color: colors.accent,
              onTap: widget.onOpenFullInfo,
            ),
            Divider(height: 1, color: colors.divider),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onExport,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Icon(Icons.copy, color: colors.accent, size: 20),
                      ),
                      Expanded(
                        child: Text(
                          context.l10n.deviceExport,
                          style: TextStyle(
                            color: colors.accent,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
