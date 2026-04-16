import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/alert_event.dart';
import '../models/app_settings.dart';
import '../models/monitor_log.dart';
import '../models/monitored_query.dart';

class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();
  static const _dbVersion = 7;

  Database? _db;

  Future<Database> get db async {
    if (_db != null) {
      return _db!;
    }
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = kIsWeb
        ? 'redmine_monitor.db'
        : join(await getDatabasesPath(), 'redmine_monitor.db');
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (database, version) async {
        await _createBaseTables(database);
        await _createMonitorLogsTable(database);

        await database.insert('settings', {
          'key': 'base_url',
          'value': '',
        });
        await database.insert('settings', {
          'key': 'api_key',
          'value': '',
        });
        await database.insert('settings', {
          'key': 'default_poll_seconds',
          'value': '180',
        });
        await database.insert('settings', {
          'key': 'alert_cooldown_seconds',
          'value': '600',
        });
        await database.insert('settings', {
          'key': 'notification_title_template',
          'value': defaultNotificationTitleTemplate,
        });
        await database.insert('settings', {
          'key': 'notification_body_template',
          'value': defaultNotificationBodyTemplate,
        });
        await database.insert('settings', {
          'key': 'theme_mode',
          'value': defaultThemeMode,
        });
        await database.insert('settings', {'key': 'notification_increase_title_template', 'value': ''});
        await database.insert('settings', {'key': 'notification_increase_body_template', 'value': ''});
        await database.insert('settings', {'key': 'notification_decrease_title_template', 'value': ''});
        await database.insert('settings', {'key': 'notification_decrease_body_template', 'value': ''});
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createMonitorLogsTable(database);
        }
        if (oldVersion < 3) {
          await database.insert(
            'settings',
            {
              'key': 'notification_title_template',
              'value': defaultNotificationTitleTemplate,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          await database.insert(
            'settings',
            {
              'key': 'notification_body_template',
              'value': defaultNotificationBodyTemplate,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        if (oldVersion < 4) {
          await database.insert(
            'settings',
            {
              'key': 'alert_cooldown_seconds',
              'value': '600',
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        if (oldVersion < 5) {
          await database.insert(
            'settings',
            {
              'key': 'theme_mode',
              'value': defaultThemeMode,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        if (oldVersion < 6) {
          await database.execute(
            "ALTER TABLE queries ADD COLUMN alert_on TEXT NOT NULL DEFAULT 'any'",
          );
        }
        if (oldVersion < 7) {
          await database.execute(
            'ALTER TABLE alerts ADD COLUMN is_read INTEGER NOT NULL DEFAULT 0',
          );
          await database.execute(
            'ALTER TABLE queries ADD COLUMN notification_title_template TEXT',
          );
          await database.execute(
            'ALTER TABLE queries ADD COLUMN notification_body_template TEXT',
          );
          for (final key in [
            'notification_increase_title_template',
            'notification_increase_body_template',
            'notification_decrease_title_template',
            'notification_decrease_body_template',
          ]) {
            await database.insert(
              'settings',
              {'key': key, 'value': ''},
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }
      },
    );
  }

  Future<void> _createBaseTables(Database database) async {
    await database.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE queries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        endpoint TEXT NOT NULL,
        direct_url TEXT NOT NULL,
        count_path TEXT NOT NULL DEFAULT 'total_count',
        poll_seconds INTEGER,
        enabled INTEGER NOT NULL DEFAULT 1,
        alert_on TEXT NOT NULL DEFAULT 'any',
        last_count INTEGER,
        last_checked_at TEXT
      )
    ''');

    await database.execute('''
      CREATE TABLE alerts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        query_id INTEGER NOT NULL,
        query_name TEXT NOT NULL,
        previous_count INTEGER NOT NULL,
        current_count INTEGER NOT NULL,
        direct_url TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createMonitorLogsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS monitor_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        level TEXT NOT NULL,
        message TEXT NOT NULL,
        query_name TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<AppSettings> loadSettings() async {
    final database = await db;
    final rows = await database.query('settings');
    final map = <String, String>{
      for (final row in rows)
        row['key'] as String: row['value'] as String,
    };

    return AppSettings(
      baseUrl: map['base_url'] ?? '',
      apiKey: map['api_key'] ?? '',
      defaultPollSeconds: int.tryParse(map['default_poll_seconds'] ?? '') ?? 180,
      alertCooldownSeconds: int.tryParse(map['alert_cooldown_seconds'] ?? '') ?? 600,
      notificationTitleTemplate:
          map['notification_title_template'] ?? defaultNotificationTitleTemplate,
      notificationBodyTemplate:
          map['notification_body_template'] ?? defaultNotificationBodyTemplate,
      themeMode: map['theme_mode'] ?? defaultThemeMode,
      notificationIncreaseTitleTemplate:
          map['notification_increase_title_template']?.isEmpty == true
              ? null
              : map['notification_increase_title_template'],
      notificationIncreaseBodyTemplate:
          map['notification_increase_body_template']?.isEmpty == true
              ? null
              : map['notification_increase_body_template'],
      notificationDecreaseTitleTemplate:
          map['notification_decrease_title_template']?.isEmpty == true
              ? null
              : map['notification_decrease_title_template'],
      notificationDecreaseBodyTemplate:
          map['notification_decrease_body_template']?.isEmpty == true
              ? null
              : map['notification_decrease_body_template'],
    );
  }

  Future<void> saveSettings(AppSettings settings) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.insert(
        'settings',
        {'key': 'base_url', 'value': settings.baseUrl},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'settings',
        {'key': 'api_key', 'value': settings.apiKey},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'settings',
        {'key': 'default_poll_seconds', 'value': '${settings.defaultPollSeconds}'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'settings',
        {
          'key': 'alert_cooldown_seconds',
          'value': '${settings.alertCooldownSeconds}',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'settings',
        {
          'key': 'notification_title_template',
          'value': settings.notificationTitleTemplate,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'settings',
        {
          'key': 'notification_body_template',
          'value': settings.notificationBodyTemplate,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'settings',
        {
          'key': 'theme_mode',
          'value': settings.themeMode,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'settings',
        {
          'key': 'notification_increase_title_template',
          'value': settings.notificationIncreaseTitleTemplate ?? '',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'settings',
        {
          'key': 'notification_increase_body_template',
          'value': settings.notificationIncreaseBodyTemplate ?? '',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'settings',
        {
          'key': 'notification_decrease_title_template',
          'value': settings.notificationDecreaseTitleTemplate ?? '',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'settings',
        {
          'key': 'notification_decrease_body_template',
          'value': settings.notificationDecreaseBodyTemplate ?? '',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<List<MonitoredQuery>> listQueries() async {
    final database = await db;
    final rows = await database.query('queries', orderBy: 'name ASC');
    return rows.map(MonitoredQuery.fromDbMap).toList();
  }

  Future<int> insertQuery(MonitoredQuery query) async {
    final database = await db;
    return database.insert('queries', query.toDbMap());
  }

  Future<void> updateQuery(MonitoredQuery query) async {
    final database = await db;
    await database.update(
      'queries',
      query.toDbMap(),
      where: 'id = ?',
      whereArgs: [query.id],
    );
  }

  Future<void> deleteQuery(int id) async {
    final database = await db;
    await database.delete('queries', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearQueries() async {
    final database = await db;
    await database.delete('queries');
  }

  Future<void> updateQueryLastCheck({
    required int queryId,
    required int lastCount,
    required DateTime checkedAt,
  }) async {
    final database = await db;
    await database.update(
      'queries',
      {
        'last_count': lastCount,
        'last_checked_at': checkedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [queryId],
    );
  }

  Future<List<AlertEvent>> listAlerts({int limit = 100}) async {
    final database = await db;
    final rows = await database.query(
      'alerts',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(AlertEvent.fromDbMap).toList();
  }

  Future<AlertEvent> addAlert(AlertEvent alert) async {
    final database = await db;
    final id = await database.insert('alerts', alert.toDbMap());
    return AlertEvent(
      id: id,
      queryId: alert.queryId,
      queryName: alert.queryName,
      previousCount: alert.previousCount,
      currentCount: alert.currentCount,
      directUrl: alert.directUrl,
      createdAt: alert.createdAt,
      isRead: alert.isRead,
    );
  }

  Future<void> markAlertRead(int id) async {
    final database = await db;
    await database.update(
      'alerts',
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAlert(int id) async {
    final database = await db;
    await database.delete('alerts', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAlerts() async {
    final database = await db;
    await database.delete('alerts');
  }

  Future<List<MonitorLog>> listMonitorLogs({int limit = 200}) async {
    final database = await db;
    final rows = await database.query(
      'monitor_logs',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(MonitorLog.fromDbMap).toList();
  }

  Future<void> addMonitorLog({
    required String level,
    required String message,
    String? queryName,
  }) async {
    final database = await db;
    await database.insert('monitor_logs', {
      'level': level,
      'message': message,
      'query_name': queryName,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> clearMonitorLogs() async {
    final database = await db;
    await database.delete('monitor_logs');
  }

  /// Removes logs older than [maxAge] and trims to the most recent [maxCount].
  Future<void> pruneMonitorLogs({
    Duration maxAge = const Duration(hours: 2),
    int maxCount = 500,
  }) async {
    final database = await db;
    final cutoff = DateTime.now().subtract(maxAge).toIso8601String();

    await database.delete(
      'monitor_logs',
      where: 'created_at < ?',
      whereArgs: [cutoff],
    );

    await database.rawDelete('''
      DELETE FROM monitor_logs
      WHERE id NOT IN (
        SELECT id FROM monitor_logs
        ORDER BY created_at DESC
        LIMIT ?
      )
    ''', [maxCount]);
  }
}
