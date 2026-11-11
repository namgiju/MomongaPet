import Cocoa
import Carbon
import Network

// MARK: - 설정
// 사용자 스프라이트 폴더가 있으면 우선, 없으면 앱 안에 들어 있는 기본 스프라이트 사용
let spriteDir = (NSHomeDirectory() as NSString).appendingPathComponent("MomongaPet/sprites")
let bundledSpriteDir = Bundle.main.resourcePath.map { ($0 as NSString).appendingPathComponent("sprites") }
let petSize = NSSize(width: 50, height: 50)
let animFPS = 8.0
let sleepFPS = 3.0                  // 자는 애니메이션은 느리게
let walkFPS = 5.0                   // 걷기 애니메이션 (걷는 속도에 맞춰 느리게)
let watchFPS = 2.0                  // 쳐다볼 때 눈동자 움직임 (느리게)
let walkSpeed: CGFloat = 45
let dizzyDuration = 2.0            // 떨어진 뒤 헤롱거리는 시간(초)

// 창 위에서 마우스 쳐다보기
let noticeDuration = 0.5            // 처음 알아챘을 때 "!" 표시 시간(초)
let watchTimeout = 2.0              // 서 있는 창 안에서 마우스가 이만큼 안 움직이면 평소대로
let mouseMoveThreshold: CGFloat = 2 // 이보다 작게 움직이면 무시 (떨림)
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
let hopRange: CGFloat = 60          // 창 높이 차가 이보다 작거나 아래 창이면 가볍게 폴짝
let hopClearance: CGFloat = 15      // 폴짝 뛸 때 더 오르는 높이
let jumpHeightLimit: CGFloat = 0.95  // 점프 높이(dy+여유)가 화면 높이의 이 비율 미만일 때만 점프
let maxJumpDX: CGFloat = 300        // 창까지 가로 거리가 이보다 멀면 걸어서 다가간 뒤 점프
let jumpReactDelay = 0.6...1.4      // 새 창이 뜨고 이만큼(초) 뒤에 반응
let softDropLimit: CGFloat = 30     // 발판이 이보다 조금 내려가면 상태 유지한 채 툭 떨어짐

// 드래그 흔들림
let wobbleDegrees: CGFloat = 10
let wobbleHz = 2.0
let dragScale = CGSize(width: 0.95, height: 1.06)

// 흔들림·늘어남이 잘리지 않도록 창을 펫보다 조금 크게 (투명 여백은 클릭이 통과됨)
let padX = ceil(petSize.height * 0.2)
let padTop = ceil(petSize.height * 0.1)
let windowSize = NSSize(width: petSize.width + padX * 2, height: petSize.height + padTop)

