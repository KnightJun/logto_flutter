import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:logto_dart_sdk/src/utilities/utils.dart';

class _SignInInfo {
  final String termsOfUseUrl;
  final String privacyPolicyUrl;
  final List<String> socialSignInConnectorTargets;
  final List<SocialConnector> socialConnectors;

  _SignInInfo({
    required this.termsOfUseUrl,
    required this.privacyPolicyUrl,
    required this.socialSignInConnectorTargets,
    required this.socialConnectors,
  });

  SocialConnector findSocialConnector(String connectorName) {
    return socialConnectors.firstWhere(
      (element) => element.target == connectorName,
      orElse: () {
        throw "not support connector $connectorName";
      },
    );
  }

  factory _SignInInfo.fromJson(Map<String, dynamic> json) {
    var socialConnectorsList = json['socialConnectors'] as List;
    List<SocialConnector> connectors = socialConnectorsList.map((i) => SocialConnector.fromJson(i)).toList();

    return _SignInInfo(
      termsOfUseUrl: json['termsOfUseUrl'],
      privacyPolicyUrl: json['privacyPolicyUrl'],
      socialSignInConnectorTargets: List<String>.from(json['socialSignInConnectorTargets']),
      socialConnectors: connectors,
    );
  }
}

class SocialConnector {
  final String id;
  final String target;
  final String platform;

  SocialConnector({
    required this.id,
    required this.target,
    required this.platform,
  });

  factory SocialConnector.fromJson(Map<String, dynamic> json) {
    return SocialConnector(
      id: json['id'],
      target: json['target'],
      platform: json['platform'],
    );
  }
}

String replaceQueryParam(String urlStr, String paramName, String newValue) {
  // 解析 URL
  var uri = Uri.parse(urlStr);
  // 构建新的查询参数字符串
  var newQueryParams = Map<String, dynamic>.from(uri.queryParameters);
  newQueryParams[paramName] = newValue;
  var newQueryString = Uri(queryParameters: newQueryParams).query;
  // 构建新的 URL
  var newUrl = '${uri.scheme}://${uri.host}${uri.path}?$newQueryString';
  if (uri.hasFragment) {
    newUrl += '#${uri.fragment}';
  }
  // 返回新的 URL
  return newUrl;
}

String replaceUrlWithNewUrlAndKeepQueryParams(String oldUrl, String newUrl) {
  // Extract the query parameters from the old URL
  String queryParams = Uri.parse(oldUrl).query;
  // Replace the URL with the new URL
  // Combine the new URL and the query parameters to form the final URL
  String finalUrl = Uri.parse(newUrl).replace(query: queryParams).toString();
  return finalUrl;
}

Future<String> getCookieValue(CookieJar cookieJar, String url, String cookieName) async {
  final cookies = await cookieJar.loadForRequest(Uri.parse(url));
  for (final cookie in cookies) {
    if (cookie.name == cookieName) {
      return cookie.value;
    }
  }
  throw "can't find cookie $cookieName";
}

Future<void> printCookieValue(CookieJar cookieJar, String url) async {
  final cookies = await cookieJar.loadForRequest(Uri.parse(url));
  for (final cookie in cookies) {
    print("${cookie.name}:${cookie.value}");
  }
}

String getHeader(Response response, String headerName) {
  if (response.headers.map.containsKey(headerName)) {
    return response.headers.map[headerName]!.first;
  }
  throw "can't find header $headerName";
}

Future<String> directSignInAuthenticate(
    {required String connector,
    required String url,
    required String callbackUrlScheme,
    required bool preferEphemeral,
    required AuthenticateFunction webAuthAuthenticate}) async {
  CookieJar cookieJar = CookieJar();
  final dio = Dio();
  dio.options.followRedirects = false;
  dio.interceptors.add(CookieManager(cookieJar));
  try {
    await dio.get(url);
  } on DioError catch (e) {
    if (!(e.response != null && e.response!.statusCode == 303)) {
      rethrow;
    }
  }
  Response response = await dio.get("${Uri.parse(url).origin}/api/.well-known/sign-in-exp");
  final signInInfo = _SignInInfo.fromJson(response.data);
  final connectorInfo = signInInfo.findSocialConnector(connector);
  response = await dio.put("${Uri.parse(url).origin}/api/interaction", data: {"event": "SignIn"});
  response = await dio.post("${Uri.parse(url).origin}/api/interaction/verification/social-authorization-uri", data: {
    "connectorId": connectorInfo.id,
    "state": "pixcv_sUnfmzGElu0",
    "redirectUri": "${Uri.parse(url).origin}/callback/${connectorInfo.id}"
  });
  final redirectUri = replaceQueryParam(
      response.data["redirectTo"], "redirect_uri", "https://dev-api.deepview.art/public/google/logincallback");

  final googleBack = await webAuthAuthenticate(
      callbackUrlScheme: callbackUrlScheme, preferEphemeral: preferEphemeral, url: redirectUri);
  final googleBackUri = Uri.parse(googleBack);

  final logtoCbUrl =
      replaceUrlWithNewUrlAndKeepQueryParams(googleBack, "${Uri.parse(url).origin}/callback/${connectorInfo.id}");
  await dio.get(logtoCbUrl);
  var interactionId = await getCookieValue(cookieJar, url, "_interaction");
  print("interactionId: $interactionId");
  try {
    response = await dio.patch("${Uri.parse(url).origin}/api/interaction/identifiers", data: {
      "connectorData": {
        "redirectUri": "https://dev-api.deepview.art/public/google/logincallback",
        "code": googleBackUri.queryParameters["code"],
        "scope":
            "email profile https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/userinfo.email openid",
        "authuser": "0",
        "prompt": "none"
      },
      "connectorId": connectorInfo.id
    });
    response = await dio.post("${Uri.parse(url).origin}/api/interaction/submit");
    response = await dio.get(response.data["redirectTo"]);
  } on DioError catch (e) {
    if (!(e.response != null && e.response!.statusCode == 303)) {
      rethrow;
    }
  }
  await printCookieValue(cookieJar, url);
  response = await dio.get("${Uri.parse(url).origin}/sign-in/consent");

  response = await dio.post("${Uri.parse(url).origin}/api/interaction/consent");
  interactionId = await getCookieValue(cookieJar, url, "_interaction");
  print("interactionId: $interactionId");
  late final String callbackUrl;
  try {
    response = await dio.get("${Uri.parse(url).origin}/oidc/auth/$interactionId");
  } on DioError catch (e) {
    if (!(e.response != null && e.response!.statusCode == 303)) {
      rethrow;
    }
    callbackUrl = getHeader(e.response!, "location");
  }

  print(callbackUrl);
  return callbackUrl;
}
