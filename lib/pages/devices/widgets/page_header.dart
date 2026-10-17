import 'package:flutter/material.dart';

import '../../../services/localization/l10n.dart';
import '../../../theme/theme.dart';
import '../models/device_info.dart';
import 'flipper_mockup.dart';

class DevicePageHeader extends StatelessWidget {
  const DevicePageHeader({
    super.key,
    required this.topInset,
    required this.headerHeight,
    required this.title,
    required this.subtitle,
    required this.active,
    this.dfu = false,
    this.infoEntries = const [],
    this.deviceInfo = const {},
    this.connectionLabel = 'USB',
    this.connectionIcon = Icons.usb,
    this.showStats = false,
    this.onOpenFullInfo,
  });

  final double topInset;
  final double headerHeight;
  final String title;
  final String subtitle;
  final bool active;
  final bool dfu;
  final List<MapEntry<String, String>> infoEntries;
  final Map<String, String> deviceInfo;
  final String connectionLabel;
  final IconData connectionIcon;
  final bool showStats;
  final VoidCallback? onOpenFullInfo;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: colors.accent,
        padding: EdgeInsets.only(top: topInset),
        height: headerHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 560;
            if (wide && infoEntries.isNotEmpty) {
              return Stack(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: FlipperMockupHero(
                        active: active,
                        dfu: dfu,
                        title: title,
                        infoEntries: infoEntries,
                        deviceInfo: deviceInfo,
                        connectionLabel: connectionLabel,
                        connectionIcon: connectionIcon,
                        stats: showStats
                            ? HeaderDeviceStats(
                                deviceInfo: deviceInfo,
                                color: colors.onAccent,
                              )
                            : null,
                      ),
                    ),
                  ),
                  if (onOpenFullInfo != null)
                    Positioned(
                      right: 14,
                      bottom: 14,
                      child: TextButton.icon(
                        onPressed: onOpenFullInfo,
                        icon: const Icon(Icons.info_outline, size: 16),
                        label: Text(context.l10n.deviceFullInfo),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.onAccent,
                          fixedSize: const Size.fromHeight(36),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: colors.onAccent.withValues(alpha: .28),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            }

            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7, right: 18, bottom: 7),
                  child: SizedBox(
                    height: 100,
                    child: FlipperMockupWidget(active: active, dfu: dfu),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.onAccent,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: colors.onAccent),
                    ),
                    if (showStats) ...[
                      const SizedBox(height: 6),
                      HeaderDeviceStats(
                        deviceInfo: deviceInfo,
                        color: colors.onAccent,
                      ),
                    ],
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class HeaderDeviceStats extends StatelessWidget {
  const HeaderDeviceStats({
    super.key,
    required this.deviceInfo,
    required this.color,
  });

  final Map<String, String> deviceInfo;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final charge = DeviceInfoReader.number(deviceInfo, const [
      'power.charge_level',
      'power.charge',
      'charge_level',
      'charge',
    ]);
    final current = DeviceInfoReader.number(deviceInfo, const [
      'power.battery_current',
      'power.current_gauge',
      'power.current',
    ]);
    final charging = current != null && current > 5;
    final usedBytes = DeviceInfoReader.number(deviceInfo, const [
      'storage.sdcard.used_bytes',
      'storage.sdcard.used',
    ]);
    final totalBytes = DeviceInfoReader.number(deviceInfo, const [
      'storage.sdcard.total_bytes',
      'storage.sdcard.total',
    ]);
    final storage = usedBytes != null && totalBytes != null && totalBytes > 0
        ? (usedBytes / totalBytes * 100).clamp(0.0, 100.0)
        : DeviceInfoReader.number(deviceInfo, const [
            'storage.sdcard.used_percent',
          ]);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Stat(
          icon: charging ? Icons.battery_charging_full : Icons.battery_full,
          value: _percent(charge),
          color: color,
        ),
        const SizedBox(width: 12),
        _Stat(icon: Icons.sd_card, value: _percent(storage), color: color),
      ],
    );
  }

  static String _percent(double? value) {
    if (value == null || !value.isFinite) return '—';
    return '${value.round()}%';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.color});

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
