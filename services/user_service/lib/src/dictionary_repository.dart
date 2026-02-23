import 'package:postgres/postgres.dart';

import 'models.dart';

class DictionaryRepository {
  final PostgreSQLConnection _conn;

  DictionaryRepository(this._conn);

  Future<List<DictionaryEntry>> listRoles() async {
    final rows = await _conn.query(
      'SELECT id, name FROM roles ORDER BY name',
    );
    return rows
        .map((row) => DictionaryEntry(
              id: row[0].toString(),
              name: row[1] as String,
            ))
        .toList();
  }

  Future<List<DictionaryEntry>> listDisciplines() async {
    final rows = await _conn.query(
      'SELECT id, name FROM disciplines ORDER BY name',
    );
    return rows
        .map((row) => DictionaryEntry(
              id: row[0].toString(),
              name: row[1] as String,
            ))
        .toList();
  }

  Future<bool> rolesExist(List<String> roleIds) async {
    if (roleIds.isEmpty) return true;
    final rows = await _conn.query(
      'SELECT COUNT(*) FROM roles WHERE id = ANY(@ids)',
      substitutionValues: {'ids': roleIds},
    );
    final count = (rows.first[0] as int?) ?? 0;
    return count == roleIds.length;
  }

  Future<bool> disciplinesExist(List<String> disciplineIds) async {
    if (disciplineIds.isEmpty) return true;
    final rows = await _conn.query(
      'SELECT COUNT(*) FROM disciplines WHERE id = ANY(@ids)',
      substitutionValues: {'ids': disciplineIds},
    );
    final count = (rows.first[0] as int?) ?? 0;
    return count == disciplineIds.length;
  }
}
