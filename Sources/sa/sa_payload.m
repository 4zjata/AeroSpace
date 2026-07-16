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

static void *handle_client(void *client_fd_ptr) {
    int client_fd = *(int *)client_fd_ptr;
    free(client_fd_ptr);
    
    uint32_t packet[2];
    if (read(client_fd, packet, sizeof(packet)) == sizeof(packet)) {
        uint32_t wid = packet[0];
        int32_t level = packet[1];
        
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
    return NULL;
}

static void *socket_server_thread(void *unused) {
    NSLog(@"[aerospace-sa] Socket server thread starting...");
    int server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd == -1) {
        NSLog(@"[aerospace-sa] Failed to create socket");
        return NULL;
    }
    
    struct sockaddr_un addr;
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, "/tmp/aerospace-sa.socket", sizeof(addr.sun_path) - 1);
    unlink(addr.sun_path);
    
    if (bind(server_fd, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
        NSLog(@"[aerospace-sa] Failed to bind socket");
        close(server_fd);
        return NULL;
    }
    
    chmod(addr.sun_path, 0666);
    
    if (listen(server_fd, 5) == -1) {
        NSLog(@"[aerospace-sa] Failed to listen on socket");
        close(server_fd);
        return NULL;
    }
    
    NSLog(@"[aerospace-sa] Socket server listening on %s", addr.sun_path);
    
    while (1) {
        int client_fd = accept(server_fd, NULL, NULL);
        if (client_fd != -1) {
            int *ptr = malloc(sizeof(int));
            if (ptr) {
                *ptr = client_fd;
                pthread_t thread;
                pthread_create(&thread, NULL, handle_client, ptr);
                pthread_detach(thread);
            } else {
                close(client_fd);
            }
        }
    }
    
    close(server_fd);
    return NULL;
}

__attribute__((constructor))
void load_payload(void) {
    NSLog(@"[aerospace-sa] loaded payload into process %d", getpid());
    
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
