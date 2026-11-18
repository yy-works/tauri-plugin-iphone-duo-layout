import CoreGraphics
import Foundation

// 纯几何层：不 import UIKit / SwiftUI，可在 macOS 上单测。
// 所有距离都是「被测视图（通常是整窗口）」的本地 pt。

/// 折叠形态。判定只来自运行时观测（铰链 API、保留区、实际窗口几何），不看机型字符串。
public enum DuoFoldState: String, Codable, Sendable, Equatable {
    /// 合上：外屏工作。
    case folded
    /// 半开（书本姿态）：内屏工作，铰链处于 partially open。
    case half
    /// 完全展开：内屏工作，铰链 fully open。
    case expanded
    /// 系统没有报告铰链（普通 iPhone / iPad / 旧系统）。此时本层退化为「普通安全区 + 圆角避让」。
    case notFoldable
}

/// 物理方向的四边（left/right 不随 RTL 翻转）。
public struct DuoInsets: Codable, Sendable, Equatable {
    public var top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat
    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }
    public static let zero = DuoInsets()
}

/// 屏幕四角各自的圆角（pt，窗口坐标系，已随界面方向旋转）。
/// 折叠屏各角可以不同：iPhone Duo 外屏铰链侧（左）两角 8pt、外侧两角 59pt；内屏四角 55pt。
public struct DuoCorners: Codable, Sendable, Equatable {
    public var topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat
    public init(topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) {
        self.topLeft = topLeft; self.topRight = topRight; self.bottomLeft = bottomLeft; self.bottomRight = bottomRight
    }
    public init(uniform r: CGFloat) { self.init(topLeft: r, topRight: r, bottomLeft: r, bottomRight: r) }
    public var max: CGFloat { Swift.max(topLeft, topRight, bottomLeft, bottomRight) }
}

/// 底边策略。
public enum DuoBottomPolicy: Sendable, Equatable {
    /// 系统安全区原值（Home Indicator 区域整段让出，HIG 默认）。
    case safeArea
    /// 只给 Home Indicator 留 `reserve` pt（例如 8 或 14），把系统 34pt 中多出来的部分还给内容。
    /// 仅在系统底边安全区 > reserve 时生效；没有 Home Indicator（底边 0）时保持 0。
    case homeIndicator(reserve: CGFloat)
}

/// 一次完整测量的结果（值类型，可比较、可编码）。
public struct DuoLayout: Sendable, Equatable {
    /// 被测视图尺寸（整窗口时即当前激活屏幕的可用尺寸）。
    public var size: CGSize
    /// 系统报告的安全区（UIView.safeAreaInsets 原值）。
    public var safeArea: DuoInsets
    /// 实测屏幕四角圆角；nil = 测不到（此时不做圆角避让，不回退任何写死数值）。
    public var cornerRadii: DuoCorners?
    /// 四角最大值（兼容只要一个数的调用方）。
    public var cornerRadius: CGFloat? { cornerRadii?.max }
    /// 圆角来源，便于回执核对：`containerConcentric`（iOS 26 公开 API）、`screenPrivate`（旧系统兜底）、`unavailable`。
    public var cornerRadiusSource: String
    public var state: DuoFoldState
    /// 判定依据（人读），例如 `hinge=partiallyOpen`、`division=1/active`、`size=951x669`。
    public var stateBasis: [String]
    /// 铰链角度（度），只有系统提供时有值。
    public var hingeAngle: CGFloat?

    public init(size: CGSize, safeArea: DuoInsets, cornerRadii: DuoCorners?, cornerRadiusSource: String,
                state: DuoFoldState, stateBasis: [String], hingeAngle: CGFloat? = nil) {
        self.size = size; self.safeArea = safeArea; self.cornerRadii = cornerRadii
        self.cornerRadiusSource = cornerRadiusSource; self.state = state
        self.stateBasis = stateBasis; self.hingeAngle = hingeAngle
    }

    /// 按策略算出的内容边距：安全区 ∪ 圆角避让（见 `DuoGeometry.contentInsets`）。
    public func contentInsets(bottom policy: DuoBottomPolicy = .safeArea,
                              cornerTolerance: CGFloat = DuoGeometry.defaultCornerTolerance) -> DuoInsets {
        DuoGeometry.contentInsets(safe: safeArea, corners: cornerRadii, bottom: policy, tolerance: cornerTolerance)
    }
}

public enum DuoGeometry {
    /// 角点越界 ≤ 该值视为可接受。普通 iPhone 竖屏底角（左右 0、底 34、R≈55）只越界约 4pt，
    /// 系统自己的 Tab Bar 也是这样排的；取 6pt 保证非折叠设备退化为「普通安全区」不多让。
    public static let defaultCornerTolerance: CGFloat = 6

    /// 45° 方向的圆角让位：R·(1−1/√2)。两条相邻边都至少让这么多，矩形角点就恰好落在圆弧上。
    public static func cornerClearance(radius: CGFloat) -> CGFloat {
        max(0, radius) * (1 - 1 / 2.0.squareRoot())
    }

