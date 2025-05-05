import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart'; // Добавлено для Element
import 'package:path/path.dart' as p;
import 'package:dart_code_graph/logger_config.dart'; // Импортируйте общую конфигурацию

import 'package:dart_code_graph/models/graph_node.dart';
import 'package:dart_code_graph/models/graph_edge.dart';

class CodeGraphBuilder {
  final List<GraphNode> nodes = [];
  final List<GraphEdge> edges = [];
  final Set<String> _processedFiles = {}; // Чтобы не обрабатывать файлы дважды

  /// Анализирует все Dart файлы в указанной директории (рекурсивно).
  Future<void> analyzeDirectory(String directoryPath) async {
    final collection = AnalysisContextCollection(
      includedPaths: [p.normalize(p.absolute(directoryPath))],
    );

    for (final context in collection.contexts) {
      final analyzedFiles = context.contextRoot.analyzedFiles().toList();
      logger.i(// Changed from print
          'Analyzing ${analyzedFiles.length} files in ${context.contextRoot.root.path}...');

      for (final filePath in analyzedFiles) {
        if (!filePath.endsWith('.dart') || _processedFiles.contains(filePath)) {
          continue;
        }
        _processedFiles.add(filePath);

        try {
          final result = await context.currentSession.getResolvedUnit(filePath);
          if (result is ResolvedUnitResult) {
            logger.i('Processing: $filePath'); // Changed from print
            _processAst(result.unit, filePath);
          } else {
            logger.e('Error resolving file: $filePath'); // Changed from print
          }
        } catch (e, stackTrace) {
          logger.e('Error processing file $filePath: $e',
              error: e,
              stackTrace:
                  stackTrace); // Changed from print and added error/stackTrace parameters
          // Логгирование ошибки уже выполнено логгером
        }
      }
    }
    logger.i(// Changed from print
        'Analysis complete. Found ${nodes.length} nodes and ${edges.length} edges.');
  }

  /// Обрабатывает AST одного файла.
  void _processAst(CompilationUnit unit, String filePath) {
    // Создаем узел для файла
    final fileNode = FileNode(path: filePath);
    // Проверяем, не был ли узел файла уже добавлен (маловероятно, но для надежности)
    if (!nodes.any((node) => node is FileNode && node.id == filePath)) {
      nodes.add(fileNode);
    }

    // Запускаем посетителя AST
    final visitor = _AstVisitor(filePath, nodes, edges);
    unit.visitChildren(visitor);
  }

  /// Возвращает граф в формате JSON.
  Map<String, dynamic> toJson() {
    return {
      'nodes': nodes.map((n) => n.toJson()).toList(),
      'edges': edges.map((e) => e.toJson()).toList(),
    };
  }
}

