import 'package:flutter/material.dart';

/// Large circular connect button with gradient and glow effect
class ConnectButton extends StatefulWidget {
  final bool isConnected;
  final bool isConnecting;
  final VoidCallback onPressed;

  const ConnectButton({
    super.key,
    required this.isConnected,
    required this.isConnecting,
    required this.onPressed,
  });

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _spinController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _spinAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _spinController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _spinAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _spinController, curve: Curves.linear),
    );
    _updateAnimations();
  }

  @override
  void didUpdateWidget(ConnectButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAnimations();
  }

  void _updateAnimations() {
    if (widget.isConnecting) {
      _pulseController.stop();
      if (!_spinController.isAnimating) {
        _spinController.repeat();
      }
    } else if (widget.isConnected) {
      _spinController.stop();
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _spinController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine colors based on state
    Color startColor;
    Color endColor;
    Color glowColor;
    IconData icon;

    if (widget.isConnected) {
      startColor = const Color(0xFF00B894);
      endColor = const Color(0xFF55EFC4);
      glowColor = const Color(0xFF00B894);
      icon = Icons.stop;
    } else if (widget.isConnecting) {
      startColor = const Color(0xFFFDCB6E);
      endColor = const Color(0xFFFFEAA7);
      glowColor = const Color(0xFFFDCB6E);
      icon = Icons.autorenew;
    } else {
      startColor = const Color(0xFF6C5CE7);
      endColor = const Color(0xFFA29BFE);
      glowColor = const Color(0xFF6C5CE7);
      icon = Icons.power_settings_new;
    }

    return GestureDetector(
      onTap: widget.onPressed,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseAnimation, _spinAnimation]),
        builder: (context, child) {
          return Transform.scale(
            scale: widget.isConnected ? _pulseAnimation.value : 1.0,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [startColor, endColor],
                ),
                boxShadow: [
                  BoxShadow(
                    color: glowColor.withValues(alpha: 0.4),
                    blurRadius: 40,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Inner ring
                  Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                  ),
                  // Icon or spinner
                  if (widget.isConnecting)
                    Transform.rotate(
                      angle: _spinAnimation.value * 2 * 3.14159,
                      child: SizedBox(
                        width: 50,
                        height: 50,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 3,
                        ),
                      ),
                    )
                  else
                    Icon(
                      icon,
                      size: 60,
                      color: Colors.white,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
