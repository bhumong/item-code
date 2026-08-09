class AppConfig {
  const AppConfig._();

  /// Backend base URL. Override at build/run time with:
  /// `flutter run --dart-define=BACKEND_URL=http://localhost:8090`
  static const String backendBaseUrl =
      String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8090');
}
