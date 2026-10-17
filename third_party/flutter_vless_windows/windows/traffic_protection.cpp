#include "traffic_protection.h"
#include <fwpmu.h>
#include <string>

namespace flutter_vless {
namespace {
const GUID provider = {0x258726c7,0x1b37,0x4524,{0xb4,0x53,0x80,0x7a,0xe3,0x17,0x39,0x06}};
}
bool TrafficProtection::Open() {
  if (engine_) return true;
#ifdef FLUTTER_VLESS_TEST_OWNER
  // The recording backend must not compete with a real running VPN session.
  const auto event_name = L"Local\\FlutterVlessPolicyTest-" + std::to_wstring(GetCurrentProcessId());
  owner_ = CreateEventW(nullptr, TRUE, FALSE, event_name.c_str());
#else
  owner_ = CreateEventW(nullptr, TRUE, FALSE, L"Global\\FlutterVlessProtectedVpn");
#endif
  if (!owner_) { last_error_.store(GetLastError()); return false; }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    last_error_.store(ERROR_ALREADY_EXISTS);
    CloseHandle(owner_); owner_ = nullptr; return false;
  }
  if (!Check(FwpmEngineOpen0(nullptr, RPC_C_AUTHN_WINNT, nullptr, nullptr, &engine_))) {
    CloseHandle(owner_); owner_ = nullptr; return false;
  }
  return true;
}
TrafficProtection::~TrafficProtection() {
  // Inspection alone must never change the machine's firewall.
  if (engine_) FwpmEngineClose0(engine_);
  if (owner_) CloseHandle(owner_);
}
bool TrafficProtection::OwnedFilterIds(std::vector<UINT64>& ids) {
  ids.clear();
  HANDLE enumeration = nullptr;
  if (!Check(FwpmFilterCreateEnumHandle0(engine_, nullptr, &enumeration))) return false;
  bool ok = true;
  for (;;) {
    FWPM_FILTER0** entries = nullptr; UINT32 count = 0;
    if (!Check(FwpmFilterEnum0(engine_, enumeration, 256, &entries, &count))) { ok = false; break; }
    for (UINT32 i = 0; i < count; ++i) {
      if (entries[i]->providerKey && IsEqualGUID(*entries[i]->providerKey, provider)) {
        ids.push_back(entries[i]->filterId);
      }
    }
    if (entries) FwpmFreeMemory0(reinterpret_cast<void**>(&entries));
    if (!count) break;
  }
  FwpmFilterDestroyEnumHandle0(engine_, enumeration);
  return ok;
}
bool TrafficProtection::Inspect() {
  if (!Open()) return false;
  std::vector<UINT64> ids;
  if (!OwnedFilterIds(ids)) return false;
  retained_count_.store(ids.size());
  active_.store(!ids.empty());
  return true;
}
bool TrafficProtection::DeleteFilters() {
  std::vector<UINT64> ids;
  if (!OwnedFilterIds(ids)) return false;
  for (auto id : ids) {
    const auto error = FwpmFilterDeleteById0(engine_, id);
    if (error != FWP_E_FILTER_NOT_FOUND && !Check(error)) return false;
  }
  return true;
}
bool TrafficProtection::Install(const std::filesystem::path&, const NET_LUID*) {
  // LOKI explicitly uses fail-open networking. Never add a WFP block rule.
  // Retain the session lock while removing only the old plugin's filters.
  if (!Open() || !Check(FwpmTransactionBegin0(engine_, 0))) return false;
  if (!DeleteFilters()) { FwpmTransactionAbort0(engine_); return false; }
  if (!Check(FwpmTransactionCommit0(engine_))) {
    FwpmTransactionAbort0(engine_); return false;
  }
  retained_count_.store(0);
  active_.store(false);
  return true;
}
bool TrafficProtection::Release() {
  // An explicit stop can recover retained rules even in a fresh process.
  if (!Install({})) return false;
  FwpmEngineClose0(engine_); engine_ = nullptr;
  CloseHandle(owner_); owner_ = nullptr;
  return true;
}
}  // namespace flutter_vless
