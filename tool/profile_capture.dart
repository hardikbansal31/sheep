// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Captures a 5-second performance timeline from a running Flutter app
/// via the Dart VM Service Protocol, with Flutter framework tracing enabled.
void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run tool/profile_capture.dart <ws_url>');
    exit(1);
  }

  final wsUrl = args[0];
  print('Connecting to $wsUrl ...');

  final ws = await WebSocket.connect(wsUrl);
  int id = 0;
  final pendingRequests = <int, Completer<Map<String, dynamic>>>{};

  ws.listen((msg) {
    final response = jsonDecode(msg as String) as Map<String, dynamic>;
    final respId = response['id'] as int?;
    if (respId != null && pendingRequests.containsKey(respId)) {
      pendingRequests[respId]!.complete(response);
      pendingRequests.remove(respId);
    }
  }, onError: (e) => print('WebSocket error: $e'));

  Future<Map<String, dynamic>> send(String method, [Map<String, dynamic>? params]) {
    final reqId = ++id;
    final completer = Completer<Map<String, dynamic>>();
    pendingRequests[reqId] = completer;
    ws.add(jsonEncode({
      'jsonrpc': '2.0',
      'id': reqId,
      'method': method,
      if (params != null) 'params': params,
    }));
    return completer.future;
  }

  // 1. Get VM info
  final vmResponse = await send('getVM');
  final isolates = (vmResponse['result']['isolates'] as List);
  final isolateId = (isolates.first as Map)['id'] as String;
  print('Main isolate: $isolateId');

  // 2. Enable ALL timeline streams including Dart (which captures Flutter framework events)
  await send('setVMTimelineFlags', {
    'recordedStreams': ['Dart', 'Embedder', 'GC', 'Compiler', 'API'],
  });

  // 3. Clear old data
  await send('clearVMTimeline');

  print('Timeline recording started. SCROLL NOW for 5 seconds...');
  await Future.delayed(const Duration(seconds: 5));

  // 4. Capture
  print('Capturing timeline...');
  final timelineResponse = await send('getVMTimeline');
  final traceEvents = (timelineResponse['result']['traceEvents'] as List)
      .cast<Map<String, dynamic>>();
  print('Captured ${traceEvents.length} trace events');

  // 5. Collect all Begin/End pairs
  final beginStacks = <String, List<Map<String, dynamic>>>{};
  final completedPairs = <Map<String, dynamic>>[];

  // Also collect Complete events (ph=X)
  final completeEvents = <Map<String, dynamic>>[];

  for (final e in traceEvents) {
    final ph = e['ph'] as String? ?? '';
    final name = e['name'] as String? ?? '';
    final ts = e['ts'] as int? ?? 0;
    final tid = e['tid']?.toString() ?? '0';
    final key = '$tid:$name';

    if (ph == 'X' && e['dur'] != null) {
      completeEvents.add(e);
    } else if (ph == 'B') {
      beginStacks.putIfAbsent(key, () => []).add(e);
    } else if (ph == 'E') {
      final stack = beginStacks[key];
      if (stack != null && stack.isNotEmpty) {
        final begin = stack.removeLast();
        final durUs = ts - (begin['ts'] as int);
        completedPairs.add({
          'name': name,
          'cat': begin['cat'] ?? e['cat'] ?? '',
          'dur': durUs,
          'ts': begin['ts'],
          'args': begin['args'] ?? e['args'],
        });
      }
    }
  }

  // Merge both types of duration events
  final allDurationEvents = [
    ...completeEvents.map((e) => {
      'name': e['name'],
      'cat': e['cat'] ?? '',
      'dur': e['dur'] as int,
      'ts': e['ts'],
      'args': e['args'],
    }),
    ...completedPairs,
  ];

  allDurationEvents.sort((a, b) => (b['dur'] as int).compareTo(a['dur'] as int));

  // 6. Categorize
  int buildCount = 0, layoutCount = 0, paintCount = 0, gcCount = 0, rasterCount = 0, vsyncCount = 0;
  double buildTotalMs = 0, layoutTotalMs = 0, paintTotalMs = 0, gcTotalMs = 0, rasterTotalMs = 0, vsyncTotalMs = 0;

  for (final e in allDurationEvents) {
    final name = (e['name'] as String? ?? '').toLowerCase();
    final cat = (e['cat'] as String? ?? '').toLowerCase();
    final durMs = (e['dur'] as int) / 1000.0;

    if (cat.contains('gc') || name.contains('gc') || name.contains('mark') || name.contains('sweep')) {
      gcCount++; gcTotalMs += durMs;
    } else if (name.contains('vsync') || name.contains('animator')) {
      vsyncCount++; vsyncTotalMs += durMs;
    } else if (name.contains('raster') || name.contains('gpuraster') || name.contains('composit')) {
      rasterCount++; rasterTotalMs += durMs;
    } else if (name.contains('build') || name.contains('buildscope')) {
      buildCount++; buildTotalMs += durMs;
    } else if (name.contains('layout') || name.contains('performlayout') || name.contains('flushLayout')) {
      layoutCount++; layoutTotalMs += durMs;
    } else if (name.contains('paint') || name.contains('flushpaint') || name.contains('flushPaint')) {
      paintCount++; paintTotalMs += durMs;
    }
  }

  print('\n===== TIMELINE ANALYSIS (5 seconds) =====\n');
  print('Total duration events: ${allDurationEvents.length}');
  print('');
  print('Category breakdown:');
  print('  Vsync/Animator: $vsyncCount events, ${vsyncTotalMs.toStringAsFixed(1)}ms total');
  print('  Build:          $buildCount events, ${buildTotalMs.toStringAsFixed(1)}ms total');
  print('  Layout:         $layoutCount events, ${layoutTotalMs.toStringAsFixed(1)}ms total');
  print('  Paint:          $paintCount events, ${paintTotalMs.toStringAsFixed(1)}ms total');
  print('  Raster:         $rasterCount events, ${rasterTotalMs.toStringAsFixed(1)}ms total');
  print('  GC:             $gcCount events, ${gcTotalMs.toStringAsFixed(1)}ms total');

  // 7. Top 30 slowest
  print('\n--- Top 30 Slowest Events ---\n');
  for (int i = 0; i < allDurationEvents.length && i < 30; i++) {
    final e = allDurationEvents[i];
    final durMs = (e['dur'] as int) / 1000.0;
    print('${(i + 1).toString().padLeft(2)}. ${durMs.toStringAsFixed(2).padLeft(8)}ms  ${e['name']}  [${e['cat']}]');
  }

  // 8. Jank summary
  final jank16 = allDurationEvents.where((e) => (e['dur'] as int) > 16000).toList();
  final jank8 = allDurationEvents.where((e) => (e['dur'] as int) > 8000).toList();

  print('\n--- Jank Summary ---\n');
  print('Events > 16ms (missed frame):  ${jank16.length}');
  print('Events >  8ms (half frame):    ${jank8.length}');

  if (jank16.isNotEmpty) {
    print('\n--- Events > 16ms (frame drops) ---\n');
    for (final e in jank16) {
      final durMs = (e['dur'] as int) / 1000.0;
      print('  ${durMs.toStringAsFixed(2).padLeft(8)}ms  ${e['name']}  [${e['cat']}]');
    }
  }

  // 9. Unique event name frequency for names that appear > 10 times
  final nameCounts = <String, int>{};
  final nameTotalDur = <String, double>{};
  for (final e in allDurationEvents) {
    final name = e['name'] as String? ?? 'unknown';
    nameCounts[name] = (nameCounts[name] ?? 0) + 1;
    nameTotalDur[name] = (nameTotalDur[name] ?? 0) + (e['dur'] as int) / 1000.0;
  }

  final frequentNames = nameCounts.entries.where((e) => e.value > 5).toList();
  frequentNames.sort((a, b) => nameTotalDur[b.key]!.compareTo(nameTotalDur[a.key]!));

  print('\n--- Frequent Events (by total time) ---\n');
  print('${'Name'.padRight(40)} ${'Count'.padLeft(6)} ${'Total ms'.padLeft(10)} ${'Avg ms'.padLeft(8)}');
  print('-' * 70);
  for (final entry in frequentNames.take(20)) {
    final name = entry.key;
    final count = entry.value;
    final totalMs = nameTotalDur[name]!;
    final avgMs = totalMs / count;
    print('${name.padRight(40)} ${count.toString().padLeft(6)} ${totalMs.toStringAsFixed(1).padLeft(10)} ${avgMs.toStringAsFixed(2).padLeft(8)}');
  }

  // 10. Save timeline
  final outputFile = File('tool/timeline_profile.json');
  await outputFile.writeAsString(jsonEncode({'traceEvents': traceEvents}));
  print('\nFull timeline saved to ${outputFile.path}');
  print('Open in chrome://tracing or ui.perfetto.dev for visual analysis.');

  await send('setVMTimelineFlags', {'recordedStreams': <String>[]});
  await ws.close();
  print('Done.');
}
