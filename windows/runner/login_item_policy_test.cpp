// Tests for login_item_policy.h (M1.7 launch at login on Windows,
// docs/design/settings-and-expiry.md, "Launch at login"): the HKCU Run value,
// the read-only StartupApproved check, the --login start, and the controller
// behind loginItemStatus and setLoginItem, against a fake registry. No
// Windows dependencies, so this builds anywhere:
//   clang++ -std=c++17 windows/runner/login_item_policy_test.cpp
// (see tool/test_windows_policy.sh). It is not part of the Windows build,
// and it never touches a real registry.
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "login_item_policy.h"

using namespace kusunga::login_item;

static int failures = 0;
#define CHECK(cond)                                              \
  do {                                                           \
    if (!(cond)) {                                               \
      std::printf("FAILED line %d: %s\n", __LINE__, #cond);      \
      failures++;                                                \
    }                                                            \
  } while (0)

// The registry as a map of one Run value and one StartupApproved value.
class FakeRegistry : public Registry {
 public:
  bool has_run = false;
  std::wstring run;
  bool has_approved = false;
  std::vector<unsigned char> approved;
  long read_error = kOk;
  long write_error = kOk;
  long delete_error = kOk;
  long approved_error = kOk;
  int writes = 0;
  int deletes = 0;
  std::vector<std::wstring> written;

  long ReadRunValue(std::wstring* value) override {
    if (read_error != kOk) return read_error;
    if (!has_run) return kNotFound;
    *value = run;
    return kOk;
  }
  long WriteRunValue(const std::wstring& value) override {
    writes++;
    if (write_error != kOk) return write_error;
    has_run = true;
    run = value;
    written.push_back(value);
    return kOk;
  }
  long DeleteRunValue() override {
    deletes++;
    if (delete_error != kOk) return delete_error;
    if (!has_run) return kNotFound;
    has_run = false;
    return kOk;
  }
  long ReadStartupApproved(std::vector<unsigned char>* data) override {
    if (approved_error != kOk) return approved_error;
    if (!has_approved) return kNotFound;
    *data = approved;
    return kOk;
  }
};

static const std::wstring kExe = L"C:\\Users\\a\\AppData\\Local\\Kusunga\\kusunga.exe";

int main() {
  // The keys and the value: per user, the standard Run key, named Kusunga.
  CHECK(std::wstring(kRunKey) ==
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Run");
  CHECK(std::wstring(kStartupApprovedKey) ==
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\"
        L"StartupApproved\\Run");
  CHECK(std::wstring(kValueName) == L"Kusunga");

  // The value is the quoted full exe path, then --login.
  CHECK(RunValueFor(kExe) == L"\"" + kExe + L"\" --login");
  CHECK(RunValueFor(L"C:\\Program Files\\Kusunga\\kusunga.exe") ==
        L"\"C:\\Program Files\\Kusunga\\kusunga.exe\" --login");
  // No path, no value (a write would start nothing useful).
  CHECK(RunValueFor(L"").empty());
  // A path with a quote cannot be quoted safely: no value.
  CHECK(RunValueFor(L"C:\\a\"b.exe").empty());

  // --login, exactly, anywhere in the arguments.
  CHECK(IsLoginLaunch({"--login"}));
  CHECK(IsLoginLaunch({"--other", "qa", "--login"}));
  CHECK(!IsLoginLaunch({}));
  CHECK(!IsLoginLaunch({"--Login"}));
  CHECK(!IsLoginLaunch({"--login=1"}));
  CHECK(!IsLoginLaunch({"login"}));

  // StartupApproved: an odd first byte means turned off in Task Manager;
  // even, empty or missing means allowed.
  CHECK(!ApprovedDisabled(nullptr));
  {
    std::vector<unsigned char> d;
    CHECK(!ApprovedDisabled(&d));
    d = {0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    CHECK(!ApprovedDisabled(&d));
    d[0] = 0x06;
    CHECK(!ApprovedDisabled(&d));
    d[0] = 0x03;
    CHECK(ApprovedDisabled(&d));
    d[0] = 0x07;
    CHECK(ApprovedDisabled(&d));
  }

  // State names: the Dart channel contract (lib/settings/login_item.dart).
  CHECK(std::string(StateName(State::kEnabled)) == "enabled");
  CHECK(std::string(StateName(State::kNotRegistered)) == "notRegistered");
  CHECK(std::string(StateName(State::kDisabledByUser)) == "disabledByUser");
  CHECK(std::string(StateName(State::kError)) == "error");

  // Off by default: no value, not registered; reading writes nothing.
  {
    FakeRegistry reg;
    Controller c(&reg, kExe);
    Answer a = c.Status();
    CHECK(a.state == State::kNotRegistered);
    CHECK(!a.has_error);
    CHECK(reg.writes == 0 && reg.deletes == 0);
  }

  // Turning on writes the value and answers enabled.
  {
    FakeRegistry reg;
    Controller c(&reg, kExe);
    Answer a = c.Set(true);
    CHECK(a.state == State::kEnabled);
    CHECK(reg.has_run && reg.run == RunValueFor(kExe));
    CHECK(reg.writes == 1);
  }

  // Turning on while Task Manager has it off: the value is written, and the
  // answer says turned off in Task Manager. StartupApproved is never written.
  {
    FakeRegistry reg;
    reg.has_approved = true;
    reg.approved = {0x03, 0, 0, 0};
    Controller c(&reg, kExe);
    Answer a = c.Set(true);
    CHECK(a.state == State::kDisabledByUser);
    CHECK(reg.has_run);
    CHECK(reg.approved[0] == 0x03);
  }

  // Status with the value there: enabled, or turned off in Task Manager.
  {
    FakeRegistry reg;
    reg.has_run = true;
    reg.run = RunValueFor(kExe);
    Controller c(&reg, kExe);
    CHECK(c.Status().state == State::kEnabled);
    reg.has_approved = true;
    reg.approved = {0x02};
    CHECK(c.Status().state == State::kEnabled);
    reg.approved = {0x03};
    CHECK(c.Status().state == State::kDisabledByUser);
    // A StartupApproved read error counts as allowed (the Run value decides).
    reg.approved_error = 5;
    CHECK(c.Status().state == State::kEnabled);
  }

  // A Run read error is an error with its number.
  {
    FakeRegistry reg;
    reg.read_error = 5;
    Controller c(&reg, kExe);
    Answer a = c.Status();
    CHECK(a.state == State::kError);
    CHECK(a.has_error && a.error == 5);
  }

  // A failed write is an error with its number; nothing changes.
  {
    FakeRegistry reg;
    reg.write_error = 5;
    Controller c(&reg, kExe);
    Answer a = c.Set(true);
    CHECK(a.state == State::kError);
    CHECK(a.has_error && a.error == 5);
    CHECK(!reg.has_run);
  }

  // No exe path: turning on is an error, and nothing is written.
  {
    FakeRegistry reg;
    Controller c(&reg, L"");
    Answer a = c.Set(true);
    CHECK(a.state == State::kError);
    CHECK(reg.writes == 0);
  }

  // Turning off deletes the value; already off is fine.
  {
    FakeRegistry reg;
    reg.has_run = true;
    reg.run = RunValueFor(kExe);
    Controller c(&reg, kExe);
    CHECK(c.Set(false).state == State::kNotRegistered);
    CHECK(!reg.has_run && reg.deletes == 1);
    CHECK(c.Set(false).state == State::kNotRegistered);
  }

  // A failed delete is an error with its number.
  {
    FakeRegistry reg;
    reg.has_run = true;
    reg.delete_error = 5;
    Controller c(&reg, kExe);
    Answer a = c.Set(false);
    CHECK(a.state == State::kError);
    CHECK(a.has_error && a.error == 5);
  }

  // At each launch while on, the value is rewritten with this exe's path
  // (a moved app keeps working). While off, nothing is written.
  {
    FakeRegistry reg;
    reg.has_run = true;
    reg.run = L"\"D:\\Old\\kusunga.exe\" --login";
    Controller c(&reg, kExe);
    c.RefreshAtLaunch();
    CHECK(reg.run == RunValueFor(kExe));
    CHECK(reg.writes == 1);
    c.RefreshAtLaunch();
    CHECK(reg.writes == 2);
  }
  {
    FakeRegistry reg;
    Controller c(&reg, kExe);
    c.RefreshAtLaunch();
    CHECK(reg.writes == 0 && !reg.has_run);
  }
  {
    FakeRegistry reg;
    reg.read_error = 5;
    Controller c(&reg, kExe);
    c.RefreshAtLaunch();
    CHECK(reg.writes == 0);
  }
  {
    FakeRegistry reg;
    reg.has_run = true;
    Controller c(&reg, L"");
    c.RefreshAtLaunch();
    CHECK(reg.writes == 0);
  }

  // Only ever its own value: every write is RunValueFor(exe).
  {
    FakeRegistry reg;
    Controller c(&reg, kExe);
    c.Set(true);
    c.RefreshAtLaunch();
    c.Set(false);
    c.Set(true);
    for (const auto& w : reg.written) CHECK(w == RunValueFor(kExe));
  }

  if (failures == 0) std::printf("all login item checks passed\n");
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
