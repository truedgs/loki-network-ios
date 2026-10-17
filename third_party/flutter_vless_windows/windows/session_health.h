#pragma once
#include "connectivity_policy.h"
#include "xray_config.h"
#include <chrono>
#include <charconv>
#include <limits>
#include <optional>
#include <set>

namespace flutter_vless::native {
inline std::optional<int64_t> TrafficCounter(const xray_config::Json& value) {
  if (value.is_number_unsigned()) {
    const auto number = value.get<uint64_t>();
    if (number <= static_cast<uint64_t>((std::numeric_limits<int64_t>::max)())) return static_cast<int64_t>(number);
  } else if (value.is_number_integer()) {
    const auto number = value.get<int64_t>();
    if (number >= 0) return number;
  } else if (value.is_string()) {
    const auto& text = value.get_ref<const std::string&>();
    int64_t number = 0;
    const auto parsed = std::from_chars(text.data(), text.data() + text.size(), number);
    if (parsed.ec == std::errc{} && parsed.ptr == text.data() + text.size() && number >= 0) return number;
  }
  return std::nullopt;
}
class SustainedFailure {
 public:
  using Clock = std::chrono::steady_clock;
  explicit SustainedFailure(std::chrono::seconds grace) : grace_(grace) {}
  bool ShouldStop(bool healthy, Clock::time_point now) {
    if (healthy) { since_.reset(); return false; }
    if (!since_) since_ = now;
    return now - *since_ >= grace_;
  }
 private:
  std::chrono::seconds grace_;
  std::optional<Clock::time_point> since_;
};

// Count real remote outbounds, not the local TUN challenge or DNS relay.
inline std::set<std::string> RemoteDownloadKeys(const xray_config::Json& config) {
  std::set<std::string> result;
  if (!config.contains("outbounds") || !config["outbounds"].is_array()) return result;
  for (const auto& outbound : config["outbounds"]) {
    if (!outbound.is_object() || !outbound.contains("protocol") || !outbound["protocol"].is_string()
        || !outbound.contains("tag") || !outbound["tag"].is_string()) continue;
    const auto protocol = outbound["protocol"].get<std::string>();
    if (std::set<std::string>{"vless", "vmess", "trojan", "shadowsocks", "socks", "http", "hysteria", "wireguard"}.count(protocol))
      result.insert("outbound>>>" + outbound["tag"].get<std::string>() + ">>>traffic>>>downlink");
  }
  return result;
}

class RemoteSessionHealth {
 public:
  bool HasProgress(std::optional<int64_t> download) const {
    return download && last_download_ && *download > *last_download_;
  }
  bool ShouldStop(bool probe_healthy, std::optional<int64_t> download) {
    const bool forwarding = HasProgress(download);
    if (download) last_download_ = download;
    return failures_.ShouldStop(probe_healthy || forwarding);
  }
 private:
  std::optional<int64_t> last_download_;
  ConsecutiveHealthFailures failures_;
};
}  // namespace flutter_vless::native
