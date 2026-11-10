import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../data/sponsors.dart';
import '../data/spot_link.dart';
import '../location/spot_place.dart';
import '../outdoor/outdoor_loader.dart';
import '../outdoor/outdoor_nav.dart';
import '../screens/directions_screen.dart';
import '../screens/outdoor_directions.dart';
import '../services/location_service.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../theme/brand.dart';
import 'agenda_share.dart' show CopyLinkButton, LinkQr;
import 'common.dart';

/// A room or sponsor booth picked as the spot.
class SpotPick {
  const SpotPick({required this.roomId, required this.label, this.note});
  final String roomId;

  /// "Hall A-C", "Codemagic · Booth 115 · Halls A-C".
  final String label;

  /// Suggested note ("at the Codemagic booth") when picked from a booth.
  final String? note;
}

enum _SpotMode { location, room }

/// "Share my spot": name, where (GPS or a room / booth), an optional note,
/// then a link + QR that pins it on the other person's map.
class SpotShareSheet extends StatefulWidget {
  const SpotShareSheet({super.key, required this.locate, this.lastFix});

  /// Asks for permission and a fix (injectable for tests).
  final LocationProvider locate;

  /// A fix the Map tab already has, used instead of asking again.
  final LocationFix? lastFix;

  static Future<void> show(
    BuildContext context, {
    required LocationProvider locate,
    LocationFix? lastFix,
  }) {
    final app = AppScope.read(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AppScope(
        state: app,
        child: SpotShareSheet(locate: locate, lastFix: lastFix),
      ),
    );
  }

  @override
  State<SpotShareSheet> createState() => _SpotShareSheetState();
}

class _SpotShareSheetState extends State<SpotShareSheet> {
  late final AppState _app = AppScope.read(context);
  late final _name = TextEditingController(text: _app.spotName);
  final _note = TextEditingController();
  _SpotMode _mode = _SpotMode.location;
  LocationFix? _fix;
  bool _locating = false;
  String? _locationError;
  SpotPick? _pick;

