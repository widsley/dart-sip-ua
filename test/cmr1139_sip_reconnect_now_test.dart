// CMR-1139 x13: while a call's ICE restart waits for the SIP WebSocket, the
// transport can be asked to reconnect at once instead of waiting out the
// 2–30 s backoff. Nothing changes when it is connected, connecting, or closed
// on purpose.

import 'dart:io';

import 'package:test/test.dart';

import 'package:sip_ua/src/event_manager/events.dart';
import 'package:sip_ua/src/socket_transport.dart';
import 'package:sip_ua/src/transports/socket_interface.dart';

class FakeSocket implements SIPUASocketInterface {
  int connects = 0;

  /// Like SIPUAWebSocket: connect() first reports the previous socket closed,
  /// synchronously, while the new handshake is still running.
  bool reportsOldSocketClosedOnConnect = false;

  @override
  String? get url => 'wss://sip.example.test/ws';
  @override
  String? get sip_uri => 'sip:sip.example.test;transport=ws';
  @override
  String via_transport = 'WSS';
  @override
  int? get weight => 0;
  @override
  void Function()? onconnect;
  @override
  void Function(SIPUASocketInterface socket, bool error, int? closeCode,
      String? reason)? ondisconnect;
  @override
  void Function(dynamic data)? ondata;
  @override
  void connect() {
    connects++;
    if (reportsOldSocketClosedOnConnect && connects > 1) {
      ondisconnect!(this, false, 0, 'Client send disconnect');
    }
  }

  @override
  void disconnect() {}
  @override
  bool send(dynamic message) => true;
  @override
  bool isConnected() => false;
  @override
  bool isConnecting() => false;
  @override
  DateTime? get lastReceivedAt => null;
  @override
  void setPingInterval(Duration? interval) {}
}

SocketTransport _transport(FakeSocket socket) {
  final SocketTransport transport =
      SocketTransport(<SIPUASocketInterface>[socket]);
  transport.onconnecting = (SIPUASocketInterface? s, int? attempts) {};
  transport.onconnect = (SocketTransport t) {};
  transport.ondisconnect = (SIPUASocketInterface? s, ErrorCause cause) {};
  transport.ondata = (SocketTransport t, String data) {};
  return transport;
}

void main() {
  test('reconnects at once after the socket dropped, without the backoff', () {
    final FakeSocket socket = FakeSocket();
    final SocketTransport transport = _transport(socket);
    transport.connect();
    socket.onconnect!();
    socket.ondisconnect!(socket, true, 1006, 'gone');
    expect(transport.isConnected(), isFalse);
    expect(socket.connects, 1);

    expect(transport.reconnectNow(), isTrue);
    expect(socket.connects, 2);
    expect(transport.isConnecting(), isTrue);
  });

  test('stays connecting while the new handshake runs (no second socket)', () {
    final FakeSocket socket = FakeSocket()
      ..reportsOldSocketClosedOnConnect = true;
    final SocketTransport transport = _transport(socket);
    transport.connect();
    socket.onconnect!();
    socket.ondisconnect!(socket, true, 1006, 'gone');

    expect(transport.reconnectNow(), isTrue);
    expect(transport.isConnecting(), isTrue);
    expect(transport.reconnectNow(), isFalse);
    expect(socket.connects, 2);
  });

  test('a failed handshake lets the next request try again', () {
    final FakeSocket socket = FakeSocket()
      ..reportsOldSocketClosedOnConnect = true;
    final SocketTransport transport = _transport(socket);
    transport.connect();
    socket.onconnect!();
    socket.ondisconnect!(socket, true, 1006, 'gone');
    transport.reconnectNow();
    socket.ondisconnect!(socket, true, 500, 'handshake failed');

    expect(transport.reconnectNow(), isTrue);
    expect(socket.connects, 3);
  });

  test('does nothing while connected or connecting', () {
    final FakeSocket socket = FakeSocket();
    final SocketTransport transport = _transport(socket);
    transport.connect();
    expect(transport.reconnectNow(), isFalse, reason: 'connecting');
    socket.onconnect!();
    expect(transport.reconnectNow(), isFalse, reason: 'connected');
    expect(socket.connects, 1);
  });

  test('does nothing after the transport was closed on purpose', () {
    final FakeSocket socket = FakeSocket();
    final SocketTransport transport = _transport(socket);
    transport.connect();
    socket.onconnect!();
    transport.disconnect();
    expect(transport.reconnectNow(), isFalse);
    expect(socket.connects, 1);
  });

  test('UA: no reconnect after stop(), otherwise the transport decides', () {
    final String ua = File('lib/src/ua.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'\s+'), ' ');
    final int start = ua.indexOf('bool reconnectTransportNow() {');
    expect(start, isNonNegative);
    final String body =
        ua.substring(start, ua.indexOf('} bool isConnected()', start));
    expect(
        body,
        contains('if (_status == UAStatus.userClosed) { return false; } '
            'return _socketTransport?.reconnectNow() ?? false;'));
  });
}
