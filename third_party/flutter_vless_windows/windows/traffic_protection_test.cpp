// Recording WFP backend: never modifies the machine's firewall.
#include "traffic_protection.h"
#include <fwpmu.h>
#include <algorithm>
#include <cassert>
#include <iostream>
#include <vector>

namespace {
GUID owned = {0x258726c7,0x1b37,0x4524,{0xb4,0x53,0x80,0x7a,0xe3,0x17,0x39,0x06}};
GUID foreign = {0xdec0de,0x1234,0x5678,{1,2,3,4,5,6,7,8}};
std::vector<UINT64> live, pending;
size_t offset = 0;
bool transaction = false, fail_delete = false, fail_commit = false;
int mutations = 0;
}
extern "C" {
DWORD WINAPI FwpmEngineOpen0(const wchar_t*, UINT32, SEC_WINNT_AUTH_IDENTITY_W*, const FWPM_SESSION0*, HANDLE* engine) {
  *engine = reinterpret_cast<HANDLE>(1); return ERROR_SUCCESS;
}
DWORD WINAPI FwpmEngineClose0(HANDLE) { return ERROR_SUCCESS; }
DWORD WINAPI FwpmTransactionBegin0(HANDLE, UINT32) { transaction = true; pending = live; return ERROR_SUCCESS; }
DWORD WINAPI FwpmTransactionAbort0(HANDLE) { transaction = false; pending.clear(); return ERROR_SUCCESS; }
DWORD WINAPI FwpmTransactionCommit0(HANDLE) {
  if (fail_commit) return ERROR_ACCESS_DENIED;
  transaction = false; live = pending; return ERROR_SUCCESS;
}
DWORD WINAPI FwpmFilterCreateEnumHandle0(HANDLE, const FWPM_FILTER_ENUM_TEMPLATE0*, HANDLE* handle) {
  offset = 0; *handle = reinterpret_cast<HANDLE>(1); return ERROR_SUCCESS;
}
DWORD WINAPI FwpmFilterDestroyEnumHandle0(HANDLE, HANDLE) { return ERROR_SUCCESS; }
DWORD WINAPI FwpmFilterEnum0(HANDLE, HANDLE, UINT32 maximum, FWPM_FILTER0*** entries, UINT32* count) {
  const auto& source = transaction ? pending : live;
  *count = std::min<UINT32>(maximum, static_cast<UINT32>(source.size() - offset));
  auto* block = static_cast<unsigned char*>(LocalAlloc(LPTR, std::max<size_t>(1,
      *count * (sizeof(FWPM_FILTER0*) + sizeof(FWPM_FILTER0)))));
  *entries = reinterpret_cast<FWPM_FILTER0**>(block);
  auto* rows = reinterpret_cast<FWPM_FILTER0*>(block + *count * sizeof(FWPM_FILTER0*));
  for (UINT32 i = 0; i < *count; ++i) {
    rows[i].filterId = source[offset + i];
    rows[i].providerKey = rows[i].filterId == 9999 ? &foreign : &owned;
    (*entries)[i] = &rows[i];
  }
  offset += *count;
  return ERROR_SUCCESS;
}
void WINAPI FwpmFreeMemory0(void** value) { LocalFree(*value); *value = nullptr; }
DWORD WINAPI FwpmFilterDeleteById0(HANDLE, UINT64 id) {
  assert(transaction && id != 9999);
  if (fail_delete) return ERROR_ACCESS_DENIED;
  ++mutations;
  pending.erase(std::remove(pending.begin(), pending.end(), id), pending.end());
  return ERROR_SUCCESS;
}
DWORD WINAPI FwpmFilterAdd0(HANDLE, const FWPM_FILTER0*, PSECURITY_DESCRIPTOR, UINT64*) {
  assert(false && "Fail-open builds must never add WFP filters"); return ERROR_ACCESS_DENIED;
}
}
int main() {
  live = {9999, 1, 2};
  {
    flutter_vless::TrafficProtection policy;
    assert(policy.Inspect() && policy.RetainedFilterCount() == 2);
  }
  assert(mutations == 0 && live.size() == 3);
  {
    flutter_vless::TrafficProtection policy;
    assert(policy.Install(L"unused.exe"));
    assert(!policy.Active() && live == std::vector<UINT64>{9999});
    assert(policy.Install(L"unused.exe"));
    assert(policy.Release());
  }
  for (UINT64 id = 1; id <= 600; ++id) live.push_back(id);
  {
    flutter_vless::TrafficProtection policy;
    assert(policy.Inspect() && policy.RetainedFilterCount() == 600);
    fail_delete = true;
    assert(!policy.Release() && live.size() == 601);
    fail_delete = false; fail_commit = true;
    assert(!policy.Release() && live.size() == 601);
    fail_commit = false;
    assert(policy.Release() && live == std::vector<UINT64>{9999});
  }
  live.push_back(42);
  {
    flutter_vless::TrafficProtection policy;
    assert(policy.Release());
    assert(live == std::vector<UINT64>{9999});
  }
  std::cout << "PASS: no new blocking rules; read-only inspection; scoped legacy cleanup; atomic rollback; repeated cleanup\n";
}
