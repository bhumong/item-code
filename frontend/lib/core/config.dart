class AppConfig {
  const AppConfig._();

  static const String _backendUrlOverride =
      String.fromEnvironment('BACKEND_URL', defaultValue: '');

  static String get backendBaseUrl =>
      resolveBackendBaseUrl(_backendUrlOverride, Uri.base);

  static String resolveBackendBaseUrl(String override, Uri pageUri) =>
      override.isNotEmpty ? override : pageUri.origin;
}
