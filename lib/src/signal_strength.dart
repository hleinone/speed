import 'package:flutter/material.dart';

class SignalStrength extends StatelessWidget {
  /// Signal quality value, between 0.0 (worst) and 1.0 (best).
  final double value;

  const SignalStrength({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (value >= 0.9) {
      color = Colors.green;
    } else if (value >= 0.75) {
      color = Colors.lightGreen;
    } else if (value >= 0.5) {
      color = Colors.amber;
    } else {
      color = Colors.red;
    }
    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      spacing: 4,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: ColoredBox(color: color)),
        Expanded(child: ColoredBox(color: value >= 0.5 ? color : Theme.of(context).colorScheme.surfaceContainer)),
        Expanded(child: ColoredBox(color: value >= 0.75 ? color : Theme.of(context).colorScheme.surfaceContainer)),
        Expanded(child: ColoredBox(color: value >= 0.9 ? color : Theme.of(context).colorScheme.surfaceContainer)),
      ],
    );
  }
}
