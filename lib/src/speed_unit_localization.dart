import 'package:flutter/widgets.dart';
import 'package:speed/src/generated/l10n/l10n.dart';
import 'package:speed/src/speed_tracker/models.dart';

extension SpeedUnitLocalization on SpeedUnit {
  String localizedTitle(BuildContext context) {
    return switch (this) {
      SpeedUnit.kilometersPerHour => L10n.of(context).kilometersPerHour,
      SpeedUnit.milesPerHour => L10n.of(context).milesPerHour,
      SpeedUnit.metersPerSecond => L10n.of(context).metersPerSecond,
      SpeedUnit.feetPerSecond => L10n.of(context).feetPerSecond,
      SpeedUnit.knots => L10n.of(context).knots,
    };
  }
}
