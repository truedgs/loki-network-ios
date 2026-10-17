#pragma once
#include <cmath>
#include <limits>
#include <locale>
#include <sstream>
#include <string>

namespace flutter_vless::native {
inline bool SafeLatencyUrl(const std::string& url) {
  if (url.rfind("https://", 0) != 0 || url.size() <= 8 || url.size() > 2048) return false;
  for (unsigned char c : url) if (c <= 32 || c >= 127 || c == '"' || c == '\\') return false;
  return true;
}
// Curl's time_starttransfer includes the proxy, TLS and first response byte,
// not Xray process startup. This is HTTPS latency, not ICMP round-trip time.
inline int ParseLatency(bool completed, const std::string& output) {
  if (!completed) return -1;
  std::istringstream input(output);
  input.imbue(std::locale::classic());
  int status = 0;
  double seconds = 0;
  std::string extra;
  if (!(input >> status >> seconds) || input >> extra || status < 200 || status >= 300
      || !std::isfinite(seconds) || seconds <= 0 || seconds > 60) return -1;
  return static_cast<int>(std::ceil(seconds * 1000));
}
}  // namespace flutter_vless::native
