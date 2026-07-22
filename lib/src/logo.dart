import 'dart:math' as math;

import 'package:flutter/material.dart';

class SpeedLogo extends StatelessWidget {
  final double? width;
  final double? height;
  final Color? color;
  final String? semanticLabel;

  const SpeedLogo({super.key, this.width, this.height, this.color, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color ?? Colors.black;

    Widget logo = CustomPaint(painter: _SpeedLogoPainter(effectiveColor), child: const SizedBox.expand());
    logo = AspectRatio(aspectRatio: _SpeedLogoPainter.aspectRatio, child: logo);
    logo = SizedBox(
      width: width ?? (height == null ? _SpeedLogoPainter.viewBox.width : null),
      height: height ?? (width == null ? _SpeedLogoPainter.viewBox.height : null),
      child: logo,
    );

    final label = semanticLabel;
    if (label == null) {
      return logo;
    }

    return Semantics(label: label, image: true, child: logo);
  }
}

class _SpeedLogoPainter extends CustomPainter {
  static const viewBox = Size(479, 72);
  static const aspectRatio = 479 / 72;

  final Color color;

  const _SpeedLogoPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / viewBox.width, size.height / viewBox.height);
    final offset = Offset((size.width - viewBox.width * scale) / 2, (size.height - viewBox.height * scale) / 2);
    final fillPaint = Paint()
      ..color = color
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = color
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter
      ..strokeMiterLimit = 2
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(scale)
      ..clipRect(Offset.zero & viewBox);

    for (final path in _logoLetterPaths) {
      canvas
        ..drawPath(path, fillPaint)
        ..drawPath(path, strokePaint);
    }

