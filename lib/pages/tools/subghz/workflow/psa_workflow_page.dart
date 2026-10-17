import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/theme.dart';
import 'psa_workflow_controller.dart';

class PsaWorkflowPage extends StatefulWidget {
  const PsaWorkflowPage({super.key});

  @override
  State<PsaWorkflowPage> createState() => _PsaWorkflowPageState();
}

class _PsaWorkflowPageState extends State<PsaWorkflowPage> {
  late final PsaWorkflowController c;
  final _key1 = TextEditingController();
  final _key2 = TextEditingController();

  @override
  void initState() {
    super.initState();
    c = PsaWorkflowController()..addListener(_onChanged);
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    c.dispose();
    _key1.dispose();
    _key2.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _syncFields() {
    _key1.text = c.key1Hex;
    _key2.text = c.key2Hex;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        title: const Text('PSA Decrypt'),
      ),
      body: SafeArea(
        child: switch (c.state) {
          PsaWorkflowState.input => _input(colors),
          PsaWorkflowState.calculating => _calculating(colors),
          PsaWorkflowState.finished => _finished(colors),
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
          'Enter the two cipher halves from a PSA capture, or load one from the '
          'Flipper. The bruteforce recovers Serial, counter and button.',
          style: TextStyle(fontSize: 13, color: colors.textMuted),
        ),
        const SizedBox(height: 16),
        _group(colors, 'Cipher halves', [
          if (c.hasLoadedCapture)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Loaded from Flipper capture',
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
            ),
          _hexField(colors, 'Key (16 hex)', _key1, (v) => c.key1Hex = v),
          _hexField(colors, 'Key_2 (16 hex)', _key2, (v) => c.key2Hex = v),
        ]),
        if (!c.gpuAccelerated) ...[
          const SizedBox(height: 4),
          _notice(
            colors,
            'This device has no GPU kernel yet — the bruteforce runs on CPU '
            'and is slower.',
          ),
        ],
        if (c.errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(c.errorMessage!, style: TextStyle(color: colors.danger)),
        ],
        const SizedBox(height: 20),
        _accentButton(
          colors,
          'Recover',
          Icons.play_arrow_rounded,
          c.canStart ? c.start : null,
        ),
        const SizedBox(height: 6),
        Center(
          child: _textButton(colors, 'Load sample', () {
            c.loadSampleVector();
            _syncFields();
          }),
        ),
      ],
    );
  }

  Future<void> _openPicker() async {
    unawaited(c.refreshCaptures());
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _PsaPickerPage(controller: c)),
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
            'Bruteforcing…',
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
              value: c.progress > 0 ? c.progress : null,
              minHeight: 10,
              backgroundColor: colors.divider,
              valueColor: AlwaysStoppedAnimation(colors.accent),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${(c.progress * 100).toStringAsFixed(0)}% — ${c.elapsedLabel} '
            'elapsed',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
          if (c.etaLabel != null)
            Text(
              '~${c.etaLabel} left',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          const SizedBox(height: 28),
          TextButton(
            onPressed: c.cancel,
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
    final rec = c.recovered;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 16),
        if (rec != null) ...[
          Center(
            child: Text(
              'Recovered',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _kv(
            colors,
            'Serial',
            '0x${rec.serial.toRadixString(16).toUpperCase()}  (${rec.serial})',
          ),
          _kv(colors, 'Counter', '${rec.counter}'),
          _kv(colors, 'Button', '${rec.button}'),
          _kv(colors, 'Type', '${rec.type}'),
          if (rec.seed != null)
            _kv(
              colors,
              'Seed',
              '0x${rec.seed!.toRadixString(16).toUpperCase()}',
            ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'in ${c.elapsedLabel}',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ),
          const SizedBox(height: 16),
          _textButton(colors, 'Copy Serial', () {
            Clipboard.setData(ClipboardData(text: '${rec.serial}'));
          }, icon: Icons.copy),
          if (c.canWriteBack) ...[
            const SizedBox(height: 8),
            _accentButton(
              colors,
              c.writeBackDone
                  ? 'Written to Flipper'
                  : c.writingBack
                  ? 'Writing to Flipper…'
                  : 'Write fields to Flipper',
              c.writeBackDone ? Icons.check : Icons.save_outlined,
              c.writeBackDone || c.writingBack ? null : c.writeBack,
            ),
            if (c.writtenPath != null) ...[
              const SizedBox(height: 6),
              Text(
                c.writtenPath!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
            ],
          ],
        ] else ...[
          Center(
            child: Text(
              'No Match',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The bruteforce finished without a match.',
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

  Widget _kv(QAppColors colors, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(k, style: TextStyle(color: colors.textMuted)),
        ),
        Expanded(
          child: SelectableText(
            v,
            style: TextStyle(
              fontFamily: 'monospace',
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );

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

class _PsaPickerPage extends StatelessWidget {
  const _PsaPickerPage({required this.controller});

  final PsaWorkflowController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = controller.captures;
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
            title: const Text('Select a Capture'),
            actions: [
              IconButton(
                onPressed: controller.listing
                    ? null
                    : () => controller.refreshCaptures(forceReload: true),
                icon: const Icon(Icons.refresh),
              ),
              TextButton(
                onPressed: controller.selectedPath == null
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
              Expanded(
                child: items.isEmpty && !controller.listing
                    ? _empty(colors)
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: colors.divider),
                        itemBuilder: (context, i) {
                          final item = items[i];
                          final selected = controller.selectedPath == item.path;
                          return ListTile(
                            onTap: () => controller.selectCapture(item.path),
                            title: Text(
                              item.name,
                              style: TextStyle(color: colors.textPrimary),
                            ),
                            subtitle: Text(
                              'PSA · ${item.keyHint}…',
                              style: TextStyle(color: colors.textMuted),
                            ),
                            trailing: selected
                                ? Icon(Icons.check_circle, color: colors.accent)
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
              '${controller.listDone}/$total — checking for PSA',
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
              'No PSA captures needing recovery in /ext/subghz.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textMuted),
        ),
      ),
    );
  }
}
