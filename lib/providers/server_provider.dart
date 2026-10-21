import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_model.dart';
import '../services/server_service.dart';

/// Provider for server list management
class ServerProvider extends ChangeNotifier {
  ServerProvider({ServerService? serverService})
    : _serverService = serverService ?? ServerService();

  static const _favoriteServerIdsKey = 'favorite_server_ids';
  static const _selectedServerIdKey = 'selected_server_id';

  final ServerService _serverService;
  Future<void>? _pendingFetch;

  List<ServerModel> _servers = [];
  ServerModel? _selectedServer;
  Set<String> _favoriteServerIds = {};
  bool _favoritesLoaded = false;
  bool _isLoading = false;
  String _error = '';
  String _updatedAt = '';
  int _version = 1;
  final Map<String, int> _pings = {}; // server id -> ping ms

  List<ServerModel> get servers => _servers;
  List<ServerModel> get freeServers =>
      _servers.where((s) => !s.isPremium).toList();
  List<ServerModel> get premiumServers =>
      _servers.where((s) => s.isPremium).toList();
  List<ServerModel> get favoriteServers =>
      _servers.where((s) => _favoriteServerIds.contains(s.id)).toList();
  ServerModel? get selectedServer => _selectedServer;
  Set<String> get favoriteServerIds => _favoriteServerIds;
  bool get isLoading => _isLoading;
  String get error => _error;
  String get updatedAt => _updatedAt;
  int get version => _version;
  int? getPing(String serverId) => _pings[serverId];

  /// Fetch servers from backend
  Future<void> fetchServers() async {
    if (!_serverService.usesReliableRequests) return _fetchServers();
    final pending = _pendingFetch;
    if (pending != null) return pending;
    final operation = _fetchServers();
    _pendingFetch = operation;
    try {
      await operation;
    } finally {
      _pendingFetch = null;
    }
  }

  Future<void> _fetchServers() async {
    _isLoading = true;
    _error = '';
    notifyListeners();

    try {
      await _loadFavorites();
      final response = await _serverService.fetchServers();
      _servers = response.servers;
      _updatedAt = response.updatedAt;
      _version = response.version;
      _favoriteServerIds = _favoriteServerIds
          .where((id) => _servers.any((server) => server.id == id))
          .toSet();
      await _restoreSelectedServer();
    } catch (e) {
      _error = e is ServerServiceException
          ? e.message
          : 'Unable to load servers. Check your internet connection and try again.';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Select a server
  Future<void> selectServer(ServerModel server) async {
    _selectedServer = server;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedServerIdKey, server.id);
    notifyListeners();
  }

  bool isFavorite(String serverId) => _favoriteServerIds.contains(serverId);

  Future<void> toggleFavorite(ServerModel server) async {
    await _loadFavorites();
    if (_favoriteServerIds.contains(server.id)) {
      _favoriteServerIds.remove(server.id);
    } else {
      _favoriteServerIds.add(server.id);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _favoriteServerIdsKey,
      _favoriteServerIds.toList(),
    );
    notifyListeners();
  }

  /// Check if a server is accessible for the user's tier
  bool canAccess(ServerModel server, bool isPremium) {
    if (server.isLocked) return false;
    if (server.isPremium) return isPremium;
    return true;
  }

  /// Set ping for a server
  void setPing(String serverId, int ping) {
    _pings[serverId] = ping;
    notifyListeners();
  }

  Future<void> _loadFavorites() async {
    if (_favoritesLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _favoriteServerIds = (prefs.getStringList(_favoriteServerIdsKey) ?? [])
        .where((id) => id.trim().isNotEmpty)
        .toSet();
    _favoritesLoaded = true;
  }

  Future<void> _restoreSelectedServer() async {
    if (_servers.isEmpty) {
      _selectedServer = null;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final selectedId = prefs.getString(_selectedServerIdKey);
    final favorite = favoriteServers.isNotEmpty ? favoriteServers.first : null;
    final stored = selectedId == null ? null : _findServerById(selectedId);
    final current = _selectedServer == null
        ? null
        : _findServerById(_selectedServer!.id);

    _selectedServer =
        stored ??
        current ??
        favorite ??
        (freeServers.isNotEmpty ? freeServers.first : _servers.first);
  }

  ServerModel? _findServerById(String id) {
    for (final server in _servers) {
      if (server.id == id) return server;
    }
    return null;
  }
}
