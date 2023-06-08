import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_web_auth/flutter_web_auth.dart';
import 'package:dio/dio.dart' as dio;
import 'package:jose/jose.dart';
import 'package:logto_dart_sdk/flutter_web_auth_windows.dart';
import 'package:logto_dart_sdk/src/modules/direct_sign_in_handle.dart';
import 'package:logto_dart_sdk/src/utilities/utils.dart';

import '/src/exceptions/logto_auth_exceptions.dart';
import '/src/interfaces/logto_interfaces.dart';
import '/src/modules/id_token.dart';
import '/src/modules/logto_storage_strategy.dart';
import '/src/modules/pkce.dart';
import '/src/modules/token_storage.dart';
import '/src/utilities/constants.dart';
import '/src/utilities/utils.dart' as utils;
import 'logto_core.dart' as logto_core;
import 'src/interfaces/logto_user_info_response.dart';
export 'src/interfaces/logto_user_info_response.dart';
export '/src/interfaces/logto_config.dart';
export '/src/utilities/utils.dart';

// Logto SDK
class LogtoClient {
  final LogtoConfig config;

  late PKCE _pkce;
  late String _state;

  static late TokenStorage _tokenStorage;

  static AuthenticateFunction? flutterWebAuthAuthenticate;

  /// Custom [dio.Dio].
  ///
  /// Note that you will have to call `close()` yourself when passing a [dio.Dio] instance.
  late final dio.Dio _httpClient;

  bool _loading = false;

  bool get loading => _loading;

  OidcProviderConfig? _oidcConfig;
  late final LogtoStorageStrategy _storage;
  LogtoClientState loginState = LogtoClientState.unlogin;
  void Function(LogtoClientState state)? onLoginStateChange;
  void Function()? onUserCancelLogin;
  void Function()? onNetworkError;

  LogtoClient({
    required this.config,
    LogtoStorageStrategy? storageProvider,
    required dio.Dio httpClient,
  }) {
    _httpClient = httpClient;
    httpClient.options.baseUrl = config.endpoint;
    _storage = storageProvider ?? SecureStorageStrategy();
    _tokenStorage = TokenStorage(_storage);
    if (flutterWebAuthAuthenticate == null) {
      if (Platform.isWindows) {
        flutterWebAuthAuthenticate = FlutterWebAuthWindows.authenticate;
        FlutterWebAuthWindows.registerScheme(config.scheme, config.schemeDescription);
      } else {
        flutterWebAuthAuthenticate = FlutterWebAuth.authenticate;
      }
    }
    directSignInWarmUp(config.endpoint);
  }

  Future<void> cleanResources() async {
    await FlutterWebAuthWindows.unregisterScheme(config.scheme);
  }

  void changeState(LogtoClientState state) {
    loginState = state;
    onLoginStateChange?.call(loginState);
  }

  Future<bool> get isAuthenticated async {
    return await _tokenStorage.idToken != null;
  }

  Future<String?> get idToken async {
    final token = await _tokenStorage.idToken;
    return token?.serialization;
  }

  Future<OpenIdClaims?> get idTokenClaims async {
    final token = await _tokenStorage.idToken;
    return token?.claims;
  }

  Future<OidcProviderConfig> _getOidcConfig(dio.Dio httpClient) async {
    if (_oidcConfig != null) {
      return _oidcConfig!;
    }

    final discoveryUri = utils.appendUriPath(config.endpoint, discoveryPath);
    _oidcConfig = await logto_core.fetchOidcConfig(httpClient, discoveryUri);

    return _oidcConfig!;
  }

  Future<LogtoUserInfoResponse> fetchUserInfo(dio.Dio httpClient) async {
    final userInfoEndpoint = utils.appendUriPath(config.endpoint, '/oidc/me');
    final accessToken = (await _tokenStorage.getAccessToken())!;
    final userInfo = await logto_core.fetchUserInfo(
        httpClient: httpClient,
        userInfoEndpoint: userInfoEndpoint,
        accessToken: accessToken.token,
        scopes: config.scopes);
    _storage.write(key: "logtoUserInfo", value: jsonEncode(userInfo.toJson()));
    return userInfo;
  }

