import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/brand.dart';
import 'common.dart';

/// One social/profile link ready for display.
@immutable
class SpeakerLink {
  const SpeakerLink({
    required this.kind,
    required this.label,
    required this.url,
    required this.icon,
  });

  /// x, github, linkedin, bluesky or website.
  final String kind;
  final String label;
  final String url;
  final IconData icon;
}

String? _handle(String? raw, List<String> hosts, {String? pathPrefix}) {
  if (raw == null) return null;
  var v = raw.trim();
  final uri = Uri.tryParse(v.contains('://') ? v : 'https://$v');
  if (uri != null && hosts.any((h) => uri.host.endsWith(h))) {
    var segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (pathPrefix != null && segs.isNotEmpty && segs.first == pathPrefix) {
      segs = segs.skip(1).toList();
    }
    v = segs.isEmpty ? '' : segs.first;
  }
  v = v.replaceFirst(RegExp(r'^@+'), '').trim();
  return RegExp(r'^[A-Za-z0-9_.\-]+$').hasMatch(v) ? v : null;
}

/// Only http(s) links are ever opened; bare domains get https://.
String? _webUrl(String? raw) {
  if (raw == null) return null;
  final v = raw.trim();
  final uri = Uri.tryParse(v.contains('://') ? v : 'https://$v');
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  return uri.toString();
}

String _hostLabel(String url) {
  final uri = Uri.parse(url);
  final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
  final path = uri.path == '/' ? '' : uri.path;
  final label = '$host$path';
  return label.length > 32 ? '${label.substring(0, 31)}…' : label;
}

/// Normalised links for a speaker, in display order, de-duplicated.
List<SpeakerLink> speakerLinks(Speaker p) {
  final l = p.links;
  final out = <SpeakerLink>[];
  final x = _handle(l.x, ['x.com', 'twitter.com']);
  if (x != null) {
    out.add(
      SpeakerLink(
        kind: 'x',
        label: '@$x',
        url: 'https://x.com/$x',
        icon: Icons.alternate_email,
      ),
    );
  }
  final gh = _handle(l.github, ['github.com']);
  if (gh != null) {
    out.add(
      SpeakerLink(
        kind: 'github',
        label: '@$gh',
        url: 'https://github.com/$gh',
        icon: Icons.code,
      ),
    );
  }
  final liRaw = l.linkedin;
  final liHandle = _handle(liRaw, const []);
  final li = liRaw == null
      ? null
      : liRaw.contains('linkedin.com')
      ? _webUrl(liRaw)
      : liHandle == null
      ? null
      : 'https://www.linkedin.com/in/$liHandle';
  if (li != null) {
    out.add(
      SpeakerLink(
        kind: 'linkedin',
        label: 'LinkedIn',
        url: li,
        icon: Icons.work_outline,
      ),
    );
  }
  final bs = _handle(l.bluesky, ['bsky.app'], pathPrefix: 'profile');
  if (bs != null) {
    out.add(
      SpeakerLink(
        kind: 'bluesky',
        label: '@$bs',
        url: 'https://bsky.app/profile/$bs',
        icon: Icons.cloud_outlined,
      ),
    );
  }
  final web = _webUrl(l.website);
  if (web != null && !out.any((e) => _same(e.url, web))) {
    out.add(
      SpeakerLink(
        kind: 'website',
        label: _hostLabel(web),
        url: web,
        icon: Icons.language,
      ),
    );
  }
  return out;
}

bool _same(String a, String b) {
  String n(String s) => s.toLowerCase().replaceFirst(RegExp(r'/+$'), '');
  return n(a) == n(b);
}

/// Handles (x, GitHub, Bluesky) for search, lower-cased, without '@'.
Iterable<String> speakerHandles(Speaker p) =>
    speakerLinks(p)
        .where((e) => e.label.startsWith('@'))
        .map((e) => e.label.substring(1).toLowerCase());

String speakerInitials(String name) => name
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .take(2)
    .map((w) => w[0].toUpperCase())
    .join();

/// Circular speaker photo, falling back to initials while loading or when
/// the image is missing or fails.
class SpeakerAvatar extends StatelessWidget {
  const SpeakerAvatar({super.key, required this.speaker, this.size = 56});
  final Speaker speaker;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = Container(
      key: const ValueKey('speaker-initials'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: Brand.blueGradient,
      ),
      child: Text(
        speakerInitials(speaker.name),
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: Colors.white),
      ),
    );
    final photo = speaker.photo;
    if (photo == null || _webUrl(photo) == null) return initials;
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return Semantics(
      label: 'Photo of ${speaker.name}',
      image: true,
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(
            photo,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: px,
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : initials,
            frameBuilder: (context, child, frame, sync) =>
                sync || frame != null ? child : initials,
            errorBuilder: (context, error, stack) => initials,
          ),
        ),
      ),
    );
  }
}

/// Speaker card: photo, name, title · company, expandable bio, link chips.
class SpeakerCard extends StatefulWidget {
  const SpeakerCard({super.key, required this.speaker});
  final Speaker speaker;

  @override
  State<SpeakerCard> createState() => _SpeakerCardState();
}

class _SpeakerCardState extends State<SpeakerCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.speaker;
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final bio = p.bio?.trim();
    final long = bio != null && bio.length > 200;
    final links = speakerLinks(p);
    final accent = b.isDark ? Brand.dashAqua : Brand.neverBlue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: BrandCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SpeakerAvatar(speaker: p),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: text.titleSmall),
                      if (p.role.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(p.role, style: text.bodySmall),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (bio != null && bio.isNotEmpty) ...[
              const SizedBox(height: 12),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: Text(
                  bio,
                  style: text.bodyMedium,
                  maxLines: _expanded || !long ? null : 3,
                  overflow: _expanded || !long ? null : TextOverflow.ellipsis,
                ),
              ),
              if (long)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: accent,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(_expanded ? 'Show less' : 'Read more'),
                  ),
                ),
            ],
            if (links.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final l in links) _LinkChip(link: l)],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const _kindNames = {
  'x': 'X',
  'github': 'GitHub',
  'linkedin': 'LinkedIn',
  'bluesky': 'Bluesky',
  'website': 'Website',
};

class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.link});
  final SpeakerLink link;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final kind = _kindNames[link.kind] ?? link.kind;
    // Prefix the network name for handle-style chips so "@foo" is unambiguous.
    final label = link.label.startsWith('@')
        ? '$kind ${link.label}'
        : link.label;
    return Semantics(
      link: true,
      child: Material(
        color: b.subtle,
        borderRadius: BorderRadius.circular(Brand.radiusSm),
        child: InkWell(
          key: ValueKey('speaker-link-${link.kind}'),
          borderRadius: BorderRadius.circular(Brand.radiusSm),
          hoverColor: b.subtleHover,
          onTap: () => openLink(context, link.url),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(link.icon, size: 16, color: b.icon),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge?.copyWith(color: b.subtleText),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
