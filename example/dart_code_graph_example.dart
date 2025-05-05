import 'package:dart_code_graph/dart_code_graph.dart'; // Импортируем все через главный файл

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  print('--- main.dart START ---');
  logger.f('--- Logger test message ---');

  // --- Код определения projectLibDir и генерации графа (остается без изменений) ---
  String projectPath;
  if (arguments.isNotEmpty) {
    projectPath = arguments[0];
    logger.i('Using project path from arguments: $projectPath');
  } else {
    projectPath = '../part_catalog';
    logger.w(
        'No project path argument provided. Using default relative path: $projectPath');
  }
  final absoluteProjectPath = p.normalize(p.absolute(projectPath));
  final projectLibDir = p.join(absoluteProjectPath, 'lib');
  if (!Directory(projectLibDir).existsSync()) {
    logger.e('Project lib directory not found at: $projectLibDir');
    logger.e(
        'Please provide a valid path to the part_catalog project as a command line argument.');
    return;
  }
  final builder = CodeGraphBuilder();
  final outputFilePath = 'project_graph.json';
  logger.i('Starting analysis of directory: $projectLibDir');
  await builder.analyzeDirectory(projectLibDir);
  final outputFile = File(outputFilePath);
  final jsonEncoder = JsonEncoder.withIndent('  ');
  final jsonGraph = jsonEncoder.convert(builder.toJson());
  await outputFile.writeAsString(jsonGraph);
  logger.i('Graph saved to ${outputFile.path}');
  // --- Конец кода генерации графа ---

  // --- Демонстрация использования GraphRetriever (остается без изменений) ---
  logger.i('\n--- Testing GraphRetriever ---');
  final retriever = await GraphRetriever.fromJsonFile(outputFilePath);
  if (retriever == null) {
    logger.e('Failed to load graph for retrieval.');
    return;
  }
  // ... (код с примерами вызовов retriever.findNodesByType и т.д.) ...
  final allClasses = retriever.findNodesByType(NodeType.classType).toList();
  logger.i('Found ${allClasses.length} classes.');
  if (allClasses.isNotEmpty) {
    final exampleClass = allClasses.first as ClassNode;
    final classId = exampleClass.id;
    logger
        .i('\n--- Details for class: ${exampleClass.name} (ID: $classId) ---');
    // ... (логирование деталей класса через retriever) ...
  } else {
    logger.w('No classes found to demonstrate retrieval details.');
  }
  // --- Конец демонстрации GraphRetriever ---

  // --- Демонстрация использования CodeRAGService ---
  logger.i('\n--- Testing CodeRAGService ---');
  final ragService = CodeRAGService(retriever);

  // Пример: Получить контекст для первого найденного класса
  if (allClasses.isNotEmpty) {
    final exampleClassId = allClasses.first.id;
    logger.i('\nRetrieving RAG context for node ID: $exampleClassId');

    final context = ragService.retrieveContextForNode(exampleClassId);

    if (context != null) {
      logger.i('Retrieved Context:\n$context');

      // --- Здесь будет вызов LLM ---
      // final userQuery = "Объясни назначение класса ${allClasses.first.properties['name']}";
      // final prompt = """
      // Используя следующий контекст кода:
      // $context
      //
      // Ответь на вопрос: $userQuery
      // """;
      // logger.i("\n--- Prompt for LLM ---");
      // logger.i(prompt);
      // final llmResponse = await callLLMApi(prompt); // Псевдокод
      // logger.i("\n--- LLM Response ---");
      // logger.i(llmResponse);
      // --- Конец вызова LLM ---
    } else {
      logger.w('Could not retrieve context for node ID: $exampleClassId');
    }
  } else {
    logger.w('No classes found to demonstrate RAG context retrieval.');
  }
}