  Future<AccessToken?> getAccessToken({String? resource}) async {
    final accessToken = await _tokenStorage.getAccessToken(resource);

    if (accessToken != null) {
      return accessToken;
    }

    final token = await _getAccessTokenByRefreshToken(resource);

    return token;
  }

  // RBAC are not supported currently, no resource specific scopes are needed
  Future<AccessToken?> _getAccessTokenByRefreshToken(String? resource) async {
    final refreshToken = await _tokenStorage.refreshToken;

    if (refreshToken == null) {
      throw LogtoAuthException(LogtoAuthExceptions.authenticationError, 'not_authenticated');
    }

    final httpClient = _httpClient ?? dio.Dio();

    try {
      final oidcConfig = await _getOidcConfig(httpClient);

      final response = await logto_core.fetchTokenByRefreshToken(
          httpClient: httpClient,
          tokenEndPoint: oidcConfig.tokenEndpoint,
          clientId: config.appId,
          refreshToken: refreshToken,
          resource: resource);

      final scopes = response.scope.split(' ');

      await _tokenStorage.setAccessToken(response.accessToken,
          expiresIn: response.expiresIn, resource: resource, scopes: scopes);

      // renew refresh token
      await _tokenStorage.setRefreshToken(response.refreshToken);

      // verify and store id_token if not null
      if (response.idToken != null) {
        final idToken = IdToken.unverified(response.idToken!);
        await _verifyIdToken(idToken, oidcConfig);
        await _tokenStorage.setIdToken(idToken);
      }

      return await _tokenStorage.getAccessToken(resource, scopes);
    } finally {
      if (_httpClient == null) httpClient.close();
    }
  }

  Uri _replaceDomainFromUrl(String urlString, String newDomain) {
    Uri uri = Uri.parse(urlString).replace(host: Uri.parse(newDomain).host);
    return uri;
  }

  Future<void> _verifyIdToken(IdToken idToken, OidcProviderConfig oidcConfig) async {
    final keyStore = JsonWebKeyStore()..addKeySetUrl(_replaceDomainFromUrl(oidcConfig.jwksUri, config.endpoint));

    if (!await idToken.verify(keyStore)) {
      throw LogtoAuthException(LogtoAuthExceptions.idTokenValidationError, 'invalid jws signature');
    }

    final violations = idToken.claims.validate(issuer: Uri.parse(oidcConfig.issuer), clientId: config.appId);

    if (violations.isNotEmpty) {
      throw LogtoAuthException(LogtoAuthExceptions.idTokenValidationError, '$violations');
    }
  }

  Future<void> signIn(String redirectUri,
      {DirectSignInConfig? directSignInConfig,
      String? customRedirectUri,
      void Function(LogtoUserInfoResponse userInfo)? getUserInfoCB}) async {
    if (_loading) {
      throw LogtoAuthException(LogtoAuthExceptions.isLoadingError, 'Already signing in...');
    }

    final httpClient = _httpClient;

    try {
      _loading = true;
      changeState(LogtoClientState.prepareLogin);

      _pkce = PKCE.generate();
      _state = utils.generateRandomString();
      _tokenStorage.setIdToken(null);
      final oidcConfig = await _getOidcConfig(httpClient);

      final signInUri = logto_core.generateSignInUri(
        authorizationEndpoint: oidcConfig.authorizationEndpoint,
        clientId: config.appId,
        redirectUri: redirectUri,
        codeChallenge: _pkce.codeChallenge,
        state: _state,
        resources: config.resources,
        scopes: config.scopes,
      );
      String? callbackUri;
      final urlParse = Uri.parse(redirectUri);
      final redirectUriScheme = urlParse.scheme;
      if (directSignInConfig != null) {
        callbackUri = await directSignInAuthenticate(
            dio: httpClient,
            directSignInConfig: directSignInConfig,
            changeState: changeState,
            url: signInUri.toString(),
            callbackUrlScheme: redirectUriScheme,
            preferEphemeral: true,
            webAuthAuthenticate: flutterWebAuthAuthenticate!);
        if (loginState != LogtoClientState.connectorAgree) {
          return;
        }
      } else {
        changeState(LogtoClientState.waitingUserLogin);
        callbackUri = await flutterWebAuthAuthenticate!(
          url: signInUri.toString(),
          callbackUrlScheme: redirectUriScheme,
          preferEphemeral: true,
        );
      }
      changeState(LogtoClientState.authorization);
      await _handleSignInCallback(callbackUri, redirectUri, httpClient);
      if (getUserInfoCB != null) {
        changeState(LogtoClientState.gettingUserInfo);
        getUserInfoCB.call(await fetchUserInfo(httpClient));
      }
      changeState(LogtoClientState.loginFinish);
    } on PlatformException {
      onUserCancelLogin?.call();
      changeState(LogtoClientState.unlogin);
    } on HandshakeException {
      onNetworkError?.call();
      changeState(LogtoClientState.unlogin);
    } on dio.DioError {
      onNetworkError?.call();
      changeState(LogtoClientState.unlogin);
    } finally {
      _loading = false;
      if (_httpClient == null) httpClient.close();
    }
    return;
  }