    canvas.save();
    canvas.clipPath(_speedLinesClipPath);
    for (final path in _speedLinePaths) {
      canvas.drawPath(path, fillPaint);
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SpeedLogoPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

final _logoLetterPaths = <Path>[
  _logoLetterSPath(),
  _logoLetterPPath(),
  _logoLetterE1Path(),
  _logoLetterE2Path(),
  _logoLetterDPath(),
];

final _speedLinesClipPath = _createSpeedLinesClipPath()..fillType = PathFillType.evenOdd;

final _speedLinePaths = <Path>[
  _speedLine1Path(),
  _speedLine2Path(),
  _speedLine3Path(),
  _speedLine4Path(),
  _speedLine5Path(),
];

Path _logoLetterSPath() => Path()
  ..moveTo(135.767, 50.305)
  ..relativeCubicTo(-1.891, 4.058, -4.521, 7.226, -7.087, 9.648)
  ..relativeCubicTo(-2.624, 2.477, -5.966, 4.996, -10.154, 6.96)
  ..relativeCubicTo(-3.018, 1.415, -6.732, 2.592, -10.904, 2.592)
  ..relativeLineTo(-58.368, 0)
  ..relativeCubicTo(1.491, -3.2, 2.982, -6.4, 4.472, -9.6)
  ..relativeLineTo(58.368, 0)
  ..relativeCubicTo(3.186, 0, 5.966, -1.335, 8.135, -2.832)
  ..relativeCubicTo(2.205, -1.522, 4.501, -3.687, 5.937, -6.768)
  ..relativeCubicTo(0.938, -2.014, 1.547, -4.491, 0.369, -6.768)
  ..relativeCubicTo(-1.17, -2.261, -3.406, -2.832, -5.497, -2.832)
  ..relativeLineTo(-39.168, 0)
  ..relativeCubicTo(-2.759, 0, -5.927, -0.531, -8.44, -2.592)
  ..relativeCubicTo(-2.426, -1.99, -3.408, -4.533, -3.718, -6.96)
  ..relativeCubicTo(-0.444, -3.48, 0.622, -6.899, 1.903, -9.648)
  ..relativeCubicTo(1.891, -4.058, 4.521, -7.226, 7.087, -9.648)
  ..relativeCubicTo(2.634, -2.487, 5.988, -5.001, 10.202, -6.96)
  ..relativeCubicTo(3.018, -1.403, 6.738, -2.592, 10.856, -2.592)
  ..relativeLineTo(53.568, 0)
  ..relativeCubicTo(-1.491, 3.2, -2.982, 6.4, -4.472, 9.6)
  ..relativeLineTo(-53.568, 0)
  ..relativeCubicTo(-3.14, 0, -5.932, 1.362, -8.087, 2.832)
  ..relativeCubicTo(-2.231, 1.522, -4.55, 3.687, -5.985, 6.768)
  ..relativeCubicTo(-0.939, 2.017, -1.536, 4.492, -0.321, 6.768)
  ..relativeCubicTo(1.201, 2.249, 3.386, 2.832, 5.449, 2.832)
  ..relativeLineTo(39.168, 0)
  ..relativeCubicTo(2.788, 0, 6.003, 0.523, 8.488, 2.592)
  ..relativeCubicTo(2.395, 1.995, 3.361, 4.543, 3.67, 6.96)
  ..relativeCubicTo(0.444, 3.48, -0.622, 6.899, -1.903, 9.648)
  ..close();

Path _logoLetterPPath() => Path()
  ..moveTo(229.988, 26.305)
  ..relativeCubicTo(-2.28, 4.895, -5.443, 8.85, -8.829, 12.048)
  ..relativeCubicTo(-3.459, 3.267, -7.649, 6.314, -12.735, 8.688)
  ..relativeCubicTo(-4.033, 1.883, -8.647, 3.264, -13.617, 3.264)
  ..relativeLineTo(-38.592, 0)
  ..relativeCubicTo(1.476, -3.168, 2.952, -6.336, 4.428, -9.504)
  ..relativeLineTo(38.592, 0)
  ..relativeCubicTo(3.239, 0, 6.075, -0.962, 8.213, -1.968)
  ..relativeCubicTo(2.621, -1.234, 5.211, -2.953, 7.644, -5.28)
  ..relativeCubicTo(1.803, -1.724, 3.837, -4.116, 5.297, -7.248)
  ..relativeCubicTo(0.902, -1.936, 1.81, -4.594, 1.479, -7.296)
  ..relativeCubicTo(-0.185, -1.511, -0.783, -3.575, -2.769, -5.184)
  ..relativeCubicTo(-1.952, -1.581, -4.445, -1.92, -6.402, -1.92)
  ..relativeLineTo(-43.968, 0)
  ..relativeCubicTo(-8.945, 19.2, -17.889, 38.4, -26.834, 57.6)
  ..relativeLineTo(-9.6, 0)
  ..relativeCubicTo(10.436, -22.4, 20.871, -44.8, 31.307, -67.2)
  ..relativeLineTo(53.568, 0)
  ..relativeCubicTo(3.499, 0, 7.456, 0.673, 10.598, 3.216)
  ..relativeCubicTo(3.051, 2.47, 4.27, 5.649, 4.641, 8.688)
  ..relativeCubicTo(0.522, 4.287, -0.761, 8.537, -2.419, 12.096)
  ..close();

Path _logoLetterE1Path() => Path()
  ..moveTo(284.07, 69.505)
  ..relativeLineTo(-69.504, 0)
  ..relativeCubicTo(10.436, -22.4, 20.871, -44.8, 31.307, -67.2)
  ..relativeLineTo(69.504, 0)
  ..relativeCubicTo(-1.491, 3.2, -2.982, 6.4, -4.472, 9.6)
  ..relativeLineTo(-59.904, 0)
  ..relativeCubicTo(-7.454, 16, -14.908, 32, -22.362, 48)
  ..relativeLineTo(59.904, 0)
  ..relativeCubicTo(-1.491, 3.2, -2.982, 6.4, -4.472, 9.6)
  ..close()
  ..relativeMoveTo(5.257, -28.8)
  ..relativeLineTo(-46.944, 0)
  ..relativeCubicTo(1.491, -3.2, 2.982, -6.4, 4.472, -9.6)
  ..relativeLineTo(46.944, 0)
  ..relativeCubicTo(-1.491, 3.2, -2.982, 6.4, -4.472, 9.6)
  ..close();

Path _logoLetterE2Path() => Path()
  ..moveTo(359.718, 69.505)
  ..relativeLineTo(-69.504, 0)
  ..relativeCubicTo(10.436, -22.4, 20.871, -44.8, 31.307, -67.2)
  ..relativeLineTo(69.504, 0)
  ..relativeCubicTo(-1.491, 3.2, -2.982, 6.4, -4.472, 9.6)
  ..relativeLineTo(-59.904, 0)
  ..relativeCubicTo(-7.454, 16, -14.908, 32, -22.362, 48)
  ..relativeLineTo(59.904, 0)
  ..relativeCubicTo(-1.491, 3.2, -2.982, 6.4, -4.472, 9.6)
  ..close()
  ..relativeMoveTo(5.257, -28.8)
  ..relativeLineTo(-46.944, 0)
  ..relativeCubicTo(1.491, -3.2, 2.982, -6.4, 4.472, -9.6)
  ..relativeLineTo(46.944, 0)
  ..relativeCubicTo(-1.491, 3.2, -2.982, 6.4, -4.472, 9.6)
  ..close();

Path _logoLetterDPath() => Path()
  ..moveTo(460.715, 35.905)
  ..relativeCubicTo(-2.098, 4.503, -4.836, 8.906, -8.313, 13.104)
  ..relativeCubicTo(-3.465, 4.185, -7.259, 7.732, -11.275, 10.704)
  ..relativeCubicTo(-3.521, 2.605, -7.892, 5.232, -13.146, 7.2)
  ..relativeCubicTo(-3.874, 1.451, -8.55, 2.592, -13.832, 2.592)
  ..relativeLineTo(-33.888, 0)
  ..relativeCubicTo(1.491, -3.2, 2.982, -6.4, 4.472, -9.6)
  ..relativeLineTo(33.888, 0)
  ..relativeCubicTo(4.889, 0, 9.212, -1.337, 12.945, -3.264)
  ..relativeCubicTo(4.633, -2.392, 8.369, -5.455, 11.391, -8.688)
  ..relativeCubicTo(3.452, -3.693, 6.149, -7.738, 8.157, -12.048)
  ..relativeCubicTo(1.607, -3.449, 3.087, -7.736, 3.091, -12.096)
  ..relativeCubicTo(0.003, -2.924, -0.703, -6.162, -3.297, -8.688)
  ..relativeCubicTo(-2.652, -2.583, -6.529, -3.216, -9.926, -3.216)
  ..relativeLineTo(-38.688, 0)
  ..relativeCubicTo(-8.945, 19.2, -17.889, 38.4, -26.834, 57.6)
  ..relativeLineTo(-9.6, 0)
  ..relativeCubicTo(10.436, -22.4, 20.871, -44.8, 31.307, -67.2)
  ..relativeLineTo(48.288, 0)
  ..relativeCubicTo(3.597, 0, 7.826, 0.526, 11.416, 2.592)
  ..relativeCubicTo(2.563, 1.475, 4.971, 3.728, 6.415, 7.248)
  ..relativeCubicTo(1.503, 3.662, 1.616, 7.501, 1.279, 10.752)
  ..relativeCubicTo(-0.498, 4.806, -2.142, 9.338, -3.852, 13.008)
  ..close();

Path _createSpeedLinesClipPath() => Path()
  ..moveTo(41.462, 73.147)
  ..relativeLineTo(-41.462, 0)
  ..relativeLineTo(0, -76.841)
  ..relativeLineTo(158.991, 0)
  ..relativeLineTo(0, 0.499)
  ..relativeLineTo(-59.258, 0)
  ..relativeCubicTo(-6.291, 0, -11.695, 2.417, -13.174, 3.105)
  ..relativeCubicTo(-3.964, 1.843, -8.041, 4.532, -11.659, 7.948)
  ..relativeCubicTo(-4, 3.776, -6.668, 7.828, -8.297, 11.325)
  ..relativeCubicTo(-0.561, 1.205, -3.108, 6.9, -2.373, 12.666)
  ..relativeCubicTo(0.618, 4.842, 2.951, 8.275, 5.686, 10.517)
  ..relativeCubicTo(4.508, 3.697, 10.593, 3.839, 11.928, 3.839)
  ..relativeLineTo(39.168, 0)
  ..relativeCubicTo(0.075, 0, 0.436, 0.05, 0.663, 0.082)
  ..relativeCubicTo(0, 0.156, -0.06, 0.31, -0.085, 0.442)
  ..relativeCubicTo(-0.121, 0.625, -0.366, 1.103, -0.435, 1.253)
  ..relativeCubicTo(-1.222, 2.622, -3.454, 4.135, -4.076, 4.564)
  ..relativeCubicTo(-0.495, 0.342, -2.519, 1.859, -5.011, 1.859)
  ..relativeLineTo(-61.873, 0)
  ..relativeLineTo(-8.731, 18.742)
  ..close()
  ..relativeMoveTo(117.529, -76.342)
  ..relativeLineTo(2.939, 0)
  ..relativeLineTo(-2.939, 6.31)
  ..relativeLineTo(0, -6.31)
  ..close()
  ..relativeMoveTo(0, 6.31)
  ..relativeLineTo(0, 70.033)
  ..relativeLineTo(-41.19, 0)
  ..relativeCubicTo(0.982, -0.353, 1.995, -0.768, 3.032, -1.255)
  ..relativeCubicTo(3.884, -1.821, 7.946, -4.496, 11.595, -7.94)
  ..relativeCubicTo(4, -3.776, 6.668, -7.828, 8.297, -11.325)
  ..relativeLineTo(0, 0)
  ..relativeCubicTo(0.561, -1.204, 3.108, -6.9, 2.373, -12.666)
  ..relativeCubicTo(-0.625, -4.901, -2.976, -8.301, -5.606, -10.491)
  ..relativeCubicTo(-4.467, -3.72, -10.713, -3.866, -12.008, -3.866)
  ..relativeLineTo(-39.168, 0)
  ..relativeCubicTo(-0.078, 0, -0.456, -0.054, -0.654, -0.083)
  ..relativeCubicTo(-0.053, -0.273, 0.097, -0.548, 0.155, -0.759)
  ..relativeCubicTo(0.127, -0.466, 0.299, -0.81, 0.357, -0.936)
  ..relativeCubicTo(1.22, -2.619, 3.481, -4.126, 4.099, -4.547)
  ..relativeCubicTo(0.476, -0.324, 2.536, -1.875, 4.988, -1.875)
  ..relativeLineTo(57.073, 0)
  ..relativeLineTo(6.657, -14.29)
  ..close()
  ..relativeMoveTo(-41.19, 70.033)
  ..relativeCubicTo(-4.051, 1.456, -7.586, 1.858, -10.206, 1.858)
  ..relativeLineTo(-66.998, 0)
  ..relativeLineTo(0.865, -1.858)
  ..relativeLineTo(76.339, 0)
  ..close();

Path _speedLine1Path() => Path()
  ..moveTo(78.382, 40.465)
  ..relativeLineTo(-66.42, -4.56)
  ..relativeLineTo(70.892, -5.04)
  ..relativeLineTo(-4.472, 9.6)
  ..close();

Path _speedLine2Path() => Path()
  ..moveTo(126.382, 55.001)
  ..relativeLineTo(-120.244, -4.936)
  ..relativeLineTo(124.717, -4.664)
  ..relativeLineTo(-4.472, 9.6)
  ..close();

Path _speedLine3Path() => Path()
  ..moveTo(92.062, 11.425)
  ..relativeLineTo(-68.841, -4.515)
  ..relativeLineTo(73.313, -5.085)
  ..relativeLineTo(-4.472, 9.6)
  ..close();

Path _speedLine4Path() => Path()
  ..moveTo(72.096, 26.087)
  ..relativeLineTo(-54.308, -4.8)
  ..relativeLineTo(58.78, -4.8)
  ..relativeLineTo(-4.472, 9.6)
  ..close();

Path _speedLine5Path() => Path()
  ..moveTo(54.382, 69.505)
  ..relativeLineTo(-54.382, -4.641)
  ..relativeLineTo(58.854, -4.959)
  ..relativeLineTo(-4.472, 9.6)
  ..close();
