import 'package:flutter/material.dart';

import '../../../components/icon.dart';
import '../../../components/notification.dart';
import '../../../services/assembler/controller.dart';
import '../../../services/localization/l10n.dart';
import '../../../theme/theme.dart';
import '../../tools/overview/models/tool.dart';
import '../../tools/overview/page.dart';
import '../../tools/overview/pinned_tools.dart';
import '../../tools/overview/widgets/tool_item_text.dart';

class PinnedToolCards extends StatelessWidget {
  const PinnedToolCards({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        PinnedToolsStore.instance,
        AssemblerController.instance,
      ]),
      builder: (context, _) {
        final local = AssemblerController.instance.backendChoice.isLocal;
        final items = <ToolItemModel>[
          for (final id in PinnedToolsStore.instance.ids)
            ?ToolsPage.toolById(context.l10n, local, id),
        ];
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: _PinnedToolCard(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _PinnedToolCard extends StatelessWidget {
  const _PinnedToolCard({required this.item});

  final ToolItemModel item;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => ToolsPage.open(context, item),
        onLongPress: () {
          PinnedToolsStore.instance.remove(item.id);
          context.showNotification(
            context.l10n.toolsUnpinnedHome(item.title),
            type: QNotificationType.good,
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              QIconBadge(asset: item.iconAsset, color: item.iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: ToolItemText(
                  title: item.title,
                  description: item.description,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
