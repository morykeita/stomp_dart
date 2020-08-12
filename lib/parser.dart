import 'dart:convert';
import 'dart:typed_data';

import 'package:stompdart/stomp_websocket.dart';

class Parser {
  String _resultCommand;
  Map<String, String> _resultHeaders;
  String _resultBody;

  List<int> _currentToken;
  String _currentHeaderKey;
  int _bodyBytesRemaining;

  final NULL = 0;
  final LF = 10;
  final CR = 13;
  final COLON = 58;

  Function(int) _parseByte;

  bool escapeHeaders = false;

//  String deserializeFrame(dynamic data) {
//    Frame deserializedFrame;
//    Uint8List byteList;
//    if (data is String) {
//      byteList = Uint8List.fromList(utf8.encode(data));
//    } else if (data is List<int>) {
//      byteList = Uint8List.fromList(data);
//    } else {
//      throw UnsupportedError('Input data type unsupported');
//    }
//
//    for (var i = 0; i < byteList.length; i++) {
//      _parseByte(byteList[i]);
//    }
//    //return des
//  }

  String _consumeTokenAsString() {
    final result = utf8.decode(_currentToken);
    _currentToken = [];
    return result;
  }

  void _consumeByte(int byte) {
    _currentToken.add(byte);
  }

  void _reinjectByte(int byte) {
    _parseByte(byte);
  }

  /// https://stomp.github.io/stomp-specification-1.2.html#Value_Encoding
  void _unescapeResultHeaders() {
    final unescapedHeaders = <String, String>{};
    _resultHeaders.forEach((key, value) {
      unescapedHeaders[_unescapeString(key)] = _unescapeString(value);
    });
    _resultHeaders = unescapedHeaders;
  }

  String _unescapeString(String input) {
    return input
        .replaceAll(RegExp(r'\\n'), '\n')
        .replaceAll(RegExp(r'\\r'), '\r')
        .replaceAll(RegExp(r'\\c'), ':')
        .replaceAll(RegExp(r'\\\\'), '\\');
  }

  /// Order of those replaceAll is important. The \\ replace should be first,
  /// otherwise it does also replace escaped \\n etc.
  String _escapeString(String input) {
    return input
        .replaceAll(RegExp(r'\\'), '\\\\')
        .replaceAll(RegExp(r'\n'), '\\n')
        .replaceAll(RegExp(r':'), '\\c')
        .replaceAll(RegExp(r'\r'), '\\r');
  }

  Map<String, String> _escapeHeaders(Map<String, String> headers) {
    final escapedHeaders = <String, String>{};
    headers?.forEach((key, value) {
      escapedHeaders[_escapeString(key)] = _escapeString(value);
    });
    return escapedHeaders;
  }

  /// We don't need to worry about reversing the header since we use a map and
  /// the last value written would just be the most up to date value, which is
  /// also fine with the spec
  /// https://stomp.github.io/stomp-specification-1.2.html#Repeated_Header_Entries
  dynamic serializeFrame(Frame frame) {
    final serializedHeaders = serializeCmdAndHeaders(frame) ?? '';

    if (frame.binaryBody != null) {
      final binaryList = Uint8List(
          serializedHeaders.codeUnits.length + 1 + frame.binaryBody.length);
      binaryList.setRange(
          0, serializedHeaders.codeUnits.length, serializedHeaders.codeUnits);
      binaryList.setRange(
          serializedHeaders.codeUnits.length,
          serializedHeaders.codeUnits.length + frame.binaryBody.length,
          frame.binaryBody);
      binaryList[serializedHeaders.codeUnits.length + frame.binaryBody.length] =
          NULL;
      return binaryList;
    } else {
      var serializedFrame = serializedHeaders;
      serializedFrame += frame.body ?? '';
      serializedFrame += String.fromCharCode(NULL);
      return serializedFrame;
    }
  }

  String serializeCmdAndHeaders(Frame frame) {
    var serializedFrame = frame.command;
    var headers = frame.headers ?? {};
    var bodyLength = 0;
    if (frame.binaryBody != null) {
      bodyLength = frame.binaryBody.length;
    } else if (frame.body != null) {
      bodyLength = utf8.encode(frame.body).length;
    }
    if (bodyLength > 0) {
      headers['content-length'] = bodyLength.toString();
    }
    if (escapeHeaders) {
      headers = _escapeHeaders(headers);
    }
    headers.forEach((key, value) {
      serializedFrame += String.fromCharCode(LF) + key + ':' + value;
    });

    serializedFrame += String.fromCharCode(LF) + String.fromCharCode(LF);

    return serializedFrame;
  }

  void _initState() {
    _resultCommand = null;
    _resultHeaders = {};
    _resultBody = null;

    _currentToken = [];
    _currentHeaderKey = null;
  }

  /**
   * Unmarshals a String of data containing one STOMP frame.
   */
  Frame deserializeFrame(String data) {
    /**
     * search for 2 consecutives LF byte to split the command
     * and headers from the body
     **/
    int divider = data.indexOf("\n\n");
    if (divider < 0) {
      throw new ArgumentError("The data is not a valid Frame.");
    }
    List<String> headerLines = data.substring(0, divider).split("\n");
    String command = headerLines.removeAt(0);
    Map<String, String> headers = {};

    /**
     * Parse headers in reverse order so that for repeated headers, the 1st
     * value is used
     **/
    for (String line in headerLines.reversed) {
      int idx = line.indexOf(":");
      headers[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
    }

    /**
     * Parse body
     * check for content-length or stop at the first NULL byte found.
     **/
    String body = "";
    // skip the 2 LF bytes that divides the headers from the body
    int start = divider + 2;
    if (headers.containsKey("content-length")) {
      int len = int.parse(headers["content-length"]);
      List<int> dataArray = utf8.encoder.convert(data.substring(start));
      body = utf8.decoder.convert(dataArray.sublist(0, len));
    } else {
      int chr = null;
      for (int i = start; i < data.length; i++) {
        chr = data.codeUnitAt(i);
        if (chr == 0) {
          break;
        }
        body += new String.fromCharCode(chr);
      }
    }
    return new Frame(command: command, headers: headers, body: body);
    //return new Frame(command, headers, body);
  }
}
