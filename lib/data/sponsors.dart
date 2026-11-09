import 'models.dart';
import 'venue_time.dart';

/// Sponsor tiers in display order (assets/data/sponsors.json `tier`).
const sponsorTiers = [
  'Diamond',
  'Platinum',
  'Gold',
  'Silver',
  'Start-Up',
  'End User',
  'Media Partner',
];

/// Sort key for a tier; unknown tiers go last.
int tierRank(String tier) {
  final i = sponsorTiers.indexOf(tier);
  return i < 0 ? sponsorTiers.length : i;
}

String? _text(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// A sponsor or exhibitor from assets/data/sponsors.json.
class Sponsor {
  const Sponsor({
    required this.id,
    required this.name,
    required this.tier,
    this.booth,
    this.hall,
    this.roomId,
    this.website,
    this.description = '',
    this.tags = const [],
  });

  final String id;
  final String name;
  final String tier;

  /// As published, e.g. "115" or "145 + 151"; null when not listed.
  final String? booth;

  /// "Halls A-C" or "Halls 1-5".
  final String? hall;

  /// Venue room for the hall area, for "Show on map".
  final String? roomId;
  final String? website;
  final String description;
  final List<String> tags;

  /// Null without a name: such entries are skipped.
  static Sponsor? fromJson(Map<String, dynamic> j) {
    final name = _text(j['name']);
    if (name == null) return null;
    final tags = j['tags'];
    return Sponsor(
      id: _text(j['id']) ?? name.toLowerCase(),
      name: name,
      tier: _text(j['tier']) ?? 'Sponsor',
      booth: _text(j['booth']),
      hall: _text(j['hall']),
      roomId: _text(j['roomId']),
      website: _text(j['website']),
      description: _text(j['description']) ?? '',
      tags: tags is List
          ? tags.map(_text).whereType<String>().toList()
          : const [],
    );
  }

  /// Accepts `{"sponsors": [...]}` or a bare list; skips broken entries.
  /// Sorted by tier, then name.
  static List<Sponsor> listFromJson(Object? json) {
    final raw = json is List ? json : (json is Map ? json['sponsors'] : null);
    return (raw is List ? raw : const [])
        .whereType<Map>()
        .map((m) => Sponsor.fromJson(m.cast<String, dynamic>()))
        .whereType<Sponsor>()
        .toList()
      ..sort(bySponsorTier);
  }

  /// "Booth 115 · Halls A-C", "Booth 115", or null without a booth.
  String? get boothLabel {
    if (booth == null) return null;
    return ['Booth $booth', ?hall].join(' · ');
  }

  /// Booth numbers in [booth] ("145 + 151" -> 145, 151).
  List<String> get boothNumbers => booth == null
      ? const []
      : RegExp(r'[A-Za-z]?\d+').allMatches(booth!).map((m) => m[0]!).toList();
}

int bySponsorTier(Sponsor a, Sponsor b) {
  final c = tierRank(a.tier).compareTo(tierRank(b.tier));
  return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// How well a sponsor matches a search; higher is better, 0 is no match.
abstract final class SponsorMatch {
  static const none = 0;
  static const description = 1;
  static const tag = 2;
  static const booth = 3;
  static const name = 4;
  static const namePrefix = 5;
}

String _compact(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Scores [s] against [query]: name (also ignoring spaces and punctuation, so
/// "open ai" finds "OpenAI"), booth number ("115", "booth 115"), solution
/// category, then words in the description.
int sponsorMatch(Sponsor s, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return SponsorMatch.none;
  final name = s.name.toLowerCase();
  final cq = _compact(q);
  if (name.startsWith(q) || (cq.isNotEmpty && _compact(name).startsWith(cq))) {
    return SponsorMatch.namePrefix;
  }
  if (name.contains(q) || (cq.length > 2 && _compact(name).contains(cq))) {
    return SponsorMatch.name;
  }
  final boothQ = q.replaceFirst(RegExp(r'^(booth\s*|#)'), '');
  if (s.boothNumbers.any((b) => b.toLowerCase() == boothQ)) {
    return SponsorMatch.booth;
  }
  if (s.tags.any((t) => t.toLowerCase().contains(q))) return SponsorMatch.tag;
  // Descriptions are long: only match at word starts, and not for 1-2
  // letter queries, to keep results meaningful.
  if (q.length > 2 &&
      RegExp(r'(^|[^a-z0-9])' + RegExp.escape(q))
          .hasMatch(s.description.toLowerCase())) {
    return SponsorMatch.description;
  }
  return SponsorMatch.none;
}

/// Sponsors matching [query] (all when empty) in [tier] (all when null), in
/// tier then name order.
List<Sponsor> filterSponsors(
  List<Sponsor> sponsors,
  String query, {
  String? tier,
}) => [
  for (final s in sponsors)
    if ((tier == null || s.tier == tier) &&
        (query.trim().isEmpty || sponsorMatch(s, query) > 0))
      s,
];

/// Sponsors matching [query], best match first (then tier and name).
List<Sponsor> rankSponsors(List<Sponsor> sponsors, String query) {
  final scored = [
    for (final s in sponsors)
      if (sponsorMatch(s, query) case final m when m > 0) (s, m),
  ];
  scored.sort((a, b) {
    final c = b.$2.compareTo(a.$2);
    return c != 0 ? c : bySponsorTier(a.$1, b.$1);
  });
  return [for (final e in scored) e.$1];
}

/// True when [query] matches a sponsor by name or booth, the bar for showing
/// sponsors next to session results.
bool hasStrongSponsorMatch(List<Sponsor> sponsors, String query) =>
    sponsors.any((s) => sponsorMatch(s, query) >= SponsorMatch.booth);

bool _isShowcase(Happening h) =>
    h.kind == 'expo' && h.title.toLowerCase().contains('solutions showcase');

/// Solutions Showcase opening hours for the Expo header.
class ExpoHours {
  const ExpoHours({required this.title, this.detail, this.isOpen = false});
  final String title;
  final String? detail;
  final bool isOpen;
}

/// "Solutions Showcase open now until 5:15 PM", "... opens today 10:45 AM –
/// 5:15 PM", or the next day it opens. Null when there is nothing ahead.
ExpoHours? expoHours(List<Happening> happenings, DateTime now) {
  final slots =
      happenings.where(_isShowcase).where((h) => h.end.isAfter(now)).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  if (slots.isEmpty) return null;
  final h = slots.first;
  final detail = h.description.isEmpty ? null : h.description;
  if (!now.isBefore(h.start)) {
    return ExpoHours(
      title: 'Solutions Showcase open now until ${fmtTime(h.end)}',
      detail: detail,
      isOpen: true,
    );
  }
  final day = venueDay(h.start);
  final when = sameDay(day, venueDay(now)) ? 'today' : fmtDayShort(day);
  return ExpoHours(
    title: 'Solutions Showcase opens $when ${fmtRange(h.start, h.end)}',
    detail: detail,
  );
}
