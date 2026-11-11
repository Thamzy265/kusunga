#ifndef RUNNER_LOGIN_ITEM_BRIDGE_H_
#define RUNNER_LOGIN_ITEM_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

#include "login_item_policy.h"

// M1.7 launch at login on Windows: the HKCU Run value (rules in
// login_item_policy.h, tested without Windows in
// login_item_policy_test.cpp). At construction, while launch at login is on,
// the value is rewritten with this exe's path.
//
// Method channel "com.wnasoni.kusunga/login_item" (see
// lib/settings/login_item.dart): "loginItemStatus" (no arguments) and
// "setLoginItem" (a bool) answer {state, error?}; "openLoginItemsSettings"
// does nothing on Windows. No path and no user data cross the channel.
class LoginItemBridge {
 public:
  explicit LoginItemBridge(flutter::BinaryMessenger* messenger);
  ~LoginItemBridge();

  LoginItemBridge(const LoginItemBridge&) = delete;
  LoginItemBridge& operator=(const LoginItemBridge&) = delete;

 private:
  std::unique_ptr<kusunga::login_item::Registry> registry_;
  std::unique_ptr<kusunga::login_item::Controller> controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_LOGIN_ITEM_BRIDGE_H_
