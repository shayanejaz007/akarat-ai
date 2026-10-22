import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Saves the frame-timing summaries from integration_test/perf_test.dart.
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) return;
    await File('build/perf_summary.json').writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  },
);
