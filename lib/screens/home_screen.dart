import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/server_provider.dart';
import '../providers/vpn_provider.dart';
import '../services/api_config.dart';
import '../services/app_control_service.dart';
import '../services/vpn_service.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import '../widgets/connect_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _currentVersion = ApiConfig.appVersion;
  static final _premiumUrl = Uri.parse('https://lokinetwork-vpn.web.app');
  final _appControlService = AppControlService();
  bool _checkedAppControl = false;
  String _lastVpnError = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAppControl());
  }

  Future<void> _checkAppControl() async {
    if (_checkedAppControl) return;
    _checkedAppControl = true;

    try {
      final control = await _appControlService.fetchAppControl(
        appVersion: _currentVersion,
      );
      if (!mounted) return;

      if (control.update.shouldShowFor(_currentVersion)) {
        await _showUpdateDialog(control.update);
        return;
      }

      if (control.announcement.enabled &&
          control.announcement.message.trim().isNotEmpty) {
        await _showAnnouncementDialog(control.announcement);
      }
    } catch (_) {
      // App control is optional; never block the VPN UI when offline.
    }
  }

  Future<void> _showUpdateDialog(AppUpdate update) async {
    final message = update.message.trim().isNotEmpty
        ? update.message
        : 'A new version is available. Please update the app.';

    await showDialog<void>(
      context: context,
      barrierDismissible: !update.required,
      builder: (context) {
        return PopScope(
          canPop: !update.required,
          child: AlertDialog(
            title: const Text('Update Available'),
            content: Text(message),
            actions: [
              if (!update.required)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Later'),
                ),
              ElevatedButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  final url = Uri.tryParse(update.url);
                  if (url != null) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                  if (!update.required) navigator.pop();
                },
                child: const Text('Update'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAnnouncementDialog(AppAnnouncement announcement) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            announcement.title.trim().isNotEmpty
                ? announcement.title
                : 'Notice',
          ),
          content: Text(announcement.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final serverProvider = context.watch<ServerProvider>();
    final vpn = context.watch<VpnProvider>();
    final selectedServer = serverProvider.selectedServer;
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final brandTitle = Text(
      'LOKI Network',
      style: Theme.of(context).textTheme.titleMedium,
    );
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.shield_outlined,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        if (isAndroid)
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: brandTitle,
            ),
          )
        else
          brandTitle,
      ],
    );
    _showVpnErrorIfNeeded(vpn);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Top bar with premium badge and settings
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (isAndroid) ...[
                      Expanded(child: brand),
                      const SizedBox(width: 8),
                    ] else
                      brand,
                    Row(
                      children: [
                        if (isAndroid && !auth.isPremium)
                          ElevatedButton(
                            onPressed: () => _buyPremium(auth.hwid),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(0, 32),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              backgroundColor: const Color(0xFFFFC107),
                              foregroundColor: const Color(0xFF101418),
                              elevation: 0,
                              textStyle: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Buy Premium'),
                          ),
                        if (auth.isPremium)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, size: 14, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  'PREMIUM',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SettingsScreen(),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.settings_outlined,
                            color: Color(0xFFB0B8C4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Main content
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                children: [
                  const Spacer(flex: 2),

                  if (!isAndroid && !auth.isPremium) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: ElevatedButton.icon(
                        onPressed: () => _buyPremium(auth.hwid),
                        icon: const Icon(Icons.workspace_premium),
                        label: const Text('Buy VPN'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          backgroundColor: const Color(0xFFFFC107),
                          foregroundColor: const Color(0xFF101418),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  // Connection status text
                  Text(
                    vpn.connectionStatus == VpnStatus.error
                        ? 'Connection Error'
                        : vpn.isConnected
                        ? 'Connected'
                        : vpn.isConnecting
                        ? 'Connecting...'
                        : 'Disconnected',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: vpn.connectionStatus == VpnStatus.error
                          ? const Color(0xFFFF6B6B)
                          : vpn.isConnected
                          ? const Color(0xFF00B894)
                          : const Color(0xFFB0B8C4),
                    ),
                  ),
                  if (vpn.connectionStatus == VpnStatus.error &&
                      vpn.statusMessage.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Text(
                        vpn.statusMessage,
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFFF6B6B),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 30),

                  // Big circular connect button
                  ConnectButton(
                    isConnected: vpn.isConnected,
                    isConnecting: vpn.isConnecting,
                    onPressed: () async {
                      if (selectedServer != null) {
                        if (vpn.isConnected || vpn.isConnecting) {
                          await vpn.disconnect();
                        } else if (selectedServer.isPremium &&
                            !auth.isPremium) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Premium expired. Contact admin to buy Premium.',
                              ),
                              backgroundColor: Color(0xFFFF6B6B),
                            ),
                          );
                        } else {
                          await vpn.connect(selectedServer.uri);
                        }
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please select a server first'),
                            backgroundColor: Color(0xFFFF6B6B),
                          ),
                        );
                      }
                    },
                  ),

                  const SizedBox(height: 30),

                  // Duration display
                  if (vpn.isConnected)
                    Text(
                      vpn.duration,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF8B95A5),
                      ),
                    ),

                  const Spacer(flex: 1),

                  // Selected server card
                  if (selectedServer != null)
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ServersScreen(),
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B22),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF2D333B)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C2128),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  selectedServer.country,
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    selectedServer.name,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${selectedServer.protocol.toUpperCase()} • ${selectedServer.isPremium ? "Premium" : "Free"}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF8B95A5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: Color(0xFF8B95A5),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Change server button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ServersScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.dns_outlined),
                      label: const Text('Change Server'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                  ),

                  const Spacer(flex: 1),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVpnErrorIfNeeded(VpnProvider vpn) {
    if (vpn.connectionStatus != VpnStatus.error) return;
    final message = vpn.statusMessage.trim();
    if (message.isEmpty || message == _lastVpnError) return;
    _lastVpnError = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFFFF6B6B),
          duration: const Duration(seconds: 6),
        ),
      );
    });
  }

  Future<void> _buyPremium(String hwid) async {
    await Clipboard.setData(ClipboardData(text: hwid));
    final opened = await launchUrl(
      _premiumUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'HWID copied. Opening premium website...'
              : 'HWID copied. Could not open premium website.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
