// filepath: c:\FlutterProject\part_catalog\scripts\graph_builder\logger_config.dart
import 'package:logger/logger.dart';

/// Глобальный экземпляр логгера для всего скрипта
final logger = Logger(
  level: Level.all, // Устанавливаем уровень здесь
  printer: PrettyPrinter(
    methodCount: 1,
    errorMethodCount: 5,
    lineLength: 80,
    colors: true,
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.none,
  ),
);
