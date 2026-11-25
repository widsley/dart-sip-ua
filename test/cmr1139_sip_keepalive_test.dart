// CMR-1139 x16: a WebSocket ping finds a dead SIP connection after a network
// change (the socket stays "connected" until something is sent otherwise).
// Opt-in per UA (UaSettings.sipKeepalive); without it nothing pings.

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'package:sip_ua/src/config.dart' as config;
import 'package:sip_ua/src/event_manager/events.dart';
import 'package:sip_ua/src/sip_keepalive.dart';
import 'package:sip_ua/src/sip_ua_helper.dart';
import 'package:sip_ua/src/socket_transport.dart';
import 'package:sip_ua/src/transports/socket_interface.dart';
import 'package:sip_ua/src/transports/web_socket.dart';
import 'package:sip_ua/src/transports/websocket_dart_impl.dart';
import 'cmr1139_ice_recovery_test.dart' show FakeTimers;

const SipKeepalive _keepalive = SipKeepalive(
  idle: Duration(seconds: 15),
  inCall: Duration(seconds: 3),
  iceProbe: Duration(seconds: 1),
);

class _PingSocket implements SIPUASocketInterface {
  final List<Duration?> pings = <Duration?>[];
  int connects = 0;

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
  void connect() => connects++;
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
}

SocketTransport _transport(SIPUASocketInterface socket) {
  final SocketTransport transport =
      SocketTransport(<SIPUASocketInterface>[socket]);
  transport.onconnecting = (SIPUASocketInterface? s, int? attempts) {};
  transport.onconnect = (SocketTransport t) {};
  transport.ondisconnect = (SIPUASocketInterface? s, ErrorCause cause) {};
  transport.ondata = (SocketTransport t, String data) {};
  return transport;
}

/// A WebSocket server on localhost. With [answersPings] false it never reads
/// the connection, so pings get no pong, like a peer lost on another network.
Future<HttpServer> _server({required bool answersPings}) async {
  final HttpServer server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((HttpRequest request) async {
    final WebSocket ws = await WebSocketTransformer.upgrade(request);
    if (answersPings) {
      ws.listen((dynamic _) {});
    }
  });
  return server;
}

Future<int?> _closeCodeWithin(SIPUAWebSocketImpl impl, Duration limit) async {
  final Completer<int?> closed = Completer<int?>();
  impl.onClose = (int? code, String? reason) {
    if (!closed.isCompleted) closed.complete(code);
  };
  return closed.future.timeout(limit, onTimeout: () => -1);
}

