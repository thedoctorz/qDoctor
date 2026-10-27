import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/theme.dart';
import 'hitag2_workflow_controller.dart';

class Hitag2WorkflowPage extends StatefulWidget {
  const Hitag2WorkflowPage({super.key});

  @override
  State<Hitag2WorkflowPage> createState() => _Hitag2WorkflowPageState();
}

class _Hitag2WorkflowPageState extends State<Hitag2WorkflowPage> {
  late final Hitag2WorkflowController c;
  final _uid = TextEditingController();
  final _btn = TextEditingController(text: '2');
  final _hop = TextEditingController();
  final _cnt = TextEditingController();
  final _hop2 = TextEditingController();
  final _cnt2 = TextEditingController();
  final _btn2 = TextEditingController();

  @override
  void initState() {
    super.initState();
    c = Hitag2WorkflowController()..addListener(_onChanged);
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    c.dispose();
    for (final t in [_uid, _btn, _hop, _cnt, _hop2, _cnt2, _btn2]) {
      t.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _syncFields() {
    _uid.text = c.uidHex;
    _btn.text = c.btnHex;
    _hop.text = c.hopHex;
    _cnt.text = c.cntHex;
    _hop2.text = c.hop2Hex;
    _cnt2.text = c.cnt2Hex;
    _btn2.text = c.btn2Hex;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        title: const Text('Hitag2Hell'),
      ),
      body: SafeArea(
        child: switch (c.state) {
          Hitag2WorkflowState.input => _input(colors),
          Hitag2WorkflowState.calculating => _calculating(colors),
          Hitag2WorkflowState.finished => _finished(colors),
        },
      ),
    );
  }

  Widget _input(QAppColors colors) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _accentButton(
          colors,
          'Load from Flipper (.sub)',
          Icons.sim_card_outlined,
          _openPicker,
        ),
        const SizedBox(height: 8),
        _accentButton(
          colors,
          'Open local file',
          Icons.folder_open_outlined,
          _pickLocal,
        ),
        const SizedBox(height: 12),
        Text(
          'Enter two decoded hops from the same remote (Fiat V1/V2 or Renault '
          'V1). UID is shared; each press has its own hop, counter and button.',
          style: TextStyle(fontSize: 13, color: colors.textMuted),
        ),
        const SizedBox(height: 16),
        _group(colors, 'Transponder', [
          _hexField(colors, 'UID (hex)', _uid, (v) => c.uidHex = v),
          _hexField(colors, 'Button (hex)', _btn, (v) => c.btnHex = v),
        ]),
        _group(colors, 'Signal 1', [
          _hexField(colors, 'Hop (hex)', _hop, (v) => c.hopHex = v),
          _hexField(colors, 'Counter (hex)', _cnt, (v) => c.cntHex = v),
        ]),
        _group(colors, 'Signal 2 (recommended)', [
          _hexField(colors, 'Hop 2 (hex)', _hop2, (v) => c.hop2Hex = v),
          _hexField(colors, 'Counter 2 (hex)', _cnt2, (v) => c.cnt2Hex = v),
          _hexField(
            colors,
            'Button 2 (hex, optional)',
            _btn2,
            (v) => c.btn2Hex = v,
          ),
        ]),
        if (c.loadedProto != null) ...[
          const SizedBox(height: 4),
          Text(
            'Loaded ${c.loadedProto!.wireName} capture',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ],
        if (!c.gpuAccelerated) ...[
          const SizedBox(height: 8),
          _notice(
            colors,
            'This device has no GPU kernel yet — the search runs on CPU and '
            'is slower.',
          ),
        ],
        if (c.errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(c.errorMessage!, style: TextStyle(color: colors.danger)),
        ],
        const SizedBox(height: 20),
        _accentButton(
          colors,
          'Recover Key',
          Icons.play_arrow_rounded,
          c.canStart ? c.start : null,
        ),
        const SizedBox(height: 6),
        Center(
          child: Wrap(
            spacing: 20,
            children: [
              _textButton(colors, 'Load Hell sample', () {
                c.loadSampleVector();
                _syncFields();
              }),
              _textButton(colors, 'Load BCM sample', () {
                c.loadBcmSampleVector();
                _syncFields();
              }),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openPicker() async {
    unawaited(c.refreshCaptures());
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _Hitag2PickerPage(controller: c)),
    );
    _syncFields();
  }

  Future<void> _pickLocal() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['sub'],
      withData: true,
    );
    if (result == null || !mounted) return;
    final file = result.files.single;
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await io.File(file.path!).readAsBytes();
    }
    if (!mounted || bytes == null) return;
    if (c.applyLocalCapture(
      utf8.decode(bytes, allowMalformed: true),
      fileName: file.name,
    )) {
      _syncFields();
    }
  }

  Widget _calculating(QAppColors colors) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            c.phaseLabel,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: c.isBcmPhase ? null : (c.progress > 0 ? c.progress : null),
              minHeight: 10,
              backgroundColor: colors.divider,
              valueColor: AlwaysStoppedAnimation(colors.accent),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            c.isBcmPhase
                ? '${c.elapsedLabel} elapsed'
                : '${(c.progress * 100).toStringAsFixed(0)}% — '
                      '${c.elapsedLabel} elapsed',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
          if (!c.isBcmPhase && c.etaLabel != null)
            Text(
              '~${c.etaLabel} left',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          const SizedBox(height: 8),
          Text(
            'The screen stays on while this runs.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
          const SizedBox(height: 28),
          TextButton(
            onPressed: () {
              c.cancel();
              c.reset();
            },
            child: Text(
              'Cancel',
              style: TextStyle(
                color: colors.danger,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _finished(QAppColors colors) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 16),
        if (c.hasResult) ...[
          Center(
            child: Text(
              c.recoveredSeedHex != null ? 'Seed Recovered' : 'Key Recovered',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: SelectableText(
              c.recoveredSeedHex ?? c.recoveredKeyHex ?? '',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 2,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              [
                if (c.methodLabel != null) 'via ${c.methodLabel}',
                'in ${c.elapsedLabel}',
                if (c.recoveredAtPercentLabel != null)
                  'at ${c.recoveredAtPercentLabel}% of the search',
                if (c.diagLabel != null) c.diagLabel!,
              ].join('  ·  '),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ),
          const SizedBox(height: 16),
          _textButton(
            colors,
            c.recoveredSeedHex != null ? 'Copy Seed' : 'Copy Key',
            () {
              Clipboard.setData(
                ClipboardData(
                  text: (c.recoveredSeedHex ?? c.recoveredKeyHex ?? '')
                      .replaceAll(' ', ''),
                ),
              );
            },
            icon: Icons.copy,
          ),
          if (c.canWriteBack) ...[
            const SizedBox(height: 8),
            _accentButton(
              colors,
              c.writeBackDone
                  ? 'Written to Flipper'
                  : c.writingBack
                  ? 'Writing to Flipper…'
                  : (c.recoveredSeedHex != null
                        ? 'Write Seed to Flipper'
                        : 'Write Key to Flipper'),
              c.writeBackDone ? Icons.check : Icons.save_outlined,
              c.writeBackDone || c.writingBack ? null : c.writeBack,
            ),
            if (c.writtenPaths.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                c.writtenPaths.join('\n'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
            ],
          ],
        ] else ...[
          Center(
            child: Text(
              'No Key Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The search finished without a match. Double-check the hops, or '
            'capture two fresh presses with consecutive counters.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: colors.textMuted),
          ),
        ],
        if (c.errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            c.errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.danger),
          ),
        ],
        const SizedBox(height: 24),
        _accentButton(colors, 'New Recovery', Icons.refresh, () {
          c.reset();
          _syncFields();
        }),
      ],
    );
  }

  Widget _group(QAppColors colors, String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _hexField(
    QAppColors colors,
    String label,
    TextEditingController tec,
    void Function(String) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: tec,
        autocorrect: false,
        textCapitalization: TextCapitalization.characters,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 15,
          color: colors.textPrimary,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: colors.textMuted),
          isDense: true,
          filled: true,
          fillColor: colors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colors.divider),
          ),
        ),
        onChanged: (v) {
          onChanged(v);
          c.manualEdited();
        },
      ),
    );
  }

  Widget _accentButton(
    QAppColors colors,
    String label,
    IconData icon,
    VoidCallback? onTap,
  ) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: onTap == null ? colors.divider : colors.accent,
          foregroundColor: colors.onAccent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _textButton(
    QAppColors colors,
    String label,
    VoidCallback onTap, {
    IconData? icon,
  }) {
    return TextButton.icon(
      onPressed: onTap,
      icon: icon == null
          ? const SizedBox.shrink()
          : Icon(icon, size: 16, color: colors.accent),
      label: Text(label, style: TextStyle(color: colors.accent)),
    );
  }

  Widget _notice(QAppColors colors, String text) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: colors.info)),
    );
  }
}

