import Cocoa

// MARK: - 설정
// 사용자 스프라이트 폴더가 있으면 우선, 없으면 앱 안에 들어 있는 기본 스프라이트 사용
let spriteDir = (NSHomeDirectory() as NSString).appendingPathComponent("MomongaPet/sprites")
let bundledSpriteDir = Bundle.main.resourcePath.map { ($0 as NSString).appendingPathComponent("sprites") }
let petSize = NSSize(width: 50, height: 50)
let animFPS = 8.0
let sleepFPS = 3.0                  // 자는 애니메이션은 느리게
let walkFPS = 5.0                   // 걷기 애니메이션 (걷는 속도에 맞춰 느리게)
let walkSpeed: CGFloat = 45
let dizzyDuration = 2.0            // 떨어진 뒤 헤롱거리는 시간(초)
let gravity: CGFloat = -2200
let jumpPower: CGFloat = 900
let maxThrow: CGFloat = 1500
let spritesFaceRight = true         // 원본 이미지가 왼쪽을 보고 있으면 false

// 잠
let awaySleepAfter = 180.0          // 시스템 유휴(키보드·마우스 입력 없음) 이만큼(초) 지나면 잠
let napChance = 0.01                // 상태 전환 시 낮잠 확률
let napDuration = 15.0...30.0
let napCooldown = 600.0             // 깨어난 직후 이 시간 동안은 낮잠 안 잠
let wakeIdleTime = 1.5              // 깨어나서 멍하니 있는 시간

// 화면 바닥에서 다닐 가로 범위: 손쉬운 사용 권한이 있으면 Dock 아이콘 줄 범위를 2초마다 읽음
// (앱을 켜고 끄면 Dock 너비가 바뀌므로). 권한이 없을 때 쓸 고정 범위 (주 화면 기준 pt, nil이면 화면 전체)
let dockRangeFallback: ClosedRange<CGFloat>? = 106...1364

// 창 위로 점프
let windowJumpChance = 0.15
let walkOffEdgeChance = 0.10
let jumpClearance: CGFloat = 40     // 창 상단보다 이만큼 더 높이 뛰어오름
let jumpHeightLimit: CGFloat = 0.95  // 점프 높이(dy+여유)가 화면 높이의 이 비율 미만일 때만 점프
let softDropLimit: CGFloat = 30     // 발판이 이보다 조금 내려가면 상태 유지한 채 툭 떨어짐

// 드래그 흔들림
let wobbleDegrees: CGFloat = 10
let wobbleHz = 2.0
let dragScale = CGSize(width: 0.95, height: 1.06)

// 흔들림·늘어남이 잘리지 않도록 창을 펫보다 조금 크게 (투명 여백은 클릭이 통과됨)
let padX = ceil(petSize.height * 0.2)
let padTop = ceil(petSize.height * 0.1)
let windowSize = NSSize(width: petSize.width + padX * 2, height: petSize.height + padTop)

enum PetState: String { case idle, walk, drag, fall, jump, sleep, dizzy }

// MARK: - 스프라이트 로더
// 파일명 규칙: idle_01.png, walk_01.png, walk_02.png ... (없는 상태는 idle로 대체)
@MainActor
final class Sprites {
    private var frames: [String: [NSImage]] = [:]

    init() {
        for dir in [spriteDir, bundledSpriteDir].compactMap({ $0 }) {
            load(dir)
            if !frames.isEmpty { break }
        }
    }

