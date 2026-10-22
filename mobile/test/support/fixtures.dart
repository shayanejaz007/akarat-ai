import 'dart:convert';
import 'dart:io';

/// Reads a JSON fixture written by tool/gen_parity_fixtures.mjs, which runs
/// the website's own JavaScript. `flutter test` runs from the package root.
Object? fixture(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

List<Map<String, Object?>> fixtureList(String name) => (fixture(name)! as List<Object?>).cast<Map<String, Object?>>();
