import 'package:flutter/material.dart';
import '../models/server_model.dart';

/// Server list tile with country flag, name, protocol, tier badge
class ServerTile extends StatelessWidget {
  final ServerModel server;
  final bool isSelected;
  final bool isLocked;
  final bool isFavorite;
  final int? ping;
  final VoidCallback? onTap;
  final VoidCallback? onLockedTap;
  final VoidCallback? onFavoriteTap;

  const ServerTile({
    super.key,
    required this.server,
    this.isSelected = false,
    this.isLocked = false,
    this.isFavorite = false,
    this.ping,
    this.onTap,
    this.onLockedTap,
    this.onFavoriteTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLocked ? onLockedTap : onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1C2128) : const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6C5CE7)
                : const Color(0xFF2D333B),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Country flag
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  server.country,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Server info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        server.protocol.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          color: const Color(0xFF8B95A5),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (!isLocked) ...[
                        const SizedBox(width: 8),
                        Text(
                          ping == null
                              ? 'Testing...'
                              : ping! > 0
                              ? '${ping}ms'
                              : 'Timeout',
                          style: TextStyle(
                            fontSize: 11,
                            color: ping == null
                                ? const Color(0xFF8B95A5)
                                : ping! > 0 && ping! < 200
                                ? const Color(0xFF00B894)
                                : ping! > 0 && ping! < 500
                                ? const Color(0xFFFDCB6E)
                                : const Color(0xFFFF6B6B),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Tier badge or lock
            IconButton(
              tooltip: isFavorite ? 'Remove favorite' : 'Add favorite',
              onPressed: onFavoriteTap,
              icon: Icon(
                isFavorite ? Icons.star : Icons.star_border,
                color: isFavorite
                    ? const Color(0xFFFFD700)
                    : const Color(0xFF8B95A5),
                size: 22,
              ),
            ),
            if (isLocked)
              const Icon(Icons.lock_outline, color: Color(0xFF8B95A5), size: 20)
            else ...[
              if (server.isPremium)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'PRO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00B894).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF00B894).withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text(
                    'FREE',
                    style: TextStyle(
                      color: Color(0xFF00B894),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isSelected
                    ? const Color(0xFF6C5CE7)
                    : const Color(0xFF8B95A5),
                size: 22,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