    /// 距屏幕某个角 (dx, dy) 处、自身圆角 `ownRadius` 的矩形角，越出屏幕圆角多少 pt（≤0 表示在内）。
    /// 屏幕圆角按圆弧近似（continuous 曲线比圆弧略「胖」，这里偏保守）。
    public static func cornerOverflow(dx: CGFloat, dy: CGFloat, radius: CGFloat, ownRadius: CGFloat = 0) -> CGFloat {
        guard radius > 0 else { return 0 }
        let r = max(0, ownRadius)
        let cx = dx + r, cy = dy + r            // 元素自身圆角的圆心
        guard cx < radius, cy < radius else { return 0 }  // 已在直边区域，圆角无影响
        let distance = ((radius - cx) * (radius - cx) + (radius - cy) * (radius - cy)).squareRoot()
        return distance + r - radius
    }

    /// 内容边距 = 系统安全区，按底边策略调整，再对每个角用**该角自己的半径**做圆角避让：
    /// 若安全区矩形的角点越界 > tolerance，就把该角相邻两边都至少提到该角的 `cornerClearance`。
    /// 只增不减（底边策略除外），所以永远不会比系统安全区更「贴边」。
    public static func contentInsets(safe: DuoInsets, corners: DuoCorners?, bottom policy: DuoBottomPolicy,
                                     tolerance: CGFloat = defaultCornerTolerance) -> DuoInsets {
        var i = safe
        if case let .homeIndicator(reserve) = policy, safe.bottom > max(0, reserve) {
            i.bottom = max(0, reserve)
        }
        guard let c = corners else { return i }
        func fix(_ r: CGFloat, _ h: inout CGFloat, _ v: inout CGFloat) {
            guard r > 0, cornerOverflow(dx: h, dy: v, radius: r) > tolerance else { return }
            let k = cornerClearance(radius: r); h = max(h, k); v = max(v, k)
        }
        fix(c.topLeft, &i.left, &i.top)
        fix(c.topRight, &i.right, &i.top)
        fix(c.bottomLeft, &i.left, &i.bottom)
        fix(c.bottomRight, &i.right, &i.bottom)
        return i
    }

    /// 兼容旧签名：四角同一半径。
    public static func contentInsets(safe: DuoInsets, cornerRadius: CGFloat?, bottom policy: DuoBottomPolicy,
                                     tolerance: CGFloat = defaultCornerTolerance) -> DuoInsets {
        contentInsets(safe: safe, corners: cornerRadius.map { DuoCorners(uniform: $0) }, bottom: policy, tolerance: tolerance)
    }

    /// 与屏幕圆角同心的四角半径（用于 `.duoCornerClipped()`）：
    /// 某角距屏幕角 (dx, dy)，半径 = 该屏幕角 R − max(dx, dy)，不小于 0。`frame` 与 `bounds` 同一坐标系（窗口）。
    public static func concentricRadii(frame: CGRect, bounds: CGSize, corners: DuoCorners?) -> (topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) {
        guard let c = corners else { return (0, 0, 0, 0) }
        let left = max(0, frame.minX), top = max(0, frame.minY)
        let right = max(0, bounds.width - frame.maxX), bottom = max(0, bounds.height - frame.maxY)
        let half = min(frame.width, frame.height) / 2
        func r(_ radius: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { min(half, max(0, radius - max(a, b))) }
        return (r(c.topLeft, left, top), r(c.topRight, right, top), r(c.bottomLeft, left, bottom), r(c.bottomRight, right, bottom))
    }

    public static func concentricRadii(frame: CGRect, bounds: CGSize, radius: CGFloat?) -> (topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) {
        concentricRadii(frame: frame, bounds: bounds, corners: radius.map { DuoCorners(uniform: $0) })
    }

    /// 三态判定。优先级：
    /// 1. 铰链观测（iOS 27.1 `UIHingeInteraction`）：closed→folded，partiallyOpen→half，fullyOpen→expanded；
    /// 2. 没有铰链状态但窗口内存在 division 保留区（折痕）：active→half，否则 expanded（大屏在用）；
    /// 3. 两者都没有：notFoldable——本层只做「安全区 + 圆角」，行为等同普通设备。
    /// 尺寸 / 宽高比只写进 basis 作交叉核对，不单独决定形态（普通大屏手机也可能同尺寸）。
    public static func classify(hinge: String?, hingeAngle: CGFloat?, divisionRegions: Int, activeDivisionRegions: Int,
                                size: CGSize) -> (DuoFoldState, [String]) {
        var basis = [String(format: "size=%.0fx%.0f", size.width, size.height)]
        if size.width > 0, size.height > 0 {
            basis.append(String(format: "aspect=%.3f", max(size.width, size.height) / min(size.width, size.height)))
        }
        basis.append("division=\(divisionRegions)/active=\(activeDivisionRegions)")
        if let hingeAngle { basis.append(String(format: "hingeAngle=%.1f", hingeAngle)) }
        switch hinge {
        case "closed": return (.folded, ["hinge=closed"] + basis)
        case "partiallyOpen": return (.half, ["hinge=partiallyOpen"] + basis)
        case "fullyOpen": return (.expanded, ["hinge=fullyOpen"] + basis)
        default: break
        }
        if divisionRegions > 0 { return (activeDivisionRegions > 0 ? .half : .expanded, ["hinge=\(hinge ?? "none")"] + basis) }
        return (.notFoldable, ["hinge=\(hinge ?? "none")"] + basis)
    }
}
