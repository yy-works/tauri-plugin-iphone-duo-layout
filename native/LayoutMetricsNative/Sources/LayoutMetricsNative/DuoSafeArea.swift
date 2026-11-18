import SwiftUI
import UIKit

// SwiftUI 适配层。对外三样：
//   DuoLayoutMetrics        —— ObservableObject：三态 + 四边安全区 + 圆角半径 + 判定依据
//   .duoSafeArea(...)       —— 把内容限制在「安全区 ∩ 屏幕圆角内」，可选底边策略
//   .duoCornerClipped()     —— 按实测屏幕圆角做同心裁切（背景不再跑出圆角）
// 只依赖 SwiftUI + UIKit 公开几何（iOS 27.1 铰链/保留区按 #available 守卫），不依赖任何业务类型。
//
// 最小示例：
//   @main struct App: SwiftUI.App {
//     var body: some Scene { WindowGroup {
//       RootView()
//         .duoSafeArea(bottom: .homeIndicator(reserve: 8))    // 根视图挂一次
//         .background(Color.paper.ignoresSafeArea())          // 背景照常铺满
//     } }
//   }
//   struct Chip: View { @Environment(\.duoLayout) var duo
//     var body: some View { Text("贾家").padding(8).background(.red).duoCornerClipped() } }

/// 环境值：最近一次测量。根视图挂 `.duoSafeArea()` 后，子视图都能读到；未测到前为 nil。
private struct DuoLayoutKey: EnvironmentKey { static let defaultValue: DuoLayout? = nil }
public extension EnvironmentValues {
    var duoLayout: DuoLayout? {
        get { self[DuoLayoutKey.self] }
        set { self[DuoLayoutKey.self] = newValue }
    }
}

/// 可观察的测量源。通常不用自己建：`.duoSafeArea()` 内部持有一个，并经 `.environmentObject` 下发。
/// 需要在非 SwiftUI 代码里共享时，可自建后传给 `.duoSafeArea(metrics:)`。
@MainActor public final class DuoLayoutMetrics: ObservableObject {
    /// 最近测量；首帧前为 nil（此时 `.duoSafeArea()` 不改动系统安全区）。
    @Published public private(set) var layout: DuoLayout?
    public var state: DuoFoldState { layout?.state ?? .notFoldable }
    public var safeArea: DuoInsets { layout?.safeArea ?? .zero }
    public var cornerRadius: CGFloat? { layout?.cornerRadius }
    public var cornerRadii: DuoCorners? { layout?.cornerRadii }

    private let reader = LayoutSnapshotReader()

    /// - Parameter allowPrivateCornerFallback: iOS 26 以下是否用 `UIScreen._displayCornerRadius` 兜底。
    public init(allowPrivateCornerFallback: Bool = true) {
        reader.allowPrivateCornerFallback = allowPrivateCornerFallback
        reader.onChange = { [weak self] snapshot in
            let next = snapshot.duoLayout
            if self?.layout != next { self?.layout = next }
        }
    }

    /// 绑定到一个铺满窗口的 UIView（`.duoSafeArea()` 自动完成；UIKit 宿主可直接调用）。
    public func attach(to view: UIView) { reader.attach(to: view) }
    public func detach() { reader.detach() }
}

/// 铺满窗口的不可见探针：给 `DuoLayoutMetrics` 提供被测 UIView。
private struct DuoProbe: UIViewRepresentable {
    let metrics: DuoLayoutMetrics
    func makeUIView(context: Context) -> ProbeView { ProbeView(metrics: metrics) }
    func updateUIView(_ view: ProbeView, context: Context) {}
    static func dismantleUIView(_ view: ProbeView, coordinator: ()) { view.metrics.detach() }

    final class ProbeView: UIView {
        let metrics: DuoLayoutMetrics
        init(metrics: DuoLayoutMetrics) {
            self.metrics = metrics
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { metrics.attach(to: self) } else { metrics.detach() }
        }
    }
}

/// `.duoSafeArea()` 的实现。
///
/// 做法：探针铺满窗口测「系统安全区 + 屏幕圆角」，算出 `contentInsets`；
/// 只把 **超出系统安全区的那部分**（圆角避让）用 `safeAreaPadding` 追加，
/// 所以 ScrollView 的 adjustedContentInset、`safeAreaInset(edge:)` 底栏、键盘避让都照常叠加一次，不会重复。
/// 底边策略为 `.homeIndicator(reserve:)` 时，先 `ignoresSafeArea(.container, edges: .bottom)` 让出系统底边，
/// 再用 `safeAreaPadding` 补回 reserve —— 键盘（.keyboard 区域）不受影响。
public struct DuoSafeAreaModifier: ViewModifier {
    public var bottom: DuoBottomPolicy
    public var cornerTolerance: CGFloat
    @StateObject private var owned: DuoLayoutMetrics
    private let external: DuoLayoutMetrics?
    @Environment(\.layoutDirection) private var direction

