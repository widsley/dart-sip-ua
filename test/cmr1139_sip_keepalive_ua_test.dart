// CMR-1139 x16: the UA pings slowly without calls, faster during a call, and
// every second right after a call's ICE goes `disconnected` (probe). An ICE
// restart is sent only once the SIP transport is connected and, when the UA
// registers, registered again. A UA without sipKeepalive never pings.

import 'package:test/test.dart';

import 'package:sip_ua/src/config.dart' as config;
import 'package:sip_ua/src/rtc_session.dart';
import 'package:sip_ua/src/sip_keepalive.dart';
import 'package:sip_ua/src/transport_type.dart';
import 'package:sip_ua/src/transports/socket_interface.dart';
import 'package:sip_ua/src/ua.dart';
import 'package:sip_ua/src/utils.dart' as utils;

const SipKeepalive _keepalive = SipKeepalive(
  idle: Duration(seconds: 15),
  inCall: Duration(seconds: 3),
  iceProbe: Duration(seconds: 1),
);

class _Socket implements SIPUASocketInterface {
  final List<Duration?> pings = <Duration?>[];
  final List<String> sent = <String>[];
  bool connected = false;

  @override
  void setPingInterval(Duration? interval) => pings.add(interval);
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
  void connect() {}
  @override
  void disconnect() {}
  @override
  bool send(dynamic message) {
    sent.add(message.toString());
    return true;
  }

  @override
  bool isConnected() => connected;
  @override
  bool isConnecting() => false;
  @override
  DateTime? get lastReceivedAt => null;
}

UA _ua(_Socket socket, {SipKeepalive? keepalive, bool register = true}) {
  final config.Settings settings = config.Settings()
    ..sockets = <SIPUASocketInterface>[socket]
    ..uri = utils.normalizeTarget('1003@sip.example.test')
    ..transportType = TransportType.WS
    ..password = 'secret'
    ..register = register
    ..sip_keepalive = keepalive;
  return UA(settings);
}

Iterable<Duration> _nonNull(List<Duration?> pings) =>
    pings.whereType<Duration>();

void main() {
  group('ping interval follows the calls', () {
    test('idle after start, in-call with a session, idle again after it', () {
      final _Socket socket = _Socket();
      final UA ua = _ua(socket, keepalive: _keepalive);
      ua.start();
      expect(socket.pings.last, const Duration(seconds: 15));

      final RTCSession session = RTCSession(ua);
      ua.newRTCSession(session: session);
      expect(socket.pings.last, const Duration(seconds: 3));

      ua.destroyRTCSession(session);
      expect(socket.pings.last, const Duration(seconds: 15));
    });

    test('a probe pings every second', () {
      final _Socket socket = _Socket();
      final UA ua = _ua(socket, keepalive: _keepalive);
      ua.start();
      ua.newRTCSession(session: RTCSession(ua));
      expect(ua.probeTransport(), isTrue);
      expect(socket.pings.last, const Duration(seconds: 1));
    });

    test('no probe after stop()', () {
      final _Socket socket = _Socket();
      final UA ua = _ua(socket, keepalive: _keepalive);
      ua.start();
      ua.stop();
      expect(ua.probeTransport(), isFalse);
    });

    test('without sipKeepalive nothing pings and there is no probe', () {
      final _Socket socket = _Socket();
      final UA ua = _ua(socket);
      ua.start();
      final RTCSession session = RTCSession(ua);
      ua.newRTCSession(session: session);
      expect(ua.probeTransport(), isFalse);
      ua.destroyRTCSession(session);
      expect(_nonNull(socket.pings), isEmpty);
    });
  });

  group('isTransportReady (ICE restart waits for it)', () {
    test('not before the transport connects', () {
      final _Socket socket = _Socket();
      final UA ua = _ua(socket, keepalive: _keepalive);
      ua.start();
      expect(ua.isTransportReady(), isFalse);
    });

    test('connected but REGISTER not answered yet: not ready', () {
      final _Socket socket = _Socket();
      final UA ua = _ua(socket, keepalive: _keepalive);
      ua.start();
      socket.connected = true;
      socket.onconnect!();
      expect(ua.isConnected(), isTrue);
      expect(socket.sent.single, startsWith('REGISTER '));
      expect(ua.isTransportReady(), isFalse);
    });

    test('a UA that does not register is ready once connected', () {
      final _Socket socket = _Socket();
      final UA ua = _ua(socket, keepalive: _keepalive, register: false);
      ua.start();
      socket.connected = true;
      socket.onconnect!();
      expect(socket.sent, isEmpty);
      expect(ua.isTransportReady(), isTrue);
    });
  });
}
