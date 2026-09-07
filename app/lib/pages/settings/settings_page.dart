import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:get_it/get_it.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../di/app_service.dart';

class SettingsPage extends HookWidget {
  SettingsPage({super.key});

  final appinfoService = GetIt.I<AppService>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Theme(
        data: ThemeData(
          cardTheme: CardThemeData(
            elevation: 0,
            color: Colors.white,
          ),
        ),
        child: ListView(
          children: [
            _buildBase(),
            _buildMain(),
            _buildOther(),

            Container(
              padding: EdgeInsets.all(24),
              alignment: Alignment.center,
              child: Text('版本 ${appinfoService.packageInfo.version}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            )
          ]
        )
      )
    );
  }

  Widget _buildBase() {
    const colors = {
      '月白': Color(0xFFF0F8FF),      // 淡淡的蓝色，如月光
      '天青': Color(0xFF4FC3F7),      // 清澈的天空蓝
      '珊瑚橘': Color(0xFFFF7F50),    // 温暖的橘红色
      '薄荷绿': Color(0xFF98FF98),    // 清新的淡绿色
      '雾紫': Color(0xFFE6E6FA),      // 朦胧的淡紫色
      '琥珀': Color(0xFFFFBF00),      // 温暖的琥珀色
      '石墨灰': Color(0xFF424242),    // 深沉的灰色
      '初雪': Colors.white,          // 纯白色
      '深海': Color(0xFF01579B),      // 深邃的蓝色
    };
    return Card(
      elevation: 0,
      child: Column(
        children: [
          ExpansionTile(
            title: Text('主题设置'),
            leading: Icon(LucideIcons.palette),
            shape: BeveledRectangleBorder(),
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Wrap(
                  spacing: 32,
                  runSpacing: 16,
                  children: colors.entries.map((e) {
                    return GestureDetector(
                      child: Column(
                        spacing: 4,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: e.value,
                              borderRadius: BorderRadius.circular(8)
                            ),
                            width: 40,
                            height: 40
                          ),
                          Text(e.key)
                        ],
                      )
                    );
                  }).toList()
                )
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMain() {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(LucideIcons.refreshCcw),
            title: const Text('自动更新脚本'),
            value: appinfoService.autoUpdateScript,
            onChanged: (bool value) {
              appinfoService.autoUpdateScript = value;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOther() {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(LucideIcons.brushCleaning),
            title: const Text('清除缓存'),
            trailing: Icon(Icons.keyboard_arrow_right),
            onTap: () {

            },
          ),
          ListTile(
            leading: Icon(LucideIcons.scrollText),
            title: const Text('查看日志'),
            trailing: Icon(Icons.keyboard_arrow_right),
            onTap: () {
              
            },
          ),
        ],
      ),
    );
  }
}
