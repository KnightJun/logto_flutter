class LogtoConfig {
  final String endpoint;
  final String appId;
  final String? appSecret;
  final String scheme;
  final List<String>? scopes;
  final List<String>? resources;

  const LogtoConfig({
    required this.appId,
    required this.endpoint,
    required this.scheme,
    this.appSecret,
    this.resources,
    this.scopes,
  });
}
