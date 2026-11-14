// simfps: counts the frames an iOS Simulator's screen actually produces, with no
// encoding and no copy. It attaches to the simulator's framebuffer display the way
// serve-sim does (CoreSimulator's SimDeviceIOClient, registerScreenCallbacks...),
// then polls the framebuffer IOSurface's seed at about 2 kHz: each seed change is a
// new frame the simulator's compositor wrote. Frame callbacks are counted too.
//
//   simfps <udid> <seconds> [label] [--strip]   prints one JSON line
//
// --strip also reads GlassBench's frame strip (a 16-bit counter the app draws every tick, see
// GlassBench/main.swift) from each new surface: how many app frames reached the screen, how many were
// lost on the way (gaps in the counter) and how many surface frames showed no new app frame (repeats).
import Foundation
import IOSurface
import ObjectiveC

typealias FrameCB = @convention(block) () -> Void
typealias SurfCB = @convention(block) (IOSurface?, IOSurface?) -> Void
typealias PropCB = @convention(block) (AnyObject?) -> Void

@objc protocol FramebufferDescriptor {
    @objc(registerScreenCallbacksWithUUID:callbackQueue:frameCallback:surfacesChangedCallback:propertiesChangedCallback:)
    func registerScreenCallbacks(uuid: UUID, callbackQueue: DispatchQueue, frameCallback: @escaping FrameCB,
                                 surfacesChangedCallback: @escaping SurfCB, propertiesChangedCallback: @escaping PropCB)
    @objc(unregisterScreenCallbacksWithUUID:)
    func unregisterScreenCallbacks(uuid: UUID)
    @objc var framebufferSurface: IOSurface? { get }
}

