// ignore_for_file: prefer_initializing_formals
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/rule.dart';
import 'favorite_service.dart';
import 'history_service.dart';
import 'rule_service.dart';

/// 备份恢复执行结果模型
class BackupRestoreResult {
  final bool success;
  final String message;
  final int rulesImported;
  final int favoritesImported;
  final int historyImported;

  const BackupRestoreResult({
    required this.success,
    this.message = '',
    this.rulesImported = 0,
    this.favoritesImported = 0,
    this.historyImported = 0,
  });
}

/// 本地全量数据一键备份与恢复服务 (BackupService)
/// 
/// 负责规则库、收藏夹及历史记录的标准化 JSON 打包导出与差异/覆盖还原
class BackupService {
  final RuleService _ruleService;
  final FavoriteService _favoriteService;
  final HistoryService _historyService;

  BackupService({
    required RuleService ruleService,
    required FavoriteService favoriteService,
    required HistoryService historyService,
  })  : _ruleService = ruleService,
        _favoriteService = favoriteService,
        _historyService = historyService;

  /// 生成当前本地数据的全量标准化 JSON 字符串
  String generateBackupJson() {
    final now = DateTime.now();
    final data = {
      'app': 'FluxForge',
      'version': 1,
      'exportedAt': now.toIso8601String(),
      'data': {
        'rules': _ruleService.rules.map((r) => r.toJson()).toList(),
        'favorites': _favoriteService.favorites.map((f) => f.toJson()).toList(),
        'history': _historyService.searchHistory,
      },
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 一键导出备份文件并通过原生系统面板分享/保存
  Future<File> exportBackup() async {
    final jsonContent = generateBackupJson();
    final tempDir = await getTemporaryDirectory();

    final now = DateTime.now();
    final formattedDate =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final fileName = 'fluxforge_backup_$formattedDate.json';
    final file = File('${tempDir.path}/$fileName');

    await file.writeAsString(jsonContent);

    // 调用系统分享
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: '来自 FluxForge 移动端的数据备份包 ($fileName)',
      ),
    );

    return file;
  }

  /// 校验 JSON 文本是否为合法的 FluxForge 备份数据包
  bool validateBackupJson(String jsonStr) {
    try {
      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return decoded['app'] == 'FluxForge' && decoded.containsKey('data');
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 执行数据包恢复 (支持 merge: true 合并追加，或 false 完全覆盖)
  Future<BackupRestoreResult> restoreBackup({
    required String jsonStr,
    bool merge = true,
  }) async {
    try {
      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic> || decoded['app'] != 'FluxForge') {
        return const BackupRestoreResult(
          success: false,
          message: '无效的备份文件：非 FluxForge 标准数据包',
        );
      }

      final data = decoded['data'] as Map<String, dynamic>? ?? {};

      // 1. 恢复规则库
      int importedRules = 0;
      if (data.containsKey('rules') && data['rules'] is List) {
        final incomingRules = (data['rules'] as List)
            .map((e) => Rule.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();

        if (merge) {
          final current = List<Rule>.from(_ruleService.rules);
          for (final rule in incomingRules) {
            final idx = current.indexWhere((r) =>
                (r.id != null && rule.id != null && r.id == rule.id) ||
                (r.name == rule.name && r.baseUrl == rule.baseUrl));
            if (idx >= 0) {
              current[idx] = rule;
            } else {
              current.add(rule);
            }
            importedRules++;
          }
          await _ruleService.saveRules(current);
        } else {
          await _ruleService.saveRules(incomingRules);
          importedRules = incomingRules.length;
        }
      }

      // 2. 恢复收藏夹
      int importedFavorites = 0;
      if (data.containsKey('favorites') && data['favorites'] is List) {
        final incomingFavorites = (data['favorites'] as List)
            .map((e) => FavoriteItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();

        if (merge) {
          final current = List<FavoriteItem>.from(_favoriteService.favorites);
          for (final fav in incomingFavorites) {
            final idx = current.indexWhere((f) => f.id == fav.id);
            if (idx >= 0) {
              current[idx] = fav;
            } else {
              current.add(fav);
            }
            importedFavorites++;
          }
          await _favoriteService.setFavorites(current);
        } else {
          await _favoriteService.setFavorites(incomingFavorites);
          importedFavorites = incomingFavorites.length;
        }
      }

      // 3. 恢复历史记录
      int importedHistory = 0;
      if (data.containsKey('history') && data['history'] is List) {
        final incomingHistory =
            (data['history'] as List).map((e) => e.toString()).toList();

        if (merge) {
          final current = List<String>.from(_historyService.searchHistory);
          for (final h in incomingHistory) {
            if (!current.contains(h)) {
              current.add(h);
              importedHistory++;
            }
          }
          await _historyService.updateHistory(current);
        } else {
          await _historyService.updateHistory(incomingHistory);
          importedHistory = incomingHistory.length;
        }
      }

      return BackupRestoreResult(
        success: true,
        message: merge ? '合并恢复成功' : '全量覆盖恢复成功',
        rulesImported: importedRules,
        favoritesImported: importedFavorites,
        historyImported: importedHistory,
      );
    } catch (e) {
      debugPrint('[BackupService] 恢复备份发生异常: $e');
      return BackupRestoreResult(
        success: false,
        message: '数据解析或恢复失败: $e',
      );
    }
  }
}
