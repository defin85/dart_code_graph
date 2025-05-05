/// Класс для ребра графа.
class GraphEdge {
  /// ID исходного узла.
  final String sourceId;

  /// ID целевого узла.
  final String targetId;

  /// Тип ребра.
  final EdgeType type;

  /// Дополнительные свойства ребра.
  final Map<String, dynamic> properties;

  GraphEdge({
    required this.sourceId,
    required this.targetId,
    required this.type,
    this.properties = const {},
  });

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'targetId': targetId,
        'type': type.name,
        'properties': properties,
      };
}

/// Перечисление типов ребер (согласно упрощенной схеме).
enum EdgeType {
  declaresType,
  inheritsFromType,
  implementsType,
  mixesInType,
  definedInType,
}