  @override
  void initState() {
    super.initState();
    _fix = widget.lastFix;
    _name.addListener(_changed);
    _note.addListener(_changed);
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  Future<void> _useLocation() async {
    setState(() {
      _mode = _SpotMode.location;
      _locating = true;
      _locationError = null;
    });
    LocationResult res;
    try {
      res = await widget.locate();
    } catch (_) {
      res = const LocationFailure('Could not get your location.');
    }
    if (!mounted) return;
    setState(() {
      _locating = false;
      switch (res) {
        case LocationFix f:
          _fix = f;
        case LocationFailure f:
          _locationError = f.message.replaceFirst(
            RegExp(r'\s*Pick a start point instead\.?$'),
            ' Pick a room or booth instead.',
          );
      }
    });
  }

  Future<void> _pickRoom() async {
    final pick = await showSearch<SpotPick?>(
      context: context,
      delegate: SpotPlaceSearchDelegate(_app.data.venue, _app.sponsors),
    );
    if (pick == null || !mounted) return;
    setState(() {
      _mode = _SpotMode.room;
      _pick = pick;
      if (_note.text.trim().isEmpty && pick.note != null) {
        _note.text = pick.note!;
      }
    });
  }

  /// The spot as it would be shared now, or null while incomplete.
  SharedSpot? get _spot {
    final name = _name.text.trim();
    if (name.isEmpty) return null;
    final now = _app.now;
    switch (_mode) {
      case _SpotMode.location:
        final f = _fix;
        if (f == null) return null;
        return SharedSpot(
          name: name,
          lat: f.lat,
          lng: f.lng,
          note: _note.text,
          time: now,
        );
      case _SpotMode.room:
        final p = _pick;
        if (p == null) return null;
        return SharedSpot(
          name: name,
          roomId: p.roomId,
          note: _note.text,
          time: now,
        );
    }
  }

  String _where(SharedSpot? spot) {
    if (_mode == _SpotMode.room) return _pick?.label ?? '';
    final f = _fix;
    if (f == null) return '';
    final p = placeSpot(
      _app.data,
      SharedSpot(name: 'x', lat: f.lat, lng: f.lng, time: _app.now),
    );
    if (p.offVenue) {
      return p.metresAway > 0
          ? 'About ${p.awayLabel} from the venue'
          : 'Your location';
    }
    return [
      if (p.place != null) 'Near ${p.place}',
      'level unknown',
      '±${f.accuracy.round()} m',
    ].join(' · ');
  }

  Future<void> _share(BuildContext btnContext, SharedSpot spot) async {
    _app.spotName = spot.name;
    final link = spotLink(spot);
    final box = btnContext.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: [
            '${spot.name} is here',
            ?spot.note,
            'Open to see it on the KubeCon Companion map: $link',
          ].join(' · '),
          subject: 'Find me at KubeCon',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final ok = await _copy(link);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Link copied' : "Sharing isn't available on this device",
          ),
        ),
      );
    }
  }

  Future<bool> _copy(String link) async {
    _app.spotName = _name.text;
    try {
      await Clipboard.setData(ClipboardData(text: link));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final spot = _spot;
    final link = spot == null ? null : spotLink(spot);
    final where = _where(spot);
    final qrSize = (MediaQuery.sizeOf(context).width - 128).clamp(160.0, 240.0);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Share my spot',
                style: text.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Send a link that pins where you are on their venue map.',
                style: text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('spot-name'),
                controller: _name,
                maxLength: kSpotNameMax,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ModeButton(
                      selected: _mode == _SpotMode.location,
                      icon: Icons.my_location,
                      label: 'Use my location',
                      onPressed: _locating ? null : _useLocation,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ModeButton(
                      selected: _mode == _SpotMode.room,
                      icon: Icons.meeting_room_outlined,
                      label: 'Pick a room / booth',
                      onPressed: _pickRoom,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_mode == _SpotMode.location && _locating)
                Text('Finding you…', style: text.bodySmall)
              else if (_mode == _SpotMode.location && _locationError != null)
                Text(_locationError!, style: text.bodySmall)
              else if (where.isNotEmpty)
                Row(
                  children: [
                    Icon(
                      _mode == _SpotMode.room
                          ? Icons.meeting_room_outlined
                          : Icons.my_location,
                      size: 16,
                      color: Brand.swwYellow,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        where,
                        key: const ValueKey('spot-where'),
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  _mode == _SpotMode.location
                      ? 'Tap "Use my location" or pick a room.'
                      : 'Pick a room or booth.',
                  style: text.bodySmall,
                ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('spot-note'),
                controller: _note,
                maxLength: kSpotNoteMax,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'at the Codemagic booth',
                  counterText: '',
                ),
              ),
              if (link != null && spot != null) ...[
                const SizedBox(height: 20),
                Center(
                  child: LinkQr(
                    key: const ValueKey('spot-qr'),
                    data: link,
                    size: qrSize,
                    label: 'QR code for your spot link',
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  link,
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: CopyLinkButton(onCopy: () => _copy(link))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Builder(
                        builder: (btnContext) => PrimaryButton(
                          icon: Icons.ios_share,
                          label: 'Share',
                          onPressed: () => _share(btnContext, spot),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (_name.text.trim().isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Add your name to get a link.',
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the two "where" choices: primary when selected, subtle otherwise.
class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => selected
      ? PrimaryButton(icon: icon, label: label, onPressed: onPressed)
      : SubtleButton(icon: icon, label: label, onPressed: onPressed);
}

/// Rooms and sponsor booths (a booth resolves to its hall's room).
class SpotPlaceSearchDelegate extends SearchDelegate<SpotPick?> {
  SpotPlaceSearchDelegate(this.venue, this.sponsors)
    : super(searchFieldLabel: 'Room, hall or sponsor');

  final Venue venue;
  final List<Sponsor> sponsors;

  @override
  ThemeData appBarTheme(BuildContext context) {
    final t = Theme.of(context);
    return t.copyWith(
      inputDecorationTheme: t.inputDecorationTheme.copyWith(
        filled: false,
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: 'Clear',
        icon: const Icon(Icons.close),
        onPressed: () => query = '',
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    tooltip: 'Back',
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  List<(IconData, String, String?, SpotPick)> _results() =>
      spotPlaceResults(venue, sponsors, query);

  Widget _list(BuildContext context) {
    final rows = _results();
    if (rows.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: 'Nothing found',
        message: 'Try a room number like 250, a hall, or a sponsor name.',
      );
    }
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final (icon, title, subtitle, pick) = rows[i];
        return ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          onTap: () => close(context, pick),
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) => _list(context);

  @override
  Widget buildSuggestions(BuildContext context) => _list(context);
}

/// Search rows for [SpotPlaceSearchDelegate]: matching rooms, then sponsors
/// with a booth in a known hall room (best match first). With an empty
/// query, all rooms.
List<(IconData, String, String?, SpotPick)> spotPlaceResults(
  Venue venue,
  List<Sponsor> sponsors,
  String query,
) {
  final q = query.trim().toLowerCase();
  final rows = <(IconData, String, String?, SpotPick)>[];
  for (final r in venue.rooms) {
    if (q.isNotEmpty &&
        !r.name.toLowerCase().contains(q) &&
        !r.aliases.any((a) => a.toLowerCase().contains(q))) {
      continue;
    }
    rows.add((
      Icons.meeting_room_outlined,
      r.name,
      venue.level(r.levelId)?.name,
      SpotPick(roomId: r.id, label: r.name),
    ));
  }
  if (q.isEmpty) return rows;
  for (final s in rankSponsors(sponsors, q)) {
    final room = venue.room(s.roomId);
    if (room == null) continue;
    final booth = s.boothLabel ?? room.name;
    rows.add((
      Icons.storefront_outlined,
      s.name,
      booth,
      SpotPick(
        roomId: room.id,
        label: '${s.name} · $booth',
        note: 'at the ${s.name} booth',
      ),
    ));
  }
  return rows;
}

/// "Alex is here · near Hall A-C · shared 12 min ago", the note, a warning
/// when it is old, and Directions.
class SpotCard extends StatelessWidget {
  const SpotCard({
    super.key,
    required this.placement,
    required this.now,
    required this.onDirections,
    required this.onClose,
    this.onTap,
  });

  final SpotPlacement placement;
  final DateTime now;
  final VoidCallback onDirections;
  final VoidCallback onClose;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final p = placement;
    final s = p.spot;
    final age = 'shared ${fmtSpotAge(s.age(now))}';
    final label = p.offVenue
        ? [
            if (p.metresAway > 0)
              '${s.name} is about ${p.awayLabel} from the venue'
            else
              '${s.name} is here',
            age,
          ].join(' · ')
        : [
            '${s.name} is here',
            if (p.place != null) 'near ${p.place}',
            age,
          ].join(' · ');
    return Material(
      color: b.isDark ? Brand.darkSubtle : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radiusMd),
        side: BorderSide(color: b.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Brand.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Icon(
                      Icons.person_pin_circle,
                      size: 20,
                      color: Brand.swwYellow,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        label,
                        key: const ValueKey('spot-card-label'),
                        style: text.labelLarge?.copyWith(color: b.heading),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove pin',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: onClose,
                  ),
                ],
              ),
              if (s.note != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 2, 8, 0),
                  child: Text(s.note!, style: text.bodySmall),
                ),
              if (s.isStale(now))
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 6, 8, 0),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 16,
                        color: Brand.swwYellow,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Shared over 2 hours ago. They may have moved on.',
                          style: text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 28, right: 8),
                child: PrimaryButton(
                  icon: Icons.directions,
                  label: 'Directions',
                  onPressed: onDirections,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Google Maps walking directions to a coordinate.
String walkingDirectionsToUrl(double lat, double lng) =>
    'https://www.google.com/maps/dir/?api=1'
    '&destination=$lat,$lng&travelmode=walking';

/// Directions to a shared spot: indoor route to its room (or the room
/// nearest the GPS position); a GPS spot off the venue gets walking
/// directions on our street map when it covers it, else the maps app.
Future<void> openSpotDirections(
  BuildContext context,
  SpotPlacement p, {
  LocationProvider locate = currentLocation,
  LocationStreamProvider positions = locationStream,
  OutdoorLoader outdoorLoader = loadOutdoorMap,
  Future<void> Function(BuildContext context, String url) open = openLink,
}) async {
  final s = p.spot;
  final room = p.targetRoomId;
  if (!p.offVenue && room != null) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DirectionsScreen(
          roomId: room,
          locate: locate,
          positions: positions,
          outdoorLoader: outdoorLoader,
        ),
      ),
    );
    return;
  }
  if (!s.hasGeo) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text("That room isn't on the venue map.")),
    );
    return;
  }
  final lat = s.lat!, lng = s.lng!;
  final map = await outdoorLoader(DefaultAssetBundle.of(context));
  if (!context.mounted) return;
  final venue = OffsiteVenue(
    id: 'shared-spot',
    name: "${s.name}'s spot",
    address: s.note,
    lat: lat,
    lng: lng,
  );
  final covered =
      map != null &&
      resolveTarget(map, id: venue.id, name: venue.name, lat: lat, lng: lng) !=
          null;
  if (!covered) {
    await open(context, walkingDirectionsToUrl(lat, lng));
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text('To ${s.name}')),
        body: OffsiteDirections(
          venue: venue,
          locate: locate,
          positions: positions,
          loader: outdoorLoader,
        ),
      ),
    ),
  );
}
