# Kusunga: market and competitor research (draft)

Status: draft for the lead. Internal only; nothing published. Checked 2026-10-29. Facts I could not confirm from a source are marked *unverified*.

## Competitors

| App | Platforms | History limit | Snippets | Cross-device sync (E2EE?) | Price | Notable weakness |
|---|---|---|---|---|---|---|
| Paste | Mac, iOS | Unlimited | Pinboards (no abbreviations) | iCloud (Apple-only; E2EE *unverified*) | $3.99/mo, $29.99/yr, $89.99 lifetime [1] | Apple-only; users disliked the move to subscription [2] |
| Maccy | Mac | Configurable | No | None | Free, MIT [3] | Mac-only, no sync |
| Raycast | Mac, Windows (beta), iOS | Free: limited (sources say 30 days to 3 months); Pro: unlimited [4] | Yes, typed keywords | Pro: Mac and iOS (E2EE *unverified*) | Free; Pro about $8–10/mo [4] | Windows still in beta; Pro needed for sync |
| Alfred | Mac | Configurable | Yes (Powerpack) | Settings via Dropbox only | About £34 one-off [5] | Mac-only; clipboard is off by default |
| macOS Tahoe Spotlight | Mac | 30 min, 8 h or 7 days, text only [6] | No | No | Built in | Short history; no snippets |
| CopyClip | Mac | Configurable *unverified* | No | No | Free *unverified* | Basic |
| Windows Win+V | Windows | 25 items, cleared on restart unless pinned [7] | Pins only | Microsoft account cloud (encryption not documented) [7] | Built in | Small limit; warnings against syncing passwords [8] |
| Ditto | Windows | 500 default, configurable [9] | No | LAN network sync [10] | Free, open source | Windows-only |
| ClipboardFusion | Windows, plus iOS/Android companion apps | Configurable | Macros/scripts | ClipboardFusion Online (E2EE *unverified*) [11] | Free personal; Pro from $19 lifetime [11] | Windows-centric UI; mobile app is basic |
| CopyQ | Windows, Mac, Linux | Configurable [12] | Scripting, no abbreviations | No | Free, open source [12] | Power-user UI; no mobile |
| 1Clipboard | Windows, Mac | *unverified* | No | Google Drive *unverified* | Free | Looks unmaintained *unverified* |
| Clypy | Mac, Windows, Linux, iOS, Android | Free: local only | Templates, no abbreviations [13] | Yes, encrypted on device, relay sees ciphertext only [13] | Free; Pro about $24–30 one-off [13] | New and unproven; no typed abbreviations |
| ClipCascade | Windows, Mac, Linux, Android, iOS | *unverified* | No | AES-256-GCM, self-hosted [14] | Free, MIT | You must host the server yourself |
| OnePlus Clipt | Android, Windows, Mac | n/a | No | Google Drive | Closed 30 Sep 2023 [15] | Discontinued |
| Gboard | Android (iOS has no clipboard) | Items deleted after 1 h unless pinned; 24 h option in beta [16] | Pins plus personal dictionary | Not clipboard | Free | Short life; not cross-platform |
| SwiftKey | Android, iOS | About 1 h of synced items [17] | Pins | Android to Windows Win+V through Microsoft account [17] | Free | Android to Windows only; no iOS or Mac |
| Apple Universal Clipboard | Apple devices | Only the last item, for a short time [18] | No | Handoff, same Apple Account | Built in | Apple-only; no history |
| TextExpander | Mac, Windows, Chrome, iOS, Android (Android viewer only) [19] | n/a | Yes, core feature | Cloud | About $3.33–4.16/mo per user [19] | Subscription; no clipboard history |
| espanso | Windows, Mac, Linux | n/a | Yes, typed triggers | DIY via Dropbox/Git [20] | Free, open source | No mobile; you edit YAML files |
| Copied (iOS/Mac) | iOS, Mac | Unlimited | Yes | iCloud | Status unclear: pulled in 2022, later reported revived [21] | Unstable future |
| Clipboard++ (iOS), Clipper, Clip Stack, Clipboard Manager (Android) | Single platform | Varies | Clipper: yes | No | Free/freemium [22] | Badly hurt by the Android 10 and iOS 14 changes; several look abandoned *unverified* |

## 1. Does one app do all of this on all four platforms?

No, not completely. Clypy is the closest: all four platforms plus encrypted sync. But it has no typed-abbreviation snippets, and on iOS and Android it has the same OS limits as everyone else. Raycast has history and snippets, but Windows is in beta and it has no Android app. TextExpander has snippets on all four but no clipboard history. **Nobody combines history, typed snippets and E2EE sync on Mac, Windows, iOS and Android.** The gap is real but small, and a well-funded player (Raycast) could close it.

