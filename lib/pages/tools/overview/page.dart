import '../../../services/localization/l10n.dart';

import 'dart:io';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../components/cardlist.dart';
import '../../../components/icon.dart';
import '../../../components/navigation.dart';
import '../../../components/notification.dart';
import '../../../theme/theme.dart';
import '../../../components/dialogs/action.dart';
import '../../../services/assembler/controller.dart';
import '../paint/manager/page.dart';
import '../remote/desktop/page.dart';
import '../remote/cli/page.dart';
import '../infrared/categories_page.dart';
import '../mifare/recover_page.dart';
import '../plotter/page.dart';
import '../subghz/decode_raw/decode_raw_page.dart';
import '../subghz/live_rx/live_rx_page.dart';
import '../subghz/workflow/hitag2_workflow_page.dart';
import '../subghz/workflow/psa_workflow_page.dart';
import 'models/tool.dart';
import 'pinned_tools.dart';
import 'widgets/app_version.dart';
import 'widgets/tool_item_badge.dart';
import 'widgets/tool_item_text.dart';
import '../../../services/logging.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  /// [localBuilds] is on only while builds run on this computer: without a
  /// deployed SDK and toolchain, or with the build server in charge, the tool
  /// has nothing to compile a folder or a repo with.
  static List<ToolGroup> _toolGroups(L10n s, bool localBuilds) => [
    ToolGroup(
      header: ToolCardHeader(
        iconAsset: 'assets/ic/device/flipper.svg',
        iconColor: const Color(0xFF589DFF),
        title: s.toolsGroupDeviceControl,
      ),
      items: [
        ToolItemModel(
          id: 'remote',
          iconAsset: 'assets/ic/app/controller.svg',
          iconColor: const Color(0xFFFFFFFF),
          title: s.toolRemoteDesktop,
          description: s.toolRemoteDesktopSubtitle,
          routeBuilder: _buildRemoteControlPage,
        ),
        if (!Platform.isIOS)
          ToolItemModel(
            id: 'cli',
            iconAsset: 'assets/ic/app/cli.svg',
            iconColor: const Color(0xFFFF9B34),
            title: s.toolCommandLine,
            description: s.toolCommandLineSubtitle,
            onTap: _openCliPage,
          ),
        ToolItemModel(
          id: 'paint',
          iconAsset: 'assets/ic/app/paint-large.svg',
          iconColor: const Color(0xFFE85858),
          title: s.toolPixelDraw,
          description: s.toolPixelDrawSubtitle,
          routeBuilder: _buildPaintPage,
        ),
      ],
    ),
    if (localBuilds)
      ToolGroup(
        header: ToolCardHeader(
          iconAsset: 'assets/ic/app/apps.svg',
          iconColor: const Color(0xFF4DB6AC),
          title: s.toolsGroupApps,
        ),
        items: [
          ToolItemModel(
            id: 'flibler',
            iconAsset: 'assets/ic/fileformat/plugins.svg',
            iconColor: const Color(0xFF4DB6AC),
            title: 'Flibler',
            description: s.toolFliblerSubtitle,
            onTap: _openFliblerPage,
            badge: s.toolBadgeBeta,
          ),
        ],
      ),
    ToolGroup(
      header: ToolCardHeader(
        iconAsset: 'assets/ic/app/files.svg',
        iconColor: const Color(0xFF8BC34A),
        title: s.toolsGroupFileUtils,
      ),
      items: [
        ToolItemModel(
          id: 'mifare',
          iconAsset: 'assets/ic/fileformat/nfc.svg',
          iconColor: const Color(0xFF34C7A4),
          title: s.toolMifare,
          description: s.toolMifareSubtitle,
          routeBuilder: _buildRecoverPage,
          badge: s.toolBadgeBeta,
        ),
        ToolItemModel(
          id: 'ir',
          iconAsset: 'assets/ic/fileformat/ir.svg',
          iconColor: const Color(0xFFAF52DE),
          title: s.toolRemotesLibrary,
          description: s.toolRemotesLibrarySubtitle,
          routeBuilder: _buildIrLibPage,
        ),
        ToolItemModel(
          id: 'plotter',
          iconAsset: 'assets/ic/app/sub-tools.svg',
          iconColor: const Color(0xFFFF9B34),
          title: s.toolPulsePlotter,
          description: s.toolPulsePlotterSubtitle,
          routeBuilder: _buildPlotterPage,
          badge: s.toolBadgeBeta,
        ),
        ToolItemModel(
          id: 'map',
          iconAsset: 'assets/ic/fileformat/sub.svg',
          iconColor: const Color(0xFF8BC34A),
          title: s.toolSavedLocations,
          description: s.toolSavedLocationsSubtitle,
          onTap: _openFlipperMapPage,
        ),
      ],
    ),
    ToolGroup(
      header: ToolCardHeader(
        iconAsset: 'assets/ic/fileformat/sub.svg',
        iconColor: const Color(0xFF2E9E7B),
        title: 'Sub-GHz',
      ),
      items: [
        ToolItemModel(
          id: 'subghz-rx',
          iconAsset: 'assets/ic/fileformat/sub.svg',
          iconColor: const Color(0xFF2E9E7B),
          title: s.toolSubghzRx,
          description: s.toolSubghzRxSubtitle,
          routeBuilder: _buildLiveRxPage,
        ),
        ToolItemModel(
          id: 'decode-raw',
          iconAsset: 'assets/ic/fileformat/sub.svg',
          iconColor: const Color(0xFF2E9E7B),
          title: s.toolDecodeRaw,
          description: s.toolDecodeRawSubtitle,
          routeBuilder: _buildDecodeRawPage,
        ),
        ToolItemModel(
          id: 'hitag2',
          iconAsset: 'assets/ic/fileformat/sub.svg',
          iconColor: const Color(0xFF2E9E7B),
          title: 'Hitag2Hell',
          description: 'Recover Fiat/Renault Hitag2 keys from a capture',
          routeBuilder: _buildHitag2Page,
        ),
        ToolItemModel(
          id: 'psa',
          iconAsset: 'assets/ic/fileformat/sub.svg',
          iconColor: const Color(0xFF2E9E7B),
          title: 'PSA Decrypt',
          description: 'Recover PSA rolling-code fields from a capture',
          routeBuilder: _buildPsaPage,
        ),
      ],
    ),
    ToolGroup(
      items: [
        ToolItemModel(
          id: 'settings',
          iconAsset: 'assets/ic/fileformat/settings.svg',
          iconColor: const Color(0xFF9E9E9E),
          title: s.settingsTitle,
          description: s.toolSettingsSubtitle,
          onTap: _openSettingsPage,
        ),
      ],
    ),
    ToolGroup(
      items: [
        ToolItemModel(
          id: 'about',
          iconAsset: 'assets/ic/info/lg.svg',
          iconColor: const Color(0xFF589DFF),
          title: s.aboutTitle,
          description: s.toolAboutSubtitle,
          onTap: _openAboutPage,
        ),
      ],
    ),
  ];

  Widget _groupHeader(ToolCardHeader header, QAppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          QIcon(asset: header.iconAsset, color: header.iconColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              header.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolItem(BuildContext context, ToolItemModel item) {
    final colors = context.appColors;
    return Row(
      children: [
        QIconBadge(asset: item.iconAsset, color: item.iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: ToolItemText(title: item.title, description: item.description),
        ),
        if (item.badge != null) ToolItemBadge(label: item.badge!),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: QIcon(
            asset: 'assets/ic/nav/navigate-tool.svg',
            color: colors.textMuted,
            size: 16,
          ),
        ),
      ],
    );
  }

  static ToolItemModel? toolById(L10n s, bool localBuilds, String id) {
    for (final group in _toolGroups(s, localBuilds)) {
      for (final item in group.items) {
        if (item.id == id) return item;
      }
    }
    return null;
  }

  static void open(BuildContext context, ToolItemModel item) {
    final onTap = item.onTap;
    if (onTap != null) {
      onTap(context);
      return;
    }
    final routeBuilder = item.routeBuilder;
    if (routeBuilder != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: routeBuilder));
    }
  }

  VoidCallback? _resolveTap(BuildContext context, ToolItemModel item) {
    if (item.onTap == null && item.routeBuilder == null) return null;
    return () => open(context, item);
  }

  void _togglePin(BuildContext context, ToolItemModel item) {
    final added = PinnedToolsStore.instance.toggle(item.id);
    context.showNotification(
      added
          ? context.l10n.toolsPinnedHome(item.title)
          : context.l10n.toolsUnpinnedHome(item.title),
      type: QNotificationType.good,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ColoredBox(
      color: colors.background,
      child: SafeArea(
        left: false,
        right: false,
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 9, bottom: 14),
          child: AnimatedBuilder(
            animation: AssemblerController.instance,
            builder: (context, _) => Column(
              children: [
                for (final group in _toolGroups(
                  context.l10n,
                  AssemblerController.instance.backendChoice.isLocal,
                ))
                  if (group.items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: GroupedCardList<ToolItemModel>(
                        header: group.header == null
                            ? null
                            : _groupHeader(group.header!, colors),
                        items: group.items,
                        onTap: (item) => _resolveTap(context, item),
                        onLongPress: (item) =>
                            () => _togglePin(context, item),
                        itemBuilder: _toolItem,
                      ),
                    ),
                const AppVersionLabel(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _buildRecoverPage(BuildContext context) => const RecoverPage();

Widget _buildDecodeRawPage(BuildContext context) => const DecodeRawPage();

Widget _buildLiveRxPage(BuildContext context) => const LiveRxPage();

Widget _buildHitag2Page(BuildContext context) => const Hitag2WorkflowPage();

Widget _buildPsaPage(BuildContext context) => const PsaWorkflowPage();

Widget _buildPlotterPage(BuildContext context) => const PulsePlotterPage();

Future<void> _openFlipperMapPage(BuildContext context) async {
  await openRoute(context, AppRoute.archiveMap);
}

Widget _buildIrLibPage(BuildContext context) => const IrCategoriesPage();

Future<void> _openAboutPage(BuildContext context) async {
  await openRoute(context, AppRoute.about);
}

Future<void> _openSettingsPage(BuildContext context) async {
  await openRoute(context, AppRoute.appSettings);
}

Widget _buildPaintPage(BuildContext context) => const ProjectManagerPage();

Future<void> _openFliblerPage(BuildContext context) async {
  await openRoute(context, AppRoute.fliblerProject);
}

Widget _buildRemoteControlPage(BuildContext context) =>
    const RemoteControlPage();

Future<void> _openCliPage(BuildContext context) async {
  final client = FlipperOneClient().get();
  final connectedDevice = client.connectedDevice;

  if (connectedDevice?.isBle == true) {
    final shouldContinue =
        await showDialog<bool>(
          context: context,
          barrierColor: context.appColors.dialogBarrier,
          builder: (dialogContext) {
            return FlipperActionDialog(
              imageAssetPath: kCliBluetoothUnavailableAssetPath,
              title: kCliBluetoothUnavailableTitle,
              text: kCliBluetoothUnavailableMessage,
              actionText: kCliBluetoothUnavailableAction,
              onAction: () => Navigator.of(dialogContext).pop(true),
            );
          },
        ) ??
        false;
    if (!shouldContinue || !context.mounted) return;

    try {
      await client.disconnect();
    } catch (e) {
      LogService.info('[CLI] disconnect before terminal failed: $e');
      return;
    }

    if (!context.mounted) return;
  }

  await Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const CliPage()));
}
