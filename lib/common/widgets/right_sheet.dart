import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

Future<T?> showModalRightSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool clickEmptyPop = false,
  RouteSettings? routeSettings,
  bool useRootNavigator = false,
}) {
  assert(debugCheckHasMediaQuery(context));
  assert(debugCheckHasMaterialLocalizations(context));

  final NavigatorState navigator =
      Navigator.of(context, rootNavigator: useRootNavigator);
  // final MaterialLocalizations localizations = MaterialLocalizations.of(context);
  return navigator.push(_ModalRightSheetRoute<T>(
    builder: builder,
    clickEmptyPop: clickEmptyPop,
    theme: Theme.of(context),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    settings: routeSettings,
  ));
}

const Duration _kRightSheetDuration = Duration(milliseconds: 200);
const double _kMinFlingVelocity = 700.0;
const double _kCloseProgressThreshold = 0.5;

class _ModalRightSheetRoute<T> extends PopupRoute<T> {
  _ModalRightSheetRoute({
    required this.builder,
    required this.theme,
    required this.barrierLabel,
    required this.clickEmptyPop,
    required super.settings,
  });

  final WidgetBuilder builder;
  final ThemeData theme;
  final bool clickEmptyPop;

  @override
  Duration get transitionDuration => _kRightSheetDuration;

  @override
  bool get barrierDismissible => true;

  @override
  final String barrierLabel;

  @override
  Color get barrierColor => Colors.black54;

  AnimationController? _animationController;

  @override
  AnimationController createAnimationController() {
    assert(_animationController == null);
    _animationController = RightSheet.createAnimationController(navigator!);
    return _animationController!;
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    // By definition, the right sheet is aligned to the right of the page
    // and isn't exposed to the top padding of the MediaQuery.
    Widget rightSheet = MediaQuery.removePadding(
      context: context,
      removeTop: false,
      child: _ModalRightSheet<T>(
          route: this, clickEmptyPop: this.clickEmptyPop),
    );
    rightSheet = Theme(data: theme, child: rightSheet);
    return rightSheet;
  }
}

class _ModalRightSheet<T> extends StatefulWidget {
  const _ModalRightSheet(
      {super.key, required this.route, this.clickEmptyPop = true});

  final _ModalRightSheetRoute<T> route;
  final bool clickEmptyPop;

  @override
  _ModalRightSheetState<T> createState() => _ModalRightSheetState<T>();
}

class _ModalRightSheetState<T> extends State<_ModalRightSheet<T>> {
  @override
  Widget build(BuildContext context) {
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final MaterialLocalizations localizations =
        MaterialLocalizations.of(context);
    String? routeLabel;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        routeLabel = '';
        break;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        routeLabel = localizations.dialogLabel;
        break;
      default:
    }

    return GestureDetector(
        excludeFromSemantics: true,
        onTap: widget.clickEmptyPop ? () => Navigator.pop(context) : null,
        child: AnimatedBuilder(
            animation: widget.route.animation!,
            builder: (context, child) {
              // Disable the initial animation when accessible navigation is on so
              // that the semantics are added to the tree at the correct time.
              final double animationValue = mediaQuery.accessibleNavigation
                  ? 1.0
                  : widget.route.animation!.value;
              return Semantics(
                scopesRoute: true,
                namesRoute: true,
                label: routeLabel,
                explicitChildNodes: true,
                child: ClipRect(
                  child: CustomSingleChildLayout(
                    delegate: _ModalRightSheetLayout(animationValue),
                    child: RightSheet(
                      animationController: widget.route._animationController,
                      onClosing: () => Navigator.pop(context),
                      builder: widget.route.builder,
                    ),
                  ),
                ),
              );
            }));
  }
}

class _ModalRightSheetLayout extends SingleChildLayoutDelegate {
  _ModalRightSheetLayout(this.progress);

  final double progress;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
        minWidth: 0.0,
        maxWidth: constraints.maxWidth,
        minHeight: constraints.maxHeight,
        maxHeight: constraints.maxHeight);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return Offset(size.width - childSize.width * progress, 0.0);
  }

  @override
  bool shouldRelayout(_ModalRightSheetLayout oldDelegate) {
    return progress != oldDelegate.progress;
  }
}

class RightSheet extends StatefulWidget {
  /// Creates a right sheet.
  ///
  /// Typically, right sheets are created implicitly by
  /// [ScaffoldState.showRightSheet], for persistent right sheets, or by
  /// [showModalRightSheet], for modal right sheets.
  const RightSheet(
      {super.key,
      this.animationController,
      this.enableDrag = true,
      this.elevation = 8.0,
      required this.onClosing,
      required this.builder});

  /// The animation that controls the right sheet's position.
  ///
  /// The RightSheet widget will manipulate the position of this animation, it
  /// is not just a passive observer.
  final AnimationController? animationController;

  /// Called when the right sheet begins to close.
  ///
  /// A right sheet might be prevented from closing (e.g., by user
  /// interaction) even after this callback is called. For this reason, this
  /// callback might be call multiple times for a given right sheet.
  final VoidCallback onClosing;

  /// A builder for the contents of the sheet.
  ///
  /// The right sheet will wrap the widget produced by this builder in a
  /// [Material] widget.
  final WidgetBuilder builder;

  /// If true, the right sheet can dragged up and down and dismissed by swiping
  ///
  /// Default is true.
  final bool enableDrag;

  /// The z-coordinate at which to place this material. This controls the size
  /// of the shadow below the material.
  ///
  /// Defaults to 0.
  final double elevation;

  @override
  RightSheetState createState() => RightSheetState();

  /// Creates an animation controller suitable for controlling a [RightSheet].
  static AnimationController createAnimationController(TickerProvider vsync) {
    return AnimationController(
      duration: _kRightSheetDuration,
      debugLabel: 'RightSheet',
      vsync: vsync,
    );
  }
}

class RightSheetState extends State<RightSheet> {
  final GlobalKey _childKey = GlobalKey(debugLabel: 'RightSheet child');

  double get _childWidth {
    final RenderBox renderBox =
        _childKey.currentContext!.findRenderObject()! as RenderBox;
    return renderBox.size.width;
  }

  bool get _dismissUnderway =>
      widget.animationController?.status == AnimationStatus.reverse;

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_dismissUnderway) return;
    widget.animationController?.value -= details.primaryDelta! / (_childWidth);
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_dismissUnderway) return;
    if (details.velocity.pixelsPerSecond.dy > _kMinFlingVelocity) {
      final double flingVelocity =
          -details.velocity.pixelsPerSecond.dx / _childWidth;
      if (widget.animationController!.value > 0.0) {
        widget.animationController!.fling(velocity: flingVelocity);
      }
      if (flingVelocity < 0.0) widget.onClosing();
    } else if (widget.animationController!.value < _kCloseProgressThreshold) {
      if (widget.animationController!.value > 0.0) {
        widget.animationController!.fling(velocity: -1.0);
      }
      widget.onClosing();
    } else {
      widget.animationController!.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget sheet = Material(
      key: _childKey,
      elevation: widget.elevation,
      child: Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        child: widget.builder(context),
      ),
    );
    return !widget.enableDrag
        ? sheet
        : GestureDetector(
            onHorizontalDragUpdate: _handleDragUpdate,
            onHorizontalDragEnd: _handleDragEnd,
            excludeFromSemantics: true,
            child: sheet,
          );
  }
}