## 2. Platform constraints

- **iOS:** since iOS 14 the system shows a banner when an app reads the clipboard, and since iOS 16 it asks for permission each time unless the user pastes with the system Paste button (`UIPasteControl`), the edit menu or a keyboard shortcut [23]. An app cannot record history in the background. Workarounds: (a) a **custom keyboard** with Full Access. Paste's keyboard needs Full Access for history, but its snippet-only keyboard does not [24]. Full Access worries privacy-minded users [25]. (b) A **share sheet** extension. (c) A Shortcuts action. (d) Capture on the desktop, then sync to the phone. Honest result: on iOS, history is "what you sent to us", not "everything you copied".
- **Android 10+:** only the default keyboard (IME) or the app in focus can read the clipboard [26]. Workarounds: be the keyboard (as Gboard and SwiftKey are); hacks that read system logs over ADB (Tasker/Join), which are fragile and "not guaranteed" [27]; Accessibility-service capture, which Google Play reviews closely. Android 13+ also shows a toast when an app reads the clipboard.
- **Implication:** the snippets half of the idea works well on mobile through a keyboard (no clipboard read is needed to *insert*). Full clipboard history on mobile does not. Plan mobile as "snippets + synced history from desktop + share-sheet capture".

## 3. Gaps and complaints to exploit

- Subscription fatigue around Paste ("paying a sub for this seems strange", MacRumors, Nov 2025) [2].
- No reliable iPhone and Windows bridge. The market is full of small one-feature apps such as Cross Paste and Clipsync [28].
- Built-in tools have short memories: Win+V keeps 25 items and clears on restart; Gboard deletes after 1 h; Spotlight deletes after 8 h by default [6][7][16].
- Cross-platform tools disappear: Clipt was shut down, and Copied was pulled [15][21].
- Snippet tools (TextExpander, espanso) and clipboard tools are separate products, so users run two apps.

## 4. Sensitive data

- **macOS:** good managers skip `org.nspasteboard.ConcealedType`, `TransientType` and `AutoGeneratedType`, which password managers set (Maccy does this by default) [3]. Spotlight leaves out copies from Apple Passwords [6].
- **Android 13+:** apps mark secrets with `ClipDescription.EXTRA_IS_SENSITIVE` to hide the keyboard preview [26]. Respect it.
- **Windows:** Win+V cloud sync uploads every copied item. Guidance says not to copy passwords while sync is on [8]. Respect the `ExcludeClipboardContentFromMonitorProcessing` / `CanIncludeInClipboardHistory` formats (*unverified* for each competitor).
- **Common features:** app ignore lists (Maccy, Alfred), auto-expiry (Gboard, Spotlight), and a clear-all button.
- **Bank details risks:** (1) every paste exposes the data on the system clipboard, where other apps and keyboards can read it; (2) synced copies on a server are a breach target; (3) a Full Access keyboard is a trust problem; (4) storing card numbers on our servers would bring PCI DSS into scope, so store none; (5) the data shows up in screen recordings (reported for Spotlight at launch) [29]. Mitigations: keep sensitive snippets local and encrypted, unlock them with biometrics, mask them in the UI, mark the clipboard as concealed/sensitive on paste, and clear the clipboard automatically after N seconds.

## 5. Differentiation ideas (ranked)

