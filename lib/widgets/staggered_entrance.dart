import 'package:flutter/material.dart';

/// Hace que su hijo aparezca con un fundido + leve deslizamiento hacia
/// arriba, retrasado según [index] para crear un efecto de "cascada" cuando
/// se usa en una lista de tarjetas/ítems que aparecen en secuencia.
class StaggeredEntrance extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration stagger;
  final Duration duration;

  const StaggeredEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.stagger = const Duration(milliseconds: 70),
    this.duration = const Duration(milliseconds: 420),
  });

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.stagger * widget.index, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.08),
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
