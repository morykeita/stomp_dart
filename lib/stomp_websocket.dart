library stompdart;

import 'dart:async';
import 'dart:convert';

import 'package:stompdart/config.dart';
import 'package:stompdart/event.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

part 'frame.dart';

class StompWebSocket {
  // subscription callbacks indexed by subscriber's ID
  Map<String, StreamController<Frame>> _subscriptions = {};
  WebSocketChannel channel;

  bool _connected = false;

  Completer<Frame> completer;

  StreamController<Frame> _receiptController = new StreamController();
  StreamController<Frame> _errorController = new StreamController();
  //Server side ERROR frames
  Stream<Frame> get onError => _errorController.stream;

  Future<Frame> connect(Config config) {
    completer = new Completer();
    try {
      channel = IOWebSocketChannel.connect(config.url);
      channel.stream.listen(_onData,
          onError: _onError, onDone: null, cancelOnError: null);
    } on WebSocketChannelException catch (err) {
      _onError(err);
    } catch (err) {
      print(err);
    }
  }

  void _onError(dynamic event) {
    print('an error happened');
  }

  void _onData(DataEvent event) {
    String data = event.data;

    if (data == '\n') {
      // heartbeat
      return;
    }

    for (Frame frame in Frame.unmarshall(data)) {
      switch (frame.command) {
        case 'CONNECTED':
          this._connected = true;
          //_set up hearbeats
          completer.complete(frame);
          break;
        case 'MESSAGE':
          String subscription = frame.headers['subscription'];
          StreamController<Frame> controller =
              this._subscriptions[subscription];
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
  }
}
