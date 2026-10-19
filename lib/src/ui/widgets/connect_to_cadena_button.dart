import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:signer/src/ui/theme/app_Text_Styles.dart';
import 'package:signer/src/ui/theme/colors.dart';

/// Highly prominent Cadena connection CTA with accessibility-safe pulse.
class ConnectToCadenaButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isLoading;

  const ConnectToCadenaButton({
    super.key,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  State<ConnectToCadenaButton> createState() => _ConnectToCadenaButtonState();
}

class _ConnectToCadenaButtonState extends State<ConnectToCadenaButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulse = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimationWithAccessibility();
  }

  void _syncAnimationWithAccessibility() {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 1.0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Obx(() {
      final accent = secondaryColor.value;
      final fill = primaryColor.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Required: connect this device to Cadena',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.isLoading ? null : widget.onTap,
              borderRadius: BorderRadius.circular(14),
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final t = reduceMotion ? 1.0 : _pulse.value;
                  final glow = accent.withOpacity(0.25 + (0.35 * t));
                  return Opacity(
                    opacity: t,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: accent, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: glow,
                            blurRadius: 12 + (8 * t),
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.isLoading)
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          else
                            Icon(
                              Icons.link,
                              size: 24,
                              color: primaryTextColor.value,
                            ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              widget.isLoading
                                  ? 'Connecting…'
                                  : 'CONNECT to Cadena',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.buttonText.copyWith(
                                color: primaryTextColor.value,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      );
    });
  }
}