void main() {
  group('SipKeepalive value equality (x16 review)', () {
    // The app compares UA settings by value to decide whether to start the UA
    // again; a keepalive built without const must not look like a change.
    SipKeepalive build(int idle) => SipKeepalive(
        idle: Duration(seconds: idle),
        inCall: Duration(seconds: idle ~/ 10),
        iceProbe: const Duration(seconds: 2));

    test('equal values are equal, with the same hash', () {
      final SipKeepalive a = build(30);
      final SipKeepalive b = build(30);
      expect(identical(a, b), isFalse);
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('any different interval is not equal', () {
      final SipKeepalive base = build(30);
      expect(base == build(20), isFalse);
      expect(
          base ==
              SipKeepalive(
                  idle: base.idle,
                  inCall: base.inCall,
                  iceProbe: const Duration(seconds: 1)),
          isFalse);
      expect(
          base ==
              SipKeepalive(
                  idle: base.idle,
                  inCall: const Duration(seconds: 1),
                  iceProbe: base.iceProbe),
          isFalse);
    });
  });

  group('sipPingInterval', () {
    test('idle without calls, in-call with a call, probe while probing', () {
      expect(sipPingInterval(_keepalive, hasCalls: false, probing: false),
          const Duration(seconds: 15));
      expect(sipPingInterval(_keepalive, hasCalls: true, probing: false),
          const Duration(seconds: 3));
      expect(sipPingInterval(_keepalive, hasCalls: true, probing: true),
          const Duration(seconds: 1));
      expect(sipPingInterval(_keepalive, hasCalls: false, probing: true),
          const Duration(seconds: 1));
    });
  });

  group('SipKeepaliveScheduler', () {
    late FakeTimers timers;
    late List<Duration?> applied;
    late SipKeepaliveScheduler scheduler;

    setUp(() {
      timers = FakeTimers();
      applied = <Duration?>[];
      scheduler = SipKeepaliveScheduler(_keepalive,
          apply: applied.add, startTimer: timers.timer);
    });

    test('applies the idle interval first, then follows the calls', () {
      scheduler.update(hasCalls: false);
      scheduler.update(hasCalls: true);
      scheduler.update(hasCalls: false);
      expect(applied, <Duration>[
        const Duration(seconds: 15),
        const Duration(seconds: 3),
        const Duration(seconds: 15),
      ]);
    });

    test('does not apply the same interval again (re-arming delays a check)',
        () {
      scheduler.update(hasCalls: true);
      scheduler.update(hasCalls: true);
      expect(applied, <Duration>[const Duration(seconds: 3)]);
    });

    test('a probe pings every second for the probe window, then goes back', () {
      scheduler.update(hasCalls: true);
      scheduler.probe();
      expect(applied.last, const Duration(seconds: 1));
      timers.elapse(sipKeepaliveProbeWindow - const Duration(milliseconds: 1));
      expect(applied.last, const Duration(seconds: 1));
      timers.elapse(const Duration(milliseconds: 1));
      expect(applied, <Duration>[
        const Duration(seconds: 3),
        const Duration(seconds: 1),
        const Duration(seconds: 3),
      ]);
    });

    test('a second probe extends the window without re-applying', () {
      scheduler.update(hasCalls: true);
      scheduler.probe();
      timers.elapse(const Duration(seconds: 3));
      scheduler.probe();
      timers.elapse(const Duration(seconds: 3));
      expect(applied.last, const Duration(seconds: 1));
      expect(applied.where((Duration? d) => d == const Duration(seconds: 1)),
          hasLength(1));
      timers.elapse(const Duration(seconds: 2));
      expect(applied.last, const Duration(seconds: 3));
    });

    test('stop cancels the probe window', () {
      scheduler.update(hasCalls: true);
      scheduler.probe();
      scheduler.stop();
      timers.elapse(const Duration(seconds: 10));
      expect(applied.last, const Duration(seconds: 1));
    });
  });

  group('SocketTransport', () {
    test('forwards the ping interval to the socket and again on connect', () {
      final _PingSocket socket = _PingSocket();
      final SocketTransport transport = _transport(socket);
      transport.setPingInterval(const Duration(seconds: 15));
      expect(socket.pings, <Duration?>[const Duration(seconds: 15)]);
      transport.connect();
      expect(socket.pings, <Duration?>[
        const Duration(seconds: 15),
        const Duration(seconds: 15)
      ]);
      expect(socket.connects, 1);
    });
  });

  group('settings', () {
    test('off unless set; copied into the UA configuration', () {
      expect(UaSettings().sipKeepalive, isNull);
      expect(config.Settings().sip_keepalive, isNull);
      final config.Settings src = config.Settings()..sip_keepalive = _keepalive;
      final config.Settings dst = config.Settings();
      expect(config.checks.optional.containsKey('sip_keepalive'), isTrue);
      config.checks.optional['sip_keepalive']!(src, dst);
      expect(dst.sip_keepalive, same(_keepalive));
    });

    test('SIPUAHelper.start copies UaSettings.sipKeepalive', () {
      final String helper = File('lib/src/sip_ua_helper.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(helper,
          contains('_settings.sip_keepalive = uaSettings.sipKeepalive;'));
    });
  });

  group('SIPUAWebSocketImpl (dart:io)', () {
    test('closes the socket when a ping gets no pong', () async {
      final HttpServer server = await _server(answersPings: false);
      addTearDown(() => server.close(force: true));
      final SIPUAWebSocketImpl impl =
          SIPUAWebSocketImpl('ws://127.0.0.1:${server.port}', 0);
      impl.setPingInterval(const Duration(milliseconds: 100));
      final Future<int?> closed =
          _closeCodeWithin(impl, const Duration(seconds: 3));
      impl.connect(webSocketSettings: WebSocketSettings());
      expect(await closed, WebSocketStatus.goingAway);
    });

    test('stays open while pongs come back', () async {
      final HttpServer server = await _server(answersPings: true);
      addTearDown(() => server.close(force: true));
      final SIPUAWebSocketImpl impl =
          SIPUAWebSocketImpl('ws://127.0.0.1:${server.port}', 0);
      impl.setPingInterval(const Duration(milliseconds: 100));
      final Future<int?> closed =
          _closeCodeWithin(impl, const Duration(milliseconds: 800));
      impl.connect(webSocketSettings: WebSocketSettings());
      expect(await closed, -1, reason: 'no close within 800 ms');
      impl.close();
    });

    test('an interval set after the socket opened applies at once', () async {
      final HttpServer server = await _server(answersPings: false);
      addTearDown(() => server.close(force: true));
      final SIPUAWebSocketImpl impl =
          SIPUAWebSocketImpl('ws://127.0.0.1:${server.port}', 0);
      final Completer<void> opened = Completer<void>();
      impl.onOpen = opened.complete;
      final Future<int?> closed =
          _closeCodeWithin(impl, const Duration(seconds: 3));
      impl.connect(webSocketSettings: WebSocketSettings());
      await opened.future;
      impl.setPingInterval(const Duration(milliseconds: 100));
      expect(await closed, WebSocketStatus.goingAway);
    });

    test('without an interval nothing pings (an unread peer stays open)',
        () async {
      final HttpServer server = await _server(answersPings: false);
      addTearDown(() => server.close(force: true));
      final SIPUAWebSocketImpl impl =
          SIPUAWebSocketImpl('ws://127.0.0.1:${server.port}', 0);
      final Future<int?> closed =
          _closeCodeWithin(impl, const Duration(milliseconds: 800));
      impl.connect(webSocketSettings: WebSocketSettings());
      expect(await closed, -1);
      impl.close();
    });
  });

  group('SIPUAWebSocket', () {
    test('an interval set before connect closes a socket that gets no pong',
        () async {
      final HttpServer server = await _server(answersPings: false);
      addTearDown(() => server.close(force: true));
      final SIPUAWebSocket socket =
          SIPUAWebSocket('ws://127.0.0.1:${server.port}', messageDelay: 0);
      final Completer<int?> closed = Completer<int?>();
      socket.onconnect = () {};
      socket.ondata = (dynamic _) {};
      socket.ondisconnect =
          (SIPUASocketInterface s, bool error, int? code, String? reason) {
        if (!closed.isCompleted) closed.complete(code);
      };
      socket.setPingInterval(const Duration(milliseconds: 100));
      socket.connect();
      expect(
          await closed.future
              .timeout(const Duration(seconds: 3), onTimeout: () => -1),
          WebSocketStatus.goingAway);
    });
  });
}
