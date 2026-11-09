import 'package:flutter/widgets.dart';

/// 4pt grid, nothing invents its own number
class Space {
  const Space._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
}

class Radii {
  const Radii._();

  static const small = 6.0;
  static const medium = 8.0;
}

class Layout {
  const Layout._();

  /// above this the shell uses a rail, below it a bottom bar
  static const wideBreakpoint = 900.0;
  static const contentMaxWidth = 760.0;
  static const minTapTarget = 44.0;
}

class Motion {
  const Motion._();

  static const fast = Duration(milliseconds: 150);
}

extension MotionOf on BuildContext {
  /// zero when the system asks for reduced motion, so no widget has to check
  Duration motion(Duration duration) =>
      MediaQuery.disableAnimationsOf(this) ? Duration.zero : duration;
}
