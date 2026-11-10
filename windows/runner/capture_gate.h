#ifndef RUNNER_CAPTURE_GATE_H_
#define RUNNER_CAPTURE_GATE_H_

// M1.6 sensitive-content protection (docs/design/sensitive-content.md,
// option A; ADR 0005). Before any clipboard text is read, the watcher checks,
// in this order: the secret markers (clipboard_policy.h), the pause against
// the wall clock, then the source app against the ignore list. No Windows
// dependencies, so it is tested anywhere (capture_gate_test.cpp).
//
// The source app's exe name lives only inside DecideCapture, for one copy:
// it is never stored, logged or sent to Dart.

#include <cstdint>
#include <set>
#include <string>
#include <utility>

#include "clipboard_policy.h"

namespace kusunga {

// 0 not paused, -1 paused until resumed, otherwise the end time in ms since
// 1970 (UTC). At the end time the pause is over.
inline bool IsPausedAt(int64_t until, int64_t now_ms) {
  return until == -1 || until > now_ms;
}

// A FILETIME (100 ns units since 1601, from GetSystemTimeAsFileTime) as ms
// since 1970. A time before 1970 counts as 0.
inline int64_t FileTimeToEpochMs(uint64_t ticks) {
  constexpr uint64_t kEpochTicks = 116444736000000000ULL;
  if (ticks <= kEpochTicks) return 0;
  return static_cast<int64_t>((ticks - kEpochTicks) / 10000ULL);
}

// The app a copy came from: the clipboard owner's process, or, when there is
// no owner (some apps write with no window) or its name can't be read, the
// foreground window's process. Empty means unknown. Each lookup returns the
// lower-case exe name or an empty string; [foreground] is only asked when
// [owner] gives nothing.
template <typename OwnerFn, typename ForegroundFn>
std::string ChooseSource(OwnerFn owner, ForegroundFn foreground) {
  std::string id = owner();
  if (!id.empty()) return id;
  return foreground();
}

// The pause and the ignore list, as Dart last sent them.
class CaptureGate {
 public:
  // Any value below -1 counts as "not paused".
  void SetPause(int64_t until) { paused_until_ = until < -1 ? 0 : until; }
  void SetIgnored(std::set<std::string> app_ids) {
    ignored_ = std::move(app_ids);
  }

  int64_t paused_until() const { return paused_until_; }
  const std::set<std::string>& ignored() const { return ignored_; }

 private:
  int64_t paused_until_ = 0;
  std::set<std::string> ignored_;
};

enum class CaptureOutcome {
  kSecret,      // marked secret: never read (as M1.2)
  kPaused,      // history is paused: never read, nothing sent
  kIgnoredApp,  // from an app on the list: never read
  kRead,        // read the text as today
};

struct CaptureDecision {
  CaptureOutcome outcome;
  // The list is not empty but the source app could not be found, so the
  // copy is read as today (fail open). Logged as a code only.
  bool source_unknown;
};

inline std::string LowerAscii(std::string s) {
  for (char& c : s) {
    if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
  }
  return s;
}

// The whole check order. [source] is called at most once, and only when the
// copy is not secret, history is not paused and the list is not empty.
template <typename SourceFn>
CaptureDecision DecideCapture(const ClipboardFlags& flags,
                              const CaptureGate& gate, int64_t now_ms,
                              SourceFn source) {
  if (IsSecret(flags)) return {CaptureOutcome::kSecret, false};
  if (IsPausedAt(gate.paused_until(), now_ms)) {
    return {CaptureOutcome::kPaused, false};
  }
  if (gate.ignored().empty()) return {CaptureOutcome::kRead, false};
  const std::string app = LowerAscii(source());
  if (app.empty()) return {CaptureOutcome::kRead, true};
  if (gate.ignored().count(app) > 0) return {CaptureOutcome::kIgnoredApp, false};
  return {CaptureOutcome::kRead, false};
}

enum class OpenStep {
  kPaused,  // history is paused: the clipboard was not opened
  kLocked,  // another app held it open through every attempt
  kOpened,  // open now; the caller closes it
};

// Before the clipboard is opened (R6): while paused, a copy is skipped at
// once, so it never opens the clipboard, waits on it or reports "locked".
// Otherwise it is opened with OpenWithRetry, and DecideCapture still checks
// the secret markers first, then the pause again, then the source app.
template <typename OpenFn, typename SleepFn>
OpenStep OpenUnlessPaused(const CaptureGate& gate, int64_t now_ms, OpenFn open,
                          SleepFn sleep_ms) {
  if (IsPausedAt(gate.paused_until(), now_ms)) return OpenStep::kPaused;
  return OpenWithRetry(open, sleep_ms) ? OpenStep::kOpened : OpenStep::kLocked;
}

}  // namespace kusunga

#endif  // RUNNER_CAPTURE_GATE_H_
