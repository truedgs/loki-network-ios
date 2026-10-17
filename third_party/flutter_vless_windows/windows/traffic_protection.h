#ifndef FLUTTER_VLESS_TRAFFIC_PROTECTION_H_
#define FLUTTER_VLESS_TRAFFIC_PROTECTION_H_
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>
#include <filesystem>
#include <atomic>
#include <functional>
#include <vector>

namespace flutter_vless {
// Fail-open Windows policy: serialize tunnel ownership and remove legacy
// plugin filters. No new firewall filters are installed.
class TrafficProtection {
 public:
  explicit TrafficProtection(std::function<std::wstring()> dhcp_sid = {}) : dhcp_sid_(std::move(dhcp_sid)) {}
  ~TrafficProtection();
  bool Install(const std::filesystem::path& xray, const NET_LUID* tunnel = nullptr);
  bool Inspect();
  bool Release();
  bool Active() const { return active_.load(); }
  DWORD Error() const { return last_error_.load(); }
  size_t RetainedFilterCount() const { return retained_count_.load(); }
 private:
  bool Open();
  bool DeleteFilters();
  bool OwnedFilterIds(std::vector<UINT64>& ids);
  bool Check(DWORD error) { if (error != ERROR_SUCCESS) last_error_.store(error); return error == ERROR_SUCCESS; }
  HANDLE engine_ = nullptr;
  HANDLE owner_ = nullptr;
  std::atomic<bool> active_{false};
  std::atomic<size_t> retained_count_{0};
  std::atomic<DWORD> last_error_{ERROR_SUCCESS};
  std::function<std::wstring()> dhcp_sid_;
};
}  // namespace flutter_vless
#endif