    static func pngFiles(in dir: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { ($0 as NSString).pathExtension.lowercased() == "png" }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func load(_ dir: String) {
        for f in Sprites.pngFiles(in: dir) {
            let base = (f as NSString).deletingPathExtension
            let key = (base.split(separator: "_").first.map(String.init) ?? base).lowercased()
            if let img = NSImage(contentsOfFile: (dir as NSString).appendingPathComponent(f)) {
                frames[key, default: []].append(img)
            }
        }
    }

    func frames(for s: PetState) -> [NSImage] {
        if let f = frames[s.rawValue], !f.isEmpty { return f }
        if s == .jump, let f = frames["fall"], !f.isEmpty { return f }
        if let f = frames["idle"], !f.isEmpty { return f }
        return [Sprites.placeholder]
    }

    static let placeholder: NSImage = {
        let img = NSImage(size: NSSize(width: 128, height: 128))
        img.lockFocus()
        let body = NSBezierPath(ovalIn: NSRect(x: 14, y: 4, width: 100, height: 88))
        NSColor(white: 0.97, alpha: 1).setFill(); body.fill()
        NSColor(white: 0.3, alpha: 1).setStroke(); body.lineWidth = 3; body.stroke()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 44, y: 50, width: 9, height: 12)).fill()
        NSBezierPath(ovalIn: NSRect(x: 75, y: 50, width: 9, height: 12)).fill()
        img.unlockFocus()
        return img
    }()
}

// MARK: - 포어그라운드 창 조회
struct WinInfo {
    let number: Int
    let frame: NSRect   // Cocoa 좌표 (좌하단 원점)
}

/// 화면에 보이는 창 목록 (앞→뒤 순서). 화면 기록 권한 없이 얻을 수 있는 정보(pid·layer·bounds)만 사용
func onScreenWindows() -> [[String: Any]] {
    (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
}

/// CG 좌표(좌상단 원점) → Cocoa 좌표(좌하단 원점)
func cocoaRect(_ w: [String: Any]) -> NSRect? {
    guard let dict = w[kCGWindowBounds as String] as? NSDictionary,
          let cg = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return nil }
    let mainH = NSScreen.screens[0].frame.height
    return NSRect(x: cg.minX, y: mainH - cg.minY - cg.height, width: cg.width, height: cg.height)
}

/// 펫이 올라설 수 있는 일반 창이면 반환
func standableWindow(_ w: [String: Any]) -> WinInfo? {
    guard (w[kCGWindowLayer as String] as? Int) == 0,
          let f = cocoaRect(w), f.width >= 200 else { return nil }
    // 상단이 어떤 화면 안에 있어야 하고, 펫이 올라설 공간(메뉴바 아래)이 있어야 함
    guard let scr = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: f.midX, y: f.maxY - 1)) }),
          f.maxY + petSize.height <= scr.visibleFrame.maxY else { return nil }
    return WinInfo(number: w[kCGWindowNumber as String] as? Int ?? 0, frame: f)
}

/// 해당 pid의 일반 창(layer 0) 중 첫 번째
func frontWindow(pid: pid_t, excluding selfNumber: Int, in list: [[String: Any]]) -> WinInfo? {
    for w in list where (w[kCGWindowOwnerPID as String] as? pid_t) == pid {
        if let info = standableWindow(w), info.number != selfNumber { return info }
    }
    return nil
}

/// 서 있는 창의 현재 상태와, 그 창보다 앞에 있는 창들의 영역.
/// 닫힘·최소화·다른 Space 등으로 화면에 없으면 nil
func platformStatus(number: Int, in list: [[String: Any]]) -> (info: WinInfo, above: [NSRect])? {
    var above: [NSRect] = []
    for w in list {
        if (w[kCGWindowNumber as String] as? Int) == number {
            return standableWindow(w).map { ($0, above) }
        }
        guard (w[kCGWindowLayer as String] as? Int) == 0,
              (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              (w[kCGWindowOwnerPID as String] as? pid_t) != getpid(),
              let r = cocoaRect(w) else { continue }
        above.append(r)
    }
    return nil
}

/// Dock 아이콘 줄의 가로 범위 (주 화면 기준 pt). 손쉬운 사용 권한이 있고 Dock이 아래쪽에 있을 때만
func dockIconRange() -> ClosedRange<CGFloat>? {
    guard AXIsProcessTrusted(),
          let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
    let app = AXUIElementCreateApplication(dock.processIdentifier)
    var kids: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &kids) == .success,
          let list = (kids as? [AXUIElement])?.first else { return nil }
    var posRef: CFTypeRef?, sizeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(list, kAXPositionAttribute as CFString, &posRef) == .success,
          AXUIElementCopyAttributeValue(list, kAXSizeAttribute as CFString, &sizeRef) == .success,
          let posRef, let sizeRef else { return nil }
    var p = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(posRef as! AXValue, .cgPoint, &p)
    AXValueGetValue(sizeRef as! AXValue, .cgSize, &sz)
    guard sz.width > sz.height, sz.width > 0 else { return nil }   // 왼쪽·오른쪽 Dock은 무시
    return p.x...(p.x + sz.width)
}

