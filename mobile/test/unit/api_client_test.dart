import 'package:akarat/core/config/env.dart';
import 'package:akarat/core/networking/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("the user's token goes only to the website's own API, over HTTPS", () {
    final own = Uri.parse(Env.siteUrl);
    expect(carriesToken(own.replace(path: '/api/ai/search')), isTrue);
    expect(carriesToken(Uri.parse('https://example.com/api/ai/search')), isFalse, reason: 'another host');
    expect(
      carriesToken(own.replace(scheme: 'http', path: '/api/account')),
      isFalse,
      reason: 'not encrypted',
    );
    expect(
      carriesToken(Uri.parse('https://${own.host}.evil.example/api')),
      isFalse,
      reason: 'a host that merely starts with ours',
    );
  });
}
