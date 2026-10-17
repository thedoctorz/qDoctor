import 'package:flutter/material.dart';

import '../../../../../services/localization/l10n.dart';
import '../../../../../theme/theme.dart';
import '../live_rx_controller.dart';
import '../live_rx_page.dart' show formatFrequency;

class RadioConfigSheet {
  const RadioConfigSheet._();

  static Future<void> show(BuildContext context, LiveRxController controller) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RadioConfigBody(controller: controller),
    );
  }
}

class _RadioConfigBody extends StatefulWidget {
  const _RadioConfigBody({required this.controller});

  final LiveRxController controller;

  @override
  State<_RadioConfigBody> createState() => _RadioConfigBodyState();
}

class _RadioConfigBodyState extends State<_RadioConfigBody> {
  late int _frequency = widget.controller.frequency;
  late String _preset = widget.controller.preset;
  late String _presetB = widget.controller.presetB;
  late bool _hopping = widget.controller.hopping;
  late bool _modulationHopping = widget.controller.modulationHopping;
  late bool? _external = widget.controller.externalRadio;
  late bool _capturePulses = widget.controller.capturePulses;
  late bool _sound = widget.controller.sound;
  late bool _autosave = widget.controller.autosave;
  late bool _thresholdEnabled = widget.controller.thresholdEnabled;
  late Set<SubGhzIgnore> _ignored = {...widget.controller.ignored};
  bool _applying = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final s = context.l10n;
    final c = widget.controller;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            _grabber(colors),
            _header(colors, s, c),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  if (!c.settingsLoaded)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        s.subghzRxSettingsUnavailable,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.textMuted),
                      ),
                    )
                  else ...[
                    _label(colors, s.subghzRxFrequency),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final hz in c.frequencies)
                          _chip(
                            colors,
                            formatFrequency(hz).replaceAll(' MHz', ''),
                            selected: _frequency == hz,
                            onTap: () => setState(() => _frequency = hz),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _label(colors, s.subghzRxModulation),
                    const SizedBox(height: 8),
                    _presetRow(
                      colors,
                      c.presets,
                      _preset,
                      (v) => setState(() => _preset = v),
                    ),
                    const SizedBox(height: 20),
                    _label(colors, s.subghzRxRadio),
                    const SizedBox(height: 8),
                    _radioRow(colors, s),
                  ],
                  const SizedBox(height: 12),
                  _switch(
                    colors,
                    title: s.subghzRxHopping,
                    subtitle: c.hopperFrequencies.isEmpty
                        ? null
                        : c.hopperFrequencies
                              .map(
                                (hz) =>
                                    formatFrequency(hz).replaceAll(' MHz', ''),
                              )
                              .join(' · '),
                    value: _hopping,
                    onChanged: (v) => setState(() => _hopping = v),
                  ),
                  _switch(
                    colors,
                    title: s.subghzRxModulationHopping,
                    subtitle: s.subghzRxModulationHoppingHint,
                    value: _modulationHopping,
                    enabled: c.presets.length > 1,
                    onChanged: (v) => setState(() => _modulationHopping = v),
                  ),
                  if (_modulationHopping && c.settingsLoaded) ...[
                    const SizedBox(height: 8),
                    _label(colors, s.subghzRxModulationB),
                    const SizedBox(height: 8),
                    _presetRow(
                      colors,
                      c.presets,
                      _presetB,
                      (v) => setState(() => _presetB = v),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _switch(
                    colors,
                    title: s.subghzRxSound,
                    subtitle: s.subghzRxSoundHint,
                    value: _sound,
                    onChanged: (v) => setState(() => _sound = v),
                  ),
                  _switch(
                    colors,
                    title: s.subghzRxCapturePulses,
                    subtitle: s.subghzRxCapturePulsesHint,
                    value: _capturePulses,
                    onChanged: (v) => setState(() => _capturePulses = v),
                  ),
                  _switch(
                    colors,
                    title: s.subghzRxThresholdEnable,
                    subtitle: s.subghzRxThresholdHint,
                    value: _thresholdEnabled,
                    onChanged: (v) => setState(() => _thresholdEnabled = v),
                  ),
                  _switch(
                    colors,
                    title: s.subghzRxAutosave,
                    subtitle: s.subghzRxAutosaveHint,
                    value: _autosave,
                    onChanged: (v) => setState(() => _autosave = v),
                  ),
                  const SizedBox(height: 16),
                  _label(colors, s.subghzRxIgnore),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final ignore in SubGhzIgnore.values)
                        _chip(
                          colors,
                          _ignoreLabel(s, ignore),
                          selected: _ignored.contains(ignore),
                          onTap: () => setState(() {
                            if (!_ignored.remove(ignore)) _ignored.add(ignore);
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: _reset,
                    icon: Icon(
                      Icons.restart_alt,
                      size: 18,
                      color: colors.textMuted,
                    ),
                    label: Text(
                      s.subghzRxResetDefaults,
                      style: TextStyle(color: colors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _applying ? null : _apply,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: colors.onAccent,
                      disabledBackgroundColor: colors.divider,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      s.subghzRxApply,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _ignoreLabel(L10n s, SubGhzIgnore ignore) => switch (ignore) {
    SubGhzIgnore.reversRb2 => s.subghzRxIgnoreReversRb2,
    SubGhzIgnore.alarms => s.subghzRxIgnoreAlarms,
    SubGhzIgnore.sensors => s.subghzRxIgnoreSensors,
    SubGhzIgnore.princeton => s.subghzRxIgnorePrinceton,
    SubGhzIgnore.niceFlorS => s.subghzRxIgnoreNiceFlorS,
  };

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

  Widget _header(QAppColors colors, L10n s, LiveRxController c) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            s.subghzRxConfig,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
        ),
        if (c.deviceName.isNotEmpty)
          Text(
            c.deviceName,
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
      ],
    ),
  );

  Widget _label(QAppColors colors, String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.8,
      color: colors.textMuted,
    ),
  );

  Widget _presetRow(
    QAppColors colors,
    List<String> presets,
    String selected,
    ValueChanged<String> onPick,
  ) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final preset in presets)
        _chip(
          colors,
          preset,
          selected: selected == preset,
          onTap: () => onPick(preset),
        ),
    ],
  );

  Widget _radioRow(QAppColors colors, L10n s) => Wrap(
    spacing: 8,
    children: [
      _chip(
        colors,
        s.subghzRxRadioAuto,
        selected: _external == null,
        onTap: () => setState(() => _external = null),
      ),
      _chip(
        colors,
        s.subghzRxRadioInternal,
        selected: _external == false,
        onTap: () => setState(() => _external = false),
      ),
      _chip(
        colors,
        s.subghzRxRadioExternal,
        selected: _external == true,
        onTap: () => setState(() => _external = true),
      ),
    ],
  );

  Widget _switch(
    QAppColors colors, {
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? subtitle,
    bool enabled = true,
  }) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    value: value && enabled,
    onChanged: enabled ? onChanged : null,
    activeThumbColor: colors.accent,
    title: Text(
      title,
      style: TextStyle(
        fontSize: 14,
        color: enabled ? colors.textPrimary : colors.textMuted,
      ),
    ),
    subtitle: subtitle == null
        ? null
        : Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
  );

  Widget _chip(
    QAppColors colors,
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? colors.accent : colors.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? colors.onAccent : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  void _reset() {
    widget.controller.resetConfig();
    final c = widget.controller;
    setState(() {
      _preset = c.preset;
      _presetB = c.presetB;
      _hopping = c.hopping;
      _modulationHopping = c.modulationHopping;
      _capturePulses = c.capturePulses;
      _sound = c.sound;
      _autosave = c.autosave;
      _thresholdEnabled = c.thresholdEnabled;
      _ignored = {...c.ignored};
    });
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    final c = widget.controller;
    final deviceChanged = c.externalRadio != _external;
    c.frequency = _frequency;
    c.preset = _preset;
    c.presetB = _presetB;
    c.hopping = _hopping;
    c.modulationHopping = _modulationHopping;
    c.externalRadio = _external;
    c.capturePulses = _capturePulses;
    c.sound = _sound;
    c.autosave = _autosave;
    c.thresholdEnabled = _thresholdEnabled;
    c.ignored = {..._ignored};

    if (deviceChanged && c.running) {
      await c.stop();
      await c.start();
    } else {
      await c.applyConfig();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
