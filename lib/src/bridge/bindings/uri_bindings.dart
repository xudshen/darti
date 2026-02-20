/// Registers `Uri` host bindings for the CALL_HOST pipeline.
///
/// Covers Uri constructors (parse, tryParse, http, https, file, directory,
/// dataFromString), instance getters, methods (resolve, replace, etc.),
/// and static encoding/decoding utilities.
///
/// See: docs/design/04-interop.md
library;

import '../host_function_registry.dart';

/// Registers all `dart:core::Uri` host function bindings.
abstract final class UriBindings {
  static void register(HostFunctionRegistry registry) {
    _registerConstructors(registry);
    _registerGetters(registry);
    _registerMethods(registry);
    _registerStaticMethods(registry);
  }

  static void _registerConstructors(HostFunctionRegistry registry) {
    // Uri.parse(String uri, [int start = 0, int? end])
    // Kernel resolves the full 3-param signature; also register #1 for
    // simplified invoke tests.
    registry.register('dart:core::Uri::parse#1', (args) {
      return Uri.parse(args[0] as String);
    });
    registry.register('dart:core::Uri::parse#3', (args) {
      final uriStr = args[0] as String;
      final start =
          args.length > 1 && args[1] != null ? args[1] as int : 0;
      final end = args.length > 2 ? args[2] as int? : null;
      return Uri.parse(uriStr, start, end);
    });

    // Uri.tryParse(String uri, [int start = 0, int? end])
    // Kernel resolves the full 3-param signature; also register #1 for
    // simplified invoke tests.
    registry.register('dart:core::Uri::tryParse#1', (args) {
      return Uri.tryParse(args[0] as String);
    });
    registry.register('dart:core::Uri::tryParse#3', (args) {
      final uriStr = args[0] as String;
      final start =
          args.length > 1 && args[1] != null ? args[1] as int : 0;
      final end = args.length > 2 ? args[2] as int? : null;
      return Uri.tryParse(uriStr, start, end);
    });

    // Uri.http(String authority, String unencodedPath, [Map<String, dynamic>? queryParameters])
    registry.register('dart:core::Uri::http#3', (args) {
      final authority = args[0] as String;
      final path = args[1] as String;
      if (args.length > 2 && args[2] != null) {
        return Uri.http(
            authority, path, (args[2] as Map).cast<String, dynamic>());
      }
      return Uri.http(authority, path);
    });

    // Uri.https(String authority, String unencodedPath, [Map<String, dynamic>? queryParameters])
    registry.register('dart:core::Uri::https#3', (args) {
      final authority = args[0] as String;
      final path = args[1] as String;
      if (args.length > 2 && args[2] != null) {
        return Uri.https(
            authority, path, (args[2] as Map).cast<String, dynamic>());
      }
      return Uri.https(authority, path);
    });

    // Uri.file(String path, {bool windows})
    registry.register('dart:core::Uri::file#2', (args) {
      if (args.length > 1 && args[1] != null) {
        return Uri.file(args[0] as String, windows: args[1] as bool);
      }
      return Uri.file(args[0] as String);
    });

    // Uri.directory(String path, {bool windows})
    registry.register('dart:core::Uri::directory#2', (args) {
      if (args.length > 1 && args[1] != null) {
        return Uri.directory(args[0] as String, windows: args[1] as bool);
      }
      return Uri.directory(args[0] as String);
    });

    // Uri.dataFromString(String content, {String? mimeType, Encoding? encoding,
    //   Map<String, String>? parameters, bool base64 = false})
    // Simplified: register with 5 params but only commonly used ones.
    registry.register('dart:core::Uri::dataFromString#5', (args) {
      return Uri.dataFromString(
        args[0] as String,
        mimeType: args.length > 1 && args[1] != null ? args[1] as String : null,
        // encoding param skipped (requires dart:convert import)
        parameters: args.length > 3 && args[3] != null
            ? (args[3] as Map).cast<String, String>()
            : null,
        base64: args.length > 4 && args[4] != null ? args[4] as bool : false,
      );
    });
  }

