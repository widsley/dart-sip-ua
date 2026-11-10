// COM-130: behaviour of the settle-once gate behind _createLocalDescription.
// Import the pure helper directly (not the barrel) so `dart test` on the
// Dart VM does not pull in flutter_webrtc.

import 'package:test/test.dart';

import 'package:sip_ua/src/local_description_ready.dart';

const Duration _fallback = Duration(milliseconds: 20);
const Duration _afterFallback = Duration(milliseconds: 80);

void main() {
  late int settles;
  late int warnings;
  late bool canSettle;
  late LocalDescriptionSettler settler;

  setUp(() {
    settles = 0;
    warnings = 0;
    canSettle = true;
    settler = LocalDescriptionSettler(
      canSettle: () => canSettle,
      settle: () async => settles++,
      onFallback: () => warnings++,
      fallbackAfter: _fallback,
    );
  });

  test('gathering never completes: the fallback settles once and warns',
      () async {
    settler.armFallback();
    await Future<void>.delayed(_afterFallback);

    expect(settles, 1);
    expect(warnings, 1);
  });

  test('gathering settles first: settles once, the fallback does not warn',
      () async {
    settler.armFallback();
    await settler.ready();
    await Future<void>.delayed(_afterFallback);

    expect(settles, 1);
    expect(warnings, 0);
  });

  test('ready() after the fallback settled does nothing', () async {
    settler.armFallback();
    await Future<void>.delayed(_afterFallback);
    await settler.ready();

    expect(settles, 1);
    expect(warnings, 1);
  });

  test('ready() twice settles once', () async {
    await settler.ready();
    await settler.ready();

    expect(settles, 1);
    expect(warnings, 0);
  });

  test('description failed or session terminated: no settle, no warning',
      () async {
    canSettle = false;
    settler.armFallback();
    await Future<void>.delayed(_afterFallback);

    expect(settles, 0);
    expect(warnings, 0);
  });
}
