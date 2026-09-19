import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/data/sites/site_store.dart';

/// 站点新增 / 编辑弹层（[editing] 为空表示新增）
///
/// 表单校验与写库都在弹层内完成，调用方只需在关闭后刷新自身（本弹层写入的是
/// `store.sitesNotifier`，订阅方会自动回显）。
Future<void> showSiteEditorSheet(
  BuildContext context,
  SiteStore store, {
  SiteEntry? editing,
}) async {
  final nameController = TextEditingController(text: editing?.name ?? '');
  final urlController = TextEditingController(text: editing?.url ?? '');
  final formKey = GlobalKey<FormState>();
  final isDark = Theme.of(context).brightness == Brightness.dark;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    editing == null ? '添加站点' : '编辑站点',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '名称',
                      hintText: '留空则使用域名',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: urlController,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '网址',
                      hintText: 'example.com 或 https://example.com',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入网址';
                      }
                      if (!SiteStore.isValidUrl(value)) {
                        return '网址格式不正确';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      HapticFeedback.lightImpact();
                      final name = nameController.text;
                      final url = urlController.text;
                      if (editing == null) {
                        await store.add(name: name, url: url);
                      } else {
                        await store.update(editing.id, name: name, url: url);
                      }
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    },
                    child: Text(editing == null ? '添加' : '保存'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  nameController.dispose();
  urlController.dispose();
}

/// 站点长按操作弹层（编辑 / 删除）
Future<void> showSiteActionsSheet(
  BuildContext context,
  SiteStore store,
  SiteEntry entry,
) async {
  HapticFeedback.selectionClick();
  final isDark = Theme.of(context).brightness == Brightness.dark;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                entry.name,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: const Icon(Ionicons.createOutline, size: 20),
              title: const Text('编辑', style: TextStyle(fontSize: 14)),
              onTap: () {
                Navigator.pop(sheetCtx);
                showSiteEditorSheet(context, store, editing: entry);
              },
            ),
            ListTile(
              leading: const Icon(Ionicons.trashOutline,
                  size: 20, color: AppColors.danger),
              title: const Text('删除',
                  style: TextStyle(fontSize: 14, color: AppColors.danger)),
              onTap: () async {
                Navigator.pop(sheetCtx);
                await store.remove(entry.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已删除「${entry.name}」'),
                      duration: const Duration(milliseconds: 1500),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
