// GlassBench: a steady, repeatable iOS 26 UI load for measuring the simulator.
// A table of cards scrolls by itself at a fixed speed (time-based, so a dropped
// frame skips content rather than slowing the scroll) under a glass navigation bar,
// a glass tab bar and a floating glass toolbar with a glass button that keeps pulsing.
// Launch arguments: -noglass (no floating glass, opaque bars), -speed <pt/s>, -nostrip.
//
// The frame strip: every display-link tick draws a 16-bit counter as blocks at the top left, so a
// frame can be told apart from the one before it all the way to a viewer (simfps --strip at the
// simulator's screen, bench/panelbench.py through Simlock's gateway, panel-hook.js in T3's Device panel):
// 18 squares of 20 pt from (21, 120) pt: white, black (the references), then bit 0..15 (white = 1).
// Gaps in the counter are frames lost, repeats are frames shown twice.
import UIKit

let launchArgs = ProcessInfo.processInfo.arguments
let noGlass = launchArgs.contains("-noglass")
let showStrip = !launchArgs.contains("-nostrip")

final class FrameStrip: UIView {
    static let origin = CGPoint(x: 21, y: 120), block: CGFloat = 20
    private var bits: [CALayer] = []
    private(set) var count: UInt16 = 0
    init() {
        super.init(frame: CGRect(x: Self.origin.x, y: Self.origin.y, width: Self.block * 18, height: Self.block))
        isUserInteractionEnabled = false
        for i in 0..<18 {
            let l = CALayer()
            l.frame = CGRect(x: CGFloat(i) * Self.block, y: 0, width: Self.block, height: Self.block)
            l.backgroundColor = (i == 1 ? UIColor.black : UIColor.white).cgColor
            layer.addSublayer(l); bits.append(l)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    func tick() {
        count &+= 1
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for b in 0..<16 { bits[b + 2].backgroundColor = ((count >> UInt16(b)) & 1 == 1 ? UIColor.white : UIColor.black).cgColor }
        CATransaction.commit()
    }
}
var frameStrip: FrameStrip?

/// The app's own frame times: every 5 s, Documents/pace.json gets the display link's tick intervals over the
/// last window (what the app produced, before the compositor, the capture and the stream).
final class TickLog {
    private var stamps: [CFTimeInterval] = []
    private var last = CACurrentMediaTime()
    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("pace.json")
    func tick(_ t: CFTimeInterval, counter: UInt16) {
        stamps.append(t)
        guard t - last >= 5, stamps.count > 1 else { return }
        var iv = zip(stamps, stamps.dropFirst()).map { ($1 - $0) * 1000 }
        iv.sort()
        func p(_ q: Double) -> Double { (iv[min(iv.count - 1, Int(Double(iv.count - 1) * q))] * 10).rounded() / 10 }
        let out: [String: Any] = ["at": Date().timeIntervalSince1970, "counter": Int(counter), "ticks": iv.count,
                                  "fps": ((Double(iv.count) / (stamps.last! - stamps.first!)) * 10).rounded() / 10,
                                  "p50_ms": p(0.5), "p95_ms": p(0.95), "p99_ms": p(0.99), "max_ms": p(1),
                                  "gt20ms": iv.filter { $0 > 20 }.count, "gt34ms": iv.filter { $0 > 34 }.count]
        if let d = try? JSONSerialization.data(withJSONObject: out) {
            var all = (try? Data(contentsOf: url)) ?? Data()
            all.append(d); all.append(0x0a)
            try? all.write(to: url)
        }
        stamps = [t]; last = t
    }
}
let tickLog = TickLog()
let speed: CGFloat = {
    if let i = launchArgs.firstIndex(of: "-speed"), i + 1 < launchArgs.count, let v = Double(launchArgs[i + 1]) { return CGFloat(v) }
    return 900
}()

final class CardCell: UITableViewCell {
    let card = UIView()
    let gradient = CAGradientLayer()
    let icon = UIImageView()
    let title = UILabel()
    let subtitle = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        card.layer.addSublayer(gradient)
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        title.font = .preferredFont(forTextStyle: .title3)
        title.textColor = .white
        subtitle.font = .preferredFont(forTextStyle: .subheadline)
        subtitle.textColor = UIColor.white.withAlphaComponent(0.85)
        subtitle.numberOfLines = 2
        for v in [card, icon, title, subtitle] { v.translatesAutoresizingMaskIntoConstraints = false }
        contentView.addSubview(card)
        card.addSubview(icon); card.addSubview(title); card.addSubview(subtitle)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 44), icon.heightAnchor.constraint(equalToConstant: 44),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        gradient.frame = card.bounds
        CATransaction.commit()
    }

