// Duo 安全区层的验证样例（不是业务 App）。启动参数 `-mode before|after`：
//   before：常见错误写法——根视图 .ignoresSafeArea()，顶栏胶囊贴左上角、右侧按钮压系统栏、底部输入栏贴底；
//   after ：同一界面只在根视图挂 .duoSafeArea(bottom: .homeIndicator(reserve: 8))，胶囊加 .duoCornerClipped()。
// 每次几何变化把实测写到 Documents/duo-metrics.json，供截图时取数。
import SwiftUI
import LayoutMetricsNative

@main struct DuoSafeAreaDemoApp: App {
    private let after = UserDefaults.standard.string(forKey: "mode") != "before"
    var body: some Scene {
        WindowGroup {
            if after {
                DemoScreen(mode: "after").duoSafeArea(bottom: .homeIndicator(reserve: 8))
            } else {
                DemoScreen(mode: "before").ignoresSafeArea()
            }
        }
    }
}

final class FrameLog: ObservableObject {
    var frames: [String: CGRect] = [:]
    var layout: DuoLayout?
    var corner: DisplayCornerRadius.Measurement?
    var window: CGRect = .zero
    var windowSafe: UIEdgeInsets = .zero
    var mode = ""
    func set(_ key: String, _ rect: CGRect) { frames[key] = rect; flush() }
    func flush() {
        func r(_ c: CGRect) -> [String: Double] { ["x": c.minX, "y": c.minY, "w": c.width, "h": c.height, "maxX": c.maxX, "maxY": c.maxY] }
        var out: [String: Any] = ["mode": mode, "time": Date().timeIntervalSince1970, "window": r(window),
            "windowSafeArea": ["top": windowSafe.top, "left": windowSafe.left, "bottom": windowSafe.bottom, "right": windowSafe.right],
            "frames": frames.mapValues(r)]
        func c(_ v: DuoCorners?) -> Any { v.map { ["tl": $0.topLeft, "tr": $0.topRight, "bl": $0.bottomLeft, "br": $0.bottomRight] } ?? NSNull() }
        if let corner { out["corner"] = ["radius": corner.radius as Any, "source": corner.source, "corners": c(corner.corners),
                                         "concentric": c(corner.concentric), "screenPrivate": corner.screenPrivate as Any] }
        if let l = layout {
            let i = l.contentInsets(bottom: .homeIndicator(reserve: 8))
            out["duo"] = ["state": l.state.rawValue, "basis": l.stateBasis, "cornerRadius": l.cornerRadius as Any, "cornerRadii": c(l.cornerRadii),
                          "cornerRadiusSource": l.cornerRadiusSource, "hingeAngle": l.hingeAngle as Any,
                          "safeArea": ["top": l.safeArea.top, "left": l.safeArea.left, "bottom": l.safeArea.bottom, "right": l.safeArea.right],
                          "contentInsets": ["top": i.top, "left": i.left, "bottom": i.bottom, "right": i.right]]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]) else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("duo-metrics.json")
        try? data.write(to: url, options: .atomic)
    }
}

/// 独立于被测层的「裁判」：自己读窗口 safeArea 与两种圆角来源，before 模式也能记录系统值。
struct WindowReferee: UIViewRepresentable {
    let log: FrameLog
    func makeUIView(context: Context) -> V { V(log: log) }
    func updateUIView(_ v: V, context: Context) {}
    final class V: UIView {
        let log: FrameLog
        init(log: FrameLog) { self.log = log; super.init(frame: .zero); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() { super.layoutSubviews(); read() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); read() }
        override func didMoveToWindow() { super.didMoveToWindow(); read() }
        func read() {
            guard let w = window else { return }
            log.window = w.bounds; log.windowSafe = w.safeAreaInsets
            log.corner = DisplayCornerRadius.measure(in: w)
            log.flush()
        }
    }
}

struct DemoScreen: View {
    let mode: String
    @Environment(\.duoLayout) private var duo
    @StateObject private var log = FrameLog()
    @State private var text = ""

    private func track(_ key: String) -> some ViewModifier { Track(key: key, log: log) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Group A").font(.headline).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color(red: 0.66, green: 0.2, blue: 0.15), in: Capsule())
                    .modifier(OptionalCornerClip(enabled: mode == "after"))
                    .modifier(track("chip"))
                Text("Group B  Group C  Group D").foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "magnifyingglass").font(.title3)
                    .frame(width: 44, height: 44).background(Color.black.opacity(0.06), in: Circle())
                    .modifier(track("search"))
            }
            .padding(.horizontal, 4).padding(.vertical, 4)
            .background(Color(red: 0.98, green: 0.95, blue: 0.9))
            .modifier(track("toolbar"))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(mode.uppercased()).font(.largeTitle.bold())
                    if let duo {
                        let i = duo.contentInsets(bottom: .homeIndicator(reserve: 8))
                        Text("state \(duo.state.rawValue)  R=\(duo.cornerRadii.map { String(format: "TL%.0f TR%.0f BL%.0f BR%.0f", $0.topLeft, $0.topRight, $0.bottomLeft, $0.bottomRight) } ?? "nil") (\(duo.cornerRadiusSource))")
                        Text(String(format: "safe T%.0f L%.0f B%.0f R%.0f", duo.safeArea.top, duo.safeArea.left, duo.safeArea.bottom, duo.safeArea.right))
                        Text(String(format: "content T%.1f L%.1f B%.1f R%.1f", i.top, i.left, i.bottom, i.right))
                        Text(duo.stateBasis.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(0..<30, id: \.self) { n in
                        Text("Row \(n + 1)  Item A · Item B · Item C").frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10).background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(.horizontal, 12)
            }
            .modifier(track("scroll"))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    TextField("输入消息", text: $text).textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.bar)
                .modifier(track("composer"))
            }
        }
        .background(WindowReferee(log: log).allowsHitTesting(false))
        .onAppear { log.mode = mode }
        .onChange(of: duo) { _, new in log.layout = new; log.flush() }
    }
}

struct Track: ViewModifier {
    let key: String
    let log: FrameLog
    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { log.set(key, $0) }
    }
}

struct OptionalCornerClip: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View { if enabled { content.duoCornerClipped() } else { content } }
}
