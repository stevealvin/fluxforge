import 'package:get_it/get_it.dart';

import 'app_service.dart';
import 'history_service.dart';
import 'rule_service.dart';

final getIt = GetIt.instance;

void configureDependencies() {
  getIt.registerSingleton<AppService>(AppService());
  getIt.registerSingleton<RuleService>(RuleService());
  getIt.registerSingleton<HistoryService>(HistoryService());
}