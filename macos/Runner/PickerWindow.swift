import Cocoa
import FlutterMacOS

/// Where the picker and the toast go (UI spec, "Layout" and "Breakpoints").
/// Pure arithmetic, so it is tested without a screen.
enum PickerGeometry {
  static let pickerWidth: CGFloat = 560
  static let pickerHeight: CGFloat = 420
  static let minWidth: CGFloat = 360
  static let minHeight: CGFloat = 240
  static let toastSize = NSSize(width: 360, height: 96)
  static let toastGap: CGFloat = 12

  /// The screen with the pointer; the first one if it is on none of them.
  static func screenFrame(containing point: NSPoint, among frames: [NSRect]) -> NSRect? {
    frames.first { NSMouseInRect(point, $0, false) } ?? frames.first
  }

  /// 560 x 420, centred across the screen, in its upper part. On a screen
  /// narrower than 800 points the width is 90% of it (at least 360).
  static func pickerFrame(in screen: NSRect) -> NSRect {
    var width = pickerWidth
    if screen.width < 800 { width = max(minWidth, screen.width * 0.9) }
    width = min(width, screen.width)
    let height = max(minHeight, min(pickerHeight, screen.height * 0.8, screen.height))
    let x = (screen.midX - width / 2).rounded()
    let top = screen.maxY - screen.height / 6
    let y = max(screen.minY, (top - height).rounded())
    return NSRect(x: x, y: y, width: width, height: height)
  }

  /// Just below and to the right of the pointer, kept on the screen.
  static func toastFrame(pointer: NSPoint, in screen: NSRect) -> NSRect {
    let size = toastSize
    var x = pointer.x + toastGap
    var y = pointer.y - toastGap - size.height
    x = min(max(x, screen.minX), screen.maxX - size.width)
    y = min(max(y, screen.minY), screen.maxY - size.height)
    return NSRect(origin: NSPoint(x: x, y: y), size: size)
  }
}

/// Switches the one window between its normal shape (the history screen) and
/// the two small shapes: the picker and the toast. Remembers how the window was
/// so it can be put back exactly.
final class PickerWindowController {
  enum Mode { case normal, picker, toast }

  private struct Saved {
    let frame: NSRect
    let styleMask: NSWindow.StyleMask
    let level: NSWindow.Level
    let collectionBehavior: NSWindow.CollectionBehavior
    let isOpaque: Bool
    let backgroundColor: NSColor?
    let hasShadow: Bool
    let minSize: NSSize
    let ignoresMouseEvents: Bool
    let viewBackground: NSColor
  }

  private let window: NSWindow
  private let viewController: FlutterViewController
  private var saved: Saved?

  private(set) var mode = Mode.normal

  /// The history window was on screen when the picker opened (Esc brings it
  /// back).
  private(set) var manageWasVisible = false

  init(window: NSWindow, viewController: FlutterViewController) {
    self.window = window
    self.viewController = viewController
  }

  private func screenFrame() -> NSRect {
    let frames = NSScreen.screens.map { $0.visibleFrame }
    return PickerGeometry.screenFrame(containing: NSEvent.mouseLocation, among: frames)
      ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
  }

  private func saveIfNeeded() {
    if saved != nil { return }
    saved = Saved(
      frame: window.frame, styleMask: window.styleMask, level: window.level,
      collectionBehavior: window.collectionBehavior, isOpaque: window.isOpaque,
      backgroundColor: window.backgroundColor, hasShadow: window.hasShadow,
      minSize: window.minSize, ignoresMouseEvents: window.ignoresMouseEvents,
      viewBackground: viewController.backgroundColor ?? NSColor.black)
  }

  private func restoreSaved() {
    guard let s = saved else { return }
    window.styleMask = s.styleMask
    window.minSize = s.minSize
    window.level = s.level
    window.collectionBehavior = s.collectionBehavior
    window.isOpaque = s.isOpaque
    window.backgroundColor = s.backgroundColor
    window.hasShadow = s.hasShadow
    window.ignoresMouseEvents = s.ignoresMouseEvents
    viewController.backgroundColor = s.viewBackground
    window.setFrame(s.frame, display: false)
    // A changed window style can drop the first responder: keys must reach the
    // Flutter view again (the shortcut recorder in the history window).
    window.makeFirstResponder(viewController.view)
    saved = nil
  }

  private func applySmallShape(frame: NSRect) {
    window.styleMask = [.borderless]
    window.minSize = NSSize(width: 0, height: 0)
    window.level = .floating
    // Shows over a full-screen app, on the space the user is in.
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    window.isOpaque = false
    window.backgroundColor = .clear
    viewController.backgroundColor = .clear
    window.hasShadow = true
    window.setFrame(frame, display: true)
  }

  /// After the picker is shown, Kusunga may not be the active app yet (a
  /// global shortcut or a menu-bar click is still being handled), and then the
  /// window cannot be key and gets no keystrokes. The window is asked again a
  /// few times, up to about half a second, until it is key.
  static let focusRetryDelays: [TimeInterval] = [0.05, 0.15, 0.3, 0.5]

  /// Makes Kusunga active, the window key, and the Flutter view the first
  /// responder (a changed window style can drop it).
  private func takeKeyboard() {
    PickerWindowController.activateKusunga()
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(viewController.view)
  }

  private func retryTakingKeyboard(_ remaining: ArraySlice<TimeInterval>) {
    guard let delay = remaining.first else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self = self, self.mode == .picker else { return }
      if !(self.window.isKeyWindow && NSApp.isActive) { self.takeKeyboard() }
      self.retryTakingKeyboard(remaining.dropFirst())
    }
  }

  func enterPicker() {
    if mode == .normal {
      manageWasVisible = window.isVisible && !window.isMiniaturized
    } else if mode == .toast {
      manageWasVisible = false
    }
    saveIfNeeded()
    mode = .picker
    window.ignoresMouseEvents = false
    applySmallShape(frame: PickerGeometry.pickerFrame(in: screenFrame()))
    takeKeyboard()
    retryTakingKeyboard(PickerWindowController.focusRetryDelays[...])
  }

  /// Puts the window back to its normal shape. [showManage] brings the history
  /// window back (in front if [activate]); otherwise the window is hidden.
  func leavePicker(showManage: Bool, activate: Bool) {
    guard mode == .picker else { return }
    mode = .normal
    restoreSaved()
    if showManage {
      if activate {
        takeKeyboard()
      } else {
        window.orderFront(nil)
      }
    } else {
      window.orderOut(nil)
    }
  }

  /// Shows the toast near the pointer without taking focus from the app the
  /// user is in.
  func showToast() {
    guard mode != .picker else { return }
    saveIfNeeded()
    mode = .toast
    let screen = screenFrame()
    applySmallShape(frame: PickerGeometry.toastFrame(pointer: NSEvent.mouseLocation, in: screen))
    window.ignoresMouseEvents = true
    window.orderFrontRegardless()
  }

  func hideToast() {
    guard mode == .toast else { return }
    mode = .normal
    restoreSaved()
    window.orderOut(nil)
  }

  static func activateKusunga() {
    // Both: from a global shortcut or a menu-bar click the cooperative
    // `activate()` of macOS 14 and later can be refused while the other app is
    // still in front, and the older call is the one that forces it.
    NSApp.activate(ignoringOtherApps: true)
    if #available(macOS 14.0, *) {
      NSApp.activate()
    }
  }
}