    public init(bottom: DuoBottomPolicy = .safeArea, cornerTolerance: CGFloat = DuoGeometry.defaultCornerTolerance,
                metrics: DuoLayoutMetrics? = nil) {
        self.bottom = bottom
        self.cornerTolerance = cornerTolerance
        self.external = metrics
        _owned = StateObject(wrappedValue: DuoLayoutMetrics())
    }

    private var metrics: DuoLayoutMetrics { external ?? owned }

    public func body(content: Content) -> some View {
        Adapted(content: content, metrics: metrics, bottom: bottom, tolerance: cornerTolerance, direction: direction)
            .background { DuoProbe(metrics: metrics).ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true) }
    }

    private struct Adapted: View {
        let content: Content
        @ObservedObject var metrics: DuoLayoutMetrics
        let bottom: DuoBottomPolicy
        let tolerance: CGFloat
        let direction: LayoutDirection

        var body: some View {
            let layout = metrics.layout
            let safe = layout?.safeArea ?? .zero
            let target = layout?.contentInsets(bottom: bottom, cornerTolerance: tolerance) ?? safe
            // 底边被策略收紧时，系统底边整段让出，再补 target.bottom；否则只追加超出部分。
            let reduceBottom = layout != nil && target.bottom < safe.bottom
            let extra = EdgeInsets(
                top: max(0, target.top - safe.top),
                leading: max(0, direction == .leftToRight ? target.left - safe.left : target.right - safe.right),
                bottom: reduceBottom ? target.bottom : max(0, target.bottom - safe.bottom),
                trailing: max(0, direction == .leftToRight ? target.right - safe.right : target.left - safe.left))
            content
                .safeAreaPadding(extra)
                .ignoresSafeArea(.container, edges: reduceBottom ? .bottom : [])
                .environment(\.duoLayout, layout)
                .environmentObject(metrics)
        }
    }
}

/// `.duoCornerClipped()` 的实现：按视图在窗口里的位置，算出与屏幕圆角同心的四角半径并裁切。
/// 视图离屏幕角越远半径越小，离开圆角区域即为直角；测不到圆角时退回 `ContainerRelativeShape`。
public struct DuoCornerClipModifier: ViewModifier {
    @Environment(\.duoLayout) private var layout
    @State private var frame: CGRect = .zero

    public init() {}

    public func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .clipShape(shape)
    }

    private var shape: AnyShape {
        guard let layout, let corners = layout.cornerRadii, corners.max > 0 else { return AnyShape(ContainerRelativeShape()) }
        let r = DuoGeometry.concentricRadii(frame: frame, bounds: layout.size, corners: corners)
        return AnyShape(UnevenRoundedRectangle(topLeadingRadius: r.topLeft, bottomLeadingRadius: r.bottomLeft,
                                               bottomTrailingRadius: r.bottomRight, topTrailingRadius: r.topRight,
                                               style: .continuous))
    }
}

public extension View {
    /// 把内容限制在「系统安全区 ∩ 屏幕圆角内」。在根视图（铺满窗口）上挂一次。
    /// - 右侧系统栏 / 外屏胶囊：系统安全区已含，照常让出；
    /// - 安全区为 0 的角（Duo 横屏、外屏顶边）：相邻两边至少让 R·(1−1/√2)；
    /// - `bottom: .homeIndicator(reserve: 8)`：底边只留 8pt 给 Home Indicator（默认 `.safeArea` 留系统原值）。
    /// 子视图里不要再对同一边 `.padding(safeArea)`；底部输入栏用 `.safeAreaInset(edge: .bottom)` 挂在内容上即可。
    func duoSafeArea(bottom: DuoBottomPolicy = .safeArea,
                     cornerTolerance: CGFloat = DuoGeometry.defaultCornerTolerance,
                     metrics: DuoLayoutMetrics? = nil) -> some View {
        modifier(DuoSafeAreaModifier(bottom: bottom, cornerTolerance: cornerTolerance, metrics: metrics))
    }

    /// 让贴近屏幕角的背景（胶囊、卡片、整页底色）沿屏幕圆角同心裁切。需在 `.duoSafeArea()` 之内使用。
    func duoCornerClipped() -> some View { modifier(DuoCornerClipModifier()) }
}
