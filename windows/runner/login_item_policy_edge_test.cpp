// Edge tests for login_item_policy.h (M1.7 tester; launch at login on
// Windows, docs/design/settings-and-expiry.md "Launch at login" and "Trust
// boundaries and abuse cases"): quoting of exe paths, the value rewrite at
// launch, the read-only StartupApproved, registry errors, and what the
// channel answer may hold. Fake registry only: it never touches a real one.
//   clang++ -std=c++17 windows/runner/login_item_policy_edge_test.cpp
// (see tool/test_windows_policy.sh).
#include <cstdio>
#include <cstdlib>
#include <string>
#include <type_traits>
#include <vector>

#include "login_item_policy.h"

using namespace kusunga::login_item;

static int failures = 0;
#define CHECK(cond)                                         \
  do {                                                      \
    if (!(cond)) {                                          \
      std::printf("FAILED line %d: %s\n", __LINE__, #cond); \
      failures++;                                           \
    }                                                       \
  } while (0)

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
  int approved_reads = 0;
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
    approved_reads++;
    if (approved_error != kOk) return approved_error;
    if (!has_approved) return kNotFound;
    *data = approved;
    return kOk;
  }
};

static const std::wstring kExe =
    L"C:\\Users\\a\\AppData\\Local\\Kusunga\\kusunga.exe";

