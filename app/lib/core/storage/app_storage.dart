import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FluxForge 全局统一持久化键值存储服务
/// 基于 SharedPreferencesAsync 现代异步规范，提供强类型的 JSON 与基本数据类型读写
class AppStorage {
  static final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  AppStorage._();

  /// 单例实例访问器
  static final AppStorage instance = AppStorage._();

  /// 底层异步持久化引擎句柄
  SharedPreferencesAsync get prefs => _prefs;

  /// 预热初始化
  static Future<void> init() async {}

  // ----------------------- 静态方法 -----------------------
  static Future<void> setJson(String key, dynamic value) async {
    try {
      await _prefs.setString(key, jsonEncode(value));
    } catch (e) {
      debugPrint('[AppStorage] setJson error: $e (key: $key)');
    }
  }

  static Future<dynamic> getJson(String key) async {
    try {
      final str = await _prefs.getString(key);
      if (str == null || str.isEmpty) return null;
      return jsonDecode(str);
    } catch (e) {
      debugPrint('[AppStorage] getJson error: $e (key: $key)');
      return null;
    }
  }

  static Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);
  static Future<bool?> getBool(String key) => _prefs.getBool(key);

  static Future<void> setDouble(String key, double value) => _prefs.setDouble(key, value);
  static Future<double?> getDouble(String key) => _prefs.getDouble(key);

  static Future<void> setInt(String key, int value) => _prefs.setInt(key, value);
  static Future<int?> getInt(String key) => _prefs.getInt(key);

  static Future<void> setString(String key, String value) => _prefs.setString(key, value);
  static Future<String?> getString(String key) => _prefs.getString(key);

  static Future<void> setStringList(String key, List<String> value) =>
      _prefs.setStringList(key, value);
  static Future<List<String>?> getStringList(String key) => _prefs.getStringList(key);

  static Future<Map<String, Object?>> getAll({Set<String>? allowList}) =>
      _prefs.getAll(allowList: allowList);

  static Future<Set<String>> getKeys({Set<String>? allowList}) =>
      _prefs.getKeys(allowList: allowList);

  static Future<void> remove(String key) => _prefs.remove(key);

  static Future<void> clear({Set<String>? allowList}) => _prefs.clear(allowList: allowList);

  // ----------------------- 实例方法映射 (方便 instance.xxx 调用) -----------------------
  Future<void> removeKey(String key) => remove(key);
  Future<void> clearAll({Set<String>? allowList}) => clear(allowList: allowList);
}
