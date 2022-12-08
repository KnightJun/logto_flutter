class LogtoConfig {
  final String endpoint;
  final String appId;
  final String? appSecret;
  final String scheme;
  final String schemeDescription;
  final List<String>? scopes;
  final List<String>? resources;

  const LogtoConfig({
    required this.appId,
    required this.endpoint,
    required this.scheme,
    required this.schemeDescription,
    this.appSecret,
    this.resources,
    this.scopes,
  });
}
