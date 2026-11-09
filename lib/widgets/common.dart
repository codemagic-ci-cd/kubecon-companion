import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/brand.dart';

/// Flat brand card: 20 radius, gradient fill (dark) or flat fill (light),
/// outer border only, no shadow.
class BrandCard extends StatelessWidget {
  const BrandCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      margin: margin,
      decoration: b.cardDecoration,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Brand.radiusCard),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Secondary action: subtle neutral fill (never outlined).
class SubtleButton extends StatelessWidget {
  const SubtleButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final style = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed)
            ? b.subtleHover
            : b.subtle,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? b.subtleText.withValues(alpha: 0.4)
            : b.subtleText,
      ),
      iconColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? b.subtleText.withValues(alpha: 0.4)
            : b.subtleText,
      ),
    );
    return icon == null
        ? FilledButton(onPressed: onPressed, style: style, child: Text(label))
        : FilledButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
  }
}

/// Primary action: solid brand blue.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => icon == null
      ? FilledButton(onPressed: onPressed, child: Text(label))
      : FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        );
}

class CodemagicLogo extends StatelessWidget {
  const CodemagicLogo({super.key, this.height = 20});
  final double height;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    context.brand.isDark
        ? 'assets/brand/logo-white.svg'
        : 'assets/brand/logo-blue.svg',
    height: height,
    semanticsLabel: 'Codemagic',
  );
}

/// Small rounded pill with text, used for type/track/level. Pass [onTap] to
/// make it a link.
class Pill extends StatelessWidget {
  const Pill(
    this.label, {
    super.key,
    this.color,
    this.icon,
    this.onTap,
    this.semanticLabel,
  });
  final String label;
  final Color? color;
  final IconData? icon;

  /// Makes the pill a link: a bit roomier, with a ripple, hover fill and a
  /// small trailing chevron. Leave null for purely informational pills.
  final VoidCallback? onTap;

  /// Screen reader label for a tappable pill, e.g. "Show all Talk sessions".
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final tappable = onTap != null;
    final bg = color ?? b.subtle;
    final fg = color == null ? b.heading : Colors.white;
    final radius = BorderRadius.circular(Brand.radiusPill);
    final pill = Material(
      color: bg,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        hoverColor: color == null ? b.subtleHover : null,
        child: Padding(
          padding: tappable
              ? const EdgeInsets.fromLTRB(12, 6, 8, 6)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: fg),
                ),
              ),
              if (tappable) ...[
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: color == null ? b.icon : fg,
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!tappable) return pill;
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: pill,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.padding});
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding ?? const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleSmall),
        ),
        ?trailing,
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Brand.neverBlue),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: 24), action!],
        ],
      ),
    ),
  );
}

/// Icon and accent color per session/happening kind.
IconData kindIcon(String kind) => switch (kind) {
  'keynote' => Icons.mic_none_rounded,
  'talk' => Icons.record_voice_over_outlined,
  'workshop' || 'tutorial' => Icons.build_outlined,
  'lightning' => Icons.bolt_outlined,
  'panel' => Icons.forum_outlined,
  'colocated' => Icons.hub_outlined,
  'break' => Icons.coffee_outlined,
  'meal' => Icons.restaurant_outlined,
  'social' => Icons.celebration_outlined,
  'party' => Icons.nightlife_outlined,
  'expo' => Icons.storefront_outlined,
  'registration' => Icons.badge_outlined,
  _ => Icons.event_outlined,
};

Color kindColor(String kind) => switch (kind) {
  'meal' => Brand.nativeOrange,
  'break' => Brand.swwYellow,
  'social' || 'party' => Brand.pinkMagic,
  'keynote' => Brand.neverBlue,
  'expo' => Brand.continuousBlue,
  _ => Brand.continuousBlue,
};

Future<void> openLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  final messenger = ScaffoldMessenger.maybeOf(context);
  var ok = false;
  if (uri != null) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok) {
    messenger?.showSnackBar(SnackBar(content: Text('Could not open $url')));
  }
}
