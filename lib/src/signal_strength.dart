import 'package:flutter/material.dart';

typedef _SignalLevel = ({double? threshold, Color color});

const List<_SignalLevel> _signalLevels = [
  (threshold: null, color: Colors.red),
  (threshold: 0.5, color: Colors.amber),
  (threshold: 0.75, color: Colors.lightGreen),
  (threshold: 0.9, color: Colors.green),
];

bool _isActiveSignalLevel(_SignalLevel level, double value) {
  final threshold = level.threshold;
  return threshold == null || value >= threshold;
}

class SignalStrength extends StatelessWidget {
  /// Signal quality value, between 0.0 (worst) and 1.0 (best).
  final double value;

  const SignalStrength({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final color = _signalLevels.lastWhere((level) => _isActiveSignalLevel(level, value)).color;
    final inactiveColor = Theme.of(context).colorScheme.surfaceContainer;
    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      spacing: 4,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _signalLevels
          .map(
            (level) => Expanded(child: ColoredBox(color: _isActiveSignalLevel(level, value) ? color : inactiveColor)),
          )
          .toList(growable: false),
    );
  }
}