class _Hitag2PickerPage extends StatelessWidget {
  const _Hitag2PickerPage({required this.controller});

  final Hitag2WorkflowController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = controller.listedCaptures;
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
            title: const Text('Select 2 Captures'),
            actions: [
              IconButton(
                onPressed: controller.listing
                    ? null
                    : () => controller.refreshCaptures(forceReload: true),
                icon: const Icon(Icons.refresh),
              ),
              TextButton(
                onPressed: controller.selectedPaths.isEmpty
                    ? null
                    : () async {
                        await controller.loadSelected();
                        if (context.mounted &&
                            controller.errorMessage == null) {
                          Navigator.of(context).pop();
                        }
                      },
                child: Text(
                  'Load',
                  style: TextStyle(
                    color: colors.onAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              if (controller.listing) _scanProgress(colors),
              if (controller.selectedPaths.isNotEmpty)
                Container(
                  width: double.infinity,
                  color: colors.card,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    'Second file must use the same UID.',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                ),
              Expanded(
                child: items.isEmpty && !controller.listing
                    ? _empty(colors)
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: colors.divider),
                        itemBuilder: (context, i) {
                          final item = items[i];
                          final idx = controller.selectedPaths.indexOf(
                            item.path,
                          );
                          return ListTile(
                            onTap: () => controller.toggleSelected(item.path),
                            title: Text(
                              item.name,
                              style: TextStyle(color: colors.textPrimary),
                            ),
                            subtitle: Text(
                              '${item.proto.wireName}   UID '
                              '${item.uid.toRadixString(16).toUpperCase()}',
                              style: TextStyle(color: colors.textMuted),
                            ),
                            trailing: idx >= 0
                                ? Text(
                                    'Signal ${idx + 1}',
                                    style: TextStyle(
                                      color: colors.accent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _scanProgress(QAppColors colors) {
    final total = controller.listTotal;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (total == 0)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(
                  'Listing folders…',
                  style: TextStyle(color: colors.textMuted),
                ),
              ],
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: controller.listProgress,
                minHeight: 8,
                backgroundColor: colors.divider,
                valueColor: AlwaysStoppedAnimation(colors.accent),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${controller.listDone}/$total — checking for Fiat / Renault',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _empty(QAppColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          controller.errorMessage ??
              'No Fiat V1, Fiat V2 or Renault V1 key files in /ext/subghz. '
                  'RAW recordings are ignored.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textMuted),
        ),
      ),
    );
  }
}
