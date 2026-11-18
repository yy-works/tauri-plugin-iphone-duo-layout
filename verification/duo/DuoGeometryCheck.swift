// macOS 上直接跑的纯几何断言：swiftc ../../native/.../DuoGeometry.swift DuoGeometryCheck.swift -o /tmp/duo-geo && /tmp/duo-geo
import CoreGraphics
import Foundation

var passed = 0, failed = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { passed += 1 } else { failed += 1; print("FAIL \(name) \(detail())") }
}
func near(_ a: CGFloat, _ b: CGFloat, _ e: CGFloat = 0.01) -> Bool { abs(a - b) <= e }

@main struct Main { static func main() {
    let R: CGFloat = 50
    let k = DuoGeometry.cornerClearance(radius: R)
    check("clearance", near(k, 50 * (1 - 1 / 2.0.squareRoot())), "\(k)")
    // 角点越界：(0,0) 越界 R(√2−1)；(k,k) 恰在弧上；直边区域为 0
    check("overflow origin", near(DuoGeometry.cornerOverflow(dx: 0, dy: 0, radius: R), R * (2.0.squareRoot() - 1)))
    check("overflow on arc", near(DuoGeometry.cornerOverflow(dx: k, dy: k, radius: R), 0))
    check("overflow straight edge", DuoGeometry.cornerOverflow(dx: 0, dy: 60, radius: R) == 0)
    check("own radius pill", DuoGeometry.cornerOverflow(dx: 10, dy: 4, radius: R, ownRadius: 18) > 0)
    check("no radius", DuoGeometry.cornerOverflow(dx: 0, dy: 0, radius: 0) == 0)

    // 非折叠退化：普通 iPhone 竖屏 59/0/34/0、R=55，底角越界≈4pt < 6 → 内容边距 == 系统安全区
    let phone = DuoInsets(top: 59, left: 0, bottom: 34, right: 0)
    check("phone == safe area", DuoGeometry.contentInsets(safe: phone, cornerRadius: 55, bottom: .safeArea) == phone,
          "\(DuoGeometry.contentInsets(safe: phone, cornerRadius: 55, bottom: .safeArea))")
    // 圆角测不到：只用安全区
    let duoOpen = DuoInsets(top: 0, left: 0, bottom: 34, right: 84)
    check("no corner == safe", DuoGeometry.contentInsets(safe: duoOpen, cornerRadius: nil, bottom: .safeArea) == duoOpen)
    // Duo 展开横屏：顶左角 (0,0) 越界 → 顶、左提到 k；右 84 覆盖右侧两角；底 34 保留
    let open = DuoGeometry.contentInsets(safe: duoOpen, cornerRadius: R, bottom: .safeArea)
    check("open top", near(open.top, k)); check("open left", near(open.left, k))
    check("open right kept", open.right == 84); check("open bottom kept", open.bottom == 34)
    // 底边策略：34 → 8；左边已因顶左角提到 k，底左角 (k, 8) 越界 ≈4.9pt ≤ 容差 → 底边保持 8
    let compact = DuoGeometry.contentInsets(safe: duoOpen, cornerRadius: R, bottom: .homeIndicator(reserve: 8))
    check("compact bottom", compact.bottom == 8, "\(compact.bottom)")
    check("compact bl inside", DuoGeometry.cornerOverflow(dx: compact.left, dy: compact.bottom, radius: R) <= DuoGeometry.defaultCornerTolerance)
    // 只有底边（无左右避让）时：底左角 (0, 8) 越界 → 左、底都提到 k
    let bare = DuoGeometry.contentInsets(safe: DuoInsets(top: 60, bottom: 34), cornerRadius: R, bottom: .homeIndicator(reserve: 8))
    check("bare bottom raised", near(bare.bottom, k) && near(bare.left, k), "\(bare)")
    check("compact no radius", DuoGeometry.contentInsets(safe: duoOpen, cornerRadius: nil, bottom: .homeIndicator(reserve: 8)).bottom == 8)
    check("reserve > safe keeps safe", DuoGeometry.contentInsets(safe: DuoInsets(bottom: 20), cornerRadius: nil, bottom: .homeIndicator(reserve: 30)).bottom == 20)
    check("no home indicator stays 0", DuoGeometry.contentInsets(safe: .zero, cornerRadius: nil, bottom: .homeIndicator(reserve: 8)).bottom == 0)
    // 结果永远不比安全区更贴边（底边策略除外）
    for t in stride(from: CGFloat(0), through: 80, by: 20) { for r in stride(from: CGFloat(0), through: 90, by: 30) {
        let s = DuoInsets(top: t, left: 0, bottom: 34, right: r)
        let c = DuoGeometry.contentInsets(safe: s, cornerRadius: R, bottom: .safeArea)
        check("monotonic \(t)/\(r)", c.top >= s.top && c.left >= s.left && c.bottom >= s.bottom && c.right >= s.right)
        // 每个角都在弧内（误差 ≤ tolerance）
        for (dx, dy) in [(c.left, c.top), (c.right, c.top), (c.left, c.bottom), (c.right, c.bottom)] {
            check("inside \(t)/\(r)", DuoGeometry.cornerOverflow(dx: dx, dy: dy, radius: R) <= DuoGeometry.defaultCornerTolerance + 0.01)
        }
    }}

