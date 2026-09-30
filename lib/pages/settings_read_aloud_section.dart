import 'package:flutter/material.dart';

import '../widgets/read_aloud_panel.dart';

/// 设置页「朗读」分区：直接复用阅读器内的同一套设置面板。
class SettingsReadAloudSection extends StatelessWidget {
  const SettingsReadAloudSection({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          '朗读',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: ReadAloudSettingsPanel(),
      ),
    ],
  );
}
