import 'dart:async';
import 'package:flutter/material.dart';

class CountButton extends StatefulWidget {
  const CountButton({
    super.key,
    required this.minValue,
    required this.maxValue,
    required this.selectedValue,
    this.step = 1.0,
    this.backgroundColor,
    this.foregroundColor,
    this.buttonSize = const Size(35, 35),
    this.incrementIcon,
    this.decrementIcon,
    this.borderRadius = 12.0,
    required this.onChanged,
    this.valueBuilder,
    this.textStyle = const TextStyle(fontSize: 15.0, color: Colors.white),
  }) : assert(maxValue > minValue),
       assert(selectedValue >= minValue && selectedValue <= maxValue),
       assert(step > 0);

  ///minimum value user can set
  final double minValue;

  ///maximum value user can set
  final double maxValue;

  ///Currently selected integer value
  final double selectedValue;

  final double step;

  final Color? backgroundColor;

  final Color? foregroundColor;

  final Size buttonSize;

  final Widget? incrementIcon;

  final Widget? decrementIcon;

  final double borderRadius;

  final Function(double value) onChanged;

  final Widget Function(double value)? valueBuilder;

  final TextStyle? textStyle;

  @override
  State<CountButton> createState() => _CountButtonState();
}

class _CountButtonState extends State<CountButton> {
  Timer? incrementTimer;
  Timer? decrementTimer;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.backgroundColor ?? Theme.of(context).colorScheme.primary;
    final foregroundColor = widget.foregroundColor ?? Colors.white;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        padding: const EdgeInsets.all(1.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: widget.buttonSize.width,
              height: widget.buttonSize.height,
              child: GestureDetector(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: backgroundColor,
                    foregroundColor: foregroundColor,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(widget.borderRadius),
                        bottomLeft: Radius.circular(widget.borderRadius),
                      ),
                    ),
                  ),
                  onPressed: _decrementCounter,
                  child: widget.decrementIcon ?? Icon(Icons.remove_outlined, color: foregroundColor),
                ),
                onLongPress: () {
                  startDecrementTimer();
                },
                onLongPressEnd: (details) {
                  decrementTimer?.cancel();
                  decrementTimer = null;
                },
              ),
            ),
            Expanded(
              child: Container(
                height: widget.buttonSize.height,
                decoration: BoxDecoration(
                  border: Border.symmetric(horizontal: BorderSide(color: backgroundColor, width: 2)),
                ),
                child: Center(
                  child: widget.valueBuilder != null
                      ? widget.valueBuilder!.call(widget.selectedValue.round().toDouble())
                      : Text(widget.selectedValue.round().toString(), style: widget.textStyle),
                ),
              ),
            ),
            SizedBox(
              width: widget.buttonSize.width,
              height: widget.buttonSize.height,
              child: GestureDetector(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: backgroundColor,
                    foregroundColor: foregroundColor,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(widget.borderRadius),
                        bottomRight: Radius.circular(widget.borderRadius),
                      ),
                    ),
                  ),
                  onPressed: _incrementCounter,
                  child: widget.incrementIcon ?? Icon(Icons.add, color: foregroundColor),
                ),
                onLongPress: () {
                  startIncrementTimer();
                },
                onLongPressEnd: (details) {
                  incrementTimer?.cancel();
                  incrementTimer = null;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _incrementCounter() {
    final value = widget.selectedValue + widget.step;

    if (value <= widget.maxValue) {
      widget.onChanged(value);
    }
  }

  void _decrementCounter() {
    final value = widget.selectedValue - widget.step;

    if (value >= widget.minValue) {
      widget.onChanged(value);
    }
  }

  void startIncrementTimer() {
    incrementTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final value = widget.selectedValue + widget.step;

      if (value <= widget.maxValue) {
        widget.onChanged(value);
      } else {
        incrementTimer?.cancel();
        incrementTimer = null;
      }
    });
  }

  void startDecrementTimer() {
    decrementTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final value = widget.selectedValue - widget.step;

      if (value >= widget.minValue) {
        widget.onChanged(value);
      } else {
        decrementTimer?.cancel();
        decrementTimer = null;
      }
    });
  }
}
