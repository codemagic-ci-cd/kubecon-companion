import 'package:flutter_test/flutter_test.dart';
import 'package:kubecon_companion/data/session_link.dart';
import 'package:kubecon_companion/widgets/link_router.dart';

void main() {
  test('session links point at the static share page and parse back', () {
    final link = sessionLink('1247970');
    expect(link, 'https://kubecon.codemagic.app/s/1247970.html');
    expect(sessionParamFrom(Uri.parse(link)), '1247970');
    final parsed = AppLink.parse(Uri.parse(link));
    expect(parsed, isA<SessionAppLink>());
    expect((parsed! as SessionAppLink).id, '1247970');
  });

  test('the forwarded ?session= form and extension-less paths parse too', () {
    expect(
      sessionParamFrom(Uri.parse('https://kubecon.codemagic.app/?session=t1')),
      't1',
    );
    expect(
      sessionParamFrom(Uri.parse('https://kubecon.codemagic.app/s/t1')),
      't1',
    );
  });

  test('other links are not sessions', () {
    for (final u in [
      'https://kubecon.codemagic.app/',
      'https://kubecon.codemagic.app/?session=',
      'https://kubecon.codemagic.app/get/index.html',
      'https://kubecon.codemagic.app/s/../x.html',
    ]) {
      expect(sessionParamFrom(Uri.parse(u)), isNull, reason: u);
    }
    expect(sessionParamFrom(null), isNull);
  });
}
