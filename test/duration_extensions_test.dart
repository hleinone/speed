import 'package:flutter_test/flutter_test.dart';
import 'package:speed/src/util/duration_extensions.dart';

void main() {
  test('converts durations to signed fractional seconds with microsecond precision', () {
    expect(const Duration(microseconds: 1500001).inFractionalSeconds, closeTo(1.500001, 0.000000000001));
    expect(Duration.zero.inFractionalSeconds, 0);
    expect(const Duration(microseconds: -250000).inFractionalSeconds, closeTo(-0.25, 0.000000000001));
  });
}
