import 'package:flutter/material.dart';
import 'package:aveo_scanner/obd/pid.dart';

class GaugeTile extends StatelessWidget {
  const GaugeTile({
    super.key,
    required this.definition,
    required this.value,
    this.alert = false,
  });
  final PidDef definition;
  final double? value;
  final bool alert;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: MediaQuery.sizeOf(context).width > 700
        ? 250
        : (MediaQuery.sizeOf(context).width - 44) / 2,
    child: Card(
      color: alert ? Theme.of(context).colorScheme.error : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              definition.nameEs,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              value?.toStringAsFixed(definition.pid == 12 ? 0 : 1) ?? '—',
              style: Theme.of(context).textTheme.displayMedium
                  ?.copyWith(fontSize: 32),
            ),
            Text(definition.unit),
          ],
        ),
      ),
    ),
  );
}
