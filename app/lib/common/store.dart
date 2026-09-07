import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class Store {

  static final asyncPrefs = SharedPreferencesAsync();

  static Future<void> setJson(String key, dynamic value) async {
    await asyncPrefs.setString(key, jsonEncode(value));
  }
  static Future<dynamic> getJson(String key) async {
    var result = await asyncPrefs.getString(key);
    return result == null ? null : jsonDecode(result);
  }

  static Future<void> setBool(String key, bool value) async {
    await asyncPrefs.setBool(key, value);
  }
  static Future<bool?> getBool(String key) async {
    return asyncPrefs.getBool(key);
  }

  static Future<void> setDouble(String key, double value) async {
    await asyncPrefs.setDouble(key, value);
  }
  static Future<double?> getDouble(String key) async {
    return asyncPrefs.getDouble(key);
  }

  static Future<void> setInt(String key, int value) async {
    await asyncPrefs.setInt(key, value);
  }
  static Future<int?> getInt(String key) async {
    return asyncPrefs.getInt(key);
  }

  static Future<void> setString(String key, String value) async {
    await asyncPrefs.setString(key, value);
  }
  static Future<String?> getString(String key) async {
    return asyncPrefs.getString(key);
  }

  static Future<void> setStringList(String key, List<String> value) async {
    await asyncPrefs.setStringList(key, value);
  }
  static Future<List<String>?> getStringList(String key) async {
    return asyncPrefs.getStringList(key);
  }

  static Future<Map<String, Object?>> getAll({Set<String>? allowList}) async {
    return asyncPrefs.getAll(allowList: allowList);
  }

  static Future<Set<String>> getKeys({Set<String>? allowList}) async {
    return asyncPrefs.getKeys(allowList: allowList);
  }

  static Future<void> remove(String key) async {
    return asyncPrefs.remove(key);
  }

  static Future<void> clear({Set<String>? allowList}) async {
    return asyncPrefs.clear();
  }
  
}