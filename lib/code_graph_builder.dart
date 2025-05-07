import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
// Используем новую модель элементов
import 'package:analyzer/dart/element/element2.dart';
import 'package:path/path.dart' as p;
import 'package:dart_code_graph/logger_config.dart'; // Импортируйте общую конфигурацию

import 'package:dart_code_graph/models/graph_node.dart';
import 'package:dart_code_graph/models/graph_edge.dart';

/// Строит граф знаний из исходного кода Dart.
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
      logger.i(
          'Analyzing ${analyzedFiles.length} files in ${context.contextRoot.root.path}...');

      for (final filePath in analyzedFiles) {
        if (!filePath.endsWith('.dart') || _processedFiles.contains(filePath)) {
          continue;
        }
        _processedFiles.add(filePath);

        try {
          // Используем getResolvedLibrary2 для получения информации о библиотеке
          // Это может быть более надежно для получения всех фрагментов
          final result =
              await context.currentSession.getResolvedLibrary(filePath);
          if (result is ResolvedLibraryResult) {
            logger.i('Processing library associated with: $filePath');
            // Обрабатываем каждый фрагмент (файл) в библиотеке
            for (final unitResult in result.units) {
              if (_processedFiles.contains(unitResult.path)) {
                _processAst(unitResult.unit, unitResult.path);
              }
            }
          } else {
            logger.e('Error resolving library for file: $filePath');
          }
        } catch (e, stackTrace) {
          logger.e('Error processing file $filePath: $e',
              error: e, stackTrace: stackTrace);
        }
      }
    }
    logger.i(
        'Analysis complete. Found ${nodes.length} nodes and ${edges.length} edges.');
  }

  /// Обрабатывает AST одного файла (единицы компиляции).
  void _processAst(CompilationUnit unit, String filePath) {
    // Создаем узел для файла, если его еще нет
    if (!nodes.any((node) => node is FileNode && node.id == filePath)) {
      final fileNode = FileNode(path: filePath);
      nodes.add(fileNode);
      logger.t('Added file node: $filePath');
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

/// Посетитель AST для сбора информации о классах и миксинах с использованием Element Model 2.0.
class _AstVisitor extends RecursiveAstVisitor<void> {
  final String filePath; // Путь к текущему обрабатываемому файлу
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  _AstVisitor(this.filePath, this.nodes, this.edges);

  /// Генерирует стабильный ID из фрагмента объявления (Fragment).
  /// Использует URI библиотеки, имя элемента и смещение имени в фрагменте.
  // Изменяем параметр на Fragment? и переименовываем функцию
  String? _generateIdFromFragment(Fragment? fragment) {
    if (fragment == null) {
      logger.w('Cannot generate ID: Fragment is null.');
      return null;
    }
    // Получаем Element из Fragment
    final element = fragment.element;
    // Используем element.library2
    if (element.library2 == null) {
      logger.w(
          'Cannot generate ID: Element or Library2 is null for fragment ${fragment.name2} at offset ${fragment.nameOffset2}.');
      return null;
    }
    // Используем URI библиотеки + имя элемента + смещение имени фрагмента для уникальности
    final libraryUri = element.library2!.uri.toString();
    final elementName =
        element.name3 ?? 'unnamed'; // Используем name3 для Element2
    final nameOffset =
        fragment.nameOffset2; // Используем nameOffset2 для Fragment
    return '$libraryUri#$elementName@$nameOffset';
  }

  /// Добавляет ребро, если sourceId и targetId не null.
  void _addEdge(String? sourceId, String? targetId, EdgeType type) {
    if (sourceId != null && targetId != null) {
      // Избегаем добавления дубликатов ребер
      if (!edges.any((e) =>
          e.sourceId == sourceId && e.targetId == targetId && e.type == type)) {
        edges
            .add(GraphEdge(sourceId: sourceId, targetId: targetId, type: type));
      }
    } else {
      logger.w('Cannot add edge type $type: one of the IDs is null.');
    }
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    // Получаем фрагмент и элемент
    final fragment = node.declaredFragment; // ClassFragment?
    if (fragment == null) {
      logger.e(
          'Cannot get Fragment for class ${node.name.lexeme} in file $filePath');
      super.visitClassDeclaration(node);
      return;
    }
    final element = fragment.element; // ClassElement2?

    // Генерируем ID из фрагмента текущего узла
    final classId = _generateIdFromFragment(fragment);
    final className = element.name3; // Используем name3

    if (classId == null) {
      logger.e('Cannot generate ID for class $className in file $filePath');
      super.visitClassDeclaration(node);
      return;
    }

    // Создаем или обновляем узел класса
    var existingNodeIndex = nodes.indexWhere((n) => n.id == classId);
    if (existingNodeIndex == -1) {
      final classNode = ClassNode(
        id: classId,
        name: className ??
            node.name.lexeme, // Fallback to AST name if element name is null
        filePath: filePath, // Путь к файлу, где он объявлен
        isAbstract: node.abstractKeyword != null,
      );
      nodes.add(classNode);
      logger.t('Added class node: $classId ($className)');
    } else {
      // Можно добавить логику обновления существующего узла, если нужно
      logger.t('Class node $classId ($className) already exists.');
    }

    // Добавляем ребра DECLARES (файл -> класс) и DEFINED_IN (класс -> файл)
    _addEdge(filePath, classId, EdgeType.declaresType);
    _addEdge(classId, filePath, EdgeType.definedInType);

    // Обрабатываем наследование (extends)
    final extendsClause = node.extendsClause;
    if (extendsClause != null) {
      final superclassElement = extendsClause.superclass.element2; // Element2?
      // Генерируем ID из первого фрагмента связанного элемента
      final superclassId =
          _generateIdFromFragment(superclassElement?.firstFragment);
      if (superclassId != null) {
        _addEdge(classId, superclassId, EdgeType.inheritsFromType);
        logger.t('Added edge $classId --INHERITS_FROM--> $superclassId');
      } else {
        logger.w(
            'Cannot resolve superclass ${extendsClause.superclass.name2.lexeme} for class $className');
      }
    }

    // Обрабатываем реализацию интерфейсов (implements)
    final implementsClause = node.implementsClause;
    if (implementsClause != null) {
      for (final interfaceType in implementsClause.interfaces) {
        final interfaceElement = interfaceType.element2; // Element2?
        // Генерируем ID из первого фрагмента связанного элемента
        final interfaceId =
            _generateIdFromFragment(interfaceElement?.firstFragment);
        if (interfaceId != null) {
          _addEdge(classId, interfaceId, EdgeType.implementsType);
          logger.t('Added edge $classId --IMPLEMENTS--> $interfaceId');
        } else {
          logger.w(
              'Cannot resolve interface ${interfaceType.name2.lexeme} for class $className');
        }
      }
    }

    // Обрабатываем миксины (with)
    final withClause = node.withClause;
    if (withClause != null) {
      for (final mixinType in withClause.mixinTypes) {
        final mixinElement = mixinType.element2; // Element2?
        // Генерируем ID из первого фрагмента связанного элемента
        final mixinId = _generateIdFromFragment(mixinElement?.firstFragment);
        if (mixinId != null) {
          _addEdge(classId, mixinId, EdgeType.mixesInType);
          logger.t('Added edge $classId --MIXES_IN--> $mixinId');
        } else {
          logger.w(
              'Cannot resolve mixin ${mixinType.name2.lexeme} for class $className');
        }
      }
    }

    super.visitClassDeclaration(node); // Продолжаем обход дочерних узлов
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    final fragment = node.declaredFragment; // MixinFragment?
    if (fragment == null) {
      logger.e(
          'Cannot get Fragment for mixin ${node.name.lexeme} in file $filePath');
      super.visitMixinDeclaration(node);
      return;
    }
    final element = fragment.element; // MixinElement2?

    // Генерируем ID из фрагмента текущего узла
    final mixinId = _generateIdFromFragment(fragment);
    final mixinName = element.name3; // Используем name3

    if (mixinId == null) {
      logger.e('Cannot generate ID for mixin $mixinName in file $filePath');
      super.visitMixinDeclaration(node);
      return;
    }

    // Создаем или обновляем узел миксина
    var existingNodeIndex = nodes.indexWhere((n) => n.id == mixinId);
    if (existingNodeIndex == -1) {
      final mixinNode = MixinNode(
        id: mixinId,
        name: mixinName ?? node.name.lexeme, // Fallback
        filePath: filePath,
      );
      nodes.add(mixinNode);
      logger.t('Added mixin node: $mixinId ($mixinName)');
    } else {
      logger.t('Mixin node $mixinId ($mixinName) already exists.');
    }

    // Добавляем ребра DECLARES и DEFINED_IN
    _addEdge(filePath, mixinId, EdgeType.declaresType);
    _addEdge(mixinId, filePath, EdgeType.definedInType);

    // Обрабатываем ограничения 'on' (рассматриваем как реализацию интерфейса)
    final onClause = node.onClause;
    if (onClause != null) {
      for (final constraintType in onClause.superclassConstraints) {
        final constraintElement = constraintType.element2; // Element2?
        // Генерируем ID из первого фрагмента связанного элемента
        final constraintId =
            _generateIdFromFragment(constraintElement?.firstFragment);
        if (constraintId != null) {
          _addEdge(mixinId, constraintId,
              EdgeType.implementsType); // Используем IMPLEMENTS
          logger.t('Added edge $mixinId --IMPLEMENTS (ON)--> $constraintId');
        } else {
          logger.w(
              'Cannot resolve constraint (on) ${constraintType.name2.lexeme} for mixin $mixinName');
        }
      }
    }

    // Обрабатываем реализацию интерфейсов (implements)
    final implementsClause = node.implementsClause;
    if (implementsClause != null) {
      for (final interfaceType in implementsClause.interfaces) {
        final interfaceElement = interfaceType.element2; // Element2?
        // Генерируем ID из первого фрагмента связанного элемента
        final interfaceId =
            _generateIdFromFragment(interfaceElement?.firstFragment);
        if (interfaceId != null) {
          _addEdge(mixinId, interfaceId, EdgeType.implementsType);
          logger.t('Added edge $mixinId --IMPLEMENTS--> $interfaceId');
        } else {
          logger.w(
              'Cannot resolve interface ${interfaceType.name2.lexeme} for mixin $mixinName');
        }
      }
    }

    super.visitMixinDeclaration(node);
  }

  // TODO: Добавить visitEnumDeclaration, visitExtensionDeclaration, visitFunctionDeclaration, visitMethodDeclaration и т.д. по мере необходимости
}
