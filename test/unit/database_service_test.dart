// White-box unit tests: DatabaseService
// Source: lib/data/database_service.dart
//
// The sqflite plugin channel is replaced by FakeSqflite (test_harness.dart),
// which also records every call, so the tests assert on the exact SQL and
// arguments the service sends and on how it normalises returned rows.
//
// Branches covered: _mapRow (String / non-String / corrupt JSON), insertScan
// (every `??` default, List vs String vs null detections, int -> double
// casts), getAllScans / getRecentScans ordering and limit, countAll,
// countToday (zero-padded date argument), deleteScan, deleteAllScans.
//
//   UT-DB-01..11
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:system_application/data/database_service.dart';

import '../helpers/test_harness.dart';

void main() {
  configureWidgetTestEnvironment();
  final db = FakeSqflite();

  setUp(() {
    db.rows.clear();
    db.calls.clear();
    db.sqlLog.clear();
    db.install();
  });
  tearDown(db.uninstall);

  /// Column -> value map of the last INSERT sent to the plugin.
  Map<String, Object?> lastInsert() {
    final call = db.calls.lastWhere((c) => c.method == 'insert');
    final args = Map<String, Object?>.from(call.arguments as Map);
    final sql = args['sql'] as String;
    final cols = RegExp(r'\(([^)]*)\)\s*VALUES')
        .firstMatch(sql)!
        .group(1)!
        .split(',')
        .map((c) => c.trim().replaceAll(RegExp(r'["`\[\]]'), ''))
        .toList();
    final values = (args['arguments'] as List).toList();
    expect(values.length, cols.length);
    return {for (var i = 0; i < cols.length; i++) cols[i]: values[i]};
  }

  group('read paths (_mapRow)', () {
    test('UT-DB-01 detections JSON string is decoded to a List', () async {
      db.rows.add(fakeScanRow(id: 1));
      final rows = await DatabaseService.getAllScans();
      expect(rows.length, 1);
      expect(rows.first['detections'], isA<List>());
      expect((rows.first['detections'] as List).length, 1);
      expect(rows.first['label'], 'Healthy');
    });

    test('UT-DB-02 boxAreaPx is copied from box_area_px', () async {
      db.rows.add(fakeScanRow(id: 1));
      final rows = await DatabaseService.getAllScans();
      expect(rows.first['boxAreaPx'], 1000.0);
    });

    test('UT-DB-03 corrupt detections JSON becomes an empty list', () async {
      final row = fakeScanRow(id: 1);
      row['detections'] = '{not valid json';
      db.rows.add(row);
      final rows = await DatabaseService.getAllScans();
      expect(rows.first['detections'], isEmpty);
    });

    test('UT-DB-04 non-String detections are left untouched', () async {
      final row = fakeScanRow(id: 1);
      row['detections'] = null; // `raw is String` branch not taken
      db.rows.add(row);
      final rows = await DatabaseService.getAllScans();
      expect(rows.first['detections'], isNull);
    });

    test('UT-DB-05 getAllScans returns newest first; empty table -> []',
        () async {
      expect(await DatabaseService.getAllScans(), isEmpty);
      final now = DateTime.now();
      db.rows.addAll([
        fakeScanRow(id: 1, time: now.subtract(const Duration(days: 2))),
        fakeScanRow(id: 2, time: now),
        fakeScanRow(id: 3, time: now.subtract(const Duration(days: 1))),
      ]);
      final ids = (await DatabaseService.getAllScans()).map((r) => r['id']);
      expect(ids.toList(), [2, 3, 1]);
    });

    test('UT-DB-06 getRecentScans(limit) sends LIMIT and caps the result',
        () async {
      final now = DateTime.now();
      for (var i = 0; i < 5; i++) {
        db.rows.add(
            fakeScanRow(id: i + 1, time: now.subtract(Duration(hours: i))));
      }
      final rows = await DatabaseService.getRecentScans(3);
      expect(rows.map((r) => r['id']).toList(), [1, 2, 3]);
      expect(db.sqlLog.any((s) => s.contains('LIMIT 3')), isTrue);
    });
  });

  group('counts', () {
    test('UT-DB-07 countAll: 0 for empty, row count otherwise', () async {
      expect(await DatabaseService.countAll(), 0);
      db.rows.addAll([fakeScanRow(id: 1), fakeScanRow(id: 2)]);
      expect(await DatabaseService.countAll(), 2);
    });

    test('UT-DB-08 countToday sends a zero-padded YYYY-MM-DD and counts today',
        () async {
      final now = DateTime.now();
      db.rows.addAll([
        fakeScanRow(id: 1, time: now),
        fakeScanRow(id: 2, time: now),
        fakeScanRow(id: 3, time: now.subtract(const Duration(days: 3))),
      ]);
      final n = await DatabaseService.countToday();
      expect(n, 2);

      final expected = '${now.year}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final call = db.calls.lastWhere((c) =>
          c.method == 'query' &&
          ((c.arguments as Map)['sql'] as String).contains('substr(time'));
      expect((call.arguments as Map)['arguments'], [expected]);
      expect(expected, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });
  });

  group('insertScan', () {
    test('UT-DB-09 empty map -> every column gets its default', () async {
      await DatabaseService.insertScan({});
      final v = lastInsert();
      expect(v['image'], '');
      expect(v['label'], '');
      expect(v['health'], 0.0);
      expect(v['confidence'], 0.0);
      expect(v['box_area_px'], 0.0);
      expect(v['recommendation'], '');
      expect(v['detections'], '[]');
      expect(v['time'], '');
    });

    test('UT-DB-10 values are mapped, ints become doubles, List is JSON',
        () async {
      await DatabaseService.insertScan({
        'image': '/img/a.jpg',
        'label': 'Wilting',
        'health': 55, // int -> double
        'confidence': 0.8,
        'boxAreaPx': 1234, // key differs from column box_area_px
        'recommendation': 'Water.',
        'detections': [
          {'number': 1, 'label': 'Wilting'}
        ],
        'time': '2026-10-20 08:00:00.000',
      });
      final v = lastInsert();
      expect(v['image'], '/img/a.jpg');
      expect(v['label'], 'Wilting');
      expect(v['health'], 55.0);
      expect(v['health'], isA<double>());
      expect(v['box_area_px'], 1234.0);
      expect(v['recommendation'], 'Water.');
      expect(jsonDecode(v['detections'] as String), [
        {'number': 1, 'label': 'Wilting'}
      ]);
      expect(v['time'], '2026-10-20 08:00:00.000');

      // detections already a JSON String -> stored as-is
      await DatabaseService.insertScan({'detections': '[{"a":1}]'});
      expect(lastInsert()['detections'], '[{"a":1}]');
    });
  });

  group('delete', () {
    test('UT-DB-11 deleteScan removes one row; deleteAllScans clears all',
        () async {
      db.rows.addAll([
        fakeScanRow(id: 1),
        fakeScanRow(id: 2),
        fakeScanRow(id: 3),
      ]);
      await DatabaseService.deleteScan(2);
      expect(db.rows.map((r) => r['id']).toList(), [1, 3]);
      expect(db.sqlLog.any((s) => s.startsWith('DELETE FROM scans WHERE id')),
          isTrue);

      await DatabaseService.deleteAllScans();
      expect(db.rows, isEmpty);
    });
  });
}