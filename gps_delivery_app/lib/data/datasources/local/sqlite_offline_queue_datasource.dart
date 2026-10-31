import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:uuid/uuid.dart';

import '../../../core/config/env_config.dart';
import '../../../domain/entities/order_entity.dart';

class OfflineSyncRecord {
  final int id;
  final String idempotencyKey;
  final String actionType;
  final Map<String, dynamic> payload;
  final int retryCount;
  final String syncStatus;
  final int createdAtMs;
  final String? ownerScope;

  const OfflineSyncRecord({
    required this.id,
    required this.idempotencyKey,
    required this.actionType,
    required this.payload,
    required this.retryCount,
    required this.syncStatus,
    required this.createdAtMs,
    this.ownerScope,
  });

  int get nextBackoffDelayMs {
    final rawMs = math.pow(2, retryCount).toInt() * 1000;
    return math.min(rawMs, EnvConfig.maxOfflineRetryBackoffMs);
  }
}

class SqliteOfflineQueueDatasource {
  static final SqliteOfflineQueueDatasource instance =
      SqliteOfflineQueueDatasource._internal();

  factory SqliteOfflineQueueDatasource() => instance;

  SqliteOfflineQueueDatasource._internal();

  static const String _dbFileName = 'gps_delivery_production.db';
  static const int _dbVersion = 9;
  static const Uuid _uuid = Uuid();
  final String runtimeSessionId = _uuid.v4();
  String? Function()? syncScopeProvider;

  static bool _ffiInitialized = false;
  sqflite.Database? _database;
  String? _resolvedDbFilePath;
  final WebLocalStorageRelationalEngine _webEngine =
      WebLocalStorageRelationalEngine();

  String get databaseFilePath {
    if (kIsWeb) return 'localStorage://$_dbFileName';
    return _resolvedDbFilePath ?? _dbFileName;
  }

