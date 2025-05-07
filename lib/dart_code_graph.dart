/// Support for doing something awesome.
///
/// More dartdocs go here.
library;

export 'src/dart_code_graph_base.dart';

// Экспортируем основные компоненты пакета
export 'code_graph_builder.dart';
export 'graph_retriever.dart';
export 'models/graph_node.dart';
export 'models/graph_edge.dart';
export 'logger_config.dart' show logger;
export 'rag/code_rag_service.dart'; // Добавлен экспорт RAG сервиса

// TODO: Export any libraries intended for clients of this package.
