import 'package:flutter/material.dart';

class SwipeBackPageTransitionsBuilder extends PageTransitionsBuilder {
  const SwipeBackPageTransitionsBuilder(this.base);

  final PageTransitionsBuilder base;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final transition = base.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
    if (route.isFirst || route.fullscreenDialog) return transition;
    return _SwipeBack(route: route, child: transition);
  }
}

class _SwipeBack extends StatefulWidget {
  const _SwipeBack({required this.route, required this.child});

  final PageRoute<dynamic> route;
  final Widget child;

  @override
  State<_SwipeBack> createState() => _SwipeBackState();
}

class _SwipeBackState extends State<_SwipeBack> {
  static const double _minDistance = 80;
  static const double _minVelocity = 700;

  double _dx = 0;
  double _dy = 0;

  void _end(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final horizontal = _dx.abs() > _dy.abs() * 1.5;
    final swiped = _dx > _minDistance || velocity > _minVelocity;
    _dx = 0;
    _dy = 0;
    if (!horizontal || !swiped) return;
    if (!widget.route.isCurrent ||
        widget.route.animation?.isCompleted != true) {
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) {
        _dx = 0;
        _dy = 0;
      },
      onHorizontalDragUpdate: (d) {
        _dx += d.delta.dx;
        _dy += d.delta.dy;
      },
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: () {
        _dx = 0;
        _dy = 0;
      },
      child: widget.child,
    );
  }
}
