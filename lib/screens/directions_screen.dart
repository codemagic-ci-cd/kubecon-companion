import 'package:flutter/material.dart';

import '../data/directions.dart';
import '../state/app_scope.dart';
import '../theme/brand.dart';
import '../widgets/common.dart';
import '../services/location_service.dart';
import 'map_directions.dart';
import 'outdoor_directions.dart';
import '../outdoor/outdoor_loader.dart';

IconData stepIcon(StepKind kind) => switch (kind) {
  StepKind.start => Icons.door_front_door_outlined,
  StepKind.escalator => Icons.escalator,
  StepKind.elevator => Icons.elevator_outlined,
  StepKind.stairs => Icons.stairs_outlined,
  StepKind.levelChange => Icons.swap_vert,
  StepKind.arrive => Icons.flag_outlined,
  StepKind.walk => Icons.straight,
  StepKind.note => Icons.lightbulb_outline,
};

/// Step-by-step directions to a room or an off-site venue.
class DirectionsScreen extends StatelessWidget {
  const DirectionsScreen({
    super.key,
    required this.roomId,
    this.locate = currentLocation,
    this.positions = locationStream,
    this.permitted = hasLocationPermission,
    this.outdoorLoader = loadOutdoorMap,
  });
  final String roomId;

  /// Device location lookup (injectable for tests).
  final LocationProvider locate;

  /// Live positions for off-site walking directions (injectable for tests).
  final LocationStreamProvider positions;

  /// Permission check without a prompt, for the live dot on the venue map.
  final LocationPermissionCheck permitted;

  /// Loads the street map for off-site venues (injectable for tests).
  final OutdoorLoader outdoorLoader;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final loc = app.data.locate(roomId);
    final map = app.data.officialMap;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          loc is RoomLocation
              ? 'To ${shortRoomLabel(loc.room.name)}'
              : 'Directions',
        ),
      ),
      body: switch (loc) {
        RoomLocation l
            when map != null &&
                map.doorFor(l.room.id, partOf: l.room.partOf) != null =>
          MapDirections(
            map: map,
            room: l.room,
            levelLabel: l.levelLabel,
            locate: locate,
            positions: positions,
            permitted: permitted,
          ),
        RoomLocation l => _TextDirections(location: l),
        OffsiteLocation o => OffsiteDirections(
          venue: o.venue,
          locate: locate,
          positions: positions,
          loader: outdoorLoader,
        ),
        UnknownLocation u => EmptyState(
          icon: Icons.not_listed_location_outlined,
          title: u.label,
          message: 'This location is not on our venue map yet. Ask at any Info Desk or follow onsite signage.',
        ),
      },
    );
  }
}

/// Text-only directions from venue.json for rooms we have not placed on the
/// official map.
class _TextDirections extends StatelessWidget {
  const _TextDirections({required this.location});
  final RoomLocation location;

  @override
  Widget build(BuildContext context) {
    final room = location.room;
    final steps = buildSteps(room.directions);
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        Text(room.name, style: text.headlineSmall),
        const SizedBox(height: 4),
        Text(
          [
            room.building,
            location.levelLabel,
          ].whereType<String>().toSet().join(' · '),
          style: text.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (steps.isEmpty)
          Text(
            'No step-by-step directions for this room yet. Follow onsite signage or ask at any Info Desk.',
            style: text.bodyMedium,
          )
        else
          StepList(steps: steps),
      ],
    );
  }
}

/// Numbered steps; level changes are shown in a highlighted card with an
/// escalator/elevator/stairs icon.
class StepList extends StatelessWidget {
  const StepList({super.key, required this.steps});
  final List<DirectionStep> steps;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _StepRow(
            number: steps
                .take(i + 1)
                .where((s) => s.kind != StepKind.note)
                .length,
            step: steps[i],
            isLast: i == steps.length - 1,
            text: text,
            surfaces: b,
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.step,
    required this.isLast,
    required this.text,
    required this.surfaces,
  });

  final int number;
  final DirectionStep step;
  final bool isLast;
  final TextTheme text;
  final BrandSurfaces surfaces;

  @override
  Widget build(BuildContext context) {
    final change = step.isLevelChange;
    final arrive = step.kind == StepKind.arrive;
    final note = step.kind == StepKind.note;
    final badgeColor = change
        ? Brand.swwYellow
        : (arrive ? Brand.neverBlue : surfaces.subtle);
    final badgeFg = change
        ? Brand.darkPage
        : (arrive ? Colors.white : surfaces.heading);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (change)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(stepIcon(step.kind), size: 18, color: Brand.swwYellow),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    step.toLevel != null
                        ? 'Change level · to level ${step.toLevel}'
                        : 'Change level',
                    style: text.labelLarge?.copyWith(color: Brand.swwYellow),
                  ),
                ),
              ],
            ),
          ),
        Text(
          step.text,
          style:
              (change || arrive
                      ? text.bodyLarge
                      : (note ? text.bodySmall : text.bodyMedium))
                  ?.copyWith(color: change || arrive ? surfaces.heading : null),
        ),
      ],
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                  ),
                  child: change || arrive || note
                      ? Icon(stepIcon(step.kind), size: 18, color: badgeFg)
                      : Text(
                          '$number',
                          style: text.labelLarge?.copyWith(color: badgeFg),
                        ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: surfaces.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: change
                  ? Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: surfaces.subtle,
                        borderRadius: BorderRadius.circular(Brand.radiusMd),
                      ),
                      child: body,
                    )
                  : Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: body,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
