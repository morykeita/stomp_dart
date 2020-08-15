library stompdart;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:stompdart/config.dart';
import 'package:stompdart/parser.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

part 'frame.dart';

class StompWebSocket {
  // subscription callbacks indexed by subscriber's ID
  Map<String, StreamController<Frame>> _subscriptions = {};
  WebSocketChannel channel;
  Parser _parser;

  int _counter = 0;
  bool _connected = false;
  Timer _pinger, _ponger;
  DateTime _serverActivity = new DateTime.now();

  Completer<Frame> completer;

  StreamController<Frame> _receiptController;
  StreamController<Frame> _errorController;
  //Server side ERROR frames
  Stream<Frame> get onError => _errorController.stream;
  Config _config;

  /**
   * Heartbeat properties of the client
   * send heartbeat every 10s by default (value is in ms)
   * expect to receive server heartbeat at least every 10s by default (value in ms)
   **/
  int heartbeatOutgoing = 10000;
  int heartbeatIncoming = 10000;

  StompWebSocket(Config config) {
    this._config = config;
    this._parser = Parser();
    _receiptController = new StreamController();
    _errorController = new StreamController();
  }

  Future<Frame> connect() {
    completer = new Completer();
    try {
      //TODO  add headers and protocols

      channel = IOWebSocketChannel.connect(
        Uri(
          scheme: "ws",
          host: _config.host,
          port: _config.port,
          path: _config.path,
        ),
        headers: _config.headers,
      );

      //channel = IOWebSocketChannel.connect(_config.url);
      channel.stream.listen(_onData,
          onError: _onError, onDone: _onDone, cancelOnError: null);
      _connectToStomp(_config);
    } on WebSocketChannelException catch (err) {
      _onError(err);
    } catch (err) {
      print(err);
    }
  }

  void _connectToStomp(Config config) {
    var connectHeaders = config.headers ?? {};
    connectHeaders['accept-version'] = ['1.0', '1.1', '1.2'].join(',');
    _transmit(command: 'CONNECT', headers: connectHeaders);
  }

  void _transmit(
      {String command,
      Map<String, String> headers,
      String body,
      Uint8List binaryBody}) {
    final frame = Frame(
        command: command, headers: headers, body: body, binaryBody: binaryBody);

    dynamic serializedFrame = _parser.serializeFrame(frame);

    channel.sink.add(serializedFrame);
  }

  void _onDone() {
    print('done');
  }

  void _onError(dynamic event) {
    print('an error happened');
  }

  void _onData(dynamic event) {
    // deserialize frame
    Frame frame = _parser.deserializeFrame(event);

//    if (data == '\n') {
//      // heartbeat
//      return;
//    }

    switch (frame.command) {
      case 'CONNECTED':
        this._connected = true;
        this._setupHeartbeat(frame.headers);
        completer.complete(frame);
        break;
      case 'MESSAGE':
        String subscription = frame.headers['subscription'];
        StreamController<Frame> controller = this._subscriptions[subscription];
        if (controller != null && controller.hasListener) {
          controller.add(frame);
        } else {
          // unhandled frame
        }
        break;
      case 'RECEIPT':
        if (_receiptController.hasListener) {
          this._receiptController.add(frame);
        }
        break;
      case 'ERROR':
        if (!completer.isCompleted) {
          completer.completeError(frame);
        } else {
          if (frame.headers.containsKey('receipt-id') &&
              this._receiptController.hasListener) {
            this._receiptController.add(frame);
          }
        }
        break;
      default:
        // unhandled frame
        break;
    }
  }

  void send(String destination,
      {Map<String, String> headers, String body, String transactionId}) {
    headers = headers == null ? {} : headers;
    headers["destination"] = destination;

    if (transactionId != null) {
      headers["transaction"] = transactionId;
    }
    this._transmit(command: 'SEND', headers: headers, body: body);
  }

  Stream<Frame> subscribe(String destination, [Map<String, String> headers]) {
    if (headers == null) {
      headers = Map<String, String>();
    }
    // for convenience if the `id` header is not set, we create a new one for this client
    //that will be returned to be able to unsubscribe this subscription
    if (!headers.containsKey("id")) {
      headers["id"] = "sub-${this._counter}";
      this._counter++;
    }

    String id = headers["id"];
    StreamController<Frame> controller = new StreamController(onCancel: () {
      this._subscriptions.remove(id);
      this._transmit(command: 'UNSUBSCRIBE', headers: {id: id});
    });
    headers["destination"] = destination;
    this._subscriptions[id] = controller;
    this._transmit(command: 'SUBSCRIBE', headers: headers);
    return controller.stream;
  }

  //Heart-beat negotiation
  void _setupHeartbeat(headers) {
    if (!['1.0', '1.1', '1.2'].contains(headers["version"]) ||
        headers["heart-beat"] == null) {
      return;
    }

    /**
     * heart-beat header received from the server looks like:
     * heart-beat: sx, sy
     **/
    List<String> heartbeatInfo = headers["heart-beat"].split(",");
    int serverOutgoing = int.parse(heartbeatInfo[0]),
        serverIncoming = int.parse(heartbeatInfo[1]);

    if (this.heartbeatOutgoing != 0 && serverIncoming != 0) {
      int ttl = math.max(this.heartbeatOutgoing, serverIncoming);

      this._pinger =
          new Timer.periodic(new Duration(milliseconds: ttl), (Timer timer) {
        channel.sink.add("\n");
      });
    }

    if (this.heartbeatIncoming != 0 && serverOutgoing != null) {
      int ttl = math.max(this.heartbeatIncoming, serverOutgoing);
      this._ponger =
          new Timer.periodic(new Duration(milliseconds: ttl), (Timer timer) {
        Duration delta = this._serverActivity.difference(new DateTime.now());
        // We wait twice the TTL to be flexible on window's setInterval calls
        if (delta.inMilliseconds > ttl * 2) {
          this.channel.sink.close();
        }
      });
    }
  }

  void ack(String messageID, String subscription, Map<String, String> headers) {
    headers["message-id"] = messageID;
    headers["subscription"] = subscription;
    this._transmit(command: 'ACK', headers: headers);
  }

  void nack(
      String messageID, String subscription, Map<String, String> headers) {
    headers["message-id"] = messageID;
    headers["subscription"] = subscription;
    this._transmit(command: 'NACK', headers: headers);
  }

  void commit(String transaction) {
    this._transmit(command: 'COMMIT', headers: {transaction: transaction});
  }

  String begin([String transaction]) {
    String txid = transaction == null ? "tx-${this._counter++}" : transaction;
    this._transmit(command: 'BEGIN', headers: {transaction: txid});
    return txid;
  }

  void abort(String transaction) {
    this._transmit(command: 'ABORT', headers: {transaction: transaction});
  }
}
