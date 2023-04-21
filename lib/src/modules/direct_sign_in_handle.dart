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
    "state": "sUnfmzGElu0",
    "redirectUri": "${Uri.parse(url).origin}/callback/${connectorInfo.id}"
  });
  return await webAuthAuthenticate(
      callbackUrlScheme: callbackUrlScheme, preferEphemeral: preferEphemeral, url: response.data["redirectTo"]);
}
