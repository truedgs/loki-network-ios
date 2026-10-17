import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/server_model.dart';
import '../providers/auth_provider.dart';
import '../providers/server_provider.dart';
import '../providers/vpn_provider.dart';
import '../widgets/server_tile.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key});

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<String> _queuedPings = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();
    final auth = context.watch<AuthProvider>();
    final vpn = context.watch<VpnProvider>();
    final isPremium = auth.isPremium;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Server'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFA29BFE),
          unselectedLabelColor: const Color(0xFF8B95A5),
          indicatorColor: const Color(0xFF6C5CE7),
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(text: 'Favorites'),
            Tab(text: 'Free'),
            Tab(text: 'Premium'),
          ],
        ),
      ),
      body: serverProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : serverProvider.error.isNotEmpty
          ? _buildErrorView(serverProvider)
          : TabBarView(
              controller: _tabController,
              children: [
                _buildServerList(
                  serverProvider.favoriteServers,
                  isPremium,
                  vpn,
                ),
                _buildServerList(serverProvider.freeServers, isPremium, vpn),
                _buildServerList(serverProvider.premiumServers, isPremium, vpn),
              ],
            ),
    );
  }

  Widget _buildServerList(
    List<ServerModel> servers,
    bool isPremium,
    VpnProvider vpn,
  ) {
    if (servers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.dns_outlined, size: 48, color: Color(0xFF8B95A5)),
            const SizedBox(height: 12),
            Text(
              'No servers available',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    _queuePingChecks(servers, isPremium, vpn);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: servers.length,
      itemBuilder: (context, index) {
        final server = servers[index];
        final isSelected =
            context.read<ServerProvider>().selectedServer?.id == server.id;
        final isFavorite = context.watch<ServerProvider>().isFavorite(
          server.id,
        );
        final isLocked = server.isLocked || (server.isPremium && !isPremium);

        return ServerTile(
          server: server,
          isSelected: isSelected,
          isLocked: isLocked,
          isFavorite: isFavorite,
          ping: context.read<ServerProvider>().getPing(server.id),
          onFavoriteTap: () {
            context.read<ServerProvider>().toggleFavorite(server);
          },
          onLockedTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Premium server is locked. Contact admin to buy Premium.',
                ),
                backgroundColor: Color(0xFFFF6B6B),
              ),
            );
          },
          onTap: () {
            final serverProvider = context.read<ServerProvider>();
            final vpnProvider = context.read<VpnProvider>();

            serverProvider.selectServer(server);

            // If VPN is connected, reconnect to the new server
            if (vpnProvider.isConnected) {
              vpnProvider.disconnect().then((_) {
                Future.delayed(const Duration(milliseconds: 500), () {
                  vpnProvider.connect(server.uri);
                });
              });
            }

            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  void _queuePingChecks(
    List<ServerModel> servers,
    bool isPremium,
    VpnProvider vpn,
  ) {
    final provider = context.read<ServerProvider>();
    final pending = servers.where((server) {
      final canMeasure = !server.isPremium || isPremium;
      return canMeasure &&
          !server.isLocked &&
          server.uri.isNotEmpty &&
          provider.getPing(server.id) == null &&
          _queuedPings.add(server.id);
    }).toList();

    if (pending.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (final server in pending) {
        if (!mounted) return;
        final delay = await vpn.getServerDelayFromLink(server.uri);
        if (!mounted) return;
        context.read<ServerProvider>().setPing(server.id, delay);
      }
    });
  }

  Widget _buildErrorView(ServerProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Color(0xFFFF6B6B)),
            const SizedBox(height: 16),
            Text(
              'Failed to load servers',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              provider.error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => provider.fetchServers(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
