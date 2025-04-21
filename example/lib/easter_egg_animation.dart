import 'dart:math';
import 'package:flutter/material.dart';

class QualcommConfusionAnimation extends StatefulWidget {
  const QualcommConfusionAnimation({Key? key}) : super(key: key);

  @override
  _QualcommConfusionAnimationState createState() =>
      _QualcommConfusionAnimationState();
}

class _QualcommConfusionAnimationState extends State<QualcommConfusionAnimation>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _backgroundController;
  late Animation<double> _scaleAnimation;
  late Animation<Color?> _colorAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<Color?> _gradientColor1Animation;
  late Animation<Color?> _gradientColor2Animation;
  Offset _glitchOffset = Offset.zero;
  final Random _random = Random();
  final List<Color> _glitchColors = [
    Colors.cyanAccent.withOpacity(0.7),
    Colors.purpleAccent.withOpacity(0.7),
    Colors.limeAccent.withOpacity(0.7),
    Colors.pinkAccent.withOpacity(0.7),
    Colors.tealAccent.withOpacity(0.7),
    Colors.orangeAccent.withOpacity(0.7),
  ];

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    _backgroundController = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticInOut));

    _colorAnimation = ColorTweenSequence([
      ColorTweenSequenceItem(
        tween: ColorTween(begin: Colors.white, end: Colors.cyanAccent),
        weight: 1,
      ),
      ColorTweenSequenceItem(
        tween: ColorTween(begin: Colors.cyanAccent, end: Colors.purpleAccent),
        weight: 1,
      ),
      ColorTweenSequenceItem(
        tween: ColorTween(begin: Colors.purpleAccent, end: Colors.yellowAccent),
        weight: 1,
      ),
      ColorTweenSequenceItem(
        tween: ColorTween(begin: Colors.yellowAccent, end: Colors.redAccent),
        weight: 1,
      ),
      ColorTweenSequenceItem(
        tween: ColorTween(begin: Colors.redAccent, end: Colors.white),
        weight: 1,
      ),
    ]).animate(_controller);

    _rotationAnimation = Tween<double>(begin: -0.08, end: 0.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );

    _gradientColor1Animation = ColorTweenSequence([
      for (int i = 0; i < _glitchColors.length; i++)
        ColorTweenSequenceItem(
          tween: ColorTween(
            begin: _glitchColors[i],
            end: _glitchColors[(i + 1) % _glitchColors.length],
          ),
          weight: 1,
        ),
    ]).animate(_backgroundController);

    int startOffset = (_glitchColors.length ~/ 2);
    _gradientColor2Animation = ColorTweenSequence([
      for (int i = 0; i < _glitchColors.length; i++)
        ColorTweenSequenceItem(
          tween: ColorTween(
            begin: _glitchColors[(i + startOffset) % _glitchColors.length],
            end: _glitchColors[(i + startOffset + 1) % _glitchColors.length],
          ),
          weight: 1,
        ),
    ]).animate(_backgroundController);

    _controller.addListener(() {
      if (_random.nextDouble() < 0.25) {
        setState(() {
          _glitchOffset = Offset(
            (_random.nextDouble() - 0.5) * 25,
            (_random.nextDouble() - 0.5) * 25,
          );
        });
      } else if (_random.nextDouble() < 0.1) {
        setState(() {
          _glitchOffset = Offset.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _backgroundController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AnimatedBuilder(
          animation: _backgroundController,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _gradientColor1Animation.value ?? Colors.transparent,
                    _gradientColor2Animation.value ?? Colors.transparent,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: const [0.0, 1.0],
                ),
              ),
              child: child,
            );
          },
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _rotationAnimation.value,
                  child: Transform.translate(
                    offset: _glitchOffset,
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Text(
                          'QNN - 为您的 PPT 带来澎湃动力！',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: _colorAnimation.value,
                            fontFamily: 'Courier',
                            shadows: [
                              Shadow(
                                blurRadius: 15.0,
                                color: (_colorAnimation.value ?? Colors.red)
                                    .withOpacity(0.8),
                                offset: const Offset(3.0, 3.0),
                              ),
                              Shadow(
                                blurRadius: 5.0,
                                color: Colors.white.withOpacity(0.5),
                                offset: const Offset(-1.0, -1.0),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class ColorTweenSequence extends Animatable<Color?> {
  final List<ColorTweenSequenceItem> items;
  final double totalWeight;

  ColorTweenSequence(this.items)
    : totalWeight = items.fold(0.0, (sum, item) => sum + item.weight);

  @override
  Color? transform(double t) {
    if (items.isEmpty) return null;

    double currentWeight = 0.0;
    for (final item in items) {
      final itemStartT = currentWeight / totalWeight;
      final itemEndT = (currentWeight + item.weight) / totalWeight;

      if (t >= itemStartT && t <= itemEndT) {
        final itemT = (t - itemStartT) / (item.weight / totalWeight);
        return item.tween.transform(itemT);
      }
      currentWeight += item.weight;
    }
    return items.last.tween.end;
  }
}

class ColorTweenSequenceItem {
  final ColorTween tween;
  final double weight;

  ColorTweenSequenceItem({required this.tween, this.weight = 1.0});
}
