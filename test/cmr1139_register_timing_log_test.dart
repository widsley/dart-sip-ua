// CMR-1139 x14: `[ICE]` lines with the time from the SIP socket connecting
// (again) to the first REGISTER after it, when it is sent and when it is
// answered. That REGISTER is what lets the PBX reach the phone again.
// Only the fast policy logs it; the clock is injected.

import 'dart:io';

import 'package:test/test.dart';

import 'package:sip_ua/src/ice_recovery.dart';

class _Clock {
  DateTime now = DateTime(2026, 11, 17, 12);
  void advance(int ms) => now = now.add(Duration(milliseconds: ms));
}

void main() {
  late _Clock clock;
  late List<String> logs;
  late RegisterAfterConnectLog log;

  setUp(() {
    clock = _Clock();
    logs = <String>[];
    log = RegisterAfterConnectLog(log: logs.add, now: () => clock.now);
  });

  test('logs when the first REGISTER after a connect is sent and answered', () {
    log.transportConnected();
    clock.advance(300);
    log.registerSent();
    clock.advance(220);
    log.registerAnswered(200);
    expect(logs, <String>[
      'REGISTER sent 300 ms after the SIP socket connected',
      'REGISTER answered 200, 520 ms after the SIP socket connected',
    ]);
  });

  test('later REGISTERs (refresh) are not logged until the next connect', () {
    log.transportConnected();
    log.registerSent();
    log.registerAnswered(200);
    logs.clear();
    clock.advance(60000);
    log.registerSent();
    log.registerAnswered(200);
    expect(logs, isEmpty);

    log.transportConnected();
    clock.advance(150);
    log.registerSent();
    expect(
        logs, <String>['REGISTER sent 150 ms after the SIP socket connected']);
  });

  test('nothing is logged before the socket has connected', () {
    log.registerSent();
    log.registerAnswered(200);
    log.registerFailed('timeout');
    expect(logs, isEmpty);
  });

  test('a REGISTER with no answer still has its own sent line', () {
    log.transportConnected();
    clock.advance(40);
    log.registerSent();
    clock.advance(20000);
    expect(
        logs, <String>['REGISTER sent 40 ms after the SIP socket connected']);
    expect(logs.where((String l) => l.contains('answered')), isEmpty);
  });

  test('a REGISTER that fails without an answer is logged with the reason', () {
    log.transportConnected();
    log.registerSent();
    clock.advance(32000);
    log.registerFailed('timeout');
    expect(logs.last,
        'REGISTER failed (timeout), 32000 ms after the SIP socket connected');
  });

  test('provisional answers are ignored', () {
    log.transportConnected();
    log.registerSent();
    clock.advance(100);
    log.registerAnswered(100);
    log.registerAnswered(180);
    clock.advance(100);
    log.registerAnswered(200);
    expect(logs.last,
        'REGISTER answered 200, 200 ms after the SIP socket connected');
    expect(logs, hasLength(2));
  });

  test('an error answer is logged with its code', () {
    log.transportConnected();
    log.registerSent();
    clock.advance(400);
    log.registerAnswered(403);
    expect(logs.last,
        'REGISTER answered 403, 400 ms after the SIP socket connected');
  });

  group('wiring (source checks; the UA needs a real transport)', () {
    String squash(String path) =>
        File(path).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

    test('only a fast UA creates the log, after the userClosed check', () {
      final String ua = squash('lib/src/ua.dart');
      final int connect = ua.indexOf('void onTransportConnect(');
      final int closed =
          ua.indexOf('if (_status == UAStatus.userClosed) {', connect);
      final int create =
          ua.indexOf('registerLog?.transportConnected();', connect);
      expect(
          ua,
          contains('late final RegisterAfterConnectLog? registerLog = '
              '_configuration.ice_recovery_policy == IceRecoveryPolicy.fast '
              '? RegisterAfterConnectLog() : null;'));
      expect(closed, greaterThan(connect));
      expect(create, greaterThan(closed));
      expect('RegisterAfterConnectLog()'.allMatches(ua).length, 1);
    });

    test('the registrator reports send, answer, timeout and transport error',
        () {
      final String reg = squash('lib/src/registrator.dart');
      for (final String call in <String>[
        "_ua.registerLog?.registerFailed('timeout');",
        "_ua.registerLog?.registerFailed('transport error');",
        '_ua.registerLog?.registerAnswered(int.tryParse(status_code) ?? 0);',
        '_ua.registerLog?.registerSent(); request_sender.send();',
      ]) {
        expect(reg, contains(call), reason: call);
      }
      expect('_ua.registerLog?.'.allMatches(reg).length, 4,
          reason: 'only the REGISTER path, null-safe (null on standard)');
    });
  });
}