1. **One app, all four platforms, history plus typed snippets.** This is the clear gap (section 1).
2. **End-to-end encrypted sync with no account required (pairing code), local-first.** It answers the cloud-sync worries about Win+V [8] and the shutdowns, and Clypy shows demand [13].
3. **"Secure snippets" vault for bank details and IDs.** Biometric unlock, concealed paste, auto-clear, never synced unless the user opts in. No competitor treats this as a first-class feature.
4. **Mobile keyboard built around snippets first, with history second.** It works inside the OS limits. A snippet keyboard can skip Full Access (Paste's Quick Paste proves this [24]), which is a trust selling point.
5. **Fair pricing: free core plus a one-off unlock for sync.** It answers the Paste subscription complaints [2]. Alfred, ClipboardFusion and Clypy show one-off pricing is viable.
6. **Configurable limits and expiry for each type.** For example, keep 500 text items, keep images 7 days, and never save items from banking apps. Built-in tools are rigid.
7. **Sensitive-content protection by default** (Concealed type, Android sensitive flag, app ignore list, screen-capture masking). This is cheap to build and easy to market, once QA verifies it.

## Sources

1. https://apps.apple.com/app/id967805235 (checked 2026-10-29)
2. https://forums.macrumors.com/threads/what-clipboard-manager-do-you-recommend-to-replace-paste.2470509/ ; https://www.ifun.de/zwischenablage-manager-paste-steigt-auf-abo-modell-um-149588 (checked 2026-10-29)
3. https://github.com/p0deje/Maccy (checked 2026-10-29)
4. https://saas.apppricinglab.com/product/raycast/ ; https://www.raycast.com/changelog/windows/0-38 ; https://tech-insider.org/raycast-vs-alfred-2026/ (checked 2026-10-29)
5. https://www.alfredapp.com/help/features/clipboard/ ; https://makerstack.co/reviews/alfred-review/ (checked 2026-10-29)
6. https://macmost.com/how-to-use-the-spotlight-clipboard-history-in-macos-tahoe.html ; https://macmost.com/whats-new-in-macos-tahoe-26-1.html (checked 2026-10-29)
7. https://support.microsoft.com/help/4464215 (checked 2026-10-29)
8. https://www.hp.com/gb-en/tech-takes/software/how-to/windows-10-clipboard.html (checked 2026-10-29)
9. https://deepwiki.com/sabrogden/Ditto/2.2.2-options-and-configuration (checked 2026-10-29)
10. https://alternativeto.net/software/ditto/about (checked 2026-10-29)
11. https://www.clipboardfusion.com/Compare ; https://clipboardfusion.com/features/syncing/ (checked 2026-10-29)
12. https://copyq.readthedocs.io/en/latest/faq.html ; https://alternativeto.net/software/copyq (checked 2026-10-29)
13. https://www.stork.ai/en/clypy ; https://alternativeto.net/software/clypy/about/ (checked 2026-10-29)
14. https://awesome.ecosyste.ms/projects/github.com%2FUniClipboard%2FUniClipboard (search listing; ClipCascade details *unverified* on its repo) (checked 2026-10-29)
15. https://9to5google.com/2023/09/28/oneplus-clipt-shutting-down/ (checked 2026-10-29)
16. https://androidauthority.com/gboard-clipboard-duration-slider-apk-teardown-3698099 (checked 2026-10-29)
17. https://windowscentral.com/microsoft-rolls-out-another-way-sync-your-clipboard-between-windows-and-android ; https://www.howtogeek.com/745838/how-to-sync-your-clipboard-between-windows-and-android/ (checked 2026-10-29)
18. https://support.apple.com/guide/ipad/aside/ipad2a173dfb/ipados (checked 2026-10-29)
19. https://capterra.com/p/180916/TextExpander/ ; https://textexpander.com/blog/free-text-expander (checked 2026-10-29)
20. https://espanso.org/docs/sync (checked 2026-10-29)
21. https://alternativeto.net/software/copied/about ; https://macsparky.com/?p=9466 (checked 2026-10-29)
22. https://alternativeto.net/software/clipper/?p=5 (checked 2026-10-29)
23. https://developer.apple.com/documentation/uikit/uipastecontrol ; https://sarunw.com/posts/uipasteboard-privacy-change-ios16/ (checked 2026-10-29)
24. https://pasteapp.io/help/enable-and-use-paste-keyboard ; https://apps.apple.com/co/app/paste-keyboard-quick-paste/id6755791867 (checked 2026-10-29)
25. https://www.securing.pl/en/third-party-iphone-keyboards-vs-your-ios-application-security/ (checked 2026-10-29)
26. https://developer.android.com/privacy-and-security/risks/secure-clipboard-handling (checked 2026-10-29)
27. https://joaoapps.com/AutoApps/Help/Info/com.joaomgcd.join/android_10_read_logs.html (checked 2026-10-29)
28. https://apps.apple.com/app/id6755657341 ; https://www.producthunt.com/p/clipsync-2/clipsync-3 (checked 2026-10-29)
29. https://support.ntiva.com/hc/en-us/articles/39853826658701-macOS-Tahoe-Disable-Clipboard-History-in-Spotlight (checked 2026-10-29)

---

Job: research — clipboard and snippets competitors
Draft: docs/marketing/competitor-research.md (path set by the lead; the skill's default would be docs/marketing/research/<topic>.md)
Claims table: n/a — research
QA claim check: n/a — research
Privacy items for the PM: none (note for later: the bank-details vault and any sync server will need a privacy/security design before we make public claims)
Blockers: none