  Future _handleSignInCallback(String callbackUri, String redirectUri, dio.Dio httpClient) async {
    final code = logto_core.verifyAndParseCodeFromCallbackUri(
      callbackUri,
      redirectUri,
      _state,
    );

    final oidcConfig = await _getOidcConfig(httpClient);

    final tokenResponse = await logto_core.fetchTokenByAuthorizationCode(
      httpClient: httpClient,
      tokenEndPoint: oidcConfig.tokenEndpoint,
      code: code,
      codeVerifier: _pkce.codeVerifier,
      clientId: config.appId,
      redirectUri: redirectUri,
    );

    final idToken = IdToken.unverified(tokenResponse.idToken);

    await _verifyIdToken(idToken, oidcConfig);

    await _tokenStorage.save(
        idToken: idToken,
        accessToken: tokenResponse.accessToken,
        refreshToken: tokenResponse.refreshToken,
        expiresIn: tokenResponse.expiresIn);
  }

  Future<void> signOut(String redirectUri, {bool completelySignOut = false}) async {
    // Throw error is authentication status not found
    final idToken = await _tokenStorage.idToken;

    final httpClient = _httpClient;

    if (idToken == null) {
      throw LogtoAuthException(LogtoAuthExceptions.authenticationError, 'not authenticated');
    }

    try {
      final oidcConfig = await _getOidcConfig(httpClient);

      // Revoke refresh token if exist
      final refreshToken = await _tokenStorage.refreshToken;

      if (refreshToken != null) {
        try {
          changeState(LogtoClientState.prepareLogout);
          await logto_core.revoke(
            httpClient: httpClient,
            revocationEndpoint: oidcConfig.revocationEndpoint,
            clientId: config.appId,
            token: refreshToken,
          );
          if (completelySignOut) {
            changeState(LogtoClientState.waitingLogout);
            final signInUri = logto_core.generateSignOutUri(
              endSessionEndpoint: oidcConfig.endSessionEndpoint,
              idToken: idToken.serialization,
              postLogoutRedirectUri: redirectUri,
            );
            final urlParse = Uri.parse(redirectUri);
            final redirectUriScheme = urlParse.scheme;
            try {
              flutterWebAuthAuthenticate!(
                url: signInUri.toString(),
                callbackUrlScheme: redirectUriScheme,
                preferEphemeral: true,
              );
            } catch (e) {}
          }
          changeState(LogtoClientState.unlogin);
        } catch (e) {
          // Do Nothing silently revoke the token
        }
      }
      await _tokenStorage.clear();
    } finally {
      if (_httpClient == null) {
        httpClient.close();
      }
    }
  }

  void cancelSignIn() {
    if (Platform.isWindows) {
      FlutterWebAuthWindows.cancelFlag = true;
    }
  }

  Future<void> tryRecoverId({void Function(LogtoUserInfoResponse userInfo)? getUserInfoCB}) async {
    if (await isAuthenticated) {
      if (getUserInfoCB != null) {
        final logtoUserInfoString = await _storage.read(key: "logtoUserInfo");
        if (logtoUserInfoString == null) {
          return;
        }
        getUserInfoCB(LogtoUserInfoResponse.fromJson(jsonDecode(logtoUserInfoString)));
      }
      changeState(LogtoClientState.loginFinish);
    }
  }
}
