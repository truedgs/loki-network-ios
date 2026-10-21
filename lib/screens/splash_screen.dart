import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'home_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/server_provider.dart';
import '../providers/vpn_provider.dart';
import '../services/analytics_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final authProvider = context.read<AuthProvider>();
    final serverProvider = context.read<ServerProvider>();
    final vpnProvider = context.read<VpnProvider>();

    // Initialize auth (HWID check) and fetch servers in parallel
    await Future.wait([
      authProvider.initialize(),
      serverProvider.fetchServers(),
    ]);

    unawaited(AnalyticsService().sendDeviceHeartbeat());

    // Initialize VPN engine
    await vpnProvider.initialize();

    // Navigate to home
    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D1117), Color(0xFF161B22), Color(0xFF1C2128)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App logo
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C5CE7).withValues(alpha: 0.5),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  size: 60,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'LOKI Network',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Secure • Fast • Reliable',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF8B95A5),
                ),
              ),
              const SizedBox(height: 48),
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  color: Color(0xFF6C5CE7),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 16),
              Consumer<AuthProvider>(
                builder: (context, auth, _) {
                  return Text(
                    auth.isLoading
                        ? 'Checking HWID...'
                        : Theme.of(context).platform ==
                                  TargetPlatform.android &&
                              !auth.isAccountVerified
                        ? 'Account verification unavailable'
                        : auth.isPremium
                        ? 'Premium account verified'
                        : 'Free account',
                    style: Theme.of(context).textTheme.bodySmall,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
