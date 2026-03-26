import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'models/engagement_event.dart';

// ── Minimal raw-SQL local event buffer ────────────────────────────────
// We avoid Drift code-gen entirely and use raw SQL via drift's
// `customSelect` / `customStatement` on a NativeDatabase.

/// Buffers engagement events locally in SQLite and provides batch-read
/// for [SyncService].
class EventRecorder {
  EventRecorder();

  GeneratedDatabase? _db;
  Timer? _pruneTimer;

  Future<GeneratedDatabase> _getDb() async {
    if (_db != null) return _db!;
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'beta_events.sqlite'));
    _db = _RawEventDb(NativeDatabase(file));
    // Create table if needed.
    _db!.customStatement('''
      CREATE TABLE IF NOT EXISTS event_buffer (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        screen_name TEXT,
        x REAL,
        y REAL,
        duration_ms INTEGER,
        metadata_json TEXT,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    return _db!;
  }

  void start() {
    _pruneTimer?.cancel();
    _pruneTimer = Timer.periodic(const Duration(minutes: 30), (_) => prune());
  }

  void dispose() {
    _pruneTimer?.cancel();
    _db?.close();
  }

  /// Record a single event into the local buffer.
  Future<void> record(EngagementEvent event) async {
    final db = await _getDb();
    await db.customStatement(
      '''INSERT OR IGNORE INTO event_buffer
         (id, session_id, event_type, timestamp, screen_name, x, y,
          duration_ms, metadata_json, synced)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)''',
      [
        event.id,
        event.sessionId,
        event.type.name,
        event.timestamp.toUtc().toIso8601String(),
        event.screenName,
        event.x,
        event.y,
        event.durationMs,
        event.metadata != null ? jsonEncode(event.metadata) : null,
      ],
    );
  }

  /// Read up to [limit] un-synced events for batch upload.
  Future<List<EngagementEvent>> readUnsynced({int limit = 200}) async {
    final db = await _getDb();
    final rows = await db.customSelect(
      'SELECT * FROM event_buffer WHERE synced = 0 ORDER BY timestamp ASC LIMIT ?',
      variables: [Variable.withInt(limit)],
    ).get();

    return rows.map((row) => EngagementEvent(
          id: row.read<String>('id'),
          sessionId: row.read<String>('session_id'),
          type: EngagementEventType.values.byName(row.read<String>('event_type')),
          timestamp: DateTime.parse(row.read<String>('timestamp')),
          screenName: row.readNullable<String>('screen_name'),
          x: row.readNullable<double>('x'),
          y: row.readNullable<double>('y'),
          durationMs: row.readNullable<int>('duration_ms'),
          metadata: row.readNullable<String>('metadata_json') != null
              ? jsonDecode(row.read<String>('metadata_json'))
                  as Map<String, dynamic>
              : null,
        )).toList();
  }

  /// Mark events as synced after successful upload.
  Future<void> markSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _getDb();
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.customStatement(
      'UPDATE event_buffer SET synced = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  /// Remove events older than 48 hours.
  Future<void> prune() async {
    final db = await _getDb();
    final cutoff =
        DateTime.now().subtract(const Duration(hours: 48)).toUtc().toIso8601String();
    await db.customStatement(
      'DELETE FROM event_buffer WHERE timestamp < ?',
      [cutoff],
    );
  }
}

/// Thin wrapper so we can use drift's customSelect / customStatement
/// without code-gen.
class _RawEventDb extends GeneratedDatabase {
  _RawEventDb(super.e);

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          // Table created manually in _getDb().
        },
      );
}
