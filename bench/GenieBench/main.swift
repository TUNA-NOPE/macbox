// GenieBench: the macOS desktop load. A large window of its own (no Automation
// permission needed) is minimized into the Dock and restored, with the Dock's effect (Genie),
// a given number of times; each phase's start is written to ~/Library/Logs/geniebench.log so the
// host's per-second frame statistics (REIMS_VGPU_STATS) can be matched to it.
//   open -a GenieBench.app --args <cycles>
import AppKit

final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var cycles = 6
    let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/geniebench.log")

    func note(_ s: String) {
        let line = "\(Date().timeIntervalSince1970) \(s)\n"
        if let h = try? FileHandle(forWritingTo: log) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.write(to: log, atomically: true, encoding: .utf8) }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        if let a = CommandLine.arguments.dropFirst().first, let c = Int(a) { cycles = c }
        let frame = NSRect(x: 120, y: 120, width: 2400, height: 1100)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "GenieBench"
        let v = NSView(frame: frame)
        v.wantsLayer = true
        let g = CAGradientLayer()
        g.frame = v.bounds
        g.colors = [NSColor.systemPink.cgColor, NSColor.systemIndigo.cgColor, NSColor.systemTeal.cgColor]
        g.startPoint = CGPoint(x: 0, y: 0); g.endPoint = CGPoint(x: 1, y: 1)
        v.layer?.addSublayer(g)
        let t = NSTextField(labelWithString: "Genie benchmark")
        t.font = .systemFont(ofSize: 96, weight: .bold); t.textColor = .white
        t.frame = NSRect(x: 160, y: 480, width: 2000, height: 140)
        v.addSubview(t)
        window.contentView = v
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        note("start cycles=\(cycles)")
        run(0)
    }

    func run(_ i: Int) {
        guard i < cycles else { note("end"); DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.note("minimize \(i)")
            self.window.miniaturize(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.note("restore \(i)")
                self.window.deminiaturize(nil)
                self.run(i + 1)
            }
        }
    }
}

let app = NSApplication.shared
let d = Delegate()
app.delegate = d
app.setActivationPolicy(.regular)
app.run()
