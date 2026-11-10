import 'dart:convert';
import 'dart:typed_data';

/// Public web app; shared agenda links open here.
const kAppBaseUrl = 'https://kubecon.codemagic.app/';

/// Query parameter that carries an encoded agenda.
const kAgendaParam = 'agenda';

/// Version prefix of the current payload format.
const kAgendaPrefix = 'a1.';

/// Longest id list we accept from a link, to keep a hostile link cheap.
const _maxIds = 2000;

/// Numeric ids below 2^49 are stored as numbers: 7 varint bytes, exact on
/// the web. (Not `1 << 49`: shifts are 32-bit when compiled to JavaScript.)
const _maxNumeric = 562949953421312;

final _numeric = RegExp(r'^[1-9]\d{0,14}$');
final _coNumeric = RegExp(r'^co-([1-9]\d{0,14})$');

/// `https://kubecon.codemagic.app/?agenda=a1.…` for [ids].
String agendaLink(Iterable<String> ids) =>
    '$kAppBaseUrl?$kAgendaParam=${encodeAgenda(ids)}';

/// Encodes session ids into a short URL-safe payload.
///
/// Format `a1.` + base64url (no padding) of three sections, each a varint
/// count followed by its items:
/// 1. Sessionize numeric ids, sorted, as varint deltas (first absolute);
/// 2. `co-<n>` ids, same encoding of `n`;
/// 3. any other id as varint UTF-8 length + bytes.
String encodeAgenda(Iterable<String> ids) {
  final main = <int>{};
  final co = <int>{};
  final other = <String>{};
  for (final id in ids) {
    final c = _coNumeric.firstMatch(id);
    final n = _numeric.hasMatch(id) ? int.parse(id) : null;
    final cn = c == null ? null : int.parse(c.group(1)!);
    if (n != null && n < _maxNumeric) {
      main.add(n);
    } else if (cn != null && cn < _maxNumeric) {
      co.add(cn);
    } else if (id.isNotEmpty) {
      other.add(id);
    }
  }
  final out = BytesBuilder(copy: false);
  void varint(int v) {
    while (v >= 0x80) {
      out.addByte((v & 0x7f) | 0x80);
      v = v ~/ 0x80;
    }
    out.addByte(v);
  }

  void deltas(Set<int> values) {
    final sorted = values.toList()..sort();
    varint(sorted.length);
    var prev = 0;
    for (final v in sorted) {
      varint(v - prev);
      prev = v;
    }
  }

  deltas(main);
  deltas(co);
  final rest = other.toList()..sort();
  varint(rest.length);
  for (final s in rest) {
    final bytes = utf8.encode(s);
    varint(bytes.length);
    out.add(bytes);
  }
  final b64 = base64Url.encode(out.takeBytes()).replaceAll('=', '');
  return '$kAgendaPrefix$b64';
}

/// Session ids in [payload], or null when it is not a valid agenda payload.
/// Never throws.
List<String>? decodeAgenda(String payload) {
  final p = payload.trim();
  if (!p.startsWith(kAgendaPrefix)) return null;
  final Uint8List bytes;
  try {
    bytes = base64Url.decode(base64Url.normalize(p.substring(3)));
  } catch (_) {
    return null;
  }
  var i = 0;
  int? varint() {
    var result = 0;
    var mul = 1;
    for (var n = 0; n < 7; n++) {
      if (i >= bytes.length) return null;
      final b = bytes[i++];
      result += (b & 0x7f) * mul;
      if (b < 0x80) return result;
      mul *= 0x80;
    }
    return null;
  }

  final ids = <String>[];
  // A missing trailing section counts as empty.
  bool numbers(String prefix) {
    if (i >= bytes.length) return true;
    final count = varint();
    if (count == null || count > _maxIds - ids.length) return false;
    var prev = 0;
    for (var k = 0; k < count; k++) {
      final d = varint();
      if (d == null || d == 0) return false;
      prev += d;
      if (prev >= _maxNumeric) return false;
      ids.add('$prefix$prev');
    }
    return true;
  }

  if (!numbers('') || !numbers('co-')) return null;
  if (i < bytes.length) {
    final count = varint();
    if (count == null || count > _maxIds - ids.length) return null;
    for (var k = 0; k < count; k++) {
      final len = varint();
      if (len == null || len == 0 || i + len > bytes.length) return null;
      try {
        ids.add(utf8.decode(bytes.sublist(i, i + len)));
      } catch (_) {
        return null;
      }
      i += len;
    }
  }
  return ids.toSet().toList();
}

/// The agenda payload in [input]: a full share link, a link without scheme,
/// or the bare `a1.…` payload. Null when there is none.
String? agendaPayloadFrom(String input) {
  final t = input.trim();
  if (t.isEmpty) return null;
  if (t.startsWith(kAgendaPrefix)) return t;
  final uri = Uri.tryParse(t.contains('://') ? t : 'https://$t');
  final v = uri?.queryParameters[kAgendaParam];
  return v == null || v.isEmpty ? null : v;
}

/// The agenda payload in scanned QR text, or null when the code is not a
/// valid agenda (a share link or a bare `a1.…` payload that decodes).
String? agendaPayloadFromQr(String? raw) {
  if (raw == null) return null;
  final payload = agendaPayloadFrom(raw);
  if (payload == null || decodeAgenda(payload) == null) return null;
  return payload;
}
