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
    _ = unsafe setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)

    let pathBytes = socketPath.utf8CString
    let pathLen = min(pathBytes.count, 104)
    _ = unsafe withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPointer in
        let rawPointer = unsafe UnsafeMutableRawPointer(sunPathPointer)
        let destination = unsafe rawPointer.assumingMemoryBound(to: CChar.self)
        for i in 0..<pathLen {
            unsafe destination[i] = pathBytes[i]
        }
    }

    let addrSize = MemoryLayout<sockaddr_un>.size
    let connectResult = unsafe withUnsafePointer(to: &addr) { addrPointer in
        unsafe addrPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            unsafe connect(fd, sockaddrPointer, socklen_t(addrSize))
        }
    }

    if connectResult == 0 {
        var packet = [windowId, UInt32(bitPattern: levelKey)]
        _ = unsafe write(fd, &packet, MemoryLayout<UInt32>.size * 2)
    }
}