enum PetState: String { case idle, walk, drag, fall, jump, sleep, dizzy, notice, watch, listen }

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

    /// 이름으로 직접 찾기 (없으면 nil)
    func named(_ key: String) -> [NSImage]? {
        if let f = frames[key], !f.isEmpty { return f }
        return nil
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
    var facingLeft = false

    // 창 위에서 마우스 쳐다보기
    var lastMouse = NSEvent.mouseLocation
    var lastMouseMove = 0.0             // 서 있는 창 안에서 마우스가 마지막으로 움직인 시각
    var noticeFrame = 0                 // notice 시트 칸: 0 idle왼쪽, 1 idle오른쪽, 2 walk왼쪽, 3 walk오른쪽
    var watchLeft = false               // 마우스가 펫 왼쪽에 있음
    var dragTime = 0.0
    var lastTick = ProcessInfo.processInfo.systemUptime

    // 잠
    var awaySleep = false               // 자리 비움으로 잠든 건지 (낮잠과 구분)
    var sysIdle = 0.0
    var lastIdlePoll = 0.0
    var lastWake = -Double.infinity
    var bootNap = true                  // 앱을 켜거나 맥이 깨어난 직후의 잠: 인터넷이 붙고 사용자가 있으면 스스로 깸
    var bootNapAt = 0.0

    // Dock
    var dockRange = dockRangeFallback
    var lastDockPoll = -Double.infinity
    var lastDockLog = ""

    // 창
    var frontWin: WinInfo?              // 포어그라운드 앱의 대표 창 (캐시)
    var lastWinQuery = 0.0
    var platform: WinInfo?              // 지금 서 있는 창 (펫이 마지막으로 맞춘 위치)
    var platformNow: WinInfo?           // 그 창의 최신 조회 결과 (닫히거나 최소화되면 nil)
    var platformAbove: [NSRect] = []    // 그 창보다 앞에 있는 창들 (가려짐 판정용)
    var walkOffEdge = false             // 창 끝에서 돌지 않고 걸어가 떨어지기
    var pendingJump = false             // 새 창이 앞에 나타남 → 뛸 수 있게 되면 그 창으로
    var pendingJumpAt = 0.0             // 이 시각 이후에 반응
    var dropThrough: Int?               // 끌려서 움직인 발판 창: 떨어지는 동안 다시 착지 안 함
    var approaching = false             // 점프하려고 창 쪽으로 걸어가는 중
    var lastApproachDist = CGFloat.infinity

    // 마우스
    var pressLocation = NSPoint.zero        // 누른 지점 (화면 좌표)
    var dragOffset = NSPoint.zero           // 창 원점 기준 잡은 위치
    var pressIsJump = false
    var dragSamples: [(t: Double, p: NSPoint)] = []

    var assistant: Assistant!
    var pendingTalk: DispatchWorkItem?      // 한 번 클릭 → 더블클릭 간격만큼 기다렸다 말 걸기
    var pressWoke = false                   // 이번 클릭으로 깨웠으면 말 걸기 안 함

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
        assistant = Assistant(pet: self)

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
        bootNap = false
        lastWake = ProcessInfo.processInfo.systemUptime
        vx = 0
        setState(.idle)
        stateTimer = wakeIdleTime
    }

    func decide() {
        walkOffEdge = false
        approaching = false
        if isAway { sleep(away: true); return }

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastWake >= napCooldown && Double.random(in: 0..<1) < napChance {
            sleep(away: false, duration: .random(in: napDuration)); return
        }
        if Double.random(in: 0..<1) < windowJumpChance, let w = frontWin, platform?.number != w.number {
            pendingJump = true; pendingJumpAt = now                   // 다음 틱에 다가가거나 점프
            vx = 0; setState(.idle); stateTimer = 5
            return
        }

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
    /// 몸 전체가 창 안쪽에 오도록 하는 착지 x
    func jumpTargetX(_ w: WinInfo) -> CGFloat {
        max(w.frame.minX, min(body.minX, w.frame.maxX - body.width))
    }

    /// 앞 창으로: 가까우면 점프, 멀면 그쪽으로 걸어감.
    /// true = 끝(점프했거나 못 뛰는 창이라 포기), false = 아직 다가가는 중
    func goToFrontWindow() -> Bool {
        guard let w = frontWin, platform?.number != w.number else { return true }
        let dx = jumpTargetX(w) - body.minX
        // 창 끝·화면 끝에 막혀 더 못 다가가면 거기서 뜀
        let blocked = approaching && state == .walk && abs(dx) >= lastApproachDist - 0.01
        if abs(dx) > maxJumpDX && !blocked {
            if !(approaching && state == .walk) {
                approaching = true
                walkOffEdge = false
                setState(.walk)
                stateTimer = 30
            }
            vx = (dx < 0 ? -1 : 1) * walkSpeed
            lastApproachDist = abs(dx)
            return false
        }
        let wasApproaching = approaching
        approaching = false
        lastApproachDist = .infinity
        if jumpToFrontWindow() { return true }
        if wasApproaching { vx = 0; setState(.idle); stateTimer = .random(in: 1...3) }
        return true
    }

    func jumpToFrontWindow() -> Bool {
        guard state != .sleep, let w = frontWin, platform?.number != w.number else { return false }
        let f = body
        let area = (window.screen ?? NSScreen.main!).visibleFrame
        let g = abs(gravity)
        let dy = w.frame.maxY - f.minY
        let h = dy > hopRange ? jumpClearance : hopClearance          // 높은 창은 크게, 비슷하거나 낮은 창은 가볍게 폴짝 뛰어내림
        guard dy + h < area.height * jumpHeightLimit,
              w.frame.maxY + h + f.height <= area.maxY else { return false }   // 천장에 부딪혀 궤도 틀어지지 않게
        let tx = jumpTargetX(w)
        let peak = max(dy, 0) + h                                     // 출발점 기준 최고 높이
        vy = sqrt(2 * g * peak)
        let t = (vy + sqrt(2 * g * (peak - dy))) / g
        vx = (tx - f.minX) / t
        platform = nil
        dropThrough = nil
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
        dropThrough = nil
        platform = w
        platformNow = w
        walkOffEdge = false
        if let w { f.origin.x = max(w.frame.minX, min(f.origin.x, w.frame.maxX - f.width)) }
        if isAway { sleep(away: true); return }
        if bootNap {                                    // 켜지자마자 내려와서 잠
            bootNapAt = ProcessInfo.processInfo.systemUptime
            sleep(away: false); return
        }
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
        assistant.update(now: now, body: body)

        // Dock 범위 (2초 간격)
        if now - lastDockPoll >= 2 {
            lastDockPoll = now
            let r = dockIconRange()
            let next = r ?? dockRangeFallback
            if next != dockRange || lastDockLog.isEmpty {
                let msg = "trusted=\(AXIsProcessTrusted()) ax=\(r.map { "\($0)" } ?? "nil") 사용=\(next.map { "\($0)" } ?? "nil") 화면=\(NSScreen.screens.first?.frame ?? .zero)"
                if msg != lastDockLog {
                    lastDockLog = msg
                    let path = (NSHomeDirectory() as NSString).appendingPathComponent("MomongaPet/dock.log")
                    try? (msg + "\n").write(toFile: path, atomically: true, encoding: .utf8)
                }
            }
            dockRange = next
        }

        // 시스템 유휴 시간 (1초 간격)
        if now - lastIdlePoll >= 1 {
            lastIdlePoll = now
            let prev = sysIdle
            sysIdle = systemIdleSeconds()
            // 켜거나 깨어난 직후의 잠: 인터넷이 붙고 사용자가 자리에 있으면 일어남 (그 뒤 인사)
            if bootNap && state == .sleep && assistant.online && sysIdle < presentIdle && now - bootNapAt >= wakeGreetDelay {
                wakeUp()
            }
            assistant.considerChat(now: now, idle: sysIdle)
            if state == .sleep && awaySleep && (sysIdle < 1 || sysIdle < prev) { wakeUp() }
            else if isAway && (state == .idle || state == .walk || state == .dizzy || state == .watch) { sleep(away: true) }
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

        // 앞 창이 바뀌면(새 창이 뜨거나 다른 창으로 전환) 잠깐 뒤 확률 없이 그 창으로
        if let w = frontWin, w.number != prevWin?.number {
            pendingJump = true
            pendingJumpAt = now + .random(in: jumpReactDelay)
            approaching = false
            if [.idle, .walk, .notice, .watch].contains(state) {   // 바닥에 있어도 "!"로 알아챔 (헤롱헤롱 중엔 끝난 뒤에)
                noticeFrame = (state == .walk ? 2 : 0) + (facingLeft ? 0 : 1)
                vx = 0; walkOffEdge = false
                setState(.notice)
                stateTimer = pendingJumpAt - now
            }
        }
        if pendingJump && now >= pendingJumpAt {
            if frontWin == nil || platform?.number == frontWin?.number {
                pendingJump = false; approaching = false              // 이미 그 창 위
            } else if state == .sleep && !awaySleep {
                wakeUp()                                              // 낮잠이면 깨워서 다음 틱에
            } else if [.idle, .walk, .notice, .watch].contains(state), goToFrontWindow() {
                pendingJump = false
            }   // 공중이거나 헤롱헤롱 중이면 끝난 뒤 다시 시도
        }

        // 말 거는 중(입력창이 열렸거나 답을 기다림)엔 멈춰서 귀 기울이기
        let listening = assistant.input.isVisible || assistant.busy
        if listening {
            if [.idle, .walk, .notice, .watch, .dizzy, .sleep].contains(state) {
                awaySleep = false
                vx = 0; walkOffEdge = false; approaching = false
                setState(.listen)
            }
        } else if state == .listen {
            decide()
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

        // 발판 창 추적: 창이 조금이라도 움직이면(끌어서 옮김) 떨어지고, 닫힘·최소화되거나 발밑이 다른 창에 가려져도 떨어짐
        if let p = platform, !isAirborne {
            if let w = platformNow, w.number == p.number {
                if abs(w.frame.minX - p.frame.minX) > 0.5 || abs(w.frame.maxY - p.frame.maxY) > 0.5 {
                    platform = nil
                    dropThrough = w.number                            // 떨어지는 동안 이 창엔 다시 착지 안 함
                    walkOffEdge = false; approaching = false; jumped = false
                    if state == .sleep { wakeUp() }
                    vx = 0; vy = 0
                    setState(.fall)
                }
            }
            if let w = platformNow, let p = platform, w.number == p.number {
                platform = w
                let foot = NSPoint(x: f.midX, y: w.frame.maxY - 1)
                if platformAbove.contains(where: { $0.contains(foot) }) { platform = nil }
            } else {
                if platform != nil { platform = nil }
            }
        }

        // 창 위에 있을 때 그 창 안에서 마우스가 움직이면 "!" 후 쳐다보기 (Dock 위에선 안 함)
        let mouse = NSEvent.mouseLocation
        if hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y) > mouseMoveThreshold {
            lastMouse = mouse
            if let p = platform, p.frame.contains(mouse) {
                lastMouseMove = now
                if state == .idle || state == .walk {
                    noticeFrame = (state == .walk ? 2 : 0) + (facingLeft ? 0 : 1)
                    vx = 0; walkOffEdge = false
                    setState(.notice)
                    stateTimer = noticeDuration
                }
            }
        }
        if state == .notice || state == .watch { watchLeft = mouse.x < f.midX }
        if state == .watch { facingLeft = watchLeft }             // 쳐다보는 쪽 = 보고 있는 방향 (다음 "!" 방향이 어긋나지 않게)

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
            } else if let w = frontWin, w.number != dropThrough {
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
            if stateTimer <= 0 {
                if state == .dizzy && pendingJump {                // 헤롱헤롱 중에 창이 바뀌었으면 정신 차린 뒤 "!"
                    pendingJumpAt = now + .random(in: jumpReactDelay)
                    noticeFrame = facingLeft ? 0 : 1
                    setState(.notice)
                    stateTimer = pendingJumpAt - now
                } else { decide() }
            }
        case .listen:
            break                                                 // 대화가 끝날 때까지 가만히
        case .sleep:
            stateTimer -= dt
            if stateTimer <= 0 { wakeUp() }                       // 낮잠 끝
        case .notice:
            stateTimer -= dt
            if stateTimer <= 0 {
                if pendingJump { vx = 0; setState(.idle); stateTimer = 5 }   // 창 알아챈 거면 바로 출발
                else { setState(.watch) }
            }
        case .watch:
            if now - lastMouseMove >= watchTimeout {              // 2초 조용하면 평소대로
                facingLeft = watchLeft
                decide()
            }
        }

        // 펫 중심이 창 범위를 벗어나면 발판 해제
        if let p = platform, f.midX < p.frame.minX || f.midX > p.frame.maxX { platform = nil }

        // 서 있는 상태: 바닥(창 상단 또는 화면 바닥)에 붙이기
        if state == .idle || state == .walk || state == .sleep || state == .dizzy || state == .notice || state == .watch || state == .listen {
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
        if platform == nil && (state == .idle || state == .walk || state == .sleep || state == .dizzy || state == .notice || state == .watch || state == .listen) {
            f.origin.x = max(floorLo, min(f.origin.x, floorHi - f.width))
        }
        if f.origin != body.origin { body = f }

        if vx != 0 { facingLeft = vx < 0 }
        animate(dt)
    }

    func animate(_ dt: Double) {
        var frames = sprites.frames(for: state)
        var mirror = spritesFaceRight ? facingLeft : !facingLeft
        // notice·watch 그림은 방향별로 따로 있어서 뒤집지 않음
        if state == .notice, let n = sprites.named("notice"), n.count >= 4 { frames = [n[noticeFrame]]; mirror = false }
        if state == .watch, let w = sprites.named(watchLeft ? "watchleft" : "watchright") { frames = w; mirror = false }
        if state == .listen, let l = sprites.named(facingLeft ? "listenleft" : "listenright") { frames = l; mirror = false }
        view.mirrored = mirror
        animAcc += dt
        let fps = state == .sleep ? sleepFPS : state == .walk ? walkFPS : state == .watch ? watchFPS : animFPS
        if animAcc >= 1 / fps { animAcc = 0; frameIdx += 1 }
        if state == .watch && frames.count > 2 {
            // 왕복 재생 (1 2 3 2 1 2 3 …): 눈동자가 자연스럽게 오가도록
            let period = frames.count * 2 - 2
            frameIdx %= period
            view.image = frames[frameIdx < frames.count ? frameIdx : period - frameIdx]
            return
        }
        if frameIdx >= frames.count { frameIdx = state == .jump ? frames.count - 1 : 0 }   // 점프는 한 번만 재생
        view.image = frames[frameIdx]
    }

    /// 맥이 잠자기에서 깨어났을 때: 일단 자면서 인터넷 연결을 기다림
    func startBootNap() {
        bootNap = true
        bootNapAt = ProcessInfo.processInfo.systemUptime
        if !isAirborne && state != .drag && state != .listen { sleep(away: false) }   // 공중이면 내려앉은 뒤 잠
    }

    /// 비서 답이 왔을 때: 자고 있으면 깨고, 아니면 "!" 하고 잠깐 쳐다봄
    func react() {
        if state == .sleep { wakeUp(); return }
        guard state == .idle || state == .walk || state == .watch || state == .listen else { return }
        noticeFrame = (state == .walk ? 2 : 0) + (facingLeft ? 0 : 1)
        vx = 0; walkOffEdge = false
        lastMouseMove = ProcessInfo.processInfo.systemUptime
        setState(.notice)
        stateTimer = noticeDuration
    }

    // MARK: 마우스
    func mouseDown(_ e: NSEvent) {
        let m = NSEvent.mouseLocation
        pressLocation = m
        dragOffset = NSPoint(x: m.x - window.frame.minX, y: m.y - window.frame.minY)
        dragSamples = [(ProcessInfo.processInfo.systemUptime, window.frame.origin)]
        pressIsJump = e.clickCount >= 2
        pressWoke = false
        if pressIsJump { pendingTalk?.cancel(); pendingTalk = nil }   // 더블클릭이면 말 걸기 취소

        if state == .sleep && !pressIsJump {
            wakeUp()                                    // 콕 찌르면 깸
            pressWoke = true
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
        guard state == .drag else {
            // 한 번 클릭: 더블클릭이 아닌 게 확실해지면 말 걸기 창 열기/닫기
            if e.clickCount == 1 && !pressWoke {
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated { self?.pendingTalk = nil; self?.assistant.toggleInput() }
                }
                pendingTalk = work
                DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
            }
            return
        }
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
        if assistant.busy {
            menu.addItem(withTitle: "하던 일 그만두기", action: #selector(cancelTask), keyEquivalent: "").target = self
        } else {
            menu.addItem(withTitle: "말 걸기…", action: #selector(talk), keyEquivalent: "").target = self
        }
        if assistant.sessionID != nil {
            menu.addItem(withTitle: "새 대화 시작", action: #selector(newChat), keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: "말투 바꾸기…", action: #selector(Assistant.editPersona), keyEquivalent: "").target = assistant
        menu.addItem(.separator())
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
    @objc func talk() { assistant.ask() }
    @objc func cancelTask() { assistant.cancel() }
    @objc func newChat() { assistant.newChat() }
    @objc func quit() {
        assistant.process?.terminate()                  // 하던 claude 작업도 같이 끝냄
        assistant.chatProcess?.terminate()
        NSApp.terminate(nil)
    }
}

// MARK: - 비서 (Claude Code CLI)
// 우클릭 → "말 걸기"로 일을 시키면 `claude -p`를 백그라운드로 실행하고 답을 말풍선으로 보여 줌.
// 대화는 세션 ID로 이어지고, 말투는 ~/MomongaPet/persona.txt 로 바꿀 수 있음
let petHome = (NSHomeDirectory() as NSString).appendingPathComponent("MomongaPet")
let personaPath = (petHome as NSString).appendingPathComponent("persona.txt")
let lastReplyPath = (petHome as NSString).appendingPathComponent("last_reply.txt")
let claudePermissionMode = "auto"       // 위험해 보이는 동작은 Claude Code가 스스로 막음
let claudeModel = "haiku"               // 가볍게: haiku, 일을 더 잘하게: sonnet, 최고 성능: opus
let bubbleMaxChars = 240                // 이보다 긴 답은 잘라 보여 주고, 말풍선을 누르면 전체를 엶
let bubbleMaxWidth: CGFloat = 240
let talkHotKey = (code: UInt32(kVK_ANSI_M), mods: UInt32(controlKey | optionKey))   // ⌃⌥M: 어디서든 말 걸기

// 먼저 말 걸기: 사용자가 자리에 있을 때, 의미 있는 순간에만 (가벼운 호출: 도구·기본 프롬프트 없이 한마디만)
let chatMinInterval = 1800.0            // 먼저 말 거는 최소 간격(초)
let longWorkAfter = 7200.0              // 쉬지 않고 이만큼 일하면 쉬라고 챙김
let breakIdle = 300.0                   // 입력이 이만큼 없으면 쉰 걸로 침
let presentIdle = 30.0                  // 마지막 입력이 이보다 최근이어야 "자리에 있음"
let dayStartHour = 5                    // 하루의 시작 (새벽 5시 전은 전날로 침 → 밤샘 중 자정에 아침 인사 안 함)
let openerContextTime = 600.0           // 먼저 건넨 말에 이 시간(초) 안에 대답하면 그 말을 맥락으로 붙임
let wakeGreetDelay = 5.0                // 깨어나고 최소 이만큼(초) 뒤에 인사 (네트워크가 붙을 때까지는 더 기다림)
let chatRetryDelay = 15.0               // 먼저 말 걸기 호출이 실패하면 이만큼 뒤에 다시 (연결 직후 불안정할 때)
let chatMaxRetries = 2
let defaultPersona = """
너는 사용자의 macOS 화면 아래에 사는 작은 모몽가 펫이자 비서야.
반말로 귀엽고 다정하게 말해.
답은 펫 머리 위 말풍선에 뜨니까 보통 1~3문장으로 짧게 하고, 마크다운 표·코드 블록·제목은 쓰지 마.
일을 시키면 직접 처리하고, 끝나면 무엇을 했는지만 짧게 알려 줘.
"""

/// 앱을 앞으로 가져오지 않고도 키 입력을 받을 수 있는 패널
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// 펫 그림과 같은 색: 갈색 외곽선, 크림색 바탕
let inkColor = NSColor(srgbRed: 0.29, green: 0.09, blue: 0.04, alpha: 1)
let paperColor = NSColor(srgbRed: 1.0, green: 0.99, blue: 0.96, alpha: 1)

/// 둥근 시스템 글꼴 (SF Pro Rounded)
func roundedFont(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: d, size: size) ?? base
}

/// 아래로 꼬리가 달린 말풍선 모양 (말풍선·입력창 공용)
final class BubbleView: NSView {
    static let tailH: CGFloat = 8
    static let radius: CGFloat = 13
    static let lineW: CGFloat = 2
    var tailX: CGFloat = 0 { didSet { if oldValue != tailX { needsDisplay = true } } }
    var onClick: (() -> Void)?
    var passesClicks = false            // 입력창: 안쪽 텍스트 칸이 클릭을 받도록

    override func draw(_ dirtyRect: NSRect) {
        let t = BubbleView.tailH, r = BubbleView.radius, lw = BubbleView.lineW
        let b = NSRect(x: lw / 2, y: t + lw / 2, width: bounds.width - lw, height: bounds.height - t - lw)
        let x = max(b.minX + r + 7, min(tailX, b.maxX - r - 7))
        // 몸통과 꼬리를 한 선으로 이어 그림
        let path = NSBezierPath()
        path.move(to: NSPoint(x: b.minX + r, y: b.minY))
        path.line(to: NSPoint(x: x - 7, y: b.minY))
        path.line(to: NSPoint(x: x, y: lw + 0.5))
        path.line(to: NSPoint(x: x + 5, y: b.minY))
        path.appendArc(withCenter: NSPoint(x: b.maxX - r, y: b.minY + r), radius: r, startAngle: 270, endAngle: 360)
        path.appendArc(withCenter: NSPoint(x: b.maxX - r, y: b.maxY - r), radius: r, startAngle: 0, endAngle: 90)
        path.appendArc(withCenter: NSPoint(x: b.minX + r, y: b.maxY - r), radius: r, startAngle: 90, endAngle: 180)
        path.appendArc(withCenter: NSPoint(x: b.minX + r, y: b.minY + r), radius: r, startAngle: 180, endAngle: 270)
        path.close()
        path.lineJoinStyle = .round
        path.lineWidth = lw
        paperColor.setFill(); path.fill()
        inkColor.setStroke(); path.stroke()
    }
    override func hitTest(_ p: NSPoint) -> NSView? {
        passesClicks ? super.hitTest(p) : (frame.contains(p) ? self : nil)
    }
    override func mouseDown(with e: NSEvent) { onClick?() }
}

/// 펫 머리 위 말풍선
@MainActor
final class Bubble {
    let panel: NSPanel
    let view = BubbleView()
    let label = NSTextField(wrappingLabelWithString: "")
    let font = roundedFont(13, weight: .medium)
    var isVisible: Bool { panel.isVisible }

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        label.font = font
        label.textColor = inkColor
        label.isSelectable = false
        view.addSubview(label)
        panel.contentView = view
    }

    func show(_ text: String) {
        let r = NSAttributedString(string: text, attributes: [.font: font])
            .boundingRect(with: NSSize(width: bubbleMaxWidth, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let w = ceil(r.width) + 6, h = ceil(r.height) + 2
        label.stringValue = text
        label.frame = NSRect(x: 12, y: BubbleView.tailH + 9, width: w, height: h)
        panel.setContentSize(NSSize(width: w + 24, height: h + 18 + BubbleView.tailH))
        view.needsDisplay = true
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }

    /// 펫 몸통 위로 (화면 밖으로 나가지 않게)
    func place(above body: NSRect) {
        let s = panel.frame.size
        let area = (NSScreen.screens.first { $0.frame.intersects(body) } ?? NSScreen.main!).visibleFrame
        let x = max(area.minX, min(body.midX - s.width / 2, area.maxX - s.width))
        let y = min(body.maxY + 2, area.maxY - s.height)
        let o = NSPoint(x: round(x), y: round(y))
        if panel.frame.origin != o { panel.setFrameOrigin(o) }
        view.tailX = body.midX - o.x
    }
}

@MainActor
final class Assistant: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    weak var pet: Pet?
    let bubble = Bubble()
    let input: KeyPanel
    let field = NSTextField()
    var process: Process?
    var busy: Bool { process != nil }
    var thinkingSince = 0.0
    var lastDots = -1
    var hideAt = Double.infinity
    var loginPATH: String?

    // 먼저 말 걸기
    var chatProcess: Process?
    var lastChat = -Double.infinity
    var activeSince: Double?            // 쉬지 않고 일하기 시작한 시각
    var wokeAt: Double?                 // 잠자기에서 깨어난 시각 (아직 인사 전)
    var opener: (text: String, at: Double)?   // 펫이 먼저 건넨 말
    var retryChat: (situation: String, at: Double, tries: Int)?   // 실패해서 다시 해 볼 말 걸기
    var online = false                  // 인터넷 연결됨 (잠자기에서 깨어난 직후엔 잠깐 false)
    let netMonitor = NWPathMonitor()

    var sessionID: String? {
        get { UserDefaults.standard.string(forKey: "claudeSessionID") }
        set { UserDefaults.standard.set(newValue, forKey: "claudeSessionID") }
    }

    init(pet: Pet) {
        self.pet = pet
        input = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 38 + BubbleView.tailH),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        input.isOpaque = false
        input.backgroundColor = .clear
        input.hasShadow = true
        input.hidesOnDeactivate = false
        input.level = .floating
        input.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        input.delegate = self
        let font = roundedFont(13, weight: .medium)
        field.frame = NSRect(x: 15, y: BubbleView.tailH + 10, width: 270, height: 19)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.font = font
        field.textColor = inkColor
        field.placeholderAttributedString = NSAttributedString(string: "모몽가에게 말 걸기…",
            attributes: [.font: font, .foregroundColor: inkColor.withAlphaComponent(0.4)])
        field.delegate = self
        let box = BubbleView(frame: NSRect(x: 0, y: 0, width: 300, height: 38 + BubbleView.tailH))
        box.passesClicks = true
        box.addSubview(field)
        input.contentView = box
        registerHotKey()

        // 맥이 잠자기에서 깨어나면(덮개 열기 등) 다음 말 걸기는 새 대화로
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sessionID = nil
                self?.wokeAt = ProcessInfo.processInfo.systemUptime
                self?.activeSince = nil
                self?.pet?.startBootNap()
            }
        }

        // 인터넷 연결 상태 (덮개를 열면 Wi-Fi가 다시 붙을 때까지 몇 초 걸림)
        netMonitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.online = ok } }
        }
        netMonitor.start(queue: DispatchQueue.global(qos: .utility))

        // 앱은 로그인 셸의 PATH를 모름 → claude와 그 도구들이 쓸 PATH를 미리 읽어 둠
        DispatchQueue.global(qos: .utility).async {
            let path = Assistant.readLoginPATH()
            DispatchQueue.main.async { MainActor.assumeIsolated { self.loginPATH = path } }
        }
    }

    nonisolated static func readLoginPATH() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "printf %s \"$PATH\""]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let s = String(decoding: d, as: UTF8.self)
        return s.isEmpty ? nil : s
    }

    var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        env["PATH"] = loginPATH ?? "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return env
    }

    func claudePath() -> String? {
        let dirs = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + ["\(NSHomeDirectory())/.local/bin"]
        return dirs.map { ($0 as NSString).appendingPathComponent("claude") }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func loadPersona() -> String {
        let s = (try? String(contentsOfFile: personaPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? defaultPersona : s
    }

    // MARK: 입력창
    func ask() {
        guard !busy else { return }
        bubble.hide()
        field.stringValue = ""
        if let p = pet { placeInput(above: p.body) }
        input.makeKeyAndOrderFront(nil)
        input.makeFirstResponder(field)
    }

    func closeInput() { input.orderOut(nil) }

    func toggleInput() { input.isVisible ? closeInput() : ask() }

    /// 어디서든 단축키로 말 걸기 창 열기/닫기 (Carbon 핫키는 별도 권한 없이 동작)
    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ctx in
            guard let ctx else { return noErr }
            let a = Unmanaged<Assistant>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { a.toggleInput() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(talkHotKey.code, talkHotKey.mods, EventHotKeyID(signature: OSType(0x4D4D4E47), id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }

    func placeInput(above body: NSRect) {
        let s = input.frame.size
        let area = (NSScreen.screens.first { $0.frame.intersects(body) } ?? NSScreen.main!).visibleFrame
        let o = NSPoint(x: round(max(area.minX, min(body.midX - s.width / 2, area.maxX - s.width))),
                        y: round(min(body.maxY + 2, area.maxY - s.height)))
        if input.frame.origin != o { input.setFrameOrigin(o) }
        (input.contentView as? BubbleView)?.tailX = body.midX - o.x
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            closeInput()
            if !text.isEmpty {
                // 말투가 바뀌었으면 예전 말투로 쌓인 대화에 끌려가지 않게 새 대화로 시작
                let persona = loadPersona()
                if UserDefaults.standard.string(forKey: "claudeSessionPersona") != persona {
                    sessionID = nil
                    UserDefaults.standard.set(persona, forKey: "claudeSessionPersona")
                }
                var prompt = text
                if let o = opener, ProcessInfo.processInfo.systemUptime - o.at < openerContextTime {
                    prompt = "(방금 네가 먼저 \"\(o.text)\"라고 말을 걸었고, 아래는 거기에 대한 사용자의 대답이야)\n" + text
                }
                opener = nil
                run(prompt, resume: sessionID)
            }
            return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) { closeInput(); return true }
        return false
    }

    func windowDidResignKey(_ n: Notification) { closeInput() }   // 다른 곳을 누르면 닫힘

    // MARK: 실행
    /// claude를 백그라운드로 실행하고, 끝나면 메인 스레드에서 done(프로세스, stdout, stderr)
    func launch(_ args: [String], done: @escaping (Process, Data, Data) -> Void) -> Process? {
        guard let exe = claudePath() else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        p.environment = environment
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        guard (try? p.run()) != nil else { return nil }
        DispatchQueue.global(qos: .userInitiated).async {
            // stdout·stderr를 동시에 읽어야 한쪽 버퍼가 차서 멈추는 일이 없음
            let errBox = DataBox()
            let g = DispatchGroup()
            g.enter()
            DispatchQueue.global().async { errBox.data = err.fileHandleForReading.readDataToEndOfFile(); g.leave() }
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            g.wait()
            p.waitUntilExit()
            let errData = errBox.data
            DispatchQueue.main.async { MainActor.assumeIsolated { done(p, outData, errData) } }
        }
        return p
    }

    func run(_ prompt: String, resume: String?) {
        var args = ["-p", prompt,
                    "--permission-mode", claudePermissionMode,
                    "--model", claudeModel,
                    "--append-system-prompt", loadPersona(),
                    "--output-format", "json"]
        if let r = resume { args += ["--resume", r] }
        guard let p = launch(args, done: { [weak self] p, out, err in
            self?.finished(p, out: out, err: err, prompt: prompt, resumed: resume != nil)
        }) else {
            say("claude를 실행하지 못했어… Claude Code가 설치돼 있는지 봐 줘!", seconds: 8)
            return
        }
        process = p
        thinkingSince = ProcessInfo.processInfo.systemUptime
        lastDots = -1
        hideAt = .infinity
    }

    func finished(_ p: Process, out: Data, err: Data, prompt: String, resumed: Bool) {
        guard p === process else { return }                 // 취소된 작업
        process = nil
        let json = (try? JSONSerialization.jsonObject(with: out)) as? [String: Any]
        let result = ((json?["result"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let failed = json == nil || (json?["is_error"] as? Bool ?? false) || result.isEmpty
        if failed && resumed {
            // 이전 대화를 못 이어가면(세션이 지워졌거나 등) 새 대화로 한 번 더
            sessionID = nil
            run(prompt, resume: nil)
            return
        }
        if failed {
            let raw = result.isEmpty
                ? String(decoding: err.isEmpty ? out : err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                : result
            say("앗, 잘 안 됐어… " + String(raw.prefix(160)), seconds: 10)
        } else {
            if let sid = json?["session_id"] as? String { sessionID = sid }
            say(result)
        }
        pet?.react()
    }

    // MARK: 먼저 말 걸기
    /// 1초마다: 아침 첫 만남·덮개 열고 돌아옴·오래 쉬지 않고 일함 중 하나면 한마디 건넴
    func considerChat(now: Double, idle: Double) {
        if idle >= breakIdle { activeSince = nil } else if activeSince == nil { activeSince = now - idle }
        // 오프라인이면 아무 것도 소모하지 않고 연결될 때까지 기다림
        guard online, idle < presentIdle, !busy, chatProcess == nil, !input.isVisible, !bubble.isVisible else { return }
        // 켜지거나 깨어난 직후 자는 중이면, 일어나서 잠깐 멍하니 있은 뒤에 말 걺
        if let p = pet, p.bootNap || now - p.lastWake < wakeIdleTime { return }

        if let r = retryChat {
            if now >= r.at { retryChat = nil; chat(r.situation, tries: r.tries) }
            return
        }

        let day = Calendar.current.date(byAdding: .hour, value: -dayStartHour, to: Date())!
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: day)
        var situation: String?
        if UserDefaults.standard.string(forKey: "lastGreetDay") != today {
            UserDefaults.standard.set(today, forKey: "lastGreetDay")
            wokeAt = nil
            situation = "오늘 사용자를 처음 만났어. 오늘의 첫 인사를 해"
        } else if let w = wokeAt, now - w >= wakeGreetDelay {
            wokeAt = nil
            if now - lastChat >= chatMinInterval { situation = "사용자가 맥북 덮개를 열고(잠자기에서 깨어나) 돌아왔어. 반겨 줘" }
        } else if let s = activeSince, now - s >= longWorkAfter, now - lastChat >= chatMinInterval {
            activeSince = now                                   // 또 이만큼 지나면 다시
            situation = "사용자가 \(Int((now - s) / 60))분 넘게 쉬지 않고 컴퓨터를 쓰고 있어. 잠깐 쉬라고 챙겨 줘"
        }
        if let situation { chat(situation) }
    }

    func chat(_ situation: String, tries: Int = 0) {
        lastChat = ProcessInfo.processInfo.systemUptime
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 EEEE a h시 m분"
        let prompt = "지금: \(f.string(from: Date())). 상황: \(situation). 사용자에게 먼저 건넬 한마디를 해."
        let system = loadPersona() + "\n\n지금은 네가 사용자에게 먼저 말을 거는 거야. 상황에 맞는 짧은 한마디(1~2문장)만, 따옴표나 설명 없이 대사만 말해."
        let args = ["-p", prompt, "--model", claudeModel, "--system-prompt", system,
                    "--tools", "", "--no-session-persistence", "--strict-mcp-config", "--disable-slash-commands",
                    "--output-format", "json"]
        chatProcess = launch(args) { [weak self] p, out, _ in
            guard let self, p === self.chatProcess else { return }
            self.chatProcess = nil
            let json = (try? JSONSerialization.jsonObject(with: out)) as? [String: Any]
            let text = ((json?["result"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let failed = (json?["is_error"] as? Bool ?? true) || text.isEmpty
            if failed && tries < chatMaxRetries {
                // 연결 직후라 아직 불안정할 수 있음 → 잠시 뒤 다시
                self.retryChat = (situation, ProcessInfo.processInfo.systemUptime + chatRetryDelay, tries + 1)
                return
            }
            // 계속 실패했거나, 그사이 사용자가 말을 걸기 시작했으면 조용히 넘어감
            guard !failed, !self.busy, !self.input.isVisible else { return }
            self.opener = (text, ProcessInfo.processInfo.systemUptime)
            self.say(text, seconds: 15)
            self.bubble.view.onClick = { [weak self] in self?.ask() }   // 말풍선을 누르면 바로 대답
            self.pet?.react()
        }
    }

    func cancel() {
        guard let p = process else { return }
        process = nil
        p.terminate()
        say("알았어, 그만할게!", seconds: 3)
    }

    func newChat() {
        sessionID = nil
        say("새로 시작하자!", seconds: 3)
    }

    // MARK: 말풍선
    /// 답을 말풍선에 띄움. 길면 잘라 보여 주고, 전체는 파일로 저장해 말풍선을 누르면 엶
    func say(_ text: String, seconds: Double? = nil) {
        var t = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        t = t.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        try? FileManager.default.createDirectory(atPath: petHome, withIntermediateDirectories: true)
        try? (text + "\n").write(toFile: lastReplyPath, atomically: true, encoding: .utf8)
        let long = t.count > bubbleMaxChars
        if long { t = String(t.prefix(bubbleMaxChars)) + "…\n(눌러서 전체 보기)" }
        bubble.view.onClick = { [weak self] in
            if long { NSWorkspace.shared.open(URL(fileURLWithPath: lastReplyPath)) }
            self?.bubble.hide()
        }
        bubble.show(t)
        if let p = pet { bubble.place(above: p.body) }
        hideAt = ProcessInfo.processInfo.systemUptime + (seconds ?? min(25, max(5, Double(t.count) * 0.12)))
    }

    /// 매 틱: 말풍선·입력창이 펫을 따라다니고, 일하는 동안 "생각 중" 표시
    func update(now: Double, body: NSRect) {
        if busy {
            let dots = Int((now - thinkingSince) / 0.5) % 4
            if dots != lastDots {
                lastDots = dots
                bubble.view.onClick = nil
                let secs = Int(now - thinkingSince)
                bubble.show("생각 중" + String(repeating: ".", count: dots) + String(repeating: " ", count: 3 - dots)
                            + (secs >= 5 ? "  \(secs)초" : ""))
            }
        } else if bubble.isVisible && now >= hideAt {
            bubble.hide()
        }
        if bubble.isVisible { bubble.place(above: body) }
        if input.isVisible { placeInput(above: body) }
    }

    @objc func editPersona() {
        try? FileManager.default.createDirectory(atPath: petHome, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: personaPath) {
            try? (defaultPersona + "\n").write(toFile: personaPath, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: personaPath))
    }
}

final class DataBox: @unchecked Sendable { var data = Data() }

// MARK: - 실행
let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // 독 아이콘 없음
let pet = MainActor.assumeIsolated { Pet() }
app.run()
