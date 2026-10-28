// setmode: list or set the main display's mode (the guest's Reims vGPU display).
//   setmode            list the modes (WxH@Hz, * = current)
//   setmode 2560x1440  switch to that mode (1x), and keep it for later logins
import CoreGraphics
import Foundation
let d = CGMainDisplayID()
let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
let modes = (CGDisplayCopyAllDisplayModes(d, opts) as? [CGDisplayMode]) ?? []
let cur = CGDisplayCopyDisplayMode(d)
let args = CommandLine.arguments
if args.count < 2 {
  for m in modes where m.pixelWidth == m.width {
    let star = (m.pixelWidth == cur?.pixelWidth && m.pixelHeight == cur?.pixelHeight) ? "*" : " "
    print("\(star) \(m.pixelWidth)x\(m.pixelHeight)@\(Int(m.refreshRate))")
  }
  exit(0)
}
let p = args[1].split(separator: "x").compactMap { Int($0) }
guard p.count == 2, let m = modes.first(where: { $0.pixelWidth == p[0] && $0.pixelHeight == p[1] && $0.width == p[0] }) else {
  FileHandle.standardError.write("no 1x mode \(args[1])\n".data(using: .utf8)!); exit(2)
}
if cur?.pixelWidth == m.pixelWidth && cur?.pixelHeight == m.pixelHeight { print("already \(args[1])"); exit(0) }
var cfg: CGDisplayConfigRef?
CGBeginDisplayConfiguration(&cfg)
CGConfigureDisplayWithDisplayMode(cfg, d, m, nil)
let r = CGCompleteDisplayConfiguration(cfg, .permanently)
print(r == .success ? "set \(args[1])" : "failed \(r.rawValue)")
exit(r == .success ? 0 : 1)
