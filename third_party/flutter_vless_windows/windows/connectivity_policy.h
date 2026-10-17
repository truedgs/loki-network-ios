#ifndef FLUTTER_VLESS_CONNECTIVITY_POLICY_H_
#define FLUTTER_VLESS_CONNECTIVITY_POLICY_H_
#include <string>

namespace flutter_vless::native {
struct ConnectivityTarget {
  const char* label;
  const char* url;
  const char* expected_status;
};
inline constexpr ConnectivityTarget kConnectivityTargets[] = {
    {"gstatic", "https://www.gstatic.com/generate_204", "204"},
    {"cloudflare", "https://www.cloudflare.com/cdn-cgi/trace", "200"},
};
inline bool ConnectivityResponseReady(bool completed, const std::string& status,
                                      const ConnectivityTarget& target) {
  return completed && status == target.expected_status;
}
// Every attempt must use the same authenticated proxy. Never fall back to a
// direct request, which could falsely accept a broken VPN.
template <typename Probe, typename Active>
bool CheckConnectivity(Probe probe, Active active) {
  for (const auto& target : kConnectivityTargets) {
    if (!active()) return false;
    if (probe(target)) return active();
  }
  return false;
}
class ConsecutiveHealthFailures {
 public:
  bool ShouldStop(bool healthy) {
    failures_ = healthy ? 0 : failures_ + 1;
    return failures_ >= 2;
  }
 private:
  unsigned failures_ = 0;
};
}  // namespace flutter_vless::native
#endif
