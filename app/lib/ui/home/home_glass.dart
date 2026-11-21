import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app_container.dart';
import 'home_themes.dart';

/// How see-through the glass is below this point: 0 clear, 1 solid.
class GlassScope extends InheritedWidget {
  const GlassScope({super.key, required this.opacity, required super.child});

  final double opacity;

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassScope>()?.opacity ?? 0.35;

  @override
  bool updateShouldNotify(GlassScope old) => old.opacity != opacity;
}

/// Frosted glass over the wallpaper. [blur] off for small or numerous
/// pieces: every blur is redrawn as the weather moves, and a Portal's GPU is
/// modest. Without blur it is a clean tinted pane with a light edge.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onLongPress,
    this.radius = 24,
    this.blur = true,
    this.lighter = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final bool blur;

  /// A lighter pane (chips, the forecast strip).
  final bool lighter;

  @override
  Widget build(BuildContext context) {
    final o = GlassScope.of(context);
    final alpha = (lighter ? 0.04 + 0.55 * o : (blur ? 0.06 + 0.78 * o : 0.12 + 0.76 * o)).clamp(0.0, 0.95);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.10 + 0.08 * (1 - o))),
    );
    final body = Material(
      color: Color.fromRGBO(16, 18, 26, alpha),
      shape: shape,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: DecoratedBox(
          // A faint light along the top edge, like real glass.
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white.withValues(alpha: 0.07), Colors.white.withValues(alpha: 0)],
              stops: const [0, 0.35],
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: blur ? BackdropFilter(filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16), child: body) : body,
    );
  }
}

/// The wallpaper: a built-in 4K picture, Bing's photo, your photo or a
/// link, over the theme's colours while it loads.
class HomeWallpaper extends StatelessWidget {
  const HomeWallpaper({super.key, required this.container});

  final AppContainer container;

  @override
  Widget build(BuildContext context) {
    final home = container.phoenixHome;
    return ListenableBuilder(
      listenable: Listenable.merge([home.theme, home.backdrop]),
      builder: (context, _) {
        final theme = homeTheme(home.theme.value);
        final photo = home.backdrop.value;
        final mq = MediaQuery.of(context);
        // Decode at the screen's real resolution: full detail, a fraction of
        // the memory of a 4K bitmap.
        final px = (mq.size.longestSide * mq.devicePixelRatio).round();
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(center: const Alignment(-0.6, -1.1), radius: 1.5, colors: theme.background, stops: const [0, 0.45, 1]),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 1500),
              child: photo == null
                  ? const SizedBox.expand(key: ValueKey('none'))
                  : Image.memory(
                      photo,
                      key: ValueKey(identityHashCode(photo)),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      cacheWidth: px > 0 ? px : null,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
            ),
          ],
        );
      },
    );
  }
}
