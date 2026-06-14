import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let spellChannel = FlutterMethodChannel(name: "sheep/spellcheck", binaryMessenger: flutterViewController.engine.binaryMessenger)
    spellChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "checkSpelling" {
        guard let text = call.arguments as? String else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Argument must be a string", details: nil))
          return
        }
        let spellChecker = NSSpellChecker.shared
        var misspelledRanges: [[String: Int]] = []
        var currentIndex = 0
        let utf16Count = text.utf16.count
        while currentIndex < utf16Count {
          let checkRange = spellChecker.checkSpelling(of: text, startingAt: currentIndex)
          if checkRange.location == NSNotFound || checkRange.length == 0 {
            break
          }
          misspelledRanges.append([
            "location": checkRange.location,
            "length": checkRange.length
          ])
          let nextIndex = checkRange.location + checkRange.length
          if nextIndex <= currentIndex {
            break
          }
          currentIndex = nextIndex
        }
        result(misspelledRanges)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
