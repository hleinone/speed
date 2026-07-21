import 'dart:math' as math;

import 'package:flutter/material.dart';

class AnimatedAppBarGradient extends StatefulWidget {
  const AnimatedAppBarGradient({super.key, required this.colors, this.random});

  @visibleForTesting
  final math.Random? random;

  final List<Color> colors;

  @override
  State<AnimatedAppBarGradient> createState() => _AnimatedAppBarGradientState();
}

class _AnimatedAppBarGradientState extends State<AnimatedAppBarGradient> with SingleTickerProviderStateMixin {
  static const _minimumX = -0.7;
  static const _maximumX = 0.7;
  static const _minimumXTravel = 0.5;
  static const _maximumY = 0.1;
  static const _maximumTilt = 0.12;

  late final math.Random _random = widget.random ?? math.Random();
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener(_handleAnimationStatus);
  late _GradientPosition _from = _randomPosition();
  late _GradientPosition _to = _randomPosition(previous: _from);
  bool _animationsDisabled = false;
  bool _hasAnimationPreference = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final animationsDisabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_hasAnimationPreference && animationsDisabled == _animationsDisabled) {
      return;
    }

    _hasAnimationPreference = true;
    _animationsDisabled = animationsDisabled;
    if (animationsDisabled) {
      _controller.stop();
    } else if (_controller.isCompleted) {
      _startNextAnimation();
    } else {
      _controller
        ..duration = _randomDuration()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    super.dispose();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_animationsDisabled) {
      _startNextAnimation();
    }
  }

  void _startNextAnimation() {
    _from = _to;
    _to = _randomPosition(previous: _from);
    _controller
      ..duration = _randomDuration()
      ..forward(from: 0);
  }

  Duration _randomDuration() {
    return Duration(milliseconds: 16000 + _random.nextInt(6001));
  }

  _GradientPosition _randomPosition({_GradientPosition? previous}) {
    final x = previous == null ? _randomBetween(_minimumX, _maximumX) : _nextX(previous.x);
    return _GradientPosition(
      x: x,
      y: _randomBetween(-_maximumY, _maximumY),
      tilt: _randomBetween(-_maximumTilt, _maximumTilt),
    );
  }

  double _nextX(double previousX) {
    final leftMaximum = previousX - _minimumXTravel;
    final rightMinimum = previousX + _minimumXTravel;
    final canMoveLeft = leftMaximum >= _minimumX;
    final canMoveRight = rightMinimum <= _maximumX;

    if (canMoveLeft && canMoveRight) {
      return _random.nextBool() ? _randomBetween(_minimumX, leftMaximum) : _randomBetween(rightMinimum, _maximumX);
    }
    if (canMoveLeft) {
      return _randomBetween(_minimumX, leftMaximum);
    }
    return _randomBetween(rightMinimum, _maximumX);
  }

  double _randomBetween(double minimum, double maximum) {
    return minimum + _random.nextDouble() * (maximum - minimum);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final position = _animationsDisabled
              ? _GradientPosition.resting
              : _GradientPosition.lerp(_from, _to, Curves.easeInOut.transform(_controller.value));
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: position.begin, end: position.end, colors: widget.colors),
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _GradientPosition {
  const _GradientPosition({required this.x, required this.y, required this.tilt});

  static const resting = _GradientPosition(x: 0, y: 0, tilt: 0.08);
  static const _halfWidth = 1.3;

  final double x;
  final double y;
  final double tilt;

  Alignment get begin => Alignment(x - _halfWidth, y - tilt);
  Alignment get end => Alignment(x + _halfWidth, y + tilt);

  factory _GradientPosition.lerp(_GradientPosition from, _GradientPosition to, double progress) {
    return _GradientPosition(
      x: _lerpDouble(from.x, to.x, progress),
      y: _lerpDouble(from.y, to.y, progress),
      tilt: _lerpDouble(from.tilt, to.tilt, progress),
    );
  }

  static double _lerpDouble(double from, double to, double progress) {
    return from + (to - from) * progress;
  }
}
