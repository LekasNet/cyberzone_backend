import 'dart:io';

import 'package:yaml/yaml.dart';

class OpenApiAggregator {
  final List<String> specPaths;
  final int searchDepth;

  OpenApiAggregator({
    required this.specPaths,
    this.searchDepth = 4,
  });

  Future<Map<String, dynamic>> build() async {
    final merged = <String, dynamic>{
      'openapi': '3.0.3',
      'info': {
        'title': 'Cyberzone API',
        'version': '0.1.0',
      },
      'paths': <String, dynamic>{},
      'components': <String, dynamic>{},
      'tags': <Map<String, dynamic>>[],
    };

    for (final relative in specPaths) {
      final serviceName = _inferServiceName(relative);
      final file = _findSpecFile(relative, searchDepth);
      if (file == null) continue;

      final parsed = _loadSpec(file);
      if (parsed == null) continue;

      _ensureTag(merged, serviceName);
      _mergePaths(merged, parsed, serviceName);
      _mergeComponents(merged, parsed);
    }

    return merged;
  }
}

File? _findSpecFile(String relative, int searchDepth) {
  final normalized = relative.replaceAll('/', Platform.pathSeparator);
  var dir = Directory.current;

  for (var i = 0; i < searchDepth; i += 1) {
    final candidate = File('${dir.path}${Platform.pathSeparator}$normalized');
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }

  return null;
}

Map<String, dynamic>? _loadSpec(File file) {
  try {
    final doc = loadYaml(file.readAsStringSync());
    if (doc is! YamlMap) return null;
    return _yamlToMap(doc);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _yamlToMap(YamlMap yaml) {
  final map = <String, dynamic>{};
  for (final entry in yaml.entries) {
    map[entry.key.toString()] = _convertYaml(entry.value);
  }
  return map;
}

dynamic _convertYaml(dynamic value) {
  if (value is YamlMap) {
    return _yamlToMap(value);
  }
  if (value is YamlList) {
    return value.map(_convertYaml).toList();
  }
  return value;
}

void _mergePaths(
  Map<String, dynamic> merged,
  Map<String, dynamic> spec,
  String serviceName,
) {
  final mergedPaths =
      merged.putIfAbsent('paths', () => <String, dynamic>{})
          as Map<String, dynamic>;
  final paths = spec['paths'];
  if (paths is! Map) return;

  for (final entry in paths.entries) {
    final key = entry.key.toString();
    final value = entry.value;
    if (value is Map) {
      final updated = <String, dynamic>{};
      for (final opEntry in value.entries) {
        final opKey = opEntry.key.toString();
        final opValue = opEntry.value;
        if (_isHttpMethod(opKey) && opValue is Map) {
          updated[opKey] = _tagOperation(opValue, serviceName);
        } else {
          updated[opKey] = opValue;
        }
      }

      if (mergedPaths[key] is Map) {
        final existing = (mergedPaths[key] as Map).cast<String, dynamic>();
        updated.forEach((opKey, opValue) {
          existing[opKey] = opValue;
        });
        mergedPaths[key] = existing;
      } else {
        mergedPaths[key] = updated;
      }
    } else {
      mergedPaths[key] = value;
    }
  }
}

void _mergeComponents(Map<String, dynamic> merged, Map<String, dynamic> spec) {
  final components = spec['components'];
  if (components is! Map) return;

  final mergedComponents =
      merged.putIfAbsent('components', () => <String, dynamic>{})
          as Map<String, dynamic>;

  for (final entry in components.entries) {
    final key = entry.key.toString();
    final value = entry.value;

    if (value is Map) {
      final target = mergedComponents.putIfAbsent(key, () => <String, dynamic>{})
          as Map<String, dynamic>;
      for (final nested in value.entries) {
        target[nested.key.toString()] = nested.value;
      }
    } else {
      mergedComponents[key] = value;
    }
  }
}

Map<String, dynamic> _tagOperation(Map opValue, String serviceName) {
  final updated = <String, dynamic>{};
  opValue.forEach((key, value) {
    updated[key.toString()] = value;
  });

  final tagsValue = updated['tags'];
  final tags = <String>[];
  if (tagsValue is List) {
    for (final tag in tagsValue) {
      if (tag is String) tags.add(tag);
    }
  }
  if (!tags.contains(serviceName)) {
    tags.insert(0, serviceName);
  }
  updated['tags'] = tags;
  return updated;
}

void _ensureTag(Map<String, dynamic> merged, String serviceName) {
  final tags = merged['tags'];
  if (tags is! List) return;
  final exists = tags.any((entry) {
    if (entry is Map) {
      return entry['name'] == serviceName;
    }
    return false;
  });
  if (!exists) {
    tags.add({'name': serviceName});
  }
}

bool _isHttpMethod(String method) {
  switch (method.toLowerCase()) {
    case 'get':
    case 'post':
    case 'put':
    case 'delete':
    case 'patch':
      return true;
    default:
      return false;
  }
}

String _inferServiceName(String path) {
  final normalized = path.replaceAll('\\', '/').toLowerCase();
  if (normalized.contains('auth_service')) return 'auth';
  if (normalized.contains('user_service')) return 'user';
  if (normalized.contains('schedule_service')) return 'schedule';
  if (normalized.contains('event_service')) return 'event';
  if (normalized.contains('rating_service')) return 'rating';
  if (normalized.contains('chat_service')) return 'chat';
  if (normalized.contains('notification_service')) return 'notification';
  return 'service';
}
