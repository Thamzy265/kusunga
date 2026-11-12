#ifndef RUNNER_LOGIN_ITEM_POLICY_H_
#define RUNNER_LOGIN_ITEM_POLICY_H_

// Launch at login on Windows (M1.7, docs/design/settings-and-expiry.md,
// "Launch at login"). Per user, no admin rights:
//  - on: the value "Kusunga" under HKCU\Software\Microsoft\Windows\
//    CurrentVersion\Run is the quoted full exe path, then --login;
//  - off: the value is deleted;
//  - while on, the value is rewritten at each launch, so a moved app keeps
//    working;
//  - Task Manager's switch lives in ...\Explorer\StartupApproved\Run. It is
//    only ever read, never written: an odd first byte means turned off.
// The registry is behind [Registry], so the rules are tested anywhere
// (login_item_policy_test.cpp); login_item_bridge.cpp supplies the Windows
// calls. Nothing here is stored by Kusunga: the registry is the truth.

#include <string>
#include <utility>
#include <vector>

namespace kusunga {
namespace login_item {

constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kStartupApprovedKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\"
    L"StartupApproved\\Run";
constexpr wchar_t kValueName[] = L"Kusunga";

// The argument a login start passes (D5 A: then no window opens).
constexpr char kLoginArgument[] = "--login";

// Registry results, as Win32 numbers (ERROR_SUCCESS, ERROR_FILE_NOT_FOUND).
constexpr long kOk = 0;
constexpr long kNotFound = 2;

// The Run value for [exe]: "<exe>" --login. Empty when there is no path or
// the path cannot be quoted safely (it holds a quote).
inline std::wstring RunValueFor(const std::wstring& exe) {
  if (exe.empty() || exe.find(L'"') != std::wstring::npos) return L"";
  return L"\"" + exe + L"\" --login";
}

// True when the command line holds exactly "--login".
inline bool IsLoginLaunch(const std::vector<std::string>& args) {
  for (const auto& a : args) {
    if (a == kLoginArgument) return true;
  }
  return false;
}

// Task Manager turned the entry off: StartupApproved's first byte is odd
// (0x03, 0x07). Even (0x02, 0x06), empty or missing means allowed.
inline bool ApprovedDisabled(const std::vector<unsigned char>* data) {
  return data != nullptr && !data->empty() && ((*data)[0] & 1) == 1;
}

// What the channel answers. The names are the Dart contract
// (lib/settings/login_item.dart).
enum class State { kEnabled, kNotRegistered, kDisabledByUser, kError };

inline const char* StateName(State s) {
  switch (s) {
    case State::kEnabled:
      return "enabled";
    case State::kNotRegistered:
      return "notRegistered";
    case State::kDisabledByUser:
      return "disabledByUser";
    case State::kError:
      return "error";
  }
  return "error";
}

// A state and, for an error, the Win32 error number. Nothing else crosses
// the channel: no path and no user data.
struct Answer {
  State state;
  bool has_error;
  long error;
};

// The four registry operations, all under HKEY_CURRENT_USER and all on
// Kusunga's own value. Each returns a Win32 error number (kOk, kNotFound,
// ...).
class Registry {
 public:
  virtual ~Registry() = default;
  virtual long ReadRunValue(std::wstring* value) = 0;
  virtual long WriteRunValue(const std::wstring& value) = 0;
  virtual long DeleteRunValue() = 0;
  virtual long ReadStartupApproved(std::vector<unsigned char>* data) = 0;
};

class Controller {
 public:
  // [exe] is this process's full path; [registry] outlives the controller.
  Controller(Registry* registry, std::wstring exe)
      : registry_(registry), exe_(std::move(exe)) {}

  Answer Status() {
    std::wstring value;
    const long read = registry_->ReadRunValue(&value);
    if (read == kNotFound) return Ok(State::kNotRegistered);
    if (read != kOk) return Error(read);
    std::vector<unsigned char> approved;
    // A StartupApproved read error counts as allowed: the Run value decides.
    if (registry_->ReadStartupApproved(&approved) == kOk &&
        ApprovedDisabled(&approved)) {
      return Ok(State::kDisabledByUser);
    }
    return Ok(State::kEnabled);
  }

  Answer Set(bool on) {
    if (on) {
      const std::wstring value = RunValueFor(exe_);
      if (value.empty()) return Error(kNotFound);
      const long write = registry_->WriteRunValue(value);
      if (write != kOk) return Error(write);
    } else {
      const long removed = registry_->DeleteRunValue();
      if (removed != kOk && removed != kNotFound) return Error(removed);
    }
    return Status();
  }

  // At launch: while on, rewrite the value with this exe's path.
  void RefreshAtLaunch() {
    std::wstring value;
    if (registry_->ReadRunValue(&value) != kOk) return;
    const std::wstring ours = RunValueFor(exe_);
    if (ours.empty()) return;
    registry_->WriteRunValue(ours);
  }

 private:
  static Answer Ok(State s) { return Answer{s, false, 0}; }
  static Answer Error(long code) { return Answer{State::kError, true, code}; }

  Registry* registry_;
  std::wstring exe_;
};

}  // namespace login_item
}  // namespace kusunga

#endif  // RUNNER_LOGIN_ITEM_POLICY_H_