    func configure(_ row: Int) {
        let h = CGFloat(row % 24) / 24
        gradient.colors = [UIColor(hue: h, saturation: 0.75, brightness: 0.95, alpha: 1).cgColor,
                           UIColor(hue: fmod(h + 0.18, 1), saturation: 0.85, brightness: 0.6, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0); gradient.endPoint = CGPoint(x: 1, y: 1)
        let symbols = ["sparkles", "flame.fill", "leaf.fill", "bolt.fill", "drop.fill", "star.fill", "moon.fill", "sun.max.fill"]
        icon.image = UIImage(systemName: symbols[row % symbols.count])
        title.text = "Card \(row + 1)"
        subtitle.text = "Liquid Glass benchmark row \(row + 1). The content keeps moving under the bars and the toolbar."
    }
}

final class BenchViewController: UITableViewController {
    private var link: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private let pulse = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Glass Bench"
        tableView.register(CardCell.self, forCellReuseIdentifier: "card")
        tableView.rowHeight = 112
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemBackground
        tableView.showsVerticalScrollIndicator = false
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: nil, action: nil)
        if noGlass {
            let a = UINavigationBarAppearance(); a.configureWithOpaqueBackground()
            navigationController?.navigationBar.standardAppearance = a
            navigationController?.navigationBar.scrollEdgeAppearance = a
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !noGlass, let host = navigationController?.view, pulse.superview == nil { addFloatingGlass(to: host) }
        guard link == nil else { return }  // viewDidAppear runs again on every return to the app
        link = CADisplayLink(target: self, selector: #selector(step))
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        startTime = CACurrentMediaTime()
        link?.add(to: .main, forMode: .common)
    }

    private func addFloatingGlass(to host: UIView) {
        let bar = UIVisualEffectView(effect: UIGlassEffect())
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.layer.cornerRadius = 30
        bar.cornerConfiguration = .capsule()
        host.addSubview(bar)
        let stack = UIStackView()
        stack.axis = .horizontal; stack.distribution = .equalSpacing; stack.translatesAutoresizingMaskIntoConstraints = false
        for name in ["square.and.arrow.up", "heart", "bubble.left", "bookmark"] {
            let b = UIButton(type: .system); b.setImage(UIImage(systemName: name), for: .normal)
            stack.addArrangedSubview(b)
        }
        bar.contentView.addSubview(stack)
        let orb = UIVisualEffectView(effect: UIGlassEffect())
        orb.translatesAutoresizingMaskIntoConstraints = false
        orb.cornerConfiguration = .capsule()
        host.addSubview(orb)
        pulse.translatesAutoresizingMaskIntoConstraints = false
        pulse.backgroundColor = UIColor.systemPink.withAlphaComponent(0.6)
        pulse.layer.cornerRadius = 14
        orb.contentView.addSubview(pulse)
        let g = host.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 40),
            bar.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -40),
            bar.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -70),
            bar.heightAnchor.constraint(equalToConstant: 60),
            stack.leadingAnchor.constraint(equalTo: bar.contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: bar.contentView.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: bar.contentView.centerYAnchor),
            orb.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -20),
            orb.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -16),
            orb.widthAnchor.constraint(equalToConstant: 64), orb.heightAnchor.constraint(equalToConstant: 64),
            pulse.centerXAnchor.constraint(equalTo: orb.contentView.centerXAnchor),
            pulse.centerYAnchor.constraint(equalTo: orb.contentView.centerYAnchor),
            pulse.widthAnchor.constraint(equalToConstant: 28), pulse.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    @objc private func step() {
        let t = CACurrentMediaTime() - startTime
        let maxY = tableView.contentSize.height - tableView.bounds.height + tableView.adjustedContentInset.bottom
        let minY = -tableView.adjustedContentInset.top
        guard maxY > minY + 1 else { return }
        let range = maxY - minY
        tableView.contentOffset.y = minY + CGFloat(fmod(Double(speed) * t, Double(range)))
        let s = 0.75 + 0.35 * CGFloat(sin(t * 4))
        pulse.transform = CGAffineTransform(scaleX: s, y: s)
        frameStrip?.tick()
        tickLog.tick(link?.timestamp ?? CACurrentMediaTime(), counter: frameStrip?.count ?? 0)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 400 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let c = tableView.dequeueReusableCell(withIdentifier: "card", for: indexPath) as! CardCell
        c.configure(indexPath.row)
        return c
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting s: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: nil, sessionRole: s.role)
        c.delegateClass = SceneDelegate.self
        return c
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let nav = UINavigationController(rootViewController: BenchViewController(style: .plain))
        nav.navigationBar.prefersLargeTitles = true
        nav.tabBarItem = UITabBarItem(title: "Bench", image: UIImage(systemName: "speedometer"), tag: 0)
        let other = UIViewController(); other.view.backgroundColor = .systemBackground
        other.tabBarItem = UITabBarItem(title: "Other", image: UIImage(systemName: "square.grid.2x2"), tag: 1)
        let tabs = UITabBarController(); tabs.viewControllers = [nav, other]
        if noGlass { tabs.tabBar.isHidden = true }
        let w = UIWindow(windowScene: ws); w.rootViewController = tabs; w.makeKeyAndVisible()
        if showStrip { let f = FrameStrip(); w.addSubview(f); frameStrip = f }
        window = w
    }
}
