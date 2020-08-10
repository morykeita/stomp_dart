class Config {
  final String url;
  final Map<String, String> headers;
  final int pingInterval;

  Config({this.url, this.headers, this.pingInterval});
}
