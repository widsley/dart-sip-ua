// CMR-1269: which binding of a REGISTER 200 OK is ours. After the transport
// reconnects, the same UA registers again from a new connection while the old
// (dead) binding has not expired yet, so two entries share our user part.
// Import the helper directly (not the barrel) so `dart test` on the Dart VM
// does not pull in flutter_webrtc.

import 'dart:io';

import 'package:test/test.dart';

import 'package:sip_ua/src/grammar.dart';
import 'package:sip_ua/src/own_binding.dart';

/// Contact entries as the parser stores them in a response: raw + parsed.
List<dynamic> entries(List<String> raws) => raws
    .expand((String raw) => Grammar.parse(raw, 'Contact') as List<dynamic>)
    .toList();

void main() {
  const String own = 'tok1';

  group('pickOwnBinding', () {
    test(
      'two bindings with our user part: the one with the longest expiry',
      () {
        expect(
          pickOwnBinding(
              entries(<String>[
                '<sip:tok1@127.0.0.1:53356;transport=WS>;expires=200',
                '<sip:tok1@127.0.0.1:53852;transport=WS>;expires=599',
              ]),
              own),
          '<sip:tok1@127.0.0.1:53852;transport=WS>;expires=599',
        );
      },
    );

    test('order does not matter', () {
      expect(
        pickOwnBinding(
            entries(<String>[
              '<sip:tok1@127.0.0.1:53852;transport=WS>;expires=599',
              '<sip:tok1@127.0.0.1:53356;transport=WS>;expires=200',
            ]),
            own),
        '<sip:tok1@127.0.0.1:53852;transport=WS>;expires=599',
      );
    });

    test('a single binding of ours is used as it is', () {
      expect(
        pickOwnBinding(
            entries(<String>[
              '<sip:other@127.0.0.1:50000;transport=WS>;expires=599',
              '<sip:tok1@127.0.0.1:53356;transport=WS>;expires=120',
            ]),
            own),
        '<sip:tok1@127.0.0.1:53356;transport=WS>;expires=120',
      );
    });

    test('another UA with a longer expiry is never picked', () {
      expect(
        pickOwnBinding(
            entries(<String>[
              '<sip:tok1@127.0.0.1:53356;transport=WS>;expires=100',
              '<sip:other@127.0.0.1:50000;transport=WS>;expires=599',
            ]),
            own),
        '<sip:tok1@127.0.0.1:53356;transport=WS>;expires=100',
      );
    });

    test('same expiry: the first one, as before', () {
      expect(
        pickOwnBinding(
            entries(<String>[
              '<sip:tok1@127.0.0.1:1;transport=WS>;expires=599',
              '<sip:tok1@127.0.0.1:2;transport=WS>;expires=599',
            ]),
            own),
        '<sip:tok1@127.0.0.1:1;transport=WS>;expires=599',
      );
    });

    test('no expires parameter still counts as ours', () {
      expect(
        pickOwnBinding(
            entries(<String>['<sip:tok1@127.0.0.1:1;transport=WS>']), own),
        '<sip:tok1@127.0.0.1:1;transport=WS>',
      );
    });

    test('a token inside another parameter is not a match', () {
      expect(
        pickOwnBinding(
            entries(<String>[
              '<sip:other@127.0.0.1:1;transport=WS;x=tok1>;expires=599',
            ]),
            own),
        isNull,
      );
    });

    test(
      'nothing of ours: null (the caller falls back to the first entry)',
      () {
        expect(
          pickOwnBinding(
              entries(<String>[
                '<sip:other@127.0.0.1:1;transport=WS>;expires=599',
              ]),
              own),
          isNull,
        );
      },
    );
  });

  group('UA.registered uses the helper', () {
    final String source = File('lib/src/ua.dart').readAsStringSync();

    test('our binding is picked from the parsed Contact entries', () {
      expect(
        RegExp(r'contact\s*=\s*pickOwnBinding\(\s*contacts\s*,\s*ownUser\s*\)')
            .allMatches(source)
            .length,
        1,
      );
    });
  });
}
