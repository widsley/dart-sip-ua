// CMR-1139 x9: guards that the standard policy (the old PBX path) keeps its
// ICE behaviour; x9 only adds log lines there. RTCSession needs a real peer
// connection, so these checks read the source, like the app's wiring tests.
// Whitespace is collapsed, so reformatting does not break them.
// The fast policy is covered by cmr1139_ice_recovery_test.dart.

import 'dart:io';

import 'package:test/test.dart';

String _squash(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

/// Body of the member starting at [signature], up to the next line that
/// closes a 2-space indented block, with whitespace collapsed.
String _body(String signature) {
  final String source = File('lib/src/rtc_session.dart').readAsStringSync();
  final int start = source.indexOf(signature);
  expect(start, isNonNegative, reason: signature);
  return _squash(source.substring(start, source.indexOf('\n  }\n', start)));
}

/// Position of [snippet] in [body] after [from], whitespace-insensitive.
int _at(String body, String snippet, [int from = 0]) =>
    body.indexOf(_squash(snippet), from);

void main() {
  test('only the fast policy creates a recovery controller', () {
    final String body = _body('IceRecoveryController? _createIceRecovery()');
    expect(_at(body, '''
    if (_ua.configuration.ice_recovery_policy != IceRecoveryPolicy.fast) {
      return null;
    }'''), isNonNegative);
  });

  test('without a controller every ICE state takes the standard branches', () {
    final String body = _body('Future<void> _createRTCConnection(');
    expect(_at(body, '''
      if (recovery != null && recoveryState != null) {
        recovery.onIceState(recoveryState);
        return;
      }'''), isNonNegative);
  });

  test('standard: one ICE restart 20 s after disconnected', () {
    final String body = _body('Future<void> _createRTCConnection(');
    final int timer = _at(
        body, '_iceDisconnectTimer = Timer(const Duration(seconds: 20), () {');
    expect(timer, isNonNegative);
    expect(_at(body, '_isAttemptingIceRestart = true; _iceRestart();', timer),
        greaterThan(timer));
  });

  test('standard: failed ends the call unless an audio interruption is on', () {
    final String body = _body('Future<void> _createRTCConnection(');
    final int failed = _at(body,
        'if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {');
    final int suppress = _at(
        body,
        'if (!shouldTeardownOnIceFailed(audioInterrupted: _audioInterrupted)) {',
        failed);
    final int terminate = _at(
        body,
        "terminate(<String, dynamic>{ 'cause': "
        'DartSIP_C.CausesType.RTP_TIMEOUT,',
        suppress);
    expect(failed, isNonNegative);
    expect(suppress, greaterThan(failed));
    expect(terminate, greaterThan(suppress));
  });

  test('standard: the restart re-INVITE is built as before', () {
    final String body = _body('void _iceRestart() async {');
    expect(_at(body, "offerConstraints['mandatory']['IceRestart'] = true;"),
        isNonNegative);
    expect(
        _at(body,
            'final bool started = renegotiate(options: offerConstraints);'),
        isNonNegative);
  });

  test('standard: an audio interruption still resumes with _iceRestart', () {
    final String body = _body('void setAudioInterrupted(');
    final int fast = _at(body, 'if (_iceRecovery != null) {');
    expect(fast, isNonNegative);
    expect(_at(body, '_isAttemptingIceRestart = true; _iceRestart();', fast),
        greaterThan(fast));
  });

  group('fast wiring', () {
    test('the controller restarts with the audio-only, copied constraints', () {
      final String body = _body('IceRecoveryController? _createIceRecovery()');
      for (final String part in <String>[
        'isSessionOver: isEnded,',
        'isAudioInterrupted: () => _audioInterrupted,',
        'isTransportConnected: () => _ua.isConnected(),',
        'sendIceRestart: () => renegotiate( '
            'options: iceRestartRenegotiateOptions(_rtcOfferConstraints)),',
        'endCall: _endCallForIceRecovery,',
      ]) {
        expect(_at(body, part), isNonNegative, reason: part);
      }
    });

    test('the transport end is a connection error, the others an RTP timeout',
        () {
      final String body = _body('void _endCallForIceRecovery(');
      for (final String part in <String>[
        'final bool transport = reason == IceRecoveryEnd.transportNotBack;',
        "'cause': transport ? DartSIP_C.CausesType.CONNECTION_ERROR "
            ': DartSIP_C.CausesType.RTP_TIMEOUT,',
        "'status_code': transport ? 500 : 408,",
      ]) {
        expect(_at(body, part), isNonNegative, reason: part);
      }
    });

    test('closing the session disposes the controller', () {
      final String source =
          _squash(File('lib/src/rtc_session.dart').readAsStringSync());
      expect(source,
          contains(_squash('_iceRecovery?.dispose(); _iceRecovery = null;')));
    });
  });
}