    // 同心半径：贴角的视图半径 = R；离开 R 以外为 0
    let full = DuoGeometry.concentricRadii(frame: CGRect(x: 0, y: 0, width: 951, height: 669), bounds: CGSize(width: 951, height: 669), radius: R)
    check("full radii", full.topLeft == R && full.bottomRight == R)
    let chip = DuoGeometry.concentricRadii(frame: CGRect(x: 10, y: 4, width: 60, height: 32), bounds: CGSize(width: 951, height: 669), radius: R)
    check("chip tl", chip.topLeft == 16 && chip.topRight == 0, "\(chip)")
    check("nil radius", DuoGeometry.concentricRadii(frame: .zero, bounds: .zero, radius: nil) == (0, 0, 0, 0))

    // 逐角：Duo 外屏竖屏 TL/BL=8（铰链侧）、TR/BR=59；safe 0/0/34/84
    let cover = DuoCorners(topLeft: 8, topRight: 59, bottomLeft: 8, bottomRight: 59)
    let coverSafe = DuoInsets(top: 0, left: 0, bottom: 34, right: 84)
    let ci = DuoGeometry.contentInsets(safe: coverSafe, corners: cover, bottom: .safeArea)
    check("cover per-corner == safe", ci == coverSafe, "\(ci)")
    let cc = DuoGeometry.contentInsets(safe: coverSafe, corners: cover, bottom: .homeIndicator(reserve: 8))
    check("cover compact bottom 8", cc.bottom == 8 && cc.left == 0 && cc.top == 0, "\(cc)")
    // 只把左侧当 59（旧的取最大值做法）会多让 17.3 —— 逐角后不再发生
    check("max-radius overcorrects", DuoGeometry.contentInsets(safe: coverSafe, cornerRadius: 59, bottom: .safeArea).top > 17)
    // 内屏横屏四角 55：顶左 (0,0) 越界 → 顶、左提到 55·(1−1/√2)
    let inner = DuoGeometry.contentInsets(safe: coverSafe, corners: DuoCorners(uniform: 55), bottom: .safeArea)
    check("inner tl", near(inner.top, DuoGeometry.cornerClearance(radius: 55)) && near(inner.left, DuoGeometry.cornerClearance(radius: 55)), "\(inner)")
    let pr = DuoGeometry.concentricRadii(frame: CGRect(x: 0, y: 0, width: 466, height: 678), bounds: CGSize(width: 466, height: 678), corners: cover)
    check("per-corner concentric", pr.topLeft == 8 && pr.topRight == 59 && pr.bottomLeft == 8 && pr.bottomRight == 59)

    // 三态判定
    let size = CGSize(width: 951, height: 669)
    check("hinge closed", DuoGeometry.classify(hinge: "closed", hingeAngle: nil, divisionRegions: 0, activeDivisionRegions: 0, size: size).0 == .folded)
    check("hinge half", DuoGeometry.classify(hinge: "partiallyOpen", hingeAngle: 90, divisionRegions: 1, activeDivisionRegions: 1, size: size).0 == .half)
    check("hinge open", DuoGeometry.classify(hinge: "fullyOpen", hingeAngle: 180, divisionRegions: 1, activeDivisionRegions: 0, size: size).0 == .expanded)
    check("division active", DuoGeometry.classify(hinge: nil, hingeAngle: nil, divisionRegions: 1, activeDivisionRegions: 1, size: size).0 == .half)
    check("division inactive", DuoGeometry.classify(hinge: nil, hingeAngle: nil, divisionRegions: 1, activeDivisionRegions: 0, size: size).0 == .expanded)
    check("phone notFoldable", DuoGeometry.classify(hinge: nil, hingeAngle: nil, divisionRegions: 0, activeDivisionRegions: 0, size: CGSize(width: 402, height: 874)).0 == .notFoldable)
    check("basis has size", DuoGeometry.classify(hinge: nil, hingeAngle: nil, divisionRegions: 0, activeDivisionRegions: 0, size: size).1.contains("size=951x669"))

    print("DuoGeometryCheck: \(passed) passed, \(failed) failed")
    exit(failed == 0 ? 0 : 1)
}}
