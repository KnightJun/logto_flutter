import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:logto_dart_sdk/src/utilities/utils.dart';
import 'dart:math';

String _generateRandomString() {
  const chars = "abcdefghijklmnopqrstuvwxyz";
  final random = Random();
  return String.fromCharCodes(Iterable.generate(8, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
}

class _SignInInfo {
  final String termsOfUseUrl;
  final String privacyPolicyUrl;
  final List<String> socialSignInConnectorTargets;
  final List<_SocialConnector> socialConnectors;

  _SignInInfo({
    required this.termsOfUseUrl,
    required this.privacyPolicyUrl,
    required this.socialSignInConnectorTargets,
    required this.socialConnectors,
  });

  _SocialConnector findSocialConnector(String connectorName) {
    var platformName = SignInPlatform.Universal.name;
    if (connectorName == SignInConnector.wechat.name) {
      if (Platform.isIOS || Platform.isAndroid) {
        platformName = SignInPlatform.Native.name;
      } else {
        platformName = SignInPlatform.Web.name;
      }
    }
    return socialConnectors.firstWhere(
      (element) => element.target == connectorName && element.platform == platformName,
      orElse: () {
        throw "not support connector $connectorName";
      },
    );
  }

  factory _SignInInfo.fromJson(Map<String, dynamic> json) {
    var socialConnectorsList = json['socialConnectors'] as List;
    List<_SocialConnector> connectors = socialConnectorsList.map((i) => _SocialConnector.fromJson(i)).toList();

    return _SignInInfo(
      termsOfUseUrl: json['termsOfUseUrl'],
      privacyPolicyUrl: json['privacyPolicyUrl'],
      socialSignInConnectorTargets: List<String>.from(json['socialSignInConnectorTargets']),
      socialConnectors: connectors,
    );
  }
}

class _SocialConnector {
  final String id;
  final String target;
  final String platform;

  _SocialConnector({
    required this.id,
    required this.target,
    required this.platform,
  });

  factory _SocialConnector.fromJson(Map<String, dynamic> json) {
    return _SocialConnector(
      id: json['id'],
      target: json['target'],
      platform: json['platform'],
    );
  }
}

String _replaceQueryParam(String urlStr, String paramName, String newValue) {
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

_SignInInfo? _signInInfo;
Completer<void>? _signInInfoCompleter;
Future<void> directSignInWarmUp(String baseUrl) async {
  final dio = Dio();
  dio.options.baseUrl = baseUrl;
  _signInInfoCompleter = Completer<void>();
  try {
    Response response = await dio.get("/api/.well-known/sign-in-exp");
    _signInInfo = _SignInInfo.fromJson(response.data);
    _signInInfoCompleter!.complete();
  } catch (e) {
    _signInInfoCompleter!.completeError(e);
    _signInInfoCompleter = null;
  }
}

Future<String> directSignInAuthenticate(
    {required DirectSignInConfig directSignInConfig,
    required Dio dio,
    required void Function(LogtoClientState state) changeState,
    required String url,
    required String callbackUrlScheme,
    required bool preferEphemeral,
    required AuthenticateFunction webAuthAuthenticate}) async {
  CookieJar cookieJar = CookieJar();
  final cookieInterceptor = CookieManager(cookieJar);
  dio.interceptors.add(cookieInterceptor);
  dio.options.followRedirects = false;
  Future<String> get302Address(String targetUrl) async {
    try {
      await dio.get(targetUrl);
    } on DioError catch (e) {
      if (e.response == null || (e.response!.statusCode != 302 && e.response!.statusCode != 303)) {
        rethrow;
      }
      if (e.response!.headers.map.containsKey("location")) {
        return e.response!.headers.map["location"]!.first;
      }
    }
    throw "can't find header location";
  }

  Future<ConnectorResult> callWebVerify(String srcRedirectUri, String customRedirectUri) async {
    final redirectUri = _replaceQueryParam(srcRedirectUri, "redirect_uri", customRedirectUri);
    final googleBack = await webAuthAuthenticate(
        callbackUrlScheme: callbackUrlScheme, preferEphemeral: preferEphemeral, url: redirectUri);
    final googleBackUri = Uri.parse(googleBack);
    final Map<String, String?> connectorData = Map.from(googleBackUri.queryParameters);
    connectorData["redirectUri"] = customRedirectUri;
    return ConnectorResult(state: LogtoClientState.connectorAgree, data: connectorData);
  }

  await get302Address(url);
  Response response;
  late final _SignInInfo signInInfo;
  if (_signInInfoCompleter != null) {
    await _signInInfoCompleter!.future;
  }
  signInInfo = _signInInfo ?? _SignInInfo.fromJson((await dio.get("/api/.well-known/sign-in-exp")).data);
  final connectorInfo = signInInfo.findSocialConnector(directSignInConfig.connector.name);
  final connectorRedirectUrl = "${Uri.parse(url).origin}/callback/${connectorInfo.id}";
  final customRedirectUri = directSignInConfig.customRedirectUri ?? connectorRedirectUrl;
  response = await dio.put("/api/interaction", data: {"event": "SignIn"});
  response = await dio.post("/api/interaction/verification/social-authorization-uri", data: {
    "connectorId": connectorInfo.id,
    "state": "pixcv_${_generateRandomString()}",
    "redirectUri": connectorRedirectUrl
  });
  changeState(LogtoClientState.waitingUserLogin);
  ConnectorResult connectorData;
  switch (directSignInConfig.connector) {
    case SignInConnector.google:
      connectorData = await callWebVerify(response.data["redirectTo"], customRedirectUri);
      break;
    case SignInConnector.wechat:
      if (connectorInfo.platform == SignInPlatform.Native.name) {
        connectorData = await directSignInConfig.onWechatCallback!(response.data["redirectTo"]);
      } else {
        connectorData = await callWebVerify(response.data["redirectTo"], customRedirectUri);
      }
      break;
    default:
      throw "unsupport connector ${directSignInConfig.connector.name}";
  }
  changeState(connectorData.state);
  if (connectorData.state != LogtoClientState.connectorAgree) {
    return "";
  }
  response = await dio.patch("/api/interaction/identifiers",
      data: {"connectorData": connectorData.data, "connectorId": connectorInfo.id});
  try {
    response = await dio.post("/api/interaction/submit");
  } on DioError catch (e) {
    if (e.response == null || e.response!.statusCode != 422 || e.response!.data["code"] != "user.identity_not_exist") {
      rethrow;
    }
    // 自动注册
    response = await dio.put("/api/interaction/event", data: {"event": "Register"});
    response = await dio.patch("/api/interaction/profile", data: {"connectorId": connectorInfo.id});
    response = await dio.post("/api/interaction/submit");
  }
  await get302Address(response.data["redirectTo"]);
  response = await dio.post("/api/interaction/consent");
  final String callbackUrl = await get302Address(response.data["redirectTo"]);
  dio.interceptors.remove(cookieInterceptor);
  return callbackUrl;
}
