// Tester probes for OwnClipboardChanges (M1.4, PM decision D1): a snippet's
// own clipboard change is skipped by its sequence number, once, and any other
// number is an ordinary copy. Builds anywhere (see
// tool/test_windows_policy.sh); not part of the Windows build.
#include <cstdint>
#include <cstdio>
#include <cstdlib>

#include "clipboard_policy.h"

using namespace kusunga;

static int failures = 0;
#define CHECK(cond)                                         \
  do {                                                      \
    if (!(cond)) {                                          \
      std::printf("FAILED line %d: %s\n", __LINE__, #cond); \
      failures++;                                           \
    }                                                       \
  } while (0)

static void Write(OwnClipboardChanges& own, uint32_t sequence) {
  own.BeginWrite();
  own.EndWrite(sequence);
}

int main() {
  {
    // Nothing was ever written by us: no number is ours, even 0.
    OwnClipboardChanges own;
    CHECK(!own.Consume(0));
    CHECK(!own.Consume(1));
    CHECK(!own.Consume(0xFFFFFFFFu));
  }
  {
    // Two snippet writes before the watcher looks: only the newer number is
    // ours (the watcher reads the current number); the older one is not.
    OwnClipboardChanges own;
    Write(own, 8);
    Write(own, 9);
    CHECK(!own.Consume(8));
    OwnClipboardChanges again;
    Write(again, 8);
    Write(again, 9);
    CHECK(again.Consume(9));
    CHECK(!again.Consume(9));
  }
  {
    // A foreign app copies right after our write: its (newer) number is read
    // as an ordinary copy, the record is used up, and our next write is
    // skipped again on its own number.
    OwnClipboardChanges own;
    Write(own, 100);
    CHECK(!own.Consume(101));
    CHECK(!own.Consume(100));  // a stale, reused number is not ours now
    Write(own, 102);
    CHECK(own.Consume(102));
  }
  {
    // The same number twice (a reused or repeated update message): skipped
    // once only. The second one would be read as a copy.
    OwnClipboardChanges own;
    Write(own, 55);
    CHECK(own.Consume(55));
    CHECK(!own.Consume(55));
  }
  {
    // The counter wraps: 0xFFFFFFFF then 0 are different numbers.
    OwnClipboardChanges own;
    Write(own, 0xFFFFFFFFu);
    CHECK(!own.Consume(0));
    Write(own, 0xFFFFFFFFu);
    CHECK(own.Consume(0xFFFFFFFFu));
  }
  {
    // A sequence number of 0 means no access to the clipboard station; a
    // foreign copy numbered 5 is still not ours.
    OwnClipboardChanges own;
    Write(own, 0);
    CHECK(!own.Consume(5));
  }
  {
    // A failed write (the clipboard could not be opened) after an older,
    // unused record: the older record is neither renewed nor made wrong.
    OwnClipboardChanges own;
    Write(own, 40);
    own.BeginWrite();
    own.CancelWrite();
    CHECK(!own.Consume(41));  // another app's copy
    CHECK(!own.Consume(40));  // and the record went with the check above
  }
  {
    // Cancel restores the normal rules at once: a copy that arrives after a
    // failed write is not skipped.
    OwnClipboardChanges own;
    own.BeginWrite();
    own.CancelWrite();
    CHECK(!own.Consume(1));
    CHECK(!own.Consume(2));
  }
  {
    // A finished write leaves no "writing" state behind: an update that
    // arrives after EndWrite is judged by its number alone.
    OwnClipboardChanges own;
    Write(own, 7);
    CHECK(!own.Consume(6));
    CHECK(!own.Consume(7));
  }

  if (failures == 0) std::printf("all own-change edge checks passed\n");
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
