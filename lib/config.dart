import 'package:meta/meta.dart';

class Config {
  final String host;
  final int pingInterval;
  final int port;
  final String path;

  /// Headers to be passed when connecting to WebSocket
  final Map<String, dynamic> headers;

  Config(@required this.host, @required this.port, this.path,
      {this.pingInterval, this.headers});
}
