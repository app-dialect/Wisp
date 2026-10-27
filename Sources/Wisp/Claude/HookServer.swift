import Foundation

/// A tiny Unix-socket server. The hook script connects, writes one JSON line and,
/// for permission requests, waits for one JSON line back.
final class HookServer {
    typealias Reply = ([String: Any]) -> Void
    /// Called on the main queue with the event and, if the hook is waiting, a way to answer it.
    var onEvent: (([String: Any], Reply?) -> Void)?
    /// Called on the main queue when a waiting hook goes away unanswered (Claude Code
    /// timed it out, or the person answered in the terminal). Carries the `_wisp_token`.
    var onHangup: ((String) -> Void)?

    private let path: String
    private var listenFD: Int32 = -1

    init(path: String) { self.path = path }

    func start() {
        unlink(path)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, size) }
        }
        guard bound == 0, listen(listenFD, 32) == 0 else {
            NSLog("Wisp: could not listen on \(path): \(String(cString: strerror(errno)))")
            close(listenFD)
            listenFD = -1
            return
        }
        chmod(path, 0o600)

        let fd = listenFD
        Thread.detachNewThread { [weak self] in
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 {
                    if errno == EINTR { continue }
                    break
                }
                Thread.detachNewThread { self?.serve(client) }
            }
        }
    }

    func stop() {
        if listenFD >= 0 { close(listenFD) }
        unlink(path)
    }

    private func serve(_ fd: Int32) {
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        while !data.contains(0x0A) {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
            if data.count > 8_000_000 { break }
        }
        guard let line = data.split(separator: 0x0A).first,
              let parsed = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
        else { close(fd); return }

        var json = parsed
        let asks = ((json["_wisp"] as? [String: Any])?["ask"] as? Bool) == true
        let waits = (json["hook_event_name"] as? String) == "PermissionRequest" || asks
        let token = UUID().uuidString
        json["_wisp_token"] = token
        if !waits { close(fd) }

        let once = Once()
        let reply: Reply? = waits ? { answer in
            // Answers can only be sent once; a late tap after a timeout is ignored.
            guard once.claim() else { return }
            if var out = try? JSONSerialization.data(withJSONObject: answer) {
                out.append(0x0A)
                _ = out.withUnsafeBytes { write(fd, $0.baseAddress, out.count) }
            }
            close(fd)
        } : nil

        DispatchQueue.main.async { [weak self] in self?.onEvent?(json, reply) }
        guard waits else { return }

        // Watch for the hook hanging up while we wait for an answer.
        while !once.isDone {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
            let r = poll(&pfd, 1, 500)
            if r > 0, once.claim() {
                close(fd)
                DispatchQueue.main.async { [weak self] in self?.onHangup?(token) }
                return
            }
        }
    }
}

private final class Once {
    private var done = false
    private let lock = NSLock()
    var isDone: Bool { lock.lock(); defer { lock.unlock() }; return done }
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
