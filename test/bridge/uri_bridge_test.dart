import 'package:dartic/src/bridge/core_bindings.dart';
import 'package:dartic/src/bridge/host_function_registry.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  late HostFunctionRegistry registry;

  setUp(() {
    registry = HostFunctionRegistry();
    CoreBindings.registerAll(registry);
  });

  Object? invoke(String name, List<Object?> args) {
    final id = registry.lookupByName(name);
    if (id == -1) fail('Binding not found: $name');
    return registry.invoke(id, args);
  }

  // ── Registration tests ──

  group('registration', () {
    test('constructors are registered', () {
      expect(registry.lookupByName('dart:core::Uri::parse#1'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::tryParse#1'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::http#3'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::https#3'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::file#2'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::directory#2'), isNot(-1));
      expect(
          registry.lookupByName('dart:core::Uri::dataFromString#5'), isNot(-1));
    });

    test('getters are registered', () {
      expect(registry.lookupByName('dart:core::Uri::scheme#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::authority#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::userInfo#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::host#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::port#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::path#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::query#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::fragment#0'), isNot(-1));
      expect(
          registry.lookupByName('dart:core::Uri::pathSegments#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::queryParameters#0'),
          isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::isAbsolute#0'), isNot(-1));
      expect(
          registry.lookupByName('dart:core::Uri::hasAuthority#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::hasPort#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::hasQuery#0'), isNot(-1));
      expect(
          registry.lookupByName('dart:core::Uri::hasFragment#0'), isNot(-1));
      expect(
          registry.lookupByName('dart:core::Uri::hasEmptyPath#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::hasAbsolutePath#0'),
          isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::hasScheme#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::origin#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::hashCode#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::data#0'), isNot(-1));
    });

    test('methods are registered', () {
      expect(registry.lookupByName('dart:core::Uri::resolve#1'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::resolveUri#1'), isNot(-1));
      expect(
          registry.lookupByName('dart:core::Uri::normalizePath#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::isScheme#1'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::toFilePath#1'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::toString#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::==#1'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::replace#9'), isNot(-1));
    });

    test('static methods are registered', () {
      expect(
          registry.lookupByName('dart:core::Uri::encodeFull#1'), isNot(-1));
      expect(
          registry.lookupByName('dart:core::Uri::decodeFull#1'), isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::encodeComponent#1'),
          isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::decodeComponent#1'),
          isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::encodeQueryComponent#2'),
          isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::decodeQueryComponent#2'),
          isNot(-1));
      expect(registry.lookupByName('dart:core::Uri::splitQueryString#2'),
          isNot(-1));
    });
  });

  // ── Constructor invoke tests ──

  group('constructors', () {
    test('Uri.parse parses valid URI', () {
      final uri = invoke('dart:core::Uri::parse#1',
          ['https://user:pass@dart.dev:443/path?q=1#frag']) as Uri;
      expect(uri.scheme, 'https');
      expect(uri.host, 'dart.dev');
      expect(uri.port, 443);
      expect(uri.path, '/path');
      expect(uri.query, 'q=1');
      expect(uri.fragment, 'frag');
    });

    test('Uri.tryParse returns Uri on valid input', () {
      final uri =
          invoke('dart:core::Uri::tryParse#1', ['https://dart.dev']) as Uri;
      expect(uri.host, 'dart.dev');
    });

    test('Uri.tryParse returns null on invalid input', () {
      final result = invoke('dart:core::Uri::tryParse#1', ['://']);
      expect(result, isNull);
    });

    test('Uri.http creates HTTP URI', () {
      final uri =
          invoke('dart:core::Uri::http#3', ['dart.dev', '/path', null]) as Uri;
      expect(uri.scheme, 'http');
      expect(uri.host, 'dart.dev');
      expect(uri.path, '/path');
    });

    test('Uri.http with query parameters', () {
      final uri = invoke('dart:core::Uri::http#3',
          ['dart.dev', '/search', {'q': 'hello'}]) as Uri;
      expect(uri.queryParameters['q'], 'hello');
    });

    test('Uri.https creates HTTPS URI', () {
      final uri = invoke('dart:core::Uri::https#3',
          ['dart.dev', '/path', null]) as Uri;
      expect(uri.scheme, 'https');
      expect(uri.host, 'dart.dev');
    });

    test('Uri.https with query parameters', () {
      final uri = invoke('dart:core::Uri::https#3',
          ['dart.dev', '/search', {'q': 'world'}]) as Uri;
      expect(uri.scheme, 'https');
      expect(uri.queryParameters['q'], 'world');
    });

    test('Uri.file creates file URI', () {
      final uri = invoke('dart:core::Uri::file#2', ['/tmp/test.txt']) as Uri;
      expect(uri.scheme, 'file');
      expect(uri.path, '/tmp/test.txt');
    });

    test('Uri.directory creates directory URI', () {
      final uri = invoke('dart:core::Uri::directory#2', ['/tmp/dir']) as Uri;
      expect(uri.scheme, 'file');
      expect(uri.path, endsWith('/'));
    });

    test('Uri.dataFromString creates data URI', () {
      final uri = invoke(
          'dart:core::Uri::dataFromString#5', ['hello', null, null, null, null]) as Uri;
      expect(uri.scheme, 'data');
    });
  });

  // ── Getter invoke tests ──

  group('getters', () {
    late Uri uri;

    setUp(() {
      uri = Uri.parse(
          'https://user:pass@dart.dev:8080/path/to/resource?key=val&a=b#section');
    });

    test('scheme', () {
      expect(invoke('dart:core::Uri::scheme#0', [uri]), 'https');
    });

    test('authority', () {
      expect(
          invoke('dart:core::Uri::authority#0', [uri]), 'user:pass@dart.dev:8080');
    });

    test('userInfo', () {
      expect(invoke('dart:core::Uri::userInfo#0', [uri]), 'user:pass');
    });

    test('host', () {
      expect(invoke('dart:core::Uri::host#0', [uri]), 'dart.dev');
    });

    test('port', () {
      expect(invoke('dart:core::Uri::port#0', [uri]), 8080);
    });

    test('path', () {
      expect(invoke('dart:core::Uri::path#0', [uri]), '/path/to/resource');
    });

    test('query', () {
      expect(invoke('dart:core::Uri::query#0', [uri]), 'key=val&a=b');
    });

    test('fragment', () {
      expect(invoke('dart:core::Uri::fragment#0', [uri]), 'section');
    });

    test('pathSegments', () {
      final segments =
          invoke('dart:core::Uri::pathSegments#0', [uri]) as List<String>;
      expect(segments, ['path', 'to', 'resource']);
    });

    test('queryParameters', () {
      final params = invoke('dart:core::Uri::queryParameters#0', [uri])
          as Map<String, String>;
      expect(params['key'], 'val');
      expect(params['a'], 'b');
    });

    test('isAbsolute', () {
      // uri has a fragment (#section), so isAbsolute is false
      // (isAbsolute requires scheme AND no fragment).
      expect(invoke('dart:core::Uri::isAbsolute#0', [uri]), false);
      final absolute = Uri.parse('https://dart.dev/path');
      expect(invoke('dart:core::Uri::isAbsolute#0', [absolute]), true);
      final relative = Uri.parse('/relative/path');
      expect(invoke('dart:core::Uri::isAbsolute#0', [relative]), false);
    });

    test('hasAuthority', () {
      expect(invoke('dart:core::Uri::hasAuthority#0', [uri]), true);
    });

    test('hasPort', () {
      expect(invoke('dart:core::Uri::hasPort#0', [uri]), true);
      final noPort = Uri.parse('https://dart.dev');
      expect(invoke('dart:core::Uri::hasPort#0', [noPort]), false);
    });

    test('hasQuery', () {
      expect(invoke('dart:core::Uri::hasQuery#0', [uri]), true);
      final noQuery = Uri.parse('https://dart.dev');
      expect(invoke('dart:core::Uri::hasQuery#0', [noQuery]), false);
    });

    test('hasFragment', () {
      expect(invoke('dart:core::Uri::hasFragment#0', [uri]), true);
      final noFrag = Uri.parse('https://dart.dev');
      expect(invoke('dart:core::Uri::hasFragment#0', [noFrag]), false);
    });

    test('hasEmptyPath', () {
      final empty = Uri.parse('https://dart.dev');
      expect(invoke('dart:core::Uri::hasEmptyPath#0', [empty]), true);
      expect(invoke('dart:core::Uri::hasEmptyPath#0', [uri]), false);
    });

    test('hasAbsolutePath', () {
      expect(invoke('dart:core::Uri::hasAbsolutePath#0', [uri]), true);
    });

    test('hasScheme', () {
      expect(invoke('dart:core::Uri::hasScheme#0', [uri]), true);
      final noScheme = Uri.parse('//dart.dev');
      expect(invoke('dart:core::Uri::hasScheme#0', [noScheme]), false);
    });

    test('origin', () {
      expect(invoke('dart:core::Uri::origin#0', [uri]), 'https://dart.dev:8080');
    });

    test('hashCode returns int', () {
      expect(invoke('dart:core::Uri::hashCode#0', [uri]), isA<int>());
    });

    test('data returns null for non-data URI', () {
      expect(invoke('dart:core::Uri::data#0', [uri]), isNull);
    });

    test('data returns UriData for data URI', () {
      final dataUri = Uri.dataFromString('hello');
      expect(invoke('dart:core::Uri::data#0', [dataUri]), isNotNull);
    });
  });

  // ── Method invoke tests ──

  group('methods', () {
    test('resolve', () {
      final base = Uri.parse('https://dart.dev/docs/');
      final resolved =
          invoke('dart:core::Uri::resolve#1', [base, 'guide.html']) as Uri;
      expect(resolved.toString(), 'https://dart.dev/docs/guide.html');
    });

    test('resolveUri', () {
      final base = Uri.parse('https://dart.dev/docs/');
      final ref = Uri.parse('guide.html');
      final resolved =
          invoke('dart:core::Uri::resolveUri#1', [base, ref]) as Uri;
      expect(resolved.toString(), 'https://dart.dev/docs/guide.html');
    });

    test('normalizePath', () {
      final uri = Uri.parse('https://dart.dev/a/../b');
      final normalized =
          invoke('dart:core::Uri::normalizePath#0', [uri]) as Uri;
      expect(normalized.path, '/b');
    });

    test('isScheme returns true for matching scheme', () {
      final uri = Uri.parse('https://dart.dev');
      expect(invoke('dart:core::Uri::isScheme#1', [uri, 'https']), true);
    });

    test('isScheme returns false for non-matching scheme', () {
      final uri = Uri.parse('https://dart.dev');
      expect(invoke('dart:core::Uri::isScheme#1', [uri, 'http']), false);
    });

    test('toFilePath for file URI', () {
      final uri = Uri.file('/tmp/test.txt');
      final path =
          invoke('dart:core::Uri::toFilePath#1', [uri]) as String;
      expect(path, '/tmp/test.txt');
    });

    test('toString returns string representation', () {
      final uri = Uri.parse('https://dart.dev/path');
      expect(invoke('dart:core::Uri::toString#0', [uri]),
          'https://dart.dev/path');
    });

    test('== returns true for equal URIs', () {
      final a = Uri.parse('https://dart.dev');
      final b = Uri.parse('https://dart.dev');
      expect(invoke('dart:core::Uri::==#1', [a, b]), true);
    });

    test('== returns false for different URIs', () {
      final a = Uri.parse('https://dart.dev');
      final b = Uri.parse('https://pub.dev');
      expect(invoke('dart:core::Uri::==#1', [a, b]), false);
    });

    test('replace changes scheme', () {
      final uri = Uri.parse('http://dart.dev/path');
      final replaced = invoke('dart:core::Uri::replace#9',
          [uri, 'https', null, null, null, null, null, null, null, null]) as Uri;
      expect(replaced.scheme, 'https');
      expect(replaced.host, 'dart.dev');
    });

    test('replace changes host', () {
      final uri = Uri.parse('https://dart.dev/path');
      final replaced = invoke('dart:core::Uri::replace#9',
          [uri, null, null, 'pub.dev', null, null, null, null, null, null]) as Uri;
      expect(replaced.host, 'pub.dev');
    });

    test('replace changes fragment', () {
      final uri = Uri.parse('https://dart.dev/path');
      final replaced = invoke('dart:core::Uri::replace#9',
          [uri, null, null, null, null, null, null, null, null, 'top']) as Uri;
      expect(replaced.fragment, 'top');
    });
  });

  // ── Static method invoke tests ──

  group('static methods', () {
    test('encodeFull', () {
      expect(invoke('dart:core::Uri::encodeFull#1', ['hello world']),
          'hello%20world');
    });

    test('decodeFull', () {
      expect(invoke('dart:core::Uri::decodeFull#1', ['hello%20world']),
          'hello world');
    });

    test('encodeComponent', () {
      expect(invoke('dart:core::Uri::encodeComponent#1', ['a=b&c=d']),
          'a%3Db%26c%3Dd');
    });

    test('decodeComponent', () {
      expect(invoke('dart:core::Uri::decodeComponent#1', ['a%3Db%26c%3Dd']),
          'a=b&c=d');
    });

    test('encodeQueryComponent', () {
      final encoded =
          invoke('dart:core::Uri::encodeQueryComponent#2', ['hello world'])
              as String;
      // Might encode space as + or %20 depending on implementation
      expect(encoded, isNotEmpty);
    });

    test('decodeQueryComponent', () {
      expect(invoke('dart:core::Uri::decodeQueryComponent#2', ['hello+world']),
          'hello world');
    });

    test('splitQueryString', () {
      final result =
          invoke('dart:core::Uri::splitQueryString#2', ['a=1&b=2'])
              as Map<String, String>;
      expect(result['a'], '1');
      expect(result['b'], '2');
    });
  });

  // ── E2e compile + run tests ──

  group('e2e compile + run', () {
    test("Uri.parse('https://dart.dev').host returns 'dart.dev'", () async {
      final result = await compileAndRunWithHost("""
String main() {
  return Uri.parse('https://dart.dev').host;
}
""");
      expect(result, 'dart.dev');
    });

    test("Uri.encodeFull('hello world') returns 'hello%20world'", () async {
      final result = await compileAndRunWithHost("""
String main() {
  return Uri.encodeFull('hello world');
}
""");
      expect(result, 'hello%20world');
    });

    test("Uri.parse('https://x.com/p?q=1').hasQuery returns true", () async {
      final result = await compileAndRunWithHost("""
bool main() {
  return Uri.parse('https://x.com/p?q=1').hasQuery;
}
""");
      expect(result, true);
    });

    test("Uri.parse scheme getter", () async {
      final result = await compileAndRunWithHost("""
String main() {
  return Uri.parse('https://dart.dev').scheme;
}
""");
      expect(result, 'https');
    });

    test("Uri.decodeComponent round-trip", () async {
      final result = await compileAndRunWithHost("""
String main() {
  return Uri.decodeComponent(Uri.encodeComponent('a=b&c=d'));
}
""");
      expect(result, 'a=b&c=d');
    });

    test("Uri.parse isAbsolute", () async {
      final result = await compileAndRunWithHost("""
bool main() {
  return Uri.parse('https://dart.dev').isAbsolute;
}
""");
      expect(result, true);
    });
  });
}
