import Foundation

func setWindowLevelViaSA(windowId: UInt32, levelKey: Int32) {
    // SA-01/SA-03: Use per-user temp directory instead of world-writable /tmp/
    let socketPath = NSTemporaryDirectory() + "aerospace-sa.socket"

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    if fd == -1 {
        return
    }
    defer { close(fd) }

    // Set socket timeout to prevent hang if Dock is frozen
    var timeout = timeval()
    timeout.tv_sec = 0
    timeout.tv_usec = 100000 // 100ms
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)

    let pathBytes = socketPath.utf8CString
    let pathLen = min(pathBytes.count, 104)
    _ = withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPointer in
        let rawPointer = UnsafeMutableRawPointer(sunPathPointer)
        let destination = rawPointer.assumingMemoryBound(to: CChar.self)
        for i in 0..<pathLen {
            destination[i] = pathBytes[i]
        }
    }

    let addrSize = MemoryLayout<sockaddr_un>.size
    let connectResult = withUnsafePointer(to: &addr) { addrPointer in
        addrPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            connect(fd, sockaddrPointer, socklen_t(addrSize))
        }
    }

    if connectResult == 0 {
        var packet = [windowId, UInt32(bitPattern: levelKey)]
        _ = write(fd, &packet, MemoryLayout<UInt32>.size * 2)
    }
}
