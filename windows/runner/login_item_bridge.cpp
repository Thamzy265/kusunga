#include "login_item_bridge.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <cstdint>
#include <cwchar>
#include <string>
#include <variant>
#include <vector>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using kusunga::login_item::Answer;
using kusunga::login_item::Controller;
using kusunga::login_item::kRunKey;
using kusunga::login_item::kStartupApprovedKey;
using kusunga::login_item::kValueName;
using kusunga::login_item::Registry;
using kusunga::login_item::StateName;

// The real registry: HKEY_CURRENT_USER only, Kusunga's own value only.
// StartupApproved is read, never written.
class Win32Registry : public Registry {
 public:
  long ReadRunValue(std::wstring* value) override {
    DWORD size = 0;
    LSTATUS status = ::RegGetValueW(HKEY_CURRENT_USER, kRunKey, kValueName,
                                    RRF_RT_REG_SZ, nullptr, nullptr, &size);
    if (status != ERROR_SUCCESS) return status;
    std::wstring buffer(size / sizeof(wchar_t) + 1, L'\0');
    size = static_cast<DWORD>(buffer.size() * sizeof(wchar_t));
    status = ::RegGetValueW(HKEY_CURRENT_USER, kRunKey, kValueName,
                            RRF_RT_REG_SZ, nullptr, buffer.data(), &size);
    if (status != ERROR_SUCCESS) return status;
    buffer.resize(std::wcslen(buffer.c_str()));
    *value = buffer;
    return ERROR_SUCCESS;
  }

  long WriteRunValue(const std::wstring& value) override {
    return ::RegSetKeyValueW(
        HKEY_CURRENT_USER, kRunKey, kValueName, REG_SZ, value.c_str(),
        static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  }

  long DeleteRunValue() override {
    return ::RegDeleteKeyValueW(HKEY_CURRENT_USER, kRunKey, kValueName);
  }

  long ReadStartupApproved(std::vector<unsigned char>* data) override {
    DWORD size = 0;
    LSTATUS status =
        ::RegGetValueW(HKEY_CURRENT_USER, kStartupApprovedKey, kValueName,
                       RRF_RT_REG_BINARY, nullptr, nullptr, &size);
    if (status != ERROR_SUCCESS) return status;
    data->assign(size, 0);
    if (size == 0) return ERROR_SUCCESS;
    status = ::RegGetValueW(HKEY_CURRENT_USER, kStartupApprovedKey,
                            kValueName, RRF_RT_REG_BINARY, nullptr,
                            data->data(), &size);
    if (status != ERROR_SUCCESS) return status;
    data->resize(size);
    return ERROR_SUCCESS;
  }
};

// This process's full path; empty if Windows can't say.
std::wstring ExePath() {
  std::wstring path(MAX_PATH, L'\0');
  for (;;) {
    const DWORD n = ::GetModuleFileNameW(nullptr, path.data(),
                                         static_cast<DWORD>(path.size()));
    if (n == 0) return L"";
    if (n < path.size()) {
      path.resize(n);
      return path;
    }
    if (path.size() >= 32768) return L"";
    path.resize(path.size() * 2);
  }
}

EncodableValue Reply(const Answer& answer) {
  EncodableMap map;
  map[EncodableValue("state")] = EncodableValue(StateName(answer.state));
  if (answer.has_error) {
    map[EncodableValue("error")] =
        EncodableValue(static_cast<int32_t>(answer.error));
  }
  return EncodableValue(map);
}

}  // namespace

LoginItemBridge::LoginItemBridge(flutter::BinaryMessenger* messenger)
    : registry_(std::make_unique<Win32Registry>()),
      controller_(std::make_unique<Controller>(registry_.get(), ExePath())) {
  // While on, point the value at this exe (a moved app keeps working).
  controller_->RefreshAtLaunch();
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "com.wnasoni.kusunga/login_item",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        const std::string& method = call.method_name();
        if (method == "loginItemStatus") {
          result->Success(Reply(controller_->Status()));
        } else if (method == "setLoginItem") {
          const auto* on = std::get_if<bool>(call.arguments());
          if (on == nullptr) {
            result->Error("badArgs");
            return;
          }
          result->Success(Reply(controller_->Set(*on)));
        } else if (method == "openLoginItemsSettings") {
          // Mac only: nothing to open on Windows.
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

LoginItemBridge::~LoginItemBridge() = default;
