import 'package:meta/meta.dart';

class Config {
  final String host;
  final int pingInterval;
  final Map<String, String> stompConnectHeaders;
  final int port;
  final String path;

  /// Headers to be passed when connecting to WebSocket
  final Map<String, dynamic> webSocketConnectHeaders;

  Config(@required this.host, @required this.port, this.path,
      {this.stompConnectHeaders,
      this.pingInterval,
      this.webSocketConnectHeaders});
}