func die(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

let readStrip = CommandLine.arguments.contains("--strip")
let args = CommandLine.arguments.filter { $0 != "--strip" }
guard args.count >= 3, let secs = Double(args[2]) else { die("usage: simfps <udid> <seconds> [label]") }
let udid = args[1], label = args.count > 3 ? args[3] : ""
let dev = "/Applications/Xcode.app/Contents/Developer"
for p in ["/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator",
          "\(dev)/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"] { _ = dlopen(p, RTLD_NOW) }

guard let ctxClass = NSClassFromString("SimServiceContext") as? NSObject.Type,
      let ctx = ctxClass.perform(NSSelectorFromString("sharedServiceContextForDeveloperDir:error:"), with: dev, with: nil)?
          .takeUnretainedValue() as? NSObject,
      let set = ctx.perform(NSSelectorFromString("defaultDeviceSetWithError:"), with: nil)?.takeUnretainedValue() as? NSObject,
      let byUDID = set.value(forKey: "devicesByUDID") as? [NSUUID: NSObject],
      let device = byUDID[NSUUID(uuidString: udid)!]
else { die("simulator \(udid) not found") }
guard let io = device.perform(NSSelectorFromString("io"))?.takeUnretainedValue() as? NSObject else { die("no io client") }
io.perform(NSSelectorFromString("updateIOPorts"))
guard let ports = io.value(forKey: "deviceIOPorts") as? [NSObject] else { die("no io ports") }
// A simulator can have several framebuffer displays (the order varies); take the one whose
// surface is largest, which is the main screen.
var desc: NSObject?
var best = -1
for port in ports {
    guard let pid = port.perform(NSSelectorFromString("portIdentifier"))?.takeUnretainedValue(),
          "\(pid)" == "com.apple.framebuffer.display",
          let d = port.perform(NSSelectorFromString("descriptor"))?.takeUnretainedValue() as? NSObject,
          d.responds(to: NSSelectorFromString("framebufferSurface")) else { continue }
    var width = 0
    if let o = d.perform(NSSelectorFromString("framebufferSurface"))?.takeUnretainedValue() {
        width = IOSurfaceGetWidth(unsafeBitCast(o, to: IOSurface.self))
    }
    if width > best { best = width; desc = d }
}
guard let desc else { die("no framebuffer display") }

let lock = NSLock()
var surface: IOSurface?
var callbacks = 0
let q = DispatchQueue(label: "simfps.cb", qos: .userInteractive)
let uuid = UUID()
let fd = unsafeBitCast(desc, to: FramebufferDescriptor.self)
fd.registerScreenCallbacks(uuid: uuid, callbackQueue: q,
    frameCallback: { lock.lock(); callbacks += 1; lock.unlock() },
    surfacesChangedCallback: { unmasked, masked in lock.lock(); surface = unmasked ?? masked ?? surface; lock.unlock() },
    propertiesChangedCallback: { _ in })
// The surface comes through surfacesChanged, or from the descriptor (unmasked, else masked).
func descriptorSurface() -> IOSurface? {
    for name in ["framebufferSurface", "maskedFramebufferSurface"] {
        let sel = NSSelectorFromString(name)
        if desc.responds(to: sel), let o = desc.perform(sel)?.takeUnretainedValue() { return unsafeBitCast(o, to: IOSurface.self) }
    }
    return nil
}
var waited = 0
while true {
    lock.lock(); if surface == nil { surface = descriptorSurface() }; let s = surface; lock.unlock()
    if s != nil || waited > 500 { break }
    RunLoop.main.run(until: Date().addingTimeInterval(0.01)); waited += 1
}
if surface == nil { FileHandle.standardError.write("descriptor \(type(of: desc)); callbacks \(callbacks)\n".data(using: .utf8)!) }
lock.lock(); let surf0 = surface; let cb0 = callbacks; lock.unlock()
guard let surf0 else { die("framebuffer surface never arrived") }
let w = IOSurfaceGetWidth(surf0), h = IOSurfaceGetHeight(surf0)

var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
func nowNs() -> UInt64 { mach_absolute_time() * UInt64(tb.numer) / UInt64(tb.denom) }
var stamps: [UInt64] = []
var strip: [(UInt64, Int)] = []  // (time, counter or -1 when unreadable)
/// GlassBench's counter from a BGRA surface: 18 blocks of 20 pt from (21, 120) pt, at the surface's scale.
func readCounter(_ s: IOSurface) -> Int {
    let w = IOSurfaceGetWidth(s), h = IOSurfaceGetHeight(s), bpr = IOSurfaceGetBytesPerRow(s)
    let scale = Double(w) / 402.0
    guard IOSurfaceLock(s, .readOnly, nil) == kIOReturnSuccess else { return -1 }
    defer { IOSurfaceUnlock(s, .readOnly, nil) }
    let base = IOSurfaceGetBaseAddress(s).assumingMemoryBound(to: UInt8.self)
    func luma(_ i: Int) -> Int {
        let x = Int((21 + 20 * Double(i) + 10) * scale), y = Int(130 * scale)
        guard x < w, y < h else { return 0 }
        let p = base + y * bpr + x * 4
        return (Int(p[0]) + Int(p[1]) + Int(p[2])) / 3
    }
    let white = luma(0), black = luma(1)
    guard white - black > 100 else { return -1 }
    let mid = (white + black) / 2
    var n = 0
    for b in 0..<16 where luma(b + 2) > mid { n |= 1 << b }
    return n
}
stamps.reserveCapacity(Int(secs * 200))
var polls = 0
let start = nowNs(), end = start + UInt64(secs * 1e9)
var finished = false
// Poll on a thread of its own; the main thread keeps its run loop going for CoreSimulator's replies.
let poller = Thread {
    var lastSeed = IOSurfaceGetSeed(surf0)
    var lastSurf = surf0
    while true {
        let t = nowNs()
        if t >= end { break }
        lock.lock(); let s = surface ?? lastSurf; lock.unlock()
        let seed = IOSurfaceGetSeed(s)
        if s !== lastSurf || seed != lastSeed {
            stamps.append(t); lastSeed = seed; lastSurf = s
            if readStrip { strip.append((t, readCounter(s))) }
        }
        polls += 1
        usleep(500)
    }
    lock.lock(); finished = true; lock.unlock()
}
poller.qualityOfService = .userInteractive
poller.start()
while true {
    lock.lock(); let f = finished; lock.unlock()
    if f { break }
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
lock.lock(); let cbs = callbacks - cb0; lock.unlock()
fd.unregisterScreenCallbacks(uuid: uuid)

var iv: [Double] = []
for i in 1..<max(stamps.count, 1) where stamps.count > 1 { iv.append(Double(stamps[i] - stamps[i - 1]) / 1e6) }
iv.sort()
func pct(_ p: Double) -> Double { iv.isEmpty ? 0 : iv[min(iv.count - 1, Int(Double(iv.count - 1) * p))] }
let span = stamps.count > 1 ? Double(stamps.last! - stamps.first!) / 1e9 : secs
let fps = stamps.count > 1 ? Double(stamps.count - 1) / span : 0
let over = { (ms: Double) in iv.filter { $0 > ms }.count }
let out: [String: Any] = [
    "label": label, "udid": udid, "w": w, "h": h, "secs": secs, "frames": stamps.count,
    "fps": (fps * 10).rounded() / 10, "callbacks": cbs, "polls": polls,
    "p50_ms": (pct(0.5) * 10).rounded() / 10, "p90_ms": (pct(0.9) * 10).rounded() / 10,
    "p99_ms": (pct(0.99) * 10).rounded() / 10, "max_ms": ((iv.last ?? 0) * 10).rounded() / 10,
    "gt25ms": over(25), "gt50ms": over(50), "gt100ms": over(100),
]
var result = out
if readStrip {
    // Unique app frames, their intervals, frames lost between the app and the screen, and repeats.
    var unique: [(UInt64, Int)] = [], repeats = 0, lost = 0, unreadable = 0
    for (t, c) in strip {
        if c < 0 { unreadable += 1; continue }
        if let last = unique.last {
            let d = (c - last.1 + 65536) % 65536
            if d == 0 { repeats += 1; continue }
            if d < 1000 { lost += d - 1 }
        }
        unique.append((t, c))
    }
    var uiv: [Double] = []
    for i in 1..<max(unique.count, 1) where unique.count > 1 { uiv.append(Double(unique[i].0 - unique[i - 1].0) / 1e6) }
    uiv.sort()
    func up(_ p: Double) -> Double { uiv.isEmpty ? 0 : (uiv[min(uiv.count - 1, Int(Double(uiv.count - 1) * p))] * 10).rounded() / 10 }
    let uspan = unique.count > 1 ? Double(unique.last!.0 - unique.first!.0) / 1e9 : secs
    result["strip"] = [
        "unique": unique.count, "unique_fps": unique.count > 1 ? ((Double(unique.count - 1) / uspan) * 10).rounded() / 10 : 0,
        "lost": lost, "repeats": repeats, "unreadable": unreadable,
        "p50_ms": up(0.5), "p95_ms": up(0.95), "p99_ms": up(0.99), "max_ms": up(1.0),
        "gt20ms": uiv.filter { $0 > 20 }.count, "gt34ms": uiv.filter { $0 > 34 }.count,
    ] as [String: Any]
}
let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
