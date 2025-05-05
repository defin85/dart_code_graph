import 'package:dart_code_graph/graph_retriever.dart';
import 'package:dart_code_graph/models/graph_node.dart';
import 'package:dart_code_graph/logger_config.dart';

/// Сервис для извлечения контекста кода для RAG.
class CodeRAGService {
  final GraphRetriever retriever;

  CodeRAGService(this.retriever);

  /// Извлекает контекст для заданного узла графа (по ID).
  ///
  /// Возвращает строку с описанием узла и его связей,
  /// которую можно использовать как контекст для LLM.
  String? retrieveContextForNode(String nodeId) {
    final node = retriever.findNodeById(nodeId);
    if (node == null) {
      logger.w('Узел с ID "$nodeId" не найден для извлечения контекста.');
      return null;
    }

    final buffer = StringBuffer();

    // Добавляем информацию о самом узле
    _appendNodeInfo(buffer, node);

    // Добавляем информацию о связях
    _appendRelationshipInfo(buffer, node);

    // TODO: Добавить больше контекста по мере необходимости
    // - Содержимое файла определения? (может быть слишком большим)
    // - Связанные методы/поля (когда граф будет расширен)
    // - Комментарии документации (когда граф будет расширен)

    return buffer.toString();
  }

  /// Добавляет базовую информацию об узле в буфер.
  void _appendNodeInfo(StringBuffer buffer, GraphNode node) {
    buffer.writeln('--- Контекст для узла: ${node.id} ---');
    buffer.writeln('Тип: ${node.type.name}');
    buffer.writeln('Свойства:');
    node.properties.forEach((key, value) {
      buffer.writeln('  - $key: $value');
    });
    buffer.writeln();
  }

  /// Добавляет информацию о связях узла в буфер.
  void _appendRelationshipInfo(StringBuffer buffer, GraphNode node) {
    buffer.writeln('Связи:');

    final definitionFile = retriever.findDefinitionFile(node.id);
    if (definitionFile != null) {
      buffer.writeln('  - Определен в файле: ${definitionFile.path}');
    }

    if (node is ClassNode || node is MixinNode) {
      final interfaces = retriever.findImplementedInterfaces(node.id);
      if (interfaces.isNotEmpty) {
        buffer.writeln(
            '  - Реализует интерфейсы: ${interfaces.map((n) => n.properties['name'] ?? n.id).join(', ')}');
      }
    }

    if (node is ClassNode) {
      final superclass = retriever.findSuperclass(node.id);
      if (superclass != null) {
        buffer.writeln(
            '  - Наследуется от: ${superclass.properties['name'] ?? superclass.id}');
      }

      final mixins = retriever.findUsedMixins(node.id);
      if (mixins.isNotEmpty) {
        buffer.writeln(
            '  - Использует миксины: ${mixins.map((n) => n.properties['name'] ?? n.id).join(', ')}');
      }

      final subclasses = retriever.findSubclasses(node.id);
      if (subclasses.isNotEmpty) {
        buffer.writeln(
            '  - Имеет подклассы: ${subclasses.map((n) => n.properties['name'] ?? n.id).join(', ')}');
      }
    }

    if (node is MixinNode) {
      final classesUsingMixin = retriever.findClassesUsingMixin(node.id);
      if (classesUsingMixin.isNotEmpty) {
        buffer.writeln(
            '  - Используется классами: ${classesUsingMixin.map((n) => n.properties['name'] ?? n.id).join(', ')}');
      }
    }

    // Если это интерфейс (представленный ClassNode), найдем его реализации
    if (node is ClassNode) {
      // Дополнительно проверяем, может ли он быть интерфейсом
      final implementers = retriever.findImplementers(node.id);
      if (implementers.isNotEmpty) {
        buffer.writeln(
            '  - Реализуется классами/миксинами: ${implementers.map((n) => n.properties['name'] ?? n.id).join(', ')}');
      }
    }

    buffer.writeln('--- Конец контекста ---');
  }

  // TODO: Добавить методы для извлечения контекста по имени, по коду и т.д.
}
