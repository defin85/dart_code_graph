/// Базовый класс для узла графа.
abstract class GraphNode {
  /// Уникальный идентификатор узла (например, путь к файлу или полное имя класса).
  final String id;

  /// Тип узла.
  final NodeType type;

  /// Дополнительные свойства узла.
  final Map<String, dynamic> properties;

  GraphNode({required this.id, required this.type, this.properties = const {}});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphNode && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'properties': properties,
      };
}

/// Перечисление типов узлов (согласно упрощенной схеме).
enum NodeType {
  fileType, // Файл
  classType, // Класс
  mixinType, // Миксин
  // Interface - будем использовать Class
}

// --- Конкретные реализации узлов ---

class FileNode extends GraphNode {
  FileNode({required String path})
      : super(
          id: path,
          type: NodeType.fileType, // Убедимся, что имя соответствует enum
          properties: {'path': path},
        );

  String get path => properties['path'];
}

class ClassNode extends GraphNode {
  ClassNode({
    required super.id, // Используем super.id
    required String name,
    required String filePath,
    bool isAbstract = false,
  }) : super(
          type: NodeType.classType, // Убедимся, что имя соответствует enum
          properties: {
            'name': name,
            'filePath': filePath,
            'isAbstract': isAbstract,
          },
        );

  String get name => properties['name'];
  String get filePath => properties['filePath'];
  bool get isAbstract => properties['isAbstract'];
}

class MixinNode extends GraphNode {
  MixinNode({
    required super.id, // Используем super.id
    required String name,
    required String filePath,
  }) : super(
          type: NodeType.mixinType, // Убедимся, что имя соответствует enum
          properties: {
            'name': name,
            'filePath': filePath,
          },
        );

  String get name => properties['name'];
  String get filePath => properties['filePath'];
}