  static void ensureDesktopFfiInitialized() {
    if (kIsWeb || _ffiInitialized) {
      _ffiInitialized = true;
      return;
    }
    try {
      if (Platform.isWindows) {
        final exeDir = File(Platform.resolvedExecutable).parent;
        if (File(p.join(exeDir.path, 'sqlite3.dll')).existsSync() &&
            !File(p.join(Directory.current.path, 'pubspec.yaml'))
                .existsSync()) {
          Directory.current = exeDir;
        }
      }
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        sqflite_ffi.sqfliteFfiInit();
        sqflite.databaseFactory = sqflite_ffi.databaseFactoryFfiNoIsolate;
      }
    } catch (_) {}
    _ffiInitialized = true;
  }

  Future<sqflite.Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Web runtime uses WebLocalStorageRelationalEngine instead of FFI SQLite.',
      );
    }
    if (_database != null && _database!.isOpen) return _database!;
    ensureDesktopFfiInitialized();

    final isTestEnv = Platform.environment.containsKey('FLUTTER_TEST');
    String fullPath;
    if (isTestEnv) {
      fullPath = p.join(
        Directory.systemTemp.path,
        'gps_delivery_test_runtime_${pid}_$runtimeSessionId.db',
      );
    } else if (Platform.isAndroid || Platform.isIOS) {
      final mobileDbDir = await sqflite.getDatabasesPath();
      fullPath = p.join(mobileDbDir, _dbFileName);
    } else {
      final hasPubspecInCwd = File(
        p.join(Directory.current.path, 'pubspec.yaml'),
      ).existsSync();
      final baseDirPath = hasPubspecInCwd
          ? Directory.current.path
          : File(Platform.resolvedExecutable).parent.path;
      final localDbDir = Directory(p.join(baseDirPath, 'database'));
      String targetDir;
      try {
        if (!localDbDir.existsSync()) {
          localDbDir.createSync(recursive: true);
        }
        targetDir = localDbDir.path;
      } catch (_) {
        targetDir = Directory.systemTemp.path;
      }
      fullPath = p.join(targetDir, _dbFileName);
    }
    _resolvedDbFilePath = fullPath;

    _database = await sqflite.openDatabase(
      fullPath,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createRelationalSchema16Tables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createRelationalSchema16Tables(db);
        await _ensureSchemaColumnsMigrated(db);
      },
      onOpen: (db) async {
        await _createRelationalSchema16Tables(db);
        await _ensureSchemaColumnsMigrated(db);
      },
    );
    return _database!;
  }

  Future<void> _ensureColumnExists(
    sqflite.Database db,
    String table,
    String column,
    String definition,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any(
      (row) => row['name']?.toString().toLowerCase() == column.toLowerCase(),
    );
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<void> _ensureSchemaColumnsMigrated(sqflite.Database db) async {
    // Old queue entries remain unbound; never assign them to the next login.
    await _ensureColumnExists(db, 'local_sync_queue', 'owner_scope', 'TEXT');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS local_sync_queue_owner_pending '
      'ON local_sync_queue(owner_scope, sync_status, created_at_ms)',
    );
    await _ensureColumnExists(
      db,
      'drivers',
      'rejected_count',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(
      db,
      'drivers',
      'bank_name',
      "TEXT NOT NULL DEFAULT 'Vietcombank'",
    );
    await _ensureColumnExists(
      db,
      'drivers',
      'bank_account',
      "TEXT NOT NULL DEFAULT '007100****889'",
    );
    await _ensureColumnExists(db, 'drivers', 'attached_kyc_docs_json', 'TEXT');
    await _ensureColumnExists(
      db,
      'drivers',
      'is_electric_vehicle',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(
      db,
      'drivers',
      'battery_percent',
      'INTEGER NOT NULL DEFAULT 95',
    );

    await _ensureColumnExists(
      db,
      'merchants',
      'webhook_url',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumnExists(
      db,
      'merchants',
      'attached_kyc_docs_json',
      'TEXT',
    );

    await _ensureColumnExists(
      db,
      'merchant_pickup_points',
      'contact_phone',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumnExists(
      db,
      'merchant_pickup_points',
      'open_hours',
      "TEXT NOT NULL DEFAULT '08:00 - 21:00'",
    );
    await _ensureColumnExists(
      db,
      'merchant_pickup_points',
      'is_primary',
      'INTEGER',
    );
    await _ensureColumnExists(
      db,
      'merchant_pickup_points',
      'webhook_url',
      "TEXT NOT NULL DEFAULT ''",
    );

    await _ensureColumnExists(db, 'vouchers', 'usage_limit', 'INTEGER');
    await _ensureColumnExists(db, 'vouchers', 'used_count', 'INTEGER');

    await _ensureColumnExists(db, 'orders', 'delivered_at_ms', 'INTEGER');
    await _ensureColumnExists(
      db,
      'orders',
      'prefer_eco_ev',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(
      db,
      'orders',
      'declared_value_vnd',
      'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(
      db,
      'orders',
      'insurance_fee',
      'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(
      db,
      'orders',
      'is_round_trip',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(
      db,
      'orders',
      'extra_stop_count',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(db, 'orders', 'batch_group_id', 'TEXT');
    await _ensureColumnExists(
      db,
      'orders',
      'co2_saved_grams',
      'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(
      db,
      'orders',
      'green_fund_contributed',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(db, 'orders', 'public_tracking_token', 'TEXT');

    await _ensureColumnExists(db, 'order_stops', 'otp_code', 'TEXT');
    await _ensureColumnExists(db, 'order_stops', 'pod_note', 'TEXT');
    await _ensureColumnExists(db, 'order_stops', 'completed_at_ms', 'INTEGER');

    await _ensureColumnExists(
      db,
      'wallets_and_transactions',
      'owner_id',
      "TEXT NOT NULL DEFAULT ''",
    );

    await _ensureColumnExists(
      db,
      'cod_reconciliations',
      'return_cancel_fee',
      'REAL',
    );

    await _ensureColumnExists(
      db,
      'incidents_and_complaints',
      'evidence_files_json',
      'TEXT',
    );

    await _ensureColumnExists(
      db,
      'chat_messages_and_notifications',
      'recipient_key',
      'TEXT',
    );
  }

  Future<void> _createRelationalSchema16Tables(sqflite.Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS admin_roles_permissions (
        id TEXT PRIMARY KEY,
        role_name TEXT UNIQUE NOT NULL,
        permissions_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        phone TEXT UNIQUE NOT NULL,
        email TEXT,
        password_hash TEXT NOT NULL,
        full_name TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'CUSTOMER',
        default_address TEXT,
        default_lat REAL NOT NULL DEFAULT 10.7769,
        default_lng REAL NOT NULL DEFAULT 106.6953,
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_addresses (
        id TEXT PRIMARY KEY,
        user_phone TEXT NOT NULL,
        label TEXT NOT NULL,
        full_address TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS drivers (
        id TEXT PRIMARY KEY,
        phone TEXT UNIQUE NOT NULL,
        full_name TEXT NOT NULL,
        citizen_id TEXT NOT NULL,
        license_plate TEXT NOT NULL,
        vehicle_type TEXT NOT NULL,
        vehicle_color TEXT NOT NULL,
        approval_status TEXT NOT NULL,
        is_online INTEGER NOT NULL DEFAULT 1,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        rating REAL NOT NULL DEFAULT 5.0,
        total_trips INTEGER NOT NULL DEFAULT 0,
        rejected_count INTEGER NOT NULL DEFAULT 0,
        wallet_balance REAL NOT NULL DEFAULT 0.0,
        bank_name TEXT NOT NULL DEFAULT 'Vietcombank',
        bank_account TEXT NOT NULL DEFAULT '007100****889',
        is_electric_vehicle INTEGER NOT NULL DEFAULT 0,
        battery_percent INTEGER NOT NULL DEFAULT 95,
        attached_kyc_docs_json TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS merchants (
        id TEXT PRIMARY KEY,
        owner_phone TEXT NOT NULL,
        store_name TEXT NOT NULL,
        business_type TEXT NOT NULL,
        tax_code TEXT NOT NULL,
        representative_name TEXT NOT NULL,
        open_hours TEXT NOT NULL,
        bank_name TEXT NOT NULL,
        bank_account TEXT NOT NULL,
        cod_balance REAL NOT NULL DEFAULT 0.0,
        approval_status TEXT NOT NULL DEFAULT 'APPROVED',
        webhook_url TEXT NOT NULL DEFAULT '',
        attached_kyc_docs_json TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS merchant_pickup_points (
        id TEXT PRIMARY KEY,
        merchant_id TEXT NOT NULL,
        warehouse_name TEXT NOT NULL,
        full_address TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        contact_phone TEXT NOT NULL DEFAULT '',
        open_hours TEXT NOT NULL DEFAULT '08:00 - 21:00',
        is_primary INTEGER,
        webhook_url TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pricing_configs (
        id TEXT PRIMARY KEY,
        service_type TEXT UNIQUE NOT NULL,
        base_fare REAL NOT NULL,
        price_per_km REAL NOT NULL,
        peak_hour_surcharge REAL NOT NULL,
        bad_weather_surcharge REAL NOT NULL,
        is_peak_enabled INTEGER NOT NULL DEFAULT 1,
        is_weather_enabled INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS vouchers (
        code TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        discount_label TEXT NOT NULL,
        discount_value REAL NOT NULL,
        is_percentage INTEGER NOT NULL,
        max_discount REAL NOT NULL,
        min_order_value REAL NOT NULL,
        expiry_date TEXT NOT NULL,
        status TEXT NOT NULL,
        usage_limit INTEGER,
        used_count INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS orders (
        id TEXT PRIMARY KEY,
        tracking_code TEXT UNIQUE NOT NULL,
        customer_name TEXT NOT NULL,
        recipient_name TEXT NOT NULL,
        recipient_phone TEXT NOT NULL,
        pickup_address TEXT NOT NULL,
        dropoff_address TEXT NOT NULL,
        pickup_lat REAL NOT NULL,
        pickup_lng REAL NOT NULL,
        dropoff_lat REAL NOT NULL,
        dropoff_lng REAL NOT NULL,
        service_type TEXT NOT NULL,
        package_description TEXT NOT NULL,
        weight_kg REAL NOT NULL,
        dimensions_cm TEXT NOT NULL,
        distance_meters INTEGER NOT NULL,
        duration_seconds INTEGER NOT NULL,
        delivery_fee REAL NOT NULL,
        surcharge_fee REAL NOT NULL,
        discount_amount REAL NOT NULL,
        cod_amount REAL NOT NULL,
        total_amount REAL NOT NULL,
        payment_method TEXT NOT NULL,
        payment_status TEXT NOT NULL,
        status TEXT NOT NULL,
        assigned_driver_name TEXT,
        assigned_driver_plate TEXT,
        pod_image_note TEXT,
        cancel_reason TEXT,
        rating_stars INTEGER,
        rating_comment TEXT,
        created_date_label TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        delivered_at_ms INTEGER,
        prefer_eco_ev INTEGER NOT NULL DEFAULT 0,
        declared_value_vnd REAL NOT NULL DEFAULT 0,
        insurance_fee REAL NOT NULL DEFAULT 0,
        is_round_trip INTEGER NOT NULL DEFAULT 0,
        extra_stop_count INTEGER NOT NULL DEFAULT 0,
        batch_group_id TEXT,
        co2_saved_grams REAL NOT NULL DEFAULT 0,
        green_fund_contributed INTEGER NOT NULL DEFAULT 0,
        public_tracking_token TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_tracking_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id TEXT NOT NULL,
        driver_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        speed REAL NOT NULL,
        bearing REAL NOT NULL,
        is_mock_location INTEGER NOT NULL DEFAULT 0,
        recorded_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS geofence_zones (
        id TEXT PRIMARY KEY,
        zone_name TEXT NOT NULL,
        zone_type TEXT NOT NULL,
        surcharge_rate REAL NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        boundary_json TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS wallets_and_transactions (
        id TEXT PRIMARY KEY,
        owner_id TEXT NOT NULL DEFAULT '',
        owner_name TEXT NOT NULL,
        owner_role TEXT NOT NULL,
        amount REAL NOT NULL,
        bank_name TEXT NOT NULL,
        account_masked TEXT NOT NULL,
        request_date TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cod_reconciliations (
        id TEXT PRIMARY KEY,
        merchant_id TEXT NOT NULL,
        period_label TEXT NOT NULL,
        total_cod_collected REAL NOT NULL,
        total_service_fee REAL NOT NULL,
        return_cancel_fee REAL,
        net_payout_amount REAL NOT NULL,
        status TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_ratings (
        id TEXT PRIMARY KEY,
        order_tracking_code TEXT UNIQUE NOT NULL,
        customer_name TEXT NOT NULL,
        driver_name TEXT NOT NULL,
        stars INTEGER NOT NULL,
        comment TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS incidents_and_complaints (
        ticket_code TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        customer_name TEXT NOT NULL,
        driver_name TEXT NOT NULL,
        issue_type TEXT NOT NULL,
        description TEXT NOT NULL,
        status TEXT NOT NULL,
        replies_json TEXT NOT NULL,
        evidence_files_json TEXT,
        created_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages_and_notifications (
        id TEXT PRIMARY KEY,
        record_type TEXT NOT NULL,
        order_id TEXT,
        recipient_key TEXT,
        sender_name TEXT,
        is_customer INTEGER NOT NULL DEFAULT 1,
        category TEXT,
        title TEXT,
        content TEXT NOT NULL,
        target_group TEXT NOT NULL DEFAULT 'Khách hàng',
        time_label TEXT NOT NULL,
        is_read INTEGER NOT NULL DEFAULT 0,
        created_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        idempotency_key TEXT UNIQUE NOT NULL,
        action_type TEXT NOT NULL,
        owner_scope TEXT,
        payload_json TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        sync_status TEXT NOT NULL DEFAULT 'PENDING',
        created_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cached_active_orders (
        id TEXT PRIMARY KEY,
        tracking_code TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_relational_entities (
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        PRIMARY KEY (table_name, record_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_stops (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        sequence_no INTEGER NOT NULL,
        stop_type TEXT NOT NULL,
        address TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        recipient_name TEXT,
        recipient_phone TEXT,
        cod_amount REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'PENDING',
        note TEXT,
        otp_code TEXT,
        pod_note TEXT,
        completed_at_ms INTEGER,
        created_at_ms INTEGER NOT NULL,
        UNIQUE(order_id, sequence_no)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS scheduled_orders (
        id TEXT PRIMARY KEY,
        order_id TEXT UNIQUE NOT NULL,
        scheduled_at_ms INTEGER NOT NULL,
        timezone TEXT NOT NULL DEFAULT 'Asia/Ho_Chi_Minh',
        status TEXT NOT NULL DEFAULT 'PENDING',
        last_error TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_ledger (
        id TEXT PRIMARY KEY,
        owner_id TEXT,
        owner_type TEXT NOT NULL,
        order_id TEXT,
        direction TEXT NOT NULL,
        entry_type TEXT NOT NULL,
        amount REAL NOT NULL,
        currency TEXT NOT NULL DEFAULT 'VND',
        idempotency_key TEXT UNIQUE NOT NULL,
        metadata_json TEXT,
        created_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS webhook_deliveries (
        id TEXT PRIMARY KEY,
        endpoint_url TEXT NOT NULL,
        event_type TEXT NOT NULL,
        aggregate_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        signature TEXT,
        status TEXT NOT NULL DEFAULT 'PENDING',
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at_ms INTEGER,
        last_http_status INTEGER,
        last_error TEXT,
        created_at_ms INTEGER NOT NULL,
        delivered_at_ms INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_logs (
        id TEXT PRIMARY KEY,
        actor_id TEXT,
        actor_role TEXT,
        action TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT,
        before_json TEXT,
        after_json TEXT,
        ip_address TEXT,
        device_id TEXT,
        created_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS merchant_menu_items (
        id TEXT PRIMARY KEY,
        merchant_id TEXT NOT NULL,
        store_name TEXT NOT NULL,
        store_address TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT 'Cơm • Bún • Phở',
        price_vnd REAL NOT NULL,
        prep_minutes INTEGER NOT NULL DEFAULT 15,
        meal_slots_json TEXT NOT NULL DEFAULT '[]',
        is_eco_packaging INTEGER NOT NULL DEFAULT 0,
        is_cold_item INTEGER NOT NULL DEFAULT 0,
        has_promo_badge INTEGER NOT NULL DEFAULT 0,
        is_available INTEGER NOT NULL DEFAULT 1,
        rating REAL NOT NULL DEFAULT 4.8,
        sold_count INTEGER NOT NULL DEFAULT 0,
        created_at_ms INTEGER NOT NULL
      )
    ''');
  }

  Future<List<Map<String, dynamic>>> queryRows(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    if (kIsWeb) {
      return _webEngine.queryRows(
        table,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
      );
    }
    final db = await database;
    return db.query(
      table,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );
  }

  Future<void> upsertRow(String table, Map<String, Object?> values) async {
    if (kIsWeb) {
      await _webEngine.upsertRow(table, values);
      return;
    }
    final db = await database;
    await db.insert(
      table,
      values,
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  Future<int> updateRows(
    String table,
    Map<String, Object?> values, {
    required String where,
    required List<Object?> whereArgs,
  }) async {
    if (kIsWeb) {
      return _webEngine.updateRows(
        table,
        values,
        where: where,
        whereArgs: whereArgs,
      );
    }
    final db = await database;
    return db.update(table, values, where: where, whereArgs: whereArgs);
  }

  Future<int> deleteRows(
    String table, {
    required String where,
    required List<Object?> whereArgs,
  }) async {
    if (kIsWeb) {
      return _webEngine.deleteRows(table, where: where, whereArgs: whereArgs);
    }
    final db = await database;
    return db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<int> countRows(String table) async {
    if (kIsWeb) {
      return _webEngine.countRows(table);
    }
    final db = await database;
    final res = await db.rawQuery('SELECT COUNT(*) AS cnt FROM $table');
    return sqflite.Sqflite.firstIntValue(res) ?? 0;
  }

  Future<void> upsertEntityRecord({
    required String tableName,
    required String recordId,
    required Map<String, dynamic> payload,
  }) async {
    await upsertRow('local_relational_entities', {
      'table_name': tableName,
      'record_id': recordId,
      'payload_json': jsonEncode(payload),
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> getEntityRecords(String tableName) async {
    final rows = await queryRows(
      'local_relational_entities',
      where: 'table_name = ?',
      whereArgs: [tableName],
      orderBy: 'updated_at_ms DESC',
    );
    return rows
        .map(
          (r) =>
              jsonDecode(r['payload_json'] as String) as Map<String, dynamic>,
        )
        .toList();
  }

  Future<String> enqueueAction({
    required String actionType,
    required Map<String, dynamic> payload,
  }) async {
    final idempotencyKey = _uuid.v4();
    final ownerScope = syncScopeProvider?.call();
    await upsertRow('local_sync_queue', {
      'idempotency_key': idempotencyKey,
      'owner_scope': ownerScope,
      'action_type': actionType,
      'payload_json': jsonEncode(payload),
      'retry_count': 0,
      'sync_status': 'PENDING',
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
    return idempotencyKey;
  }

  Future<List<OfflineSyncRecord>> getPendingSyncItems({
    int limit = 50,
    String? ownerScope,
  }) async {
    final rows = await queryRows(
      'local_sync_queue',
      where: ownerScope == null
          ? 'sync_status = ?'
          : 'sync_status = ? AND owner_scope = ?',
      whereArgs: ['PENDING', ?ownerScope],
      orderBy: 'created_at_ms ASC',
      limit: limit,
    );

    return rows.map((row) {
      return OfflineSyncRecord(
        id: (row['id'] as num).toInt(),
        idempotencyKey: row['idempotency_key'] as String,
        actionType: row['action_type'] as String,
        payload:
            jsonDecode(row['payload_json'] as String) as Map<String, dynamic>,
        retryCount: (row['retry_count'] as num).toInt(),
        syncStatus: row['sync_status'] as String,
        createdAtMs: (row['created_at_ms'] as num).toInt(),
        ownerScope: row['owner_scope'] as String?,
      );
    }).toList();
  }

  Future<int> getPendingQueueCount() async {
    // Failed retries still need attention and must not look like a success.
    if (kIsWeb) {
      final rows = await queryRows(
        'local_sync_queue',
        where: 'sync_status != ?',
        whereArgs: ['SYNCED'],
      );
      return rows.length;
    }
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM local_sync_queue WHERE sync_status != 'SYNCED'",
    );
    return sqflite.Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> markSynced(int id) async {
    await deleteRows('local_sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> clearStaleSnapshotEntries() async {
    return deleteRows(
      'local_sync_queue',
      where: 'action_type = ?',
      whereArgs: ['STATE_SNAPSHOT'],
    );
  }

  Future<int> clearAllPendingSyncItems() async {
    return deleteRows(
      'local_sync_queue',
      where: 'sync_status = ?',
      whereArgs: ['PENDING'],
    );
  }

  Future<void> incrementRetry(int id, int currentRetry) async {
    final nextRetry = currentRetry + 1;
    final nextStatus = nextRetry >= 10 ? 'FAILED' : 'PENDING';
    await updateRows(
      'local_sync_queue',
      {'retry_count': nextRetry, 'sync_status': nextStatus},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> cacheOrder(OrderEntity order) async {
    await upsertRow('cached_active_orders', {
      'id': order.id,
      'tracking_code': order.trackingCode,
      'customer_id': order.customerId,
      'payload_json': jsonEncode(order.toMap()),
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<OrderEntity>> getCachedOrders([String? customerId]) async {
    final rows = await queryRows(
      'cached_active_orders',
      where: customerId != null ? 'customer_id = ?' : null,
      whereArgs: customerId != null ? [customerId] : null,
      orderBy: 'updated_at_ms DESC',
    );
    return rows.map((r) {
      final map =
          jsonDecode(r['payload_json'] as String) as Map<String, dynamic>;
      return OrderEntity.fromMap(map);
    }).toList();
  }
}

class WebLocalStorageRelationalEngine {
  static const String _keyPrefix = 'ghst_sql_v5_';
  SharedPreferences? _prefs;
  final Map<String, List<Map<String, dynamic>>> _tablesCache = {};
  final Map<String, int> _autoIncrementByTable = {};

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<List<Map<String, dynamic>>> _loadTable(String table) async {
    final cached = _tablesCache[table];
    if (cached != null) return cached;
    final prefs = await _ensurePrefs();
    final raw = prefs.getString('$_keyPrefix$table');
    final rows = <Map<String, dynamic>>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final map = Map<String, dynamic>.from(item);
              rows.add(map);
              final rowId = map['id'];
              final cur = _autoIncrementByTable[table] ?? 1;
              if (rowId is num && rowId.toInt() >= cur) {
                _autoIncrementByTable[table] = rowId.toInt() + 1;
              }
            }
          }
        }
      } catch (_) {}
    }
    _tablesCache[table] = rows;
    return rows;
  }

  Future<void> _persistTable(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    final prefs = await _ensurePrefs();
    await prefs.setString('$_keyPrefix$table', jsonEncode(rows));
  }

  bool _matchesWhere(
    Map<String, dynamic> row,
    String? where,
    List<Object?>? whereArgs,
  ) {
    if (where == null || where.trim().isEmpty) return true;
    final clauses = where.split(RegExp(r'\s+AND\s+', caseSensitive: false));
    int argIdx = 0;
    for (final rawClause in clauses) {
      final clause = rawClause.trim();
      if (clause.isEmpty) continue;
      final upper = clause.toUpperCase();
      if (upper.endsWith(' IS NOT NULL')) {
        final col = clause.substring(0, clause.length - 12).trim();
        if (row[col] == null) return false;
        continue;
      }
      if (upper.endsWith(' IS NULL')) {
        final col = clause.substring(0, clause.length - 8).trim();
        if (row[col] != null) return false;
        continue;
      }
      final opMatch = RegExp(r'^([a-zA-Z0-9_]+)\s*(!=|<>|<=|>=|=|<|>)\s*(.+)$')
          .firstMatch(clause);
      if (opMatch == null) return false;
      final col = opMatch.group(1)!;
      final op = opMatch.group(2)!;
      final rhs = opMatch.group(3)!.trim();
      Object? expected;
      if (rhs == '?') {
        if (whereArgs == null || argIdx >= whereArgs.length) return false;
        expected = whereArgs[argIdx++];
      } else {
        expected = rhs.replaceAll("'", '');
      }
      final actual = row[col];
      final strEq =
          actual == expected || '${actual ?? ''}' == '${expected ?? ''}';
      if (op == '=') {
        if (!strEq) return false;
      } else if (op == '!=' || op == '<>') {
        if (strEq) return false;
      } else {
        final numActual = actual is num
            ? actual.toDouble()
            : double.tryParse('${actual ?? ''}');
        final numExpected = expected is num
            ? expected.toDouble()
            : double.tryParse('${expected ?? ''}');
        final cmp = (numActual != null && numExpected != null)
            ? numActual.compareTo(numExpected)
            : '${actual ?? ''}'.compareTo('${expected ?? ''}');
        if (op == '<' && cmp >= 0) return false;
        if (op == '<=' && cmp > 0) return false;
        if (op == '>' && cmp <= 0) return false;
        if (op == '>=' && cmp < 0) return false;
      }
    }
    return true;
  }

  bool _isSamePrimaryOrUniqueKey(
    String table,
    Map<String, dynamic> existing,
    Map<String, dynamic> incoming,
  ) {
    if (table == 'local_relational_entities') {
      return existing['table_name'] == incoming['table_name'] &&
          existing['record_id'] == incoming['record_id'];
    }
    if (table == 'vouchers') {
      return existing['code'] == incoming['code'];
    }
    if (table == 'incidents_and_complaints') {
      return existing['ticket_code'] == incoming['ticket_code'];
    }
    if (incoming['id'] != null && existing['id'] == incoming['id']) {
      return true;
    }
    if (table == 'admin_roles_permissions' &&
        incoming['role_name'] != null &&
        existing['role_name'] == incoming['role_name']) {
      return true;
    }
    if ((table == 'users' || table == 'drivers') &&
        incoming['phone'] != null &&
        existing['phone'] == incoming['phone']) {
      return true;
    }
    if (table == 'orders' &&
        incoming['tracking_code'] != null &&
        existing['tracking_code'] == incoming['tracking_code']) {
      return true;
    }
    if (table == 'pricing_configs' &&
        incoming['service_type'] != null &&
        existing['service_type'] == incoming['service_type']) {
      return true;
    }
    if (table == 'order_ratings' &&
        incoming['order_tracking_code'] != null &&
        existing['order_tracking_code'] == incoming['order_tracking_code']) {
      return true;
    }
    if (table == 'local_sync_queue' &&
        incoming['idempotency_key'] != null &&
        existing['idempotency_key'] == incoming['idempotency_key']) {
      return true;
    }
    return false;
  }

  Future<List<Map<String, dynamic>>> queryRows(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    final rows = await _loadTable(table);
    var matched = rows
        .where((r) => _matchesWhere(r, where, whereArgs))
        .map(Map<String, dynamic>.from)
        .toList();
    if (orderBy != null && orderBy.trim().isNotEmpty) {
      final parts = orderBy.trim().split(RegExp(r'\s+'));
      final col = parts.first;
      final desc = parts.length > 1 && parts[1].toUpperCase() == 'DESC';
      matched.sort((a, b) {
        final va = a[col];
        final vb = b[col];
        int cmp;
        if (va is num && vb is num) {
          cmp = va.compareTo(vb);
        } else {
          cmp = '${va ?? ''}'.compareTo('${vb ?? ''}');
        }
        return desc ? -cmp : cmp;
      });
    }
    if (limit != null && limit >= 0 && matched.length > limit) {
      matched = matched.sublist(0, limit);
    }
    return matched;
  }

  Future<void> upsertRow(String table, Map<String, Object?> values) async {
    final rows = await _loadTable(table);
    final normalized = Map<String, dynamic>.from(values);
    final existingIdx = rows.indexWhere(
      (r) => _isSamePrimaryOrUniqueKey(table, r, normalized),
    );
    if (existingIdx >= 0) {
      if ((table == 'order_tracking_logs' || table == 'local_sync_queue') &&
          normalized['id'] == null) {
        normalized['id'] = rows[existingIdx]['id'];
      }
      rows[existingIdx] = normalized;
    } else {
      if ((table == 'order_tracking_logs' || table == 'local_sync_queue') &&
          normalized['id'] == null) {
        final nextId = _autoIncrementByTable[table] ?? 1;
        normalized['id'] = nextId;
        _autoIncrementByTable[table] = nextId + 1;
      }
      rows.add(normalized);
      if (table == 'order_tracking_logs' && rows.length > 200) {
        rows.removeRange(0, rows.length - 200);
      }
    }
    await _persistTable(table, rows);
  }

  Future<int> updateRows(
    String table,
    Map<String, Object?> values, {
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final rows = await _loadTable(table);
    int updated = 0;
    for (final row in rows) {
      if (_matchesWhere(row, where, whereArgs)) {
        values.forEach((k, v) {
          row[k] = v;
        });
        updated++;
      }
    }
    if (updated > 0) {
      await _persistTable(table, rows);
    }
    return updated;
  }

  Future<int> deleteRows(
    String table, {
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final rows = await _loadTable(table);
    final before = rows.length;
    rows.removeWhere((row) => _matchesWhere(row, where, whereArgs));
    final removed = before - rows.length;
    if (removed > 0) {
      await _persistTable(table, rows);
    }
    return removed;
  }

  Future<int> countRows(String table) async {
    final rows = await _loadTable(table);
    return rows.length;
  }
}