  static void _registerGetters(HostFunctionRegistry registry) {
    registry.register('dart:core::Uri::scheme#0', (args) {
      return (args[0] as Uri).scheme;
    });
    registry.register('dart:core::Uri::authority#0', (args) {
      return (args[0] as Uri).authority;
    });
    registry.register('dart:core::Uri::userInfo#0', (args) {
      return (args[0] as Uri).userInfo;
    });
    registry.register('dart:core::Uri::host#0', (args) {
      return (args[0] as Uri).host;
    });
    registry.register('dart:core::Uri::port#0', (args) {
      return (args[0] as Uri).port;
    });
    registry.register('dart:core::Uri::path#0', (args) {
      return (args[0] as Uri).path;
    });
    registry.register('dart:core::Uri::query#0', (args) {
      return (args[0] as Uri).query;
    });
    registry.register('dart:core::Uri::fragment#0', (args) {
      return (args[0] as Uri).fragment;
    });
    registry.register('dart:core::Uri::pathSegments#0', (args) {
      return (args[0] as Uri).pathSegments;
    });
    registry.register('dart:core::Uri::queryParameters#0', (args) {
      return (args[0] as Uri).queryParameters;
    });
    registry.register('dart:core::Uri::isAbsolute#0', (args) {
      return (args[0] as Uri).isAbsolute;
    });
    registry.register('dart:core::Uri::hasAuthority#0', (args) {
      return (args[0] as Uri).hasAuthority;
    });
    registry.register('dart:core::Uri::hasPort#0', (args) {
      return (args[0] as Uri).hasPort;
    });
    registry.register('dart:core::Uri::hasQuery#0', (args) {
      return (args[0] as Uri).hasQuery;
    });
    registry.register('dart:core::Uri::hasFragment#0', (args) {
      return (args[0] as Uri).hasFragment;
    });
    registry.register('dart:core::Uri::hasEmptyPath#0', (args) {
      return (args[0] as Uri).hasEmptyPath;
    });
    registry.register('dart:core::Uri::hasAbsolutePath#0', (args) {
      return (args[0] as Uri).hasAbsolutePath;
    });
    registry.register('dart:core::Uri::hasScheme#0', (args) {
      return (args[0] as Uri).hasScheme;
    });
    registry.register('dart:core::Uri::origin#0', (args) {
      return (args[0] as Uri).origin;
    });
    registry.register('dart:core::Uri::hashCode#0', (args) {
      return (args[0] as Uri).hashCode;
    });
    registry.register('dart:core::Uri::data#0', (args) {
      return (args[0] as Uri).data;
    });
  }

  static void _registerMethods(HostFunctionRegistry registry) {
    registry.register('dart:core::Uri::resolve#1', (args) {
      return (args[0] as Uri).resolve(args[1] as String);
    });
    registry.register('dart:core::Uri::resolveUri#1', (args) {
      return (args[0] as Uri).resolveUri(args[1] as Uri);
    });
    registry.register('dart:core::Uri::normalizePath#0', (args) {
      return (args[0] as Uri).normalizePath();
    });
    registry.register('dart:core::Uri::isScheme#1', (args) {
      return (args[0] as Uri).isScheme(args[1] as String);
    });
    registry.register('dart:core::Uri::toFilePath#1', (args) {
      if (args.length > 1 && args[1] != null) {
        return (args[0] as Uri).toFilePath(windows: args[1] as bool);
      }
      return (args[0] as Uri).toFilePath();
    });
    registry.register('dart:core::Uri::toString#0', (args) {
      return (args[0] as Uri).toString();
    });
    registry.register('dart:core::Uri::==#1', (args) {
      return args[0] == args[1];
    });

    // replace({scheme, userInfo, host, port, path, pathSegments, query,
    //          queryParameters, fragment})
    // 9 named params in alphabetical order after the receiver.
    registry.register('dart:core::Uri::replace#9', (args) {
      return (args[0] as Uri).replace(
        scheme: args.length > 1 ? args[1] as String? : null,
        userInfo: args.length > 2 ? args[2] as String? : null,
        host: args.length > 3 ? args[3] as String? : null,
        port: args.length > 4 ? args[4] as int? : null,
        path: args.length > 5 ? args[5] as String? : null,
        pathSegments: args.length > 6 && args[6] != null
            ? (args[6] as Iterable).cast<String>()
            : null,
        query: args.length > 7 ? args[7] as String? : null,
        queryParameters: args.length > 8 && args[8] != null
            ? (args[8] as Map).cast<String, dynamic>()
            : null,
        fragment: args.length > 9 ? args[9] as String? : null,
      );
    });
  }

  static void _registerStaticMethods(HostFunctionRegistry registry) {
    registry.register('dart:core::Uri::encodeFull#1', (args) {
      return Uri.encodeFull(args[0] as String);
    });
    registry.register('dart:core::Uri::decodeFull#1', (args) {
      return Uri.decodeFull(args[0] as String);
    });
    registry.register('dart:core::Uri::encodeComponent#1', (args) {
      return Uri.encodeComponent(args[0] as String);
    });
    registry.register('dart:core::Uri::decodeComponent#1', (args) {
      return Uri.decodeComponent(args[0] as String);
    });
    // encodeQueryComponent(String component, {Encoding encoding = utf8})
    // Simplified: ignore encoding param.
    registry.register('dart:core::Uri::encodeQueryComponent#2', (args) {
      return Uri.encodeQueryComponent(args[0] as String);
    });
    registry.register('dart:core::Uri::decodeQueryComponent#2', (args) {
      return Uri.decodeQueryComponent(args[0] as String);
    });
    // splitQueryString(String query, {Encoding encoding = utf8})
    registry.register('dart:core::Uri::splitQueryString#2', (args) {
      return Uri.splitQueryString(args[0] as String);
    });
  }
}