/// Посетитель AST для сбора информации о классах и миксинах.
class _AstVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  _AstVisitor(this.filePath, this.nodes, this.edges);

  /// Генерирует стабильный ID из Element.
  /// Использует location, который включает путь к файлу и смещение.
  String? _generateIdFromElement(Element? element) {
    if (element == null || element.location == null) {
      logger.w('Не удалось сгенерировать ID: Element или location is null.');
      return null;
    }
    // location.encoding уникально идентифицирует элемент в проекте
    return element.location!.encoding;
  }

  /// Добавляет ребро, если sourceId и targetId не null.
  void _addEdge(String? sourceId, String? targetId, EdgeType type) {
    if (sourceId != null && targetId != null) {
      edges.add(GraphEdge(sourceId: sourceId, targetId: targetId, type: type));
    } else {
      logger.w('Не удалось добавить ребро типа $type: один из ID равен null.');
    }
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final element = node.declaredElement; // Получаем Element для класса
    if (element == null) {
      logger.e(
          'Не удалось получить Element для класса ${node.name.lexeme} в файле $filePath');
      super.visitClassDeclaration(node);
      return;
    }

    final classId = _generateIdFromElement(element);
    final className = element.name; // Берем имя из Element

    if (classId == null) {
      logger.e(
          'Не удалось сгенерировать ID для класса $className в файле $filePath');
      super.visitClassDeclaration(node);
      return;
    }

    // Создаем или обновляем узел класса
    // Проверяем, существует ли узел с таким ID
    var existingNodeIndex = nodes.indexWhere((n) => n.id == classId);
    if (existingNodeIndex == -1) {
      final classNode = ClassNode(
        id: classId,
        name: className,
        filePath: filePath, // Путь к файлу, где он объявлен
        isAbstract: node.abstractKeyword != null,
      );
      nodes.add(classNode);
      logger.t('Добавлен узел класса: $classId ($className)');
    } else {
      // Узел уже мог быть создан при разрешении ссылки из другого файла
      logger.t('Узел класса $classId ($className) уже существует.');
    }

    // Добавляем ребра DECLARES и DEFINED_IN
    _addEdge(filePath, classId, EdgeType.declaresType);
    _addEdge(classId, filePath, EdgeType.definedInType);

    // Обрабатываем наследование (extends)
    final extendsClause = node.extendsClause;
    if (extendsClause != null) {
      final superclassElement =
          extendsClause.superclass.element; // Получаем Element суперкласса
      final superclassId = _generateIdFromElement(superclassElement);
      if (superclassId != null) {
        _addEdge(classId, superclassId, EdgeType.inheritsFromType);
        logger.t('Добавлено ребро $classId --INHERITS_FROM--> $superclassId');
      } else {
        logger.w(
            'Не удалось разрешить суперкласс ${extendsClause.superclass.name2.toString()} для класса $className');
      }
    }

    // Обрабатываем реализацию интерфейсов (implements)
    final implementsClause = node.implementsClause;
    if (implementsClause != null) {
      for (final interfaceType in implementsClause.interfaces) {
        final interfaceElement =
            interfaceType.element; // Получаем Element интерфейса
        final interfaceId = _generateIdFromElement(interfaceElement);
        if (interfaceId != null) {
          _addEdge(classId, interfaceId, EdgeType.implementsType);
          logger.t('Добавлено ребро $classId --IMPLEMENTS--> $interfaceId');
        } else {
          logger.w(
              'Не удалось разрешить интерфейс ${interfaceType.name2.toString()} для класса $className');
        }
      }
    }

    // Обрабатываем миксины (with)
    final withClause = node.withClause;
    if (withClause != null) {
      for (final mixinType in withClause.mixinTypes) {
        final mixinElement = mixinType.element; // Получаем Element миксина
        final mixinId = _generateIdFromElement(mixinElement);
        if (mixinId != null) {
          _addEdge(classId, mixinId, EdgeType.mixesInType);
          logger.t('Добавлено ребро $classId --MIXES_IN--> $mixinId');
        } else {
          logger.w(
              'Не удалось разрешить миксин ${mixinType.name2.toString()} для класса $className');
        }
      }
    }

    super.visitClassDeclaration(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    final element = node.declaredElement; // Получаем Element для миксина
    if (element == null) {
      logger.e(
          'Не удалось получить Element для миксина ${node.name.lexeme} в файле $filePath');
      super.visitMixinDeclaration(node);
      return;
    }

    final mixinId = _generateIdFromElement(element);
    final mixinName = element.name; // Берем имя из Element

    if (mixinId == null) {
      logger.e(
          'Не удалось сгенерировать ID для миксина $mixinName в файле $filePath');
      super.visitMixinDeclaration(node);
      return;
    }

    // Создаем или обновляем узел миксина
    var existingNodeIndex = nodes.indexWhere((n) => n.id == mixinId);
    if (existingNodeIndex == -1) {
      final mixinNode = MixinNode(
        id: mixinId,
        name: mixinName,
        filePath: filePath, // Путь к файлу, где он объявлен
      );
      nodes.add(mixinNode);
      logger.t('Добавлен узел миксина: $mixinId ($mixinName)');
    } else {
      logger.t('Узел миксина $mixinId ($mixinName) уже существует.');
    }

    // Добавляем ребра DECLARES и DEFINED_IN
    _addEdge(filePath, mixinId, EdgeType.declaresType);
    _addEdge(mixinId, filePath, EdgeType.definedInType);

    // Обрабатываем ограничения 'on' (аналог implements для миксинов)
    final onClause = node.onClause;
    if (onClause != null) {
      for (final constraintType in onClause.superclassConstraints) {
        final constraintElement =
            constraintType.element; // Получаем Element ограничения
        final constraintId = _generateIdFromElement(constraintElement);
        if (constraintId != null) {
          // Используем IMPLEMENTS, как и обсуждали
          _addEdge(mixinId, constraintId, EdgeType.implementsType);
          logger
              .t('Добавлено ребро $mixinId --IMPLEMENTS (ON)--> $constraintId');
        } else {
          logger.w(
              'Не удалось разрешить ограничение (on) ${constraintType.name2.toString()} для миксина $mixinName');
        }
      }
    }

    // Обрабатываем реализацию интерфейсов (implements)
    final implementsClause = node.implementsClause;
    if (implementsClause != null) {
      for (final interfaceType in implementsClause.interfaces) {
        final interfaceElement =
            interfaceType.element; // Получаем Element интерфейса
        final interfaceId = _generateIdFromElement(interfaceElement);
        if (interfaceId != null) {
          _addEdge(mixinId, interfaceId, EdgeType.implementsType);
          logger.t('Добавлено ребро $mixinId --IMPLEMENTS--> $interfaceId');
        } else {
          logger.w(
              'Не удалось разрешить интерфейс ${interfaceType.name2.toString()} для миксина $mixinName');
        }
      }
    }

    super.visitMixinDeclaration(node);
  }

  // TODO: Добавить visitFunctionDeclaration, visitMethodDeclaration и т.д. по мере расширения схемы
}
