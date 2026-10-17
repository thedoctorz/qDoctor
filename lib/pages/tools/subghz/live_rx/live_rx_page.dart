import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../components/notification.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../widgets/key_file_sheet.dart';
import 'live_rx_controller.dart';
import 'widgets/radio_config_sheet.dart';
import 'widgets/rssi_waveform.dart';

String formatFrequency(int hz) => '${(hz / 1000000).toStringAsFixed(2)} MHz';

class LiveRxPage extends StatefulWidget {
  const LiveRxPage({super.key});

  @override
  State<LiveRxPage> createState() => _LiveRxPageState();
}

class _LiveRxPageState extends State<LiveRxPage> {
  late final LiveRxController c;

  @override
  void initState() {
    super.initState();
    c = LiveRxController()..addListener(_onChanged);
    unawaited(c.loadSettings());
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    c.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Widget _signalsSection(QAppColors colors, L10n s) =>
      RepaintBoundary(child: _signals(colors, s));

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final s = context.l10n;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        title: Text(s.toolSubghzRx),
        actions: [
          IconButton(
            tooltip: s.subghzRxConfig,
            onPressed: c.busy ? null : _openConfig,
            icon: const Icon(Icons.tune),
          ),
          if (c.signals.isNotEmpty)
            IconButton(
              tooltip: s.subghzRxClear,
              onPressed: c.clearSignals,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: RssiWaveform(
                samples: c.rssi,
                live: c.live,
                sampleIntervalMs: LiveRxController.rssiIntervalMs,
                threshold: c.threshold,
                thresholdEnabled: c.thresholdEnabled,
                onThresholdChanged: c.setThreshold,
                running: c.running,
                retuning: c.retuning,
                windowSize: LiveRxController.rssiWindowSize,
              ),
            ),
            _quickBar(colors, s),
            _statusBar(colors, s),
            if (c.errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  c.errorMessage!,
                  style: TextStyle(color: colors.danger, fontSize: 13),
                ),
              ),
            Divider(height: 1, color: colors.divider),
            Expanded(child: _signalsSection(colors, s)),
            _controls(colors, s),
          ],
        ),
      ),
    );
  }

  Widget _quickBar(QAppColors colors, L10n s) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
    child: Row(
      children: [
        Expanded(
          flex: 3,
          child: _quickButton(
            colors,
            label: s.subghzRxFrequency,
            value: c.frequencies.isEmpty
                ? (c.loadingSettings ? '…' : s.subghzRxTapToChange)
                : formatFrequency(c.frequency),
            onTap: c.retuning || c.loadingSettings
                ? null
                : (c.frequencies.isEmpty
                      ? () => unawaited(c.loadSettings())
                      : () => _pickFrequency(colors, s)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: _quickButton(
            colors,
            label: s.subghzRxModulation,
            value: c.preset.isEmpty
                ? (c.loadingSettings ? '…' : s.subghzRxTapToChange)
                : c.preset,
            onTap: c.retuning || c.loadingSettings
                ? null
                : (c.presets.isEmpty
                      ? () => unawaited(c.loadSettings())
                      : () => _pickPreset(colors, s)),
          ),
        ),
      ],
    ),
  );

  Widget _quickButton(
    QAppColors colors, {
    required String label,
    required String value,
    required VoidCallback? onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: onTap == null
                        ? colors.textMuted
                        : colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.expand_more, size: 18, color: colors.textMuted),
        ],
      ),
    ),
  );

  Future<void> _pickFrequency(QAppColors colors, L10n s) => _pickSheet<int>(
    colors,
    title: s.subghzRxFrequency,
    options: c.frequencies,
    selected: c.frequency,
    label: formatFrequency,
    onPick: (hz) => unawaited(c.setFrequency(hz)),
  );

  Future<void> _pickPreset(QAppColors colors, L10n s) => _pickSheet<String>(
    colors,
    title: s.subghzRxModulation,
    options: c.presets,
    selected: c.preset,
    label: (preset) => preset,
    onPick: (preset) => unawaited(c.setPreset(preset)),
  );

  Future<void> _pickSheet<T>(
    QAppColors colors, {
    required String title,
    required List<T> options,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onPick,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in options)
                    InkWell(
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        onPick(option);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: option == selected
                              ? colors.accent
                              : colors.card,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: option == selected
                                ? colors.accent
                                : colors.divider,
                          ),
                        ),
                        child: Text(
                          label(option),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: option == selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: option == selected
                                ? colors.onAccent
                                : colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBar(QAppColors colors, L10n s) {
    final running = c.running;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: c.transmitting
                  ? colors.danger
                  : running
                  ? colors.success
                  : colors.textMuted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              c.transmitting
                  ? s.subghzRxTransmitting
                  : running
                  ? s.subghzRxListening(formatFrequency(c.liveFrequency))
                  : s.subghzRxIdle,
              style: TextStyle(
                fontSize: 13,
                color: c.transmitting ? colors.danger : colors.textSecondary,
              ),
            ),
          ),
          if (c.usingExternalRadio) ...[
            Icon(Icons.memory, size: 13, color: colors.info),
            const SizedBox(width: 4),
            Text(
              s.subghzRxUsingExternal,
              style: TextStyle(fontSize: 12, color: colors.info),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            s.subghzRxSignals(c.signals.length),
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _signals(QAppColors colors, L10n s) {
    if (c.signals.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            c.running ? s.subghzRxWaiting : s.toolSubghzRxSubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textMuted),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: c.signals.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: colors.divider),
      itemBuilder: (context, i) {
        final signal = c.signals[i];
        return ListTile(
          onTap: () => _openSignal(signal),
          leading: _rssiBadge(colors, signal.rssi),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  signal.protocol,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (signal.repeats > 1) ...[
                const SizedBox(width: 6),
                Text(
                  s.subghzRxRepeats(signal.repeats),
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ],
            ],
          ),
          subtitle: Text(
            signal.subtitle.isEmpty
                ? formatFrequency(signal.frequency)
                : '${formatFrequency(signal.frequency)}  ·  '
                      '${signal.subtitle}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
          trailing: signal.saved
              ? Icon(Icons.check_circle, size: 20, color: colors.accent)
              : Icon(Icons.chevron_right, color: colors.textMuted),
        );
      },
    );
  }

  Widget _rssiBadge(QAppColors colors, int rssi) {
    final color = rssi > -60
        ? colors.success
        : rssi > -85
        ? colors.info
        : colors.textMuted;
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$rssi',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _controls(QAppColors colors, L10n s) {
    final running = c.running;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: c.busy
              ? null
              : () => unawaited(running ? c.stop() : c.start()),
          icon: Icon(running ? Icons.stop : Icons.sensors, size: 18),
          label: Text(
            running ? s.subghzRxStop : s.subghzRxStart,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: c.busy
                ? colors.divider
                : (running ? colors.danger : colors.accent),
            foregroundColor: colors.onAccent,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openConfig() => RadioConfigSheet.show(context, c);

  Future<void> _openSignal(LiveRxSignal signal) {
    final s = context.l10n;
    return KeyFileSheet.show(
      context,
      title: signal.protocol,
      subtitle: signal.saved
          ? s.decodeRawSaved(signal.savedPath!.split('/').last)
          : '${formatFrequency(signal.frequency)}  ·  ${signal.rssi} dBm',
      flipperFormat: signal.flipperFormat,
      pulses: signal.pulses,
      pulsesAvailable: true,
      actions: [
        KeyFileAction(
          icon: Icons.save_outlined,
          label: s.subghzRxSave,
          enabled: !signal.saved,
          onTap: () => _save(signal),
        ),
        KeyFileAction(
          icon: Icons.podcasts,
          label: s.subghzRxTransmit,
          enabled: signal.transmittable && !c.transmitting,
          onTap: () => _transmit(signal),
        ),
      ],
    );
  }

  Future<void> _save(LiveRxSignal signal) async {
    final error = await c.save(signal);
    if (!mounted) return;
    context.showNotification(
      error ?? context.l10n.decodeRawSaved(signal.savedPath!.split('/').last),
      type: error == null ? QNotificationType.good : QNotificationType.error,
    );
  }

  Future<void> _transmit(LiveRxSignal signal) async {
    final s = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.appColors.dialogBackground,
        title: Text(
          s.subghzRxTransmit,
          style: TextStyle(color: dialogContext.appColors.dialogText),
        ),
        content: Text(
          s.subghzRxTransmitConfirm(
            signal.protocol,
            formatFrequency(signal.frequency),
          ),
          style: TextStyle(color: dialogContext.appColors.dialogMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              s.subghzRxTransmit,
              style: TextStyle(
                color: dialogContext.appColors.danger,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = await c.transmit(signal);
    if (!mounted) return;
    context.showNotification(
      result.error ?? s.subghzRxTransmitted(formatFrequency(result.frequency)),
      type: result.error == null
          ? QNotificationType.good
          : QNotificationType.error,
    );
  }
}
