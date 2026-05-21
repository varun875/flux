/// A user-defined coding project that the Flux Code agent operates on.
/// `path` is the absolute filesystem path to the project root; the agent
/// scopes all file/shell operations to this directory.
class FluxCodeProject {
  final String id;
  final String name;
  final String path;
  final DateTime createdAt;

  const FluxCodeProject({
    required this.id,
    required this.name,
    required this.path,
    required this.createdAt,
  });

  FluxCodeProject copyWith({String? name, String? path}) {
    return FluxCodeProject(
      id: id,
      name: name ?? this.name,
      path: path ?? this.path,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'createdAt': createdAt.toIso8601String(),
      };

  factory FluxCodeProject.fromJson(Map<String, dynamic> json) =>
      FluxCodeProject(
        id: json['id'] as String,
        name: json['name'] as String,
        path: json['path'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
