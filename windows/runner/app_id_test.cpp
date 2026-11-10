// Tests for app_id.h (M1.6 R7): the one rule, shared by the clipboard
// watcher and typed shortcuts, that turns a process's exe path into its app
// id. No Windows dependencies, so this builds anywhere:
//   clang++ -std=c++17 windows/runner/app_id_test.cpp
// (see tool/test_windows_policy.sh). It is not part of the Windows build.
#include <cstdio>
#include <cstdlib>
#include <string>

#include "app_id.h"

using namespace kusunga;

static int failures = 0;
#define CHECK(cond)                                              \
  do {                                                           \
    if (!(cond)) {                                               \
      std::printf("FAILED line %d: %s\n", __LINE__, #cond);      \
      failures++;                                                \
    }                                                            \
  } while (0)

int main() {
  // The file name, lower case.
  CHECK(ExeFileNameLower(L"C:\\Program Files\\1Password\\1Password.EXE") ==
        L"1password.exe");
  CHECK(ExeFileNameLower(L"C:\\Tools\\KeePass.exe") == L"keepass.exe");
  // Forward slashes count too; the last one wins.
  CHECK(ExeFileNameLower(L"C:/Apps/x\\Bitwarden.exe") == L"bitwarden.exe");
  // A bare name stays as it is, in lower case.
  CHECK(ExeFileNameLower(L"KeePassXC.exe") == L"keepassxc.exe");
  // Nothing after the last slash, or nothing at all: empty (unknown).
  CHECK(ExeFileNameLower(L"C:\\Apps\\").empty());
  CHECK(ExeFileNameLower(L"").empty());

  if (failures == 0) std::printf("all app id checks passed\n");
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
