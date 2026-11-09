import 'package:flutter/material.dart';

import '../screens/settings_screen.dart';
import '../theme/brand.dart';
import 'common.dart';

/// "KubeCon Companion" with the Codemagic logo underneath.
class AppBarTitle extends StatelessWidget {
  const AppBarTitle({super.key, this.subtitle});
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(subtitle ?? 'KubeCon Companion'),
      const SizedBox(height: 4),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'by ',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.brand.body, height: 1),
          ),
          const CodemagicLogo(height: 13),
        ],
      ),
    ],
  );
}

class SettingsAction extends StatelessWidget {
  const SettingsAction({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Settings and about',
    icon: const Icon(Icons.settings_outlined),
    onPressed: () => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
  );
}
