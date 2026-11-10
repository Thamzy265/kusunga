#ifndef RUNNER_APP_ID_H_
#define RUNNER_APP_ID_H_

// The app id of a Windows process: its exe file name in lower case
// ("C:\...\1Password.exe" -> "1password.exe"). One copy, used by the
// clipboard watcher (M1.6, clipboard_bridge.cpp) and typed shortcuts (M1.5,
// typed_shortcut_bridge.cpp). An id lives only for one check (ADR 0005): it
// is never stored, logged or sent to Dart by the watcher.
//
// The path rule has no Windows dependency, so it is tested anywhere
// (app_id_test.cpp); the process lookups below it need <windows.h>.

#include <cwctype>
#include <string>

#ifdef _WIN32
#include <windows.h>
#endif

namespace kusunga {

// The last part of [path] after "\" or "/", in lower case. Empty when there
// is none.
inline std::wstring ExeFileNameLower(const std::wstring& path) {
  const size_t slash = path.find_last_of(L"\\/");
  std::wstring name = slash == std::wstring::npos ? path : path.substr(slash + 1);
  for (wchar_t& c : name) c = static_cast<wchar_t>(std::towlower(c));
  return name;
}

#ifdef _WIN32

inline std::string AppIdUtf8(const std::wstring& wide) {
  if (wide.empty()) return std::string();
  const int size = ::WideCharToMultiByte(CP_UTF8, 0, wide.data(),
                                         static_cast<int>(wide.size()), nullptr,
                                         0, nullptr, nullptr);
  if (size <= 0) return std::string();
  std::string out(static_cast<size_t>(size), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                        out.data(), size, nullptr, nullptr);
  return out;
}

// The full path of a process's executable, or empty if it can't be read
// (for example an elevated process that refuses).
inline std::wstring ImagePathOf(DWORD pid) {
  HANDLE process =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) return std::wstring();
  wchar_t path[MAX_PATH] = {0};
  DWORD size = MAX_PATH;
  const BOOL ok = ::QueryFullProcessImageNameW(process, 0, path, &size);
  ::CloseHandle(process);
  return ok ? std::wstring(path, size) : std::wstring();
}

// "C:\...\1Password.exe" -> "1password.exe" (the app id, UTF-8).
inline std::string AppIdOf(const std::wstring& path) {
  return AppIdUtf8(ExeFileNameLower(path));
}

// The app id of a window's process, or empty if there is no window or its
// process can't be read.
inline std::string AppIdOfWindow(HWND window) {
  if (!window) return std::string();
  DWORD pid = 0;
  ::GetWindowThreadProcessId(window, &pid);
  if (!pid) return std::string();
  const std::wstring path = ImagePathOf(pid);
  return path.empty() ? std::string() : AppIdOf(path);
}

#endif  // _WIN32

}  // namespace kusunga

#endif  // RUNNER_APP_ID_H_
