import 'package:flutter_test/flutter_test.dart';
import 'package:termux_ai/agent/remote/remote_agent_session.dart';

void main() {
  group('cleanPtyText', () {
    test('strips kitty keyboard protocol 7u', () {
      final raw = '\x1b[?7u';
      expect(cleanPtyText(raw).trim(), isEmpty);
    });

    test('strips CSI and keeps real text', () {
      final raw = '\x1b[32mHello\x1b[0m world';
      expect(cleanPtyText(raw), contains('Hello'));
      expect(cleanPtyText(raw), contains('world'));
      expect(cleanPtyText(raw), isNot(contains('\x1b')));
    });

    test('strips orphan 7u tokens', () {
      expect(cleanPtyText('7u'), isEmpty);
      expect(cleanPtyText('ok 7u done'), contains('ok'));
      expect(cleanPtyText('ok 7u done'), contains('done'));
    });

    test('keeps normal prose', () {
      const s = 'You are on Debian 12. How can I help?';
      expect(cleanPtyText(s), s);
    });
  });
}
