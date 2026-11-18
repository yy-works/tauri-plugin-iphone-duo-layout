import UIKit

public struct LayoutInsets: Codable, Equatable {
    public var top: CGFloat, right: CGFloat, bottom: CGFloat, left: CGFloat
}
public struct LayoutRect: Codable, Equatable {
    public var x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
    init(_ r: CGRect) { x = r.minX; y = r.minY; width = r.width; height = r.height }
}
public struct LayoutReservedRegion: Codable, Equatable {
    public var kind: String, rect: LayoutRect, active: Bool
}
public struct NativeLayoutSnapshot: Encodable, Equatable {
    public var revision: Int, width: CGFloat, height: CGFloat
    public var safeArea: LayoutInsets
    public var foldState: String
    public var regions: [LayoutReservedRegion]
    /// 实测屏幕圆角四角最大值（pt），nil = 测不到。见 `DisplayCornerRadius`。
    public var cornerRadius: CGFloat?
    /// 逐角圆角（窗口坐标系）。Duo 外屏铰链侧与外侧不同，排版应以这个为准。
    public var cornerRadii: DuoCorners?
    public var cornerRadiusSource: String = "unavailable"
    /// 铰链角度（度），只在 iOS 27.1+ 且系统报告时有值。
    public var hingeAngle: CGFloat?
    public let source = "native"

    /// 换算成 SwiftUI 层用的 `DuoLayout`（三态判定见 `DuoGeometry.classify`）。
    public var duoLayout: DuoLayout {
        let hinge: String? = switch foldState {
        case "folded": "closed"
        case "half": "partiallyOpen"
        case "expanded": "fullyOpen"
        default: nil
        }
        let divisions = regions.filter { $0.kind == "division" }
        let size = CGSize(width: width, height: height)
        let (state, basis) = DuoGeometry.classify(hinge: hinge, hingeAngle: hingeAngle, divisionRegions: divisions.count,
                                                  activeDivisionRegions: divisions.filter(\.active).count, size: size)
        return DuoLayout(size: size,
                         safeArea: DuoInsets(top: safeArea.top, left: safeArea.left, bottom: safeArea.bottom, right: safeArea.right),
                         cornerRadii: cornerRadii ?? cornerRadius.map { DuoCorners(uniform: $0) }, cornerRadiusSource: cornerRadiusSource,
                         state: state, stateBasis: basis, hingeAngle: hingeAngle)
    }
}

/// One reader per view. Distances are in that view's local points (not screen pixels).
@MainActor public final class LayoutSnapshotReader: NSObject {
    private weak var view: UIView?
    private var probe: LayoutProbe?
    private var link: CADisplayLink?
    private var interaction: (any UIInteraction)?
    private var last: NativeLayoutSnapshot?
    private var foldState = "unknown"
    private var hingeAngle: CGFloat?
    private var corner: DisplayCornerRadius.Measurement?
    private var cornerKey: String?
    /// false = 圆角只用 iOS 26 公开 API，不碰 `UIScreen._displayCornerRadius`。
    public var allowPrivateCornerFallback = true
    private var revision = 0
    private var hasLaidOut = false
    public var onChange: ((NativeLayoutSnapshot) -> Void)?
    public var snapshot: NativeLayoutSnapshot? { last }

    deinit { link?.invalidate() }

    public func attach(to view: UIView) {
        detach()
        self.view = view
        let probe = LayoutProbe(frame: view.bounds)
        probe.isUserInteractionEnabled = false
        probe.backgroundColor = .clear
        probe.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        probe.changed = { [weak self] laidOut in
            guard let self else { return }
            if laidOut { self.hasLaidOut = true }
            self.sample()
        }
        self.probe = probe
        view.addSubview(probe)
        if #available(iOS 27.1, *) { installHinge(in: view) }
        // Reserved regions may change without resize. Emit only when values differ.
        let target = DisplayLinkTarget(reader: self)
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick))
        link.preferredFramesPerSecond = 10
        link.add(to: .main, forMode: .common)
        self.link = link
        probe.setNeedsLayout()
    }

    public func detach() {
        link?.invalidate(); link = nil
        if let interaction, let view { view.removeInteraction(interaction) }
        interaction = nil
        probe?.changed = nil; probe?.removeFromSuperview(); probe = nil
        view = nil; last = nil; hasLaidOut = false; foldState = "unknown"; hingeAngle = nil; corner = nil; cornerKey = nil
    }

    public func sample() {
        guard hasLaidOut, let view, view.window != nil,
              view.bounds.width > 0, view.bounds.height > 0 else { return }
        let safe = view.safeAreaInsets
        var regions: [LayoutReservedRegion] = []
        if #available(iOS 27.1, *) {
            regions = reservedRegions(in: view)
        }
        // 圆角只在窗口/屏幕/尺寸变化时重测（测量要临时插一个视图，不放进 10Hz 轮询）。
        if let window = view.window {
            let key = "\(ObjectIdentifier(window).hashValue)|\(ObjectIdentifier(window.screen).hashValue)|\(window.bounds.size)"
            if key != cornerKey { cornerKey = key; corner = DisplayCornerRadius.measure(in: window, allowPrivateFallback: allowPrivateCornerFallback) }
        }
        var next = NativeLayoutSnapshot(revision: 0, width: view.bounds.width, height: view.bounds.height,
            safeArea: LayoutInsets(top: safe.top, right: safe.right, bottom: safe.bottom, left: safe.left),
            foldState: foldState, regions: regions,
            cornerRadius: corner?.radius, cornerRadii: corner?.corners, cornerRadiusSource: corner?.source ?? "unavailable", hingeAngle: hingeAngle)
        if var old = last { old.revision = 0; if old == next { return } }
        revision += 1; next.revision = revision; last = next
        onChange?(next)
    }

    @available(iOS 27.1, *) private func installHinge(in view: UIView) {
        let observer = UIHingeInteraction { [weak self] _, update in
            guard let self else { return }
            if let hinge = update.hinge {
                self.hingeAngle = hinge.angle
                switch hinge.status {
                case .closed: self.foldState = "folded"
                case .partiallyOpen: self.foldState = "half"
                case .fullyOpen: self.foldState = "expanded"
                case .unknown: self.foldState = "unknown"
                @unknown default: self.foldState = "unknown"
                }
            } else { self.foldState = "unknown"; self.hingeAngle = nil }
            self.sample()
        }
        interaction = observer
        view.addInteraction(observer)
    }

    @available(iOS 27.1, *) private func reservedRegions(in view: UIView) -> [LayoutReservedRegion] {
        // frames already include OS margins. Translate a nonzero bounds origin to local 0,0.
        func map(_ region: UIView.ReservedRegion, kind: String) -> LayoutReservedRegion {
            let rect = region.frame.offsetBy(dx: -view.bounds.minX, dy: -view.bounds.minY)
            return LayoutReservedRegion(kind: kind, rect: LayoutRect(rect), active: region.isActive)
        }
        return view.reservedRegions(kind: .division, options: .includeInactive).map { map($0, kind: "division") }
            + view.reservedRegions(kind: .occlusion, options: .includeInactive).map { map($0, kind: "occlusion") }
    }
}

@MainActor private final class LayoutProbe: UIView {
    var changed: ((Bool) -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); changed?(true) }
    override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); changed?(false) }
    override func didMoveToWindow() { super.didMoveToWindow(); setNeedsLayout() }
}

@MainActor private final class DisplayLinkTarget: NSObject {
    weak var reader: LayoutSnapshotReader?
    init(reader: LayoutSnapshotReader) { self.reader = reader }
    @objc func tick() { reader?.sample() }
}
