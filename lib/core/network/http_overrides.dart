import 'dart:io';

/// Global HTTP configuration to accelerate image and API requests.
/// Increases max concurrent connections per host from 5 to 32,
/// and enables keep-alive reuse for SSL/TCP connections.
class AppHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.maxConnectionsPerHost = 32;
    client.idleTimeout = const Duration(seconds: 30);
    client.connectionTimeout = const Duration(seconds: 15);
    return client;
  }
}
