import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'constants.dart';

typedef AuthenticateFunction = Future<String> Function({
  required String url,
  required String callbackUrlScheme,
  required bool preferEphemeral,
  // ignore: non_constant_identifier_names
});

enum SignInConnector {
  wechat,
  google
}

Uri addQueryParameters(Uri url, Map<String, dynamic> parameters) => url.replace(
    queryParameters: Map.from(url.queryParameters)..addAll(parameters));

String generateRandomString([int length = 64]) {
  Random random = Random.secure();

  return base64UrlEncode(List.generate(length, (_) => random.nextInt(256)))
      .split('=')[0];
}

List<String> withReservedScopes(List<String> scopes) {
  var scopeSet = scopes.toSet();
  scopeSet.addAll(reservedScopes);

  return scopeSet.toList();
}

String appendUriPath(String endpoint, String path) {
  var uri = Uri.parse(endpoint);
  var jointUri = uri.replace(path: p.join(uri.path, path));

  return jointUri.toString();
}