/// 시스템 전체 유휴 시간(마지막 키보드·마우스 입력 이후 초)
func systemIdleSeconds() -> Double {
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
}

// MARK: - 뷰
final class PetView: NSView {
    weak var pet: Pet?
    var image: NSImage? { didSet { if oldValue !== image { needsDisplay = true } } }
    var mirrored = false { didSet { if oldValue != mirrored { needsDisplay = true } } }
    var angle: CGFloat = 0 { didSet { if oldValue != angle { needsDisplay = true } } }      // 라디안
    var stretch = CGSize(width: 1, height: 1) { didSet { if oldValue != stretch { needsDisplay = true } } }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let img = image, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let s = img.size
        guard s.width > 0, s.height > 0 else { return }
        let scale = min(petSize.width / s.width, petSize.height / s.height)
        let w = s.width * scale, h = s.height * scale
        NSGraphicsContext.current?.imageInterpolation = .high
        ctx.saveGState()
        // 발 아래 중앙을 기준점으로 회전·스케일·좌우반전
        ctx.translateBy(x: bounds.midX, y: 0)
        ctx.rotate(by: angle)
        ctx.scaleBy(x: stretch.width * (mirrored ? -1 : 1), y: stretch.height)
        img.draw(in: NSRect(x: -w / 2, y: 0, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1)
        ctx.restoreGState()
    }

    override func mouseDown(with e: NSEvent) { pet?.mouseDown(e) }
    override func mouseDragged(with e: NSEvent) { pet?.mouseDragged(e) }
    override func mouseUp(with e: NSEvent) { pet?.mouseUp(e) }
    override func rightMouseDown(with e: NSEvent) { pet?.showMenu(e, in: self) }
}

// MARK: - 펫 로직
@MainActor
final class Pet: NSObject {
    let window: NSPanel
    let view: PetView
    var sprites = Sprites()

    var state: PetState = .fall
    var vx: CGFloat = 0, vy: CGFloat = 0
    var frameIdx = 0
    var animAcc = 0.0
    var stateTimer = 0.0
    var jumped = false                  // 스스로 뛴 점프면 착지 후 헤롱거리지 않음
    var dragTime = 0.0
    var lastTick = ProcessInfo.processInfo.systemUptime

    // 잠
    var awaySleep = false               // 자리 비움으로 잠든 건지 (낮잠과 구분)
    var sysIdle = 0.0
    var lastIdlePoll = 0.0
    var lastWake = -Double.infinity

    // Dock
    var dockRange = dockRangeFallback
    var lastDockPoll = -Double.infinity

    // 창
    var frontWin: WinInfo?              // 포어그라운드 앱의 대표 창 (캐시)
    var lastWinQuery = 0.0
    var platform: WinInfo?              // 지금 서 있는 창 (펫이 마지막으로 맞춘 위치)
    var platformNow: WinInfo?           // 그 창의 최신 조회 결과 (닫히거나 최소화되면 nil)
    var platformAbove: [NSRect] = []    // 그 창보다 앞에 있는 창들 (가려짐 판정용)
    var walkOffEdge = false             // 창 끝에서 돌지 않고 걸어가 떨어지기

    // 마우스
    var pressLocation = NSPoint.zero        // 누른 지점 (화면 좌표)
    var dragOffset = NSPoint.zero           // 창 원점 기준 잡은 위치
    var pressIsJump = false
    var dragSamples: [(t: Double, p: NSPoint)] = []

