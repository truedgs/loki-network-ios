import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/server_provider.dart';
import '../providers/vpn_provider.dart';
import '../services/api_config.dart';
import '../services/vpn_service.dart';
import '../widgets/privacy_policy_button.dart';
import 'package:flutter/foundation.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final serverProvider = context.watch<ServerProvider>();
    final vpnProvider = context.watch<VpnProvider>();
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final accountUnavailable = isAndroid && !auth.isAccountVerified;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Account section
          _sectionTitle('Account'),
          const SizedBox(height: 8),
          _infoCard(
            context,
            icon: Icons.fingerprint,
            title: 'HWID',
            value: auth.hwid,
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 18, color: Color(0xFF8B95A5)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: auth.hwid));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('HWID copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          _infoCard(
            context,
            icon: auth.isPremium ? Icons.star : Icons.star_border,
            title: 'Account Type',
            value: accountUnavailable
                ? (auth.isLoading ? 'Checking...' : 'Unable to verify')
                : auth.isPremium
                ? 'Premium'
                : auth.isPremiumExpired
                ? 'Premium Expired'
                : 'Free',
            iconColor: auth.isPremium
                ? const Color(0xFFFFD700)
                : const Color(0xFF8B95A5),
          ),
          const SizedBox(height: 8),
          _infoCard(
            context,
            icon: Icons.event_available_outlined,
            title: 'Premium Expiry',
            value: accountUnavailable ? 'Unknown' : auth.premiumExpiryLabel,
            iconColor: auth.isPremiumExpired
                ? const Color(0xFFFF6B6B)
                : const Color(0xFF6C5CE7),
          ),
          if (!auth.isPremium && !accountUnavailable) ...[
            const SizedBox(height: 8),
            _infoCard(
              context,
              icon: Icons.info_outline,
              title: 'How to get Premium',
              value: auth.isPremiumExpired
                  ? 'Premium expired. Buy a plan to renew your account'
                  : 'Buy a plan from the LOKI Network website',
            ),
          ],

          const SizedBox(height: 24),

          // Server section
          _sectionTitle('Servers'),
          const SizedBox(height: 8),
          _infoCard(
            context,
            icon: Icons.dns_outlined,
            title: 'Total Servers',
            value: '${serverProvider.servers.length}',
          ),
          const SizedBox(height: 8),
          _infoCard(
            context,
            icon: Icons.cloud_outlined,
            title: 'Last Updated',
            value: serverProvider.updatedAt.isNotEmpty
                ? serverProvider.updatedAt
                : 'Unknown',
          ),
          const SizedBox(height: 8),
          _infoCard(
            context,
            icon: Icons.tag,
            title: 'Config Version',
            value: 'v${serverProvider.version}',
          ),

          const SizedBox(height: 24),

          // Network section
          _sectionTitle(
            vpnProvider.supportsConnectionModes ? 'Windows Network' : 'VPN',
          ),
          const SizedBox(height: 8),
          if (vpnProvider.supportsConnectionModes) ...[
            _modeCard(context, vpnProvider),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: () async {
              await vpnProvider.disconnect();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('VPN stopped and network settings restored'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            icon: const Icon(Icons.link_off),
            label: Text(
              vpnProvider.supportsConnectionModes
                  ? 'Stop VPN / Restore Network'
                  : 'Stop VPN',
            ),
          ),

          const SizedBox(height: 24),

          // Refresh button
          ElevatedButton.icon(
            onPressed: isAndroid && (auth.isLoading || serverProvider.isLoading)
                ? null
                : () async {
                    final vpnProvider = context.read<VpnProvider>();
                    await auth.refreshPremium();
                    await serverProvider.fetchServers();
                    final selectedServer = serverProvider.selectedServer;
                    if (selectedServer?.isPremium == true &&
                        !auth.isPremium &&
                        (!isAndroid || auth.isAccountVerified) &&
                        vpnProvider.isConnected) {
                      await vpnProvider.disconnect();
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isAndroid &&
                                    (auth.error.isNotEmpty ||
                                        serverProvider.error.isNotEmpty)
                                ? 'Could not refresh account or servers. Please retry.'
                                : 'Refreshed successfully',
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Status'),
          ),

          const SizedBox(height: 24),

          // About section
          _sectionTitle('About'),
          const SizedBox(height: 8),
          if (!kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.android ||
                  defaultTargetPlatform == TargetPlatform.iOS)) ...[
            const PrivacyPolicyButton(),
            const SizedBox(height: 8),
          ],
          _infoCard(
            context,
            icon: Icons.shield_outlined,
            title: 'App Version',
            value: ApiConfig.appVersion,
          ),
          const SizedBox(height: 8),
          _infoCard(
            context,
            icon: Icons.code,
            title: 'VPN Engine',
            value: defaultTargetPlatform == TargetPlatform.iOS
                ? 'Xray (flutter_vless)'
                : 'Xray Core 25.3.6',
          ),
          const SizedBox(height: 24),

          // Footer
          Center(
            child: Text(
              'LOKI Network\nPowered by LUCAS',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF8B95A5),
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _infoCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    Widget? trailing,
    Color? iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2D333B)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor ?? const Color(0xFF6C5CE7), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8B95A5),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _modeCard(BuildContext context, VpnProvider vpnProvider) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2D333B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.route_outlined,
                color: Color(0xFF6C5CE7),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Connection Mode',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<VpnConnectionMode>(
            segments: const [
              ButtonSegment(
                value: VpnConnectionMode.proxy,
                icon: Icon(Icons.public),
                label: Text('Proxy'),
              ),
              ButtonSegment(
                value: VpnConnectionMode.tunnel,
                icon: Icon(Icons.shield_outlined),
                label: Text('Tunnel'),
              ),
            ],
            selected: {vpnProvider.mode},
            onSelectionChanged: (selection) {
              final mode = selection.first;
              () async {
                if (vpnProvider.isConnected || vpnProvider.isConnecting) {
                  await vpnProvider.disconnect();
                }
                await vpnProvider.setMode(mode);
              }();
            },
          ),
          const SizedBox(height: 10),
          Text(
            vpnProvider.isProxyMode
                ? 'Windows system proxy'
                : 'Windows tunnel (administrator required)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
