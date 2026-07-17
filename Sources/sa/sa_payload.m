#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/stat.h>
#import <unistd.h>
#import <dlfcn.h>
#import <pthread.h>

typedef int (*SLSMainConnectionIDFunc)(void);
typedef CGError (*SLSSetWindowSubLevelFunc)(int cid, uint32_t wid, int level);

static SLSMainConnectionIDFunc _SLSMainConnectionID = NULL;
static SLSSetWindowSubLevelFunc _SLSSetWindowSubLevel = NULL;

// SA-02: Only allow known-safe window sub-level values
static BOOL is_valid_level(int32_t level) {
    return level >= 0 && level <= 3;
}

static void handle_client(int client_fd) {
    // SA-08: Set read timeout to prevent a malicious client from blocking the server
    struct timeval tv = {.tv_sec = 1, .tv_usec = 0};
    setsockopt(client_fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    uint32_t packet[2];
    ssize_t bytes_read = read(client_fd, packet, sizeof(packet));
    if (bytes_read == sizeof(packet)) {
        uint32_t wid = packet[0];
        int32_t level = (int32_t)packet[1];

        // SA-02: Validate inputs before passing to SkyLight
        if (wid == 0) {
            NSLog(@"[aerospace-sa] Rejected request: invalid window id 0");
            close(client_fd);
            return;
        }
        if (!is_valid_level(level)) {
            NSLog(@"[aerospace-sa] Rejected request: invalid level %d (allowed: 0-3)", level);
            close(client_fd);
            return;
        }

        NSLog(@"[aerospace-sa] Received set level: window %u -> level %d", wid, level);

        if (_SLSMainConnectionID && _SLSSetWindowSubLevel) {
            int cid = _SLSMainConnectionID();
            CGError err = _SLSSetWindowSubLevel(cid, wid, level);
            if (err != kCGErrorSuccess) {
                NSLog(@"[aerospace-sa] SLSSetWindowSubLevel failed with error %d", err);
            }
        } else {
            NSLog(@"[aerospace-sa] SkyLight functions not resolved!");
        }
    }

    close(client_fd);
}

static void *socket_server_thread(void *unused) {
    NSLog(@"[aerospace-sa] Socket server thread starting...");
    int server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd == -1) {
        NSLog(@"[aerospace-sa] Failed to create socket");
        return NULL;
    }

    // SA-01/SA-03: Use per-user temp directory instead of world-writable /tmp/
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *socketPathStr = [tmpDir stringByAppendingPathComponent:@"aerospace-sa.socket"];
    const char *socketPathCStr = [socketPathStr fileSystemRepresentation];

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;

    if (strlen(socketPathCStr) >= sizeof(addr.sun_path)) {
        NSLog(@"[aerospace-sa] Socket path too long: %s", socketPathCStr);
        close(server_fd);
        return NULL;
    }
    strncpy(addr.sun_path, socketPathCStr, sizeof(addr.sun_path) - 1);
    unlink(addr.sun_path);

    if (bind(server_fd, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
        NSLog(@"[aerospace-sa] Failed to bind socket");
        close(server_fd);
        return NULL;
    }

    // SA-01: Restrict socket to owner-only access
    chmod(addr.sun_path, 0600);

    if (listen(server_fd, 5) == -1) {
        NSLog(@"[aerospace-sa] Failed to listen on socket");
        close(server_fd);
        return NULL;
    }

    NSLog(@"[aerospace-sa] Socket server listening on %s", addr.sun_path);

    // SA-08: Handle connections serially instead of spawning unbounded threads.
    // Each operation (read 8 bytes + one SLSSetWindowSubLevel call) takes microseconds,
    // so serial handling does not introduce perceptible latency.
    while (1) {
        int client_fd = accept(server_fd, NULL, NULL);
        if (client_fd != -1) {
            handle_client(client_fd);
        }
    }

    close(server_fd);
    return NULL;
}

__attribute__((constructor))
void load_payload(void) {
    NSLog(@"[aerospace-sa] loaded payload into process %d", getpid());

    // Guard against double injection: if the socket already exists and is connectable, skip.
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *socketPathStr = [tmpDir stringByAppendingPathComponent:@"aerospace-sa.socket"];
    const char *socketPathCStr = [socketPathStr fileSystemRepresentation];
    struct stat st;
    if (stat(socketPathCStr, &st) == 0 && (st.st_mode & S_IFSOCK)) {
        int test_fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (test_fd != -1) {
            struct sockaddr_un addr;
            memset(&addr, 0, sizeof(addr));
            addr.sun_family = AF_UNIX;
            strncpy(addr.sun_path, socketPathCStr, sizeof(addr.sun_path) - 1);
            if (connect(test_fd, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
                close(test_fd);
                NSLog(@"[aerospace-sa] Payload already loaded (socket exists and is connectable). Skipping.");
                return;
            }
            close(test_fd);
        }
    }

    void *skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW);
    if (skylight) {
        _SLSMainConnectionID = (SLSMainConnectionIDFunc)dlsym(skylight, "SLSMainConnectionID");
        _SLSSetWindowSubLevel = (SLSSetWindowSubLevelFunc)dlsym(skylight, "SLSSetWindowSubLevel");
        NSLog(@"[aerospace-sa] SkyLight symbols resolved successfully.");
    } else {
        NSLog(@"[aerospace-sa] Failed to load SkyLight private framework.");
    }

    pthread_t thread;
    pthread_create(&thread, NULL, socket_server_thread, NULL);
    pthread_detach(thread);
}
