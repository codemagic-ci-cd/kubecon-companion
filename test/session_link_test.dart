import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/session_link.dart';
import 'package:kubecon_companion/widgets/link_router.dart';

void main() {
  test('session links round-trip, including odd ids', () {
    for (final id in ['t1', 'abc 123', 'x&y=z']) {
      final link = sessionLink(id);
      expect(link, startsWith('https://kubecon.codemagic.app/?session='));
      expect(sessionParamFrom(Uri.parse(link)), id);
      final parsed = AppLink.parse(Uri.parse(link));
      expect(parsed, isA<SessionAppLink>());
      expect((parsed! as SessionAppLink).id, id);
    }
  });

  test('missing or empty session param is ignored', () {
    expect(
      sessionParamFrom(Uri.parse('https://kubecon.codemagic.app/')),
      isNull,
    );
    expect(
      sessionParamFrom(Uri.parse('https://kubecon.codemagic.app/?session=')),
      isNull,
    );
    expect(sessionParamFrom(null), isNull);
  });
}
