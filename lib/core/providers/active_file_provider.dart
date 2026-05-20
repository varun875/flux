import 'package:flutter_riverpod/flutter_riverpod.dart';

class ActiveFile {
  final String name;
  final String path;
  final String content;

  ActiveFile({
    required this.name,
    required this.path,
    required this.content,
  });
}

final activeFileProvider = StateProvider<ActiveFile?>((ref) => null);
