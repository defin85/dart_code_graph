import 'dart:convert';
import 'dart:io';

import 'package:dart_code_graph/logger_config.dart'; // Импортируйте общую конфигурацию

import 'package:dart_code_graph/models/graph_node.dart';
import 'package:dart_code_graph/models/graph_edge.dart';

class GraphRetriever {
  final List<GraphNode> _nodes;
  final List<GraphEdge> _edges;

  // Индексы для быстрого доступа
  final Map<String, GraphNode> _nodesById = {};
  final Map<String, List<GraphEdge>> _outgoingEdges = {};
  final Map<String, List<GraphEdge>> _incomingEdges = {};

  /// Приватный конструктор для инициализации из списков.
  GraphRetriever._(this._nodes, this._edges) {
    _buildIndexes();
  }

  /// Фабричный конструктор для загрузки графа из JSON-файла.
  static Future<GraphRetriever?> fromJsonFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        logger.e('Файл графа не найден: $filePath');
        return null;
      }
      final content = await file.readAsString();
      final jsonGraph = jsonDecode(content) as Map<String, dynamic>;

      final nodesJson = jsonGraph['nodes'] as List<dynamic>? ?? [];
      final edgesJson = jsonGraph['edges'] as List<dynamic>? ?? [];

      final nodes = nodesJson
          .map((nodeJson) {
            final typeName = nodeJson['type'] as String?;
            final id = nodeJson['id'] as String?;
            final properties =
                nodeJson['properties'] as Map<String, dynamic>? ?? {};

            if (id == null || typeName == null) {
              logger.w('Пропуск узла с отсутствующим id или type: $nodeJson');
              return null; // Пропускаем некорректные узлы
            }

            final nodeType = NodeType.values.firstWhere(
              (e) => e.name == typeName,
              orElse: () {
                logger.w('Неизвестный тип узла "$typeName" для id "$id".');
                return NodeType.values[0]; // Или бросить исключение?
              },
            );

            // Воссоздаем конкретные типы узлов (можно улучшить фабрикой)
            switch (nodeType) {
              case NodeType.fileType:
                return FileNode(path: properties['path'] ?? id);
              case NodeType.classType:
                return ClassNode(
                  id: id,
                  name: properties['name'] ?? 'Unknown',
                  filePath: properties['filePath'] ?? 'Unknown',
                  isAbstract: properties['isAbstract'] ?? false,
                );
              case NodeType.mixinType:
                return MixinNode(
                  id: id,
                  name: properties['name'] ?? 'Unknown',
                  filePath: properties['filePath'] ?? 'Unknown',
                );
              // Добавить другие типы узлов по мере их появления
            }
          })
          .whereType<GraphNode>()
          .toList(); // Отфильтровываем null

      final edges = edgesJson
          .map((edgeJson) {
            final sourceId = edgeJson['sourceId'] as String?;
            final targetId = edgeJson['targetId'] as String?;
            final typeName = edgeJson['type'] as String?;
            final properties =
                edgeJson['properties'] as Map<String, dynamic>? ?? {};

            if (sourceId == null || targetId == null || typeName == null) {
              logger.w(
                  'Пропуск ребра с отсутствующим sourceId, targetId или type: $edgeJson');
              return null; // Пропускаем некорректные ребра
            }

            final edgeType = EdgeType.values.firstWhere(
              (e) => e.name == typeName,
              orElse: () {
                logger.w(
                    'Неизвестный тип ребра "$typeName" между "$sourceId" и "$targetId".');
                return EdgeType.values[0]; // Или бросить исключение?
              },
            );

            return GraphEdge(
              sourceId: sourceId,
              targetId: targetId,
              type: edgeType,
              properties: properties,
            );
          })
          .whereType<GraphEdge>()
          .toList(); // Отфильтровываем null

      logger.i(
          'Граф успешно загружен из $filePath (${nodes.length} узлов, ${edges.length} ребер).');
      return GraphRetriever._(nodes, edges);
    } catch (e, stackTrace) {
      logger.e('Ошибка при загрузке или парсинге графа из $filePath',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Строит внутренние индексы для быстрого поиска.
  void _buildIndexes() {
    for (final node in _nodes) {
      _nodesById[node.id] = node;
    }
    for (final edge in _edges) {
      _outgoingEdges.putIfAbsent(edge.sourceId, () => []).add(edge);
      _incomingEdges.putIfAbsent(edge.targetId, () => []).add(edge);
    }
    logger.t('Внутренние индексы графа построены.');
  }

  // --- Методы для запроса графа ---

  /// Находит узел по его уникальному ID.
  GraphNode? findNodeById(String id) {
    return _nodesById[id];
  }

  /// Находит все узлы заданного типа.
  Iterable<GraphNode> findNodesByType(NodeType type) {
    return _nodes.where((node) => node.type == type);
  }

  /// Получает список ID соседних узлов для данного узла.
  ///
  /// [nodeId]: ID узла, для которого ищутся соседи.
  /// [edgeType]: Опциональный фильтр по типу ребра.
  /// [direction]: Направление поиска ('outgoing', 'incoming', 'both').
  Set<String> getNeighborIds(
    String nodeId, {
    EdgeType? edgeType,
    String direction = 'both', // 'outgoing', 'incoming', 'both'
  }) {
    final neighbors = <String>{};

    if (direction == 'outgoing' || direction == 'both') {
      final edges = _outgoingEdges[nodeId] ?? [];
      for (final edge in edges) {
        if (edgeType == null || edge.type == edgeType) {
          neighbors.add(edge.targetId);
        }
      }
    }

    if (direction == 'incoming' || direction == 'both') {
      final edges = _incomingEdges[nodeId] ?? [];
      for (final edge in edges) {
        if (edgeType == null || edge.type == edgeType) {
          neighbors.add(edge.sourceId);
        }
      }
    }
    return neighbors;
  }

  /// Получает список соседних узлов для данного узла.
  Set<GraphNode> getNeighbors(
    String nodeId, {
    EdgeType? edgeType,
    String direction = 'both',
  }) {
    final neighborIds =
        getNeighborIds(nodeId, edgeType: edgeType, direction: direction);
    return neighborIds
        .map((id) => findNodeById(id))
        .whereType<GraphNode>()
        .toSet();
  }

  /// Находит суперкласс для данного ID класса.
  GraphNode? findSuperclass(String classId) {
    final neighborIds = getNeighborIds(classId,
        edgeType: EdgeType.inheritsFromType, direction: 'outgoing');
    return neighborIds.isNotEmpty ? findNodeById(neighborIds.first) : null;
  }

  /// Находит интерфейсы, реализуемые данным ID класса или миксина.
  Set<GraphNode> findImplementedInterfaces(String classOrMixinId) {
    return getNeighbors(classOrMixinId,
        edgeType: EdgeType.implementsType, direction: 'outgoing');
  }

  /// Находит миксины, используемые данным ID класса.
  Set<GraphNode> findUsedMixins(String classId) {
    return getNeighbors(classId,
        edgeType: EdgeType.mixesInType, direction: 'outgoing');
  }

  /// Находит классы/миксины, которые реализуют данный интерфейс (ID класса).
  Set<GraphNode> findImplementers(String interfaceId) {
    return getNeighbors(interfaceId,
        edgeType: EdgeType.implementsType, direction: 'incoming');
  }

  /// Находит классы, которые наследуются от данного класса (ID).
  Set<GraphNode> findSubclasses(String classId) {
    return getNeighbors(classId,
        edgeType: EdgeType.inheritsFromType, direction: 'incoming');
  }

  /// Находит классы, которые используют данный миксин (ID).
  Set<GraphNode> findClassesUsingMixin(String mixinId) {
    return getNeighbors(mixinId,
        edgeType: EdgeType.mixesInType, direction: 'incoming');
  }

  /// Находит файл, в котором определен данный узел (класс, миксин и т.д.).
  FileNode? findDefinitionFile(String elementId) {
    final neighborIds = getNeighborIds(elementId,
        edgeType: EdgeType.definedInType, direction: 'outgoing');
    final fileNode =
        neighborIds.isNotEmpty ? findNodeById(neighborIds.first) : null;
    return fileNode is FileNode ? fileNode : null;
  }

  /// Находит все элементы (классы, миксины), объявленные в данном файле (ID файла).
  Set<GraphNode> findDeclarationsInFile(String fileId) {
    return getNeighbors(fileId,
        edgeType: EdgeType.declaresType, direction: 'outgoing');
  }

  // TODO: Добавить более сложные методы запросов по мере необходимости
  // Например, поиск по имени, поиск цепочки наследования, поиск всех вызовов метода и т.д.
}
