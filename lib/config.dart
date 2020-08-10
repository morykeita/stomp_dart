class Config {
  final String url;
  final int pingInterval;
  final Map<String, String> stompConnectHeaders;

  /// Headers to be passed when connecting to WebSocket
  final Map<String, dynamic> webSocketConnectHeaders;

  Config(
      {this.url,
      this.stompConnectHeaders,
      this.pingInterval,
      this.webSocketConnectHeaders});
}