int main() {
  // Quoting: the whole path is inside one pair of quotes, then --login.
  const wchar_t* paths[] = {
      L"C:\\Program Files (x86)\\Kusunga App\\kusunga.exe",
      L"C:\\Users\\Zo\u00eb O'Brien\\AppData\\Local\\Kusunga\\kusunga.exe",
      L"\\\\server\\share name\\kusunga.exe",
      L"C:\\a&b\\c^d\\e%PATH%\\f;g\\kusunga.exe",
      L"C:\\  two  spaces  \\kusunga.exe",
      L"D:\\\u65e5\u672c\u8a9e\\kusunga.exe",
  };
  for (const wchar_t* p : paths) {
    const std::wstring exe = p;
    CHECK(RunValueFor(exe) == L"\"" + exe + L"\" --login");
    // Exactly two quotes: nothing in the path can end the quoting early.
    int quotes = 0;
    for (wchar_t c : RunValueFor(exe)) quotes += (c == L'"');
    CHECK(quotes == 2);
  }
  // A long path (MAX_PATH-ish) is not cut.
  {
    std::wstring longpath = L"C:\\";
    while (longpath.size() < 300) longpath += L"folder\\";
    longpath += L"kusunga.exe";
    CHECK(RunValueFor(longpath) == L"\"" + longpath + L"\" --login");
  }
  // A quote anywhere (start, middle, end) means no value at all.
  CHECK(RunValueFor(L"\"C:\\a.exe").empty());
  CHECK(RunValueFor(L"C:\\a\".exe").empty());
  CHECK(RunValueFor(L"C:\\a.exe\"").empty());
  CHECK(RunValueFor(L"C:\\a.exe\" --evil").empty());
  CHECK(RunValueFor(L"\"").empty());
  // The argument is the one the app checks for (D5 A).
  CHECK(std::string(kLoginArgument) == "--login");

  // --login is matched exactly: a prefix, a suffix, a space or a different
  // case is not a login start, and extra arguments around it are fine.
  CHECK(!IsLoginLaunch({"--logins"}));
  CHECK(!IsLoginLaunch({"--login "}));
  CHECK(!IsLoginLaunch({" --login"}));
  CHECK(!IsLoginLaunch({"--LOGIN"}));
  CHECK(!IsLoginLaunch({"-login"}));
  CHECK(!IsLoginLaunch({"--login=true"}));
  CHECK(!IsLoginLaunch({""}));
  CHECK(IsLoginLaunch({"--login", "--login"}));
  CHECK(IsLoginLaunch({"-KusungaDataProfile", "qa", "--login"}));

  // StartupApproved: only the first byte counts; its parity decides.
  for (int b = 0; b < 256; b++) {
    std::vector<unsigned char> d = {static_cast<unsigned char>(b), 0xFF, 0xFF};
    CHECK(ApprovedDisabled(&d) == ((b & 1) == 1));
  }
  {
    std::vector<unsigned char> one = {0x03};
    CHECK(ApprovedDisabled(&one));
    std::vector<unsigned char> evenFirstOddRest = {0x02, 0x01, 0x03};
    CHECK(!ApprovedDisabled(&evenFirstOddRest));
  }

  // Status: every StartupApproved shape.
  {
    FakeRegistry reg;
    reg.has_run = true;
    reg.run = L"anything";
    Controller c(&reg, kExe);
    CHECK(c.Status().state == State::kEnabled);  // no StartupApproved entry
    reg.has_approved = true;
    reg.approved = {};
    CHECK(c.Status().state == State::kEnabled);  // empty
    reg.approved = {0x02, 0, 0, 0};
    CHECK(c.Status().state == State::kEnabled);
    reg.approved = {0x03, 0, 0, 0};
    CHECK(c.Status().state == State::kDisabledByUser);
    reg.approved_error = 5;  // read error: the Run value decides
    CHECK(c.Status().state == State::kEnabled);
    CHECK(reg.writes == 0 && reg.deletes == 0);
  }
  // The Run value is missing: StartupApproved is not even looked at, and an
  // old "disabled" entry does not make the switch look on.
  {
    FakeRegistry reg;
    reg.has_approved = true;
    reg.approved = {0x03};
    Controller c(&reg, kExe);
    Answer a = c.Status();
    CHECK(a.state == State::kNotRegistered);
    CHECK(reg.approved_reads == 0);
  }
  // A read error is an error with the Win32 number, not "off".
  for (long code : {5L, 1450L, 87L}) {
    FakeRegistry reg;
    reg.read_error = code;
    Controller c(&reg, kExe);
    Answer a = c.Status();
    CHECK(a.state == State::kError && a.has_error && a.error == code);
  }

  // Set(true): exactly one write of the quoted value; StartupApproved is only
  // read; the answer is the state afterwards.
  {
    FakeRegistry reg;
    Controller c(&reg, kExe);
    Answer a = c.Set(true);
    CHECK(a.state == State::kEnabled);
    CHECK(reg.writes == 1 && reg.deletes == 0);
    CHECK(reg.written.size() == 1 && reg.written[0] == RunValueFor(kExe));
  }
  // Set(true) while Task Manager has it off: the value is written, the answer
  // says turned off, and nothing in StartupApproved is changed (the fake has
  // no way to change it, and the interface has none: see the guard test).
  {
    FakeRegistry reg;
    reg.has_approved = true;
    reg.approved = {0x03};
    Controller c(&reg, kExe);
    Answer a = c.Set(true);
    CHECK(a.state == State::kDisabledByUser);
    CHECK(reg.writes == 1);
    CHECK(reg.approved == std::vector<unsigned char>({0x03}));
  }
  // Set(true) with an exe path that cannot be quoted: an error, no write, no
  // value that starts something else.
  {
    FakeRegistry reg;
    Controller c(&reg, L"C:\\bad\"name.exe");
    Answer a = c.Set(true);
    CHECK(a.state == State::kError && a.has_error);
    CHECK(reg.writes == 0 && !reg.has_run);
    Controller empty(&reg, L"");
    CHECK(empty.Set(true).state == State::kError);
    CHECK(reg.writes == 0);
  }
  // A failed write is an error with its number and does not read back.
  {
    FakeRegistry reg;
    reg.write_error = 5;
    Controller c(&reg, kExe);
    Answer a = c.Set(true);
    CHECK(a.state == State::kError && a.has_error && a.error == 5);
    CHECK(!reg.has_run);
  }
  // Set(false): deletes only our value; a value that is already gone is fine;
  // another error is reported.
  {
    FakeRegistry reg;
    reg.has_run = true;
    reg.run = L"x";
    Controller c(&reg, kExe);
    CHECK(c.Set(false).state == State::kNotRegistered);
    CHECK(reg.deletes == 1 && reg.writes == 0 && !reg.has_run);
    CHECK(c.Set(false).state == State::kNotRegistered);  // again: fine
    reg.has_run = true;
    reg.delete_error = 5;
    Answer a = c.Set(false);
    CHECK(a.state == State::kError && a.error == 5);
    CHECK(reg.has_run);
  }
  // Off and on, many times: one value, never a second entry.
  {
    FakeRegistry reg;
    Controller c(&reg, kExe);
    for (int i = 0; i < 5; i++) {
      CHECK(c.Set(true).state == State::kEnabled);
      CHECK(c.Set(true).state == State::kEnabled);
      CHECK(c.Set(false).state == State::kNotRegistered);
    }
    CHECK(!reg.has_run);
  }

  // RefreshAtLaunch: only while on. Off writes nothing, ever.
  {
    FakeRegistry reg;
    Controller c(&reg, kExe);
    c.RefreshAtLaunch();
    CHECK(reg.writes == 0 && !reg.has_run);
  }
  // On, with a path that has moved: rewritten to this exe.
  {
    FakeRegistry reg;
    reg.has_run = true;
    reg.run = L"\"C:\\Old Place\\kusunga.exe\" --login";
    Controller c(&reg, kExe);
    c.RefreshAtLaunch();
    CHECK(reg.run == RunValueFor(kExe));
    CHECK(reg.writes == 1);
  }
  // On but turned off in Task Manager: the value is rewritten, the switch
  // stays off in Task Manager, and StartupApproved is not touched.
  {
    FakeRegistry reg;
    reg.has_run = true;
    reg.run = L"old";
    reg.has_approved = true;
    reg.approved = {0x03};
    Controller c(&reg, kExe);
    c.RefreshAtLaunch();
    CHECK(reg.run == RunValueFor(kExe));
    CHECK(reg.approved == std::vector<unsigned char>({0x03}));
    CHECK(c.Status().state == State::kDisabledByUser);
  }
  // A registry read error (not "not found"): nothing is written.
  {
    FakeRegistry reg;
    reg.has_run = true;
    reg.run = L"old";
    reg.read_error = 5;
    Controller c(&reg, kExe);
    c.RefreshAtLaunch();
    CHECK(reg.writes == 0);
  }
  // An exe path that cannot be quoted: the old value is left, not replaced by
  // a broken one.
  {
    FakeRegistry reg;
    reg.has_run = true;
    reg.run = L"old";
    Controller c(&reg, L"C:\\a\"b.exe");
    c.RefreshAtLaunch();
    CHECK(reg.writes == 0 && reg.run == L"old");
  }
  // A failing write at launch does not throw or change what Status says.
  {
    FakeRegistry reg;
    reg.has_run = true;
    reg.run = L"old";
    reg.write_error = 5;
    Controller c(&reg, kExe);
    c.RefreshAtLaunch();
    CHECK(reg.run == L"old");
    CHECK(c.Status().state == State::kEnabled);
  }

  // What crosses the channel: a state name and an optional number. Every
  // answer for every case above is one of the four contract names.
  {
    FakeRegistry reg;
    Controller c(&reg, kExe);
    const char* names[] = {StateName(c.Status().state),
                           StateName(c.Set(true).state),
                           StateName(c.Set(false).state)};
    for (const char* n : names) {
      const std::string s = n;
      CHECK(s == "enabled" || s == "notRegistered" || s == "disabledByUser" ||
            s == "error");
      CHECK(s.find('\\') == std::string::npos);
      CHECK(s.find(':') == std::string::npos);
    }
    CHECK((std::is_trivially_copyable<Answer>::value));
    CHECK(std::string(StateName(static_cast<State>(99))) == "error");
  }

  if (failures == 0) std::printf("login_item_policy_edge_test: all passed\n");
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
