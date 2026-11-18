import UIKit

/// 读取「当前窗口所在屏幕」的真实圆角半径（pt）。不写死任何机型数值。
///
/// 取值顺序：
/// 1. iOS 26+ 公开 API：在窗口里临时放一个铺满窗口的视图，`cornerConfiguration = .corners(radius: .containerConcentric())`，
///    逐角读 `effectiveRadius(corner:)`。铺满窗口时同心半径 = 该屏幕角的圆角（随界面方向旋转），source = `containerConcentric`。
///    折叠屏各角可能不同（Duo 外屏铰链侧 8pt、外侧 59pt），所以**逐角保留**，不取最大值。
/// 2. 旧系统兜底：`UIScreen` 的 `_displayCornerRadius`（私有 KVC，先 `responds(to:)` 再取，取不到不崩），
///    只有一个数，按四角相同处理（对小圆角的角偏保守），source = `screenPrivate`。只在 1 不可用时使用；需要完全避开私有 API 的 app 传 `allowPrivateFallback: false`。
/// 3. 都取不到：返回 nil（`unavailable`），上层不做圆角避让，行为等同普通安全区。
@MainActor public enum DisplayCornerRadius {
    public struct Measurement: Equatable, Sendable {
        public var corners: DuoCorners?
        public var source: String
        /// 两种来源各自的读数（调试/回执用；没取到为 nil）。
        public var concentric: DuoCorners?
        public var screenPrivate: CGFloat?
        /// 四角最大值。
        public var radius: CGFloat? { corners?.max }
    }

    public static func measure(in window: UIWindow, allowPrivateFallback: Bool = true) -> Measurement {
        let concentric = concentricRadius(in: window)
        let privateValue = screenPrivateRadius(of: window.screen)
        if let concentric, concentric.max > 0 {
            return Measurement(corners: concentric, source: "containerConcentric", concentric: concentric, screenPrivate: privateValue)
        }
        if allowPrivateFallback, let privateValue, privateValue > 0 {
            return Measurement(corners: DuoCorners(uniform: privateValue), source: "screenPrivate", concentric: concentric, screenPrivate: privateValue)
        }
        return Measurement(corners: nil, source: "unavailable", concentric: concentric, screenPrivate: privateValue)
    }

    static func concentricRadius(in window: UIWindow) -> DuoCorners? {
        guard #available(iOS 26.0, *) else { return nil }
        let probe = UIView(frame: window.bounds)
        probe.isUserInteractionEnabled = false
        probe.alpha = 0
        probe.cornerConfiguration = .corners(radius: .containerConcentric())
        window.addSubview(probe)
        defer { probe.removeFromSuperview() }
        probe.layoutIfNeeded()
        func r(_ corner: UIRectCorner) -> CGFloat { let v = probe.effectiveRadius(corner: corner); return v.isFinite ? max(0, v) : 0 }
        return DuoCorners(topLeft: r(.topLeft), topRight: r(.topRight), bottomLeft: r(.bottomLeft), bottomRight: r(.bottomRight))
    }

    static func screenPrivateRadius(of screen: UIScreen) -> CGFloat? {
        let key = "_displayCornerRadius"
        guard screen.responds(to: NSSelectorFromString(key)) else { return nil }
        if let number = screen.value(forKey: key) as? NSNumber {
            let value = CGFloat(number.doubleValue)
            return value.isFinite && value > 0 ? value : nil
        }
        return nil
    }
}