    /// 펫 몸통(발 아래 왼쪽 기준) 사각형. 창은 여기서 좌우·위로 여백만큼 큼
    /// 창 위치는 정수로 버림되므로(1pt 미만 이동이 사라짐) 실제 위치는 소수점까지 따로 보관.
    /// 드래그 등으로 창이 다른 곳으로 옮겨졌으면 창 위치를 따름
    var exactOrigin: NSPoint?
    var body: NSRect {
        get {
            let wf = window.frame.origin
            var o = NSPoint(x: wf.x + padX, y: wf.y)
            if let e = exactOrigin, abs(e.x - padX - wf.x) < 1, abs(e.y - wf.y) < 1 { o = e }
            return NSRect(origin: o, size: petSize)
        }
        set {
            exactOrigin = newValue.origin
            window.setFrameOrigin(NSPoint(x: newValue.minX - padX, y: newValue.minY))
        }
    }

    var isAirborne: Bool { state == .fall || state == .jump }

    override init() {
        let area = NSScreen.main!.visibleFrame
        let origin = NSPoint(x: area.midX - windowSize.width / 2, y: area.maxY - windowSize.height)
        // 비활성 패널: 펫을 클릭해도 이 앱이 앞으로 나오지 않음 → 포어그라운드 창이 그대로 유지됨
        window = NSPanel(contentRect: NSRect(origin: origin, size: windowSize),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        view = PetView(frame: NSRect(origin: .zero, size: windowSize))
        super.init()

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = view
        view.pet = self
        window.orderFrontRegardless()

        let t = Timer(timeInterval: 1.0 / 60, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
    }

    func setState(_ s: PetState) {
        guard s != state else { return }
        state = s
        frameIdx = 0
        animAcc = 0
    }

    // MARK: 잠
    var isAway: Bool { sysIdle >= awaySleepAfter }

    func sleep(away: Bool, duration: Double = .infinity) {
        vx = 0
        walkOffEdge = false
        awaySleep = away
        setState(.sleep)
        stateTimer = duration
    }

    /// 깨어나면 잠깐 멍하니 있다가 평소대로
    func wakeUp() {
        awaySleep = false
        lastWake = ProcessInfo.processInfo.systemUptime
        vx = 0
        setState(.idle)
        stateTimer = wakeIdleTime
    }

    func decide() {
        walkOffEdge = false
        if isAway { sleep(away: true); return }

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastWake >= napCooldown && Double.random(in: 0..<1) < napChance {
            sleep(away: false, duration: .random(in: napDuration)); return
        }
        if Double.random(in: 0..<1) < windowJumpChance && jumpToFrontWindow() { return }

        if Double.random(in: 0..<1) < 0.5 {
            setState(.walk)
            if let p = platform, Double.random(in: 0..<1) < walkOffEdgeChance {
                // 가까운 창 끝 쪽으로 걸어가서 떨어지기
                walkOffEdge = true
                vx = (body.midX < p.frame.midX ? -1 : 1) * walkSpeed
                stateTimer = 30
            } else {
                vx = (Bool.random() ? 1 : -1) * walkSpeed
                stateTimer = .random(in: 2...6)
            }
        } else {
            setState(.idle)
            vx = 0
            stateTimer = .random(in: 2...5)
        }
    }

    // MARK: 창 점프
    func jumpToFrontWindow() -> Bool {
        guard state != .sleep, let w = frontWin, platform?.number != w.number else { return false }
        let f = body
        let area = (window.screen ?? NSScreen.main!).visibleFrame
        let g = abs(gravity), h = jumpClearance
        let dy = w.frame.maxY - f.minY
        guard dy > 0, dy + h < area.height * jumpHeightLimit,
              w.frame.maxY + h + f.height <= area.maxY else { return false }   // 천장에 부딪혀 궤도 틀어지지 않게
        let tx = max(w.frame.minX, min(f.minX, w.frame.maxX - f.width))   // 몸 전체가 창 안쪽에 오도록
        vy = sqrt(2 * g * (dy + h))
        let t = (vy + sqrt(2 * g * h)) / g
        vx = (tx - f.minX) / t
        platform = nil
        walkOffEdge = false
        jumped = true
        setState(.jump)
        return true
    }

    func refreshWindows() {
        let list = onScreenWindows()
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() {
            frontWin = frontWindow(pid: app.processIdentifier, excluding: window.windowNumber, in: list)
        }   // 펫 자신이 앞이면 직전 값 유지
        // 서 있는 창은 맨 앞이 아니어도 계속 추적
        let st = platform.flatMap { platformStatus(number: $0.number, in: list) }
        platformNow = st?.info
        platformAbove = st?.above ?? []
    }

    func land(_ f: inout NSRect, y: CGFloat, on w: WinInfo?) {
        f.origin.y = y
        vx = 0; vy = 0
        platform = w
        platformNow = w
        walkOffEdge = false
        if let w { f.origin.x = max(w.frame.minX, min(f.origin.x, w.frame.maxX - f.width)) }
        if isAway { sleep(away: true); return }
        if jumped {
            jumped = false
            setState(.idle)
            stateTimer = .random(in: 1...3)
        } else {
            setState(.dizzy)                            // 떨어지거나 던져졌으면 잠깐 헤롱헤롱
            stateTimer = dizzyDuration
        }
    }

    // MARK: 틱
    @objc func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(now - lastTick, 0.05)
        lastTick = now

        // Dock 범위 (2초 간격)
        if now - lastDockPoll >= 2 {
            lastDockPoll = now
            dockRange = dockIconRange() ?? dockRangeFallback
        }

        // 시스템 유휴 시간 (1초 간격)
        if now - lastIdlePoll >= 1 {
            lastIdlePoll = now
            let prev = sysIdle
            sysIdle = systemIdleSeconds()
            if state == .sleep && awaySleep && (sysIdle < 1 || sysIdle < prev) { wakeUp() }
            else if isAway && (state == .idle || state == .walk || state == .dizzy) { sleep(away: true) }
        }

        // 드래그 중엔 이동·중력·타이머 전부 정지하고 흔들림만
        if state == .drag {
            dragTime += dt
            view.angle = wobbleDegrees * .pi / 180 * CGFloat(sin(2 * .pi * wobbleHz * dragTime))
            view.stretch = dragScale
            animate(dt)
            return
        }
        view.angle = 0
        view.stretch = CGSize(width: 1, height: 1)

        // 포어그라운드 창 조회 (서 있을 땐 0.15초, 공중에선 0.05초 간격)
        let prevWin = frontWin
        if now - lastWinQuery >= (isAirborne ? 0.05 : 0.15) {
            lastWinQuery = now
            refreshWindows()
        }

        var f = body
        let prevBottom = f.minY
        let area = (window.screen ?? NSScreen.main!).visibleFrame
        let screenFloor = area.minY
        let cdt = CGFloat(dt)
        // 화면 바닥(Dock 위)에서 다닐 수 있는 가로 범위
        var floorLo = area.minX, floorHi = area.maxX
        if let d = dockRange, (window.screen ?? NSScreen.main) == NSScreen.screens.first {
            floorLo = max(floorLo, d.lowerBound); floorHi = min(floorHi, d.upperBound)
        }

        // 발판 창 추적: 가로 이동은 따라가고, 닫힘·최소화되거나 발밑이 다른 창에 가려지면 떨어짐
        if let p = platform, !isAirborne {
            if let w = platformNow, w.number == p.number {
                f.origin.x += w.frame.minX - p.frame.minX
                platform = w
                let foot = NSPoint(x: f.midX, y: w.frame.maxY - 1)
                if platformAbove.contains(where: { $0.contains(foot) }) { platform = nil }
            } else {
                platform = nil
            }
        }

        switch state {
        case .drag:
            break
        case .fall, .jump:
            vy += gravity * cdt
            f.origin.x += vx * cdt
            f.origin.y += vy * cdt
            if f.minX <= area.minX { f.origin.x = area.minX; vx = abs(vx) * 0.5 }
            if f.maxX >= area.maxX { f.origin.x = area.maxX - f.width; vx = -abs(vx) * 0.5 }
            if f.maxY >= area.maxY { f.origin.y = area.maxY - f.height; vy = min(vy, 0) }   // 천장
            if state == .jump && vy < 0 { setState(.fall) }

            if vy < 0 && f.origin.y <= screenFloor {
                land(&f, y: screenFloor, on: nil)                 // 화면 바닥이 항상 우선
                f.origin.x = max(floorLo, min(f.origin.x, floorHi - f.width))
            } else if let w = frontWin {
                // 이전 틱 대비 상대 위치로 판정 (펫과 창이 같이 움직여도 통과하지 않게)
                let prevTop = (prevWin?.number == w.number ? prevWin?.frame.maxY : nil) ?? w.frame.maxY
                if prevBottom >= prevTop && f.minY <= w.frame.maxY
                    && f.midX >= w.frame.minX && f.midX <= w.frame.maxX {
                    land(&f, y: w.frame.maxY, on: w)
                }
            }
        case .walk:
            f.origin.x += vx * cdt
            if let p = platform, !walkOffEdge {
                if f.minX <= p.frame.minX { f.origin.x = p.frame.minX; vx = abs(vx) }
                if f.maxX >= p.frame.maxX { f.origin.x = p.frame.maxX - f.width; vx = -abs(vx) }
            }
            let lo = platform == nil ? floorLo : area.minX, hi = platform == nil ? floorHi : area.maxX
            if f.minX <= lo { f.origin.x = lo; vx = abs(vx) }
            if f.maxX >= hi { f.origin.x = hi - f.width; vx = -abs(vx) }
            stateTimer -= dt
            if stateTimer <= 0 { decide() }
        case .idle, .dizzy:
            stateTimer -= dt
            if stateTimer <= 0 { decide() }
        case .sleep:
            stateTimer -= dt
            if stateTimer <= 0 { wakeUp() }                       // 낮잠 끝
        }

        // 펫 중심이 창 범위를 벗어나면 발판 해제
        if let p = platform, f.midX < p.frame.minX || f.midX > p.frame.maxX { platform = nil }

        // 서 있는 상태: 바닥(창 상단 또는 화면 바닥)에 붙이기
        if state == .idle || state == .walk || state == .sleep || state == .dizzy {
            let ground = platform?.frame.maxY ?? screenFloor
            let gap = f.minY - ground
            if gap <= 1 {
                f.origin.y = ground; vy = 0                        // 창이 올라오면 즉시 밀어올림
            } else if state == .sleep {
                wakeUp(); platform = nil; setState(.fall)          // 자다가 발판이 내려가거나 사라지면 깨서 떨어짐
            } else if platform != nil && gap < softDropLimit {
                // 조금 내려간 발판: 상태 유지한 채 툭 떨어져 다시 착지
                vy += gravity * cdt
                f.origin.y = max(ground, f.origin.y + vy * cdt)
                if f.origin.y <= ground { vy = 0 }
            } else {
                platform = nil; walkOffEdge = false
                setState(.fall)
            }
        }
        f.origin.x = max(area.minX, min(f.origin.x, area.maxX - f.width))
        if platform == nil && (state == .idle || state == .walk || state == .sleep || state == .dizzy) {
            f.origin.x = max(floorLo, min(f.origin.x, floorHi - f.width))
        }
        if f.origin != body.origin { body = f }

        if vx != 0 { view.mirrored = spritesFaceRight ? (vx < 0) : (vx > 0) }
        animate(dt)
    }

    func animate(_ dt: Double) {
        let frames = sprites.frames(for: state)
        animAcc += dt
        let fps = state == .sleep ? sleepFPS : state == .walk ? walkFPS : animFPS
        if animAcc >= 1 / fps { animAcc = 0; frameIdx += 1 }
        if frameIdx >= frames.count { frameIdx = state == .jump ? frames.count - 1 : 0 }   // 점프는 한 번만 재생
        view.image = frames[frameIdx]
    }

    // MARK: 마우스
    func mouseDown(_ e: NSEvent) {
        let m = NSEvent.mouseLocation
        pressLocation = m
        dragOffset = NSPoint(x: m.x - window.frame.minX, y: m.y - window.frame.minY)
        dragSamples = [(ProcessInfo.processInfo.systemUptime, window.frame.origin)]
        pressIsJump = e.clickCount >= 2

        if state == .sleep && !pressIsJump {
            wakeUp()                                    // 콕 찌르면 깸
            return
        }
        if pressIsJump && state != .fall && state != .jump {
            vy = jumpPower; vx = 0
            platform = nil
            jumped = true
            setState(.jump)
        }
    }

    func mouseDragged(_ e: NSEvent) {
        if pressIsJump { return }                       // 더블클릭은 점프만
        let m = NSEvent.mouseLocation
        if state != .drag {
            // 살짝 떨린 클릭은 드래그로 치지 않음
            guard hypot(m.x - pressLocation.x, m.y - pressLocation.y) > 3 else { return }
            if state == .sleep { wakeUp() }
            setState(.drag)
            dragTime = 0
            vx = 0; vy = 0
            platform = nil
            walkOffEdge = false
            jumped = false                      // 점프 중 잡혀서 던져지면 헤롱거림
        }
        let p = NSPoint(x: m.x - dragOffset.x, y: m.y - dragOffset.y)
        let now = ProcessInfo.processInfo.systemUptime
        dragSamples.append((now, p))
        dragSamples.removeAll { now - $0.t > 0.1 }
        window.setFrameOrigin(p)                        // 화면 경계 제한 없음 (모니터 간 이동 가능)
    }

    func mouseUp(_ e: NSEvent) {
        guard state == .drag else { return }
        // 최근 0.1초 동안의 이동만으로 던지는 속도 계산 (멈췄다 놓으면 0)
        let now = ProcessInfo.processInfo.systemUptime
        let recent = dragSamples.filter { now - $0.t <= 0.1 }
        vx = 0; vy = 0
        if let a = recent.first, let b = recent.last, b.t - a.t > 0.005 {
            let dt = CGFloat(b.t - a.t)
            vx = max(-maxThrow, min((b.p.x - a.p.x) / dt, maxThrow))
            vy = max(-maxThrow, min((b.p.y - a.p.y) / dt, maxThrow))
        }
        dragSamples = []
        setState(.fall)
    }

    // MARK: 메뉴
    func showMenu(_ e: NSEvent, in v: NSView) {
        let menu = NSMenu()
        menu.addItem(withTitle: "스프라이트 폴더 열기", action: #selector(openFolder), keyEquivalent: "").target = self
        menu.addItem(withTitle: "스프라이트 다시 불러오기", action: #selector(reloadSprites), keyEquivalent: "").target = self
        menu.addItem(withTitle: "재우기", action: #selector(goSleep), keyEquivalent: "").target = self
        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: "Dock 크기 자동 맞추기 (권한 필요)…", action: #selector(askAccessibility), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "").target = self
        NSMenu.popUpContextMenu(menu, with: e, for: v)
    }

    @objc func openFolder() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: spriteDir, withIntermediateDirectories: true)
        // 처음 열 때 폴더가 비어 있으면 앱에 들어 있는 기본 스프라이트를 복사해 둠 (보고 고치기 쉽게)
        if Sprites.pngFiles(in: spriteDir).isEmpty, let src = bundledSpriteDir {
            for f in Sprites.pngFiles(in: src) {
                try? fm.copyItem(atPath: (src as NSString).appendingPathComponent(f),
                                 toPath: (spriteDir as NSString).appendingPathComponent(f))
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: spriteDir))
    }
    @objc func reloadSprites() { sprites = Sprites(); frameIdx = 0 }
    @objc func goSleep() {
        guard !isAirborne && state != .drag else { return }
        sleep(away: false, duration: .random(in: napDuration))
    }
    @objc func askAccessibility() {
        // 시스템 권한 요청 창을 띄우고, 설정의 손쉬운 사용 화면도 열어 줌
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func quit() { NSApp.terminate(nil) }
}

// MARK: - 실행
let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // 독 아이콘 없음
let pet = MainActor.assumeIsolated { Pet() }
app.run()
