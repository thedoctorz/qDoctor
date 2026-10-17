import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../components/format.dart';
import '../../../../components/navigation.dart';
import '../../../../components/notification.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../widgets/key_file_sheet.dart';
import 'widgets/capture_envelope.dart';
import 'decode_raw_controller.dart';

class DecodeRawPage extends StatefulWidget {
  const DecodeRawPage({super.key, this.args});

  final DecodeRawArgs? args;

  @override
  State<DecodeRawPage> createState() => _DecodeRawPageState();
}

class _DecodeRawPageState extends State<DecodeRawPage> {
  late final DecodeRawController c;

  @override
  void initState() {
    super.initState();
    c = DecodeRawController()..addListener(_onChanged);
    final args = widget.args;
    if (args == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final remote = args.remotePath;
      if (remote != null && remote.isNotEmpty) {
        unawaited(c.decodeRemote(remote, name: args.name));
        return;
      }
      final bytes = args.localBytes;
      if (bytes != null) {
        unawaited(c.decodeLocal(bytes, args.name ?? 'capture.sub'));
      }
    });
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

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        title: Text(context.l10n.toolDecodeRaw),
      ),
      body: SafeArea(
        child: switch (c.phase) {
          DecodeRawPhase.idle => _idle(colors),
          DecodeRawPhase.decoding => _live(colors),
          DecodeRawPhase.results => _live(colors),
        },
      ),
    );
  }

  String? _captureCaption(L10n s) {
    final capture = c.capture;
    if (capture.isEmpty) return null;
    return s.decodeRawCaptureSummary(
      capture.pulseCount,
      (capture.durationMicros / 1000000).toStringAsFixed(1),
    );
  }

  Widget _idle(QAppColors colors) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          context.l10n.toolDecodeRawSubtitle,
          style: TextStyle(fontSize: 13, color: colors.textMuted),
        ),
        const SizedBox(height: 16),
        _accentButton(
          colors,
          context.l10n.decodeRawLoadFromFlipper,
          Icons.sim_card_outlined,
          c.isConnected ? _openPicker : null,
        ),
        const SizedBox(height: 12),
        _accentButton(
          colors,
          context.l10n.decodeRawPickFile,
          Icons.folder_open_outlined,
          c.isConnected ? _pickLocal : null,
        ),
        if (!c.isConnected) ...[
          const SizedBox(height: 16),
          Text(
            context.l10n.decodeRawConnectFirst,
            style: TextStyle(color: colors.textMuted),
          ),
        ],
        if (c.errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(c.errorMessage!, style: TextStyle(color: colors.danger)),
        ],
      ],
    );
  }

  Widget _live(QAppColors colors) {
    final s = context.l10n;
    final decoding = c.isDecoding;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: CaptureEnvelope(
            envelope: c.envelope,
            progress: c.cursor,
            live: decoding,
            hitPositions: c.hitMarks,
            caption: _captureCaption(s),
            loading: c.preparing,
            loadingLabel: c.parsing
                ? s.decodeRawReadingCapture
                : s.decodeRawFetchingCapture(
                    (c.fetchProgress * 100).clamp(0, 100).round(),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  decoding
                      ? '${(c.progress * 100).toStringAsFixed(0)}%  ·  '
                            '${s.decodeRawHits(c.hits.length)}'
                      : s.decodeRawHits(c.hits.length),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (decoding)
                TextButton(
                  onPressed: c.cancelling
                      ? null
                      : () => unawaited(c.cancelDecode()),
                  child: Text(
                    c.cancelling ? s.decodeRawCancelling : s.decodeRawCancel,
                    style: TextStyle(
                      color: c.cancelling ? colors.textMuted : colors.danger,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else if (c.unsavedCount > 0)
                TextButton(
                  onPressed: () => unawaited(_saveAll()),
                  child: Text(
                    s.decodeRawSaveAll,
                    style: TextStyle(
                      color: colors.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (c.errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              c.errorMessage!,
              style: TextStyle(color: colors.danger),
            ),
          ),
        if (c.cancelled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              s.decodeRawCancelled,
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ),
        if (c.uploadedPath != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              s.decodeRawUploadedTo(c.uploadedPath!),
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ),
        Divider(height: 1, color: colors.divider),
        Expanded(
          child: c.hits.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      decoding ? s.decodeRawDecoding : s.decodeRawNoHits,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.textMuted),
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: c.hits.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: colors.divider),
                  itemBuilder: (context, i) {
                    final item = c.hits[i];
                    final subtitle = item.view.subtitle;
                    return ListTile(
                      onTap: () => _openHit(item),
                      title: Text(
                        item.view.protocol,
                        style: TextStyle(color: colors.textPrimary),
                      ),
                      subtitle: Text(
                        item.saved
                            ? s.decodeRawSaved(item.savedPath!.split('/').last)
                            : (subtitle.isEmpty
                                  ? s.decodeRawHitReady
                                  : subtitle),
                        style: TextStyle(color: colors.textMuted),
                      ),
                      trailing: item.saved
                          ? Icon(Icons.check_circle, color: colors.accent)
                          : TextButton(
                              onPressed: () => unawaited(_saveOne(item)),
                              child: Text(
                                s.decodeRawSave,
                                style: TextStyle(
                                  color: colors.accent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                    );
                  },
                ),
        ),
        if (!decoding)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _accentButton(
              colors,
              s.decodeRawNew,
              Icons.refresh,
              c.reset,
            ),
          ),
      ],
    );
  }

  Future<void> _openPicker() async {
    unawaited(c.refreshRawFiles());
    final picked = await Navigator.of(context).push<DecodeRawListedFile>(
      MaterialPageRoute(builder: (_) => _DecodeRawPickerPage(controller: c)),
    );
    if (picked == null || !mounted) return;
    unawaited(c.decodeRemote(picked.path, name: picked.name));
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
    if (!mounted) return;
    if (bytes == null) {
      context.showNotification(
        context.l10n.decodeRawInvalidFile,
        type: QNotificationType.error,
      );
      return;
    }
    unawaited(c.decodeLocal(bytes, file.name));
  }

  Future<void> _openHit(DecodeRawHitItem item) {
    final s = context.l10n;
    return KeyFileSheet.show(
      context,
      title: item.view.protocol,
      subtitle: item.saved
          ? s.decodeRawSaved(item.savedPath!.split('/').last)
          : item.view.subtitle,
      flipperFormat: item.view.flipperFormat,
      actions: [
        KeyFileAction(
          icon: Icons.save_outlined,
          label: s.decodeRawSave,
          enabled: !item.saved,
          onTap: () => _saveOne(item),
        ),
      ],
    );
  }

  Future<void> _saveOne(DecodeRawHitItem item) async {
    await c.saveHit(item);
    if (!mounted) return;
    final path = item.savedPath;
    if (path != null) {
      context.showNotification(
        context.l10n.decodeRawSaved(path.split('/').last),
        type: QNotificationType.good,
      );
    }
  }

  Future<void> _saveAll() async {
    final n = await c.saveAll();
    if (!mounted || n == 0) return;
    context.showNotification(
      context.l10n.decodeRawSavedCount(n),
      type: QNotificationType.good,
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
}

class _DecodeRawPickerPage extends StatelessWidget {
  const _DecodeRawPickerPage({required this.controller});

  final DecodeRawController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final s = context.l10n;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = controller.listed;
        return Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
            title: Text(s.decodeRawPickerTitle),
            actions: [
              IconButton(
                onPressed: controller.listing
                    ? null
                    : () => unawaited(controller.refreshRawFiles(force: true)),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: Column(
            children: [
              if (controller.listing) _scanProgress(context, colors),
              Expanded(
                child: items.isEmpty && !controller.listing
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            controller.errorMessage ?? s.decodeRawEmpty,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.textMuted),
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: colors.divider),
                        itemBuilder: (context, i) {
                          final item = items[i];
                          return ListTile(
                            onTap: () => Navigator.of(context).pop(item),
                            title: Text(
                              item.name,
                              style: TextStyle(color: colors.textPrimary),
                            ),
                            subtitle: Text(
                              formatBytes(item.size),
                              style: TextStyle(color: colors.textMuted),
                            ),
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

  Widget _scanProgress(BuildContext context, QAppColors colors) {
    final total = controller.listTotal;
    final s = context.l10n;
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
                  s.decodeRawListingFolders,
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
              s.decodeRawListingProgress(controller.listDone, total),
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
