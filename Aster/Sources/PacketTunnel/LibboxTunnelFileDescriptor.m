#import <stdint.h>
#import <string.h>
#import <sys/ioctl.h>
#import <sys/socket.h>
#import <unistd.h>

// These Darwin kernel-control layouts are part of the public utun socket
// interface, but are not shipped in the iPhoneOS SDK headers. Keep the
// ABI-local definitions here instead of importing private NetworkExtension
// implementation types.
struct aster_ctl_info {
    uint32_t ctl_id;
    char ctl_name[96];
};

struct aster_sockaddr_ctl {
    uint8_t sc_len;
    uint8_t sc_family;
    uint16_t ss_sysaddr;
    uint32_t sc_id;
    uint32_t sc_unit;
    uint32_t sc_reserved[5];
};

#ifndef AF_SYSTEM
#define AF_SYSTEM 32
#endif
#ifndef AF_SYS_CONTROL
#define AF_SYS_CONTROL 2
#endif
#define ASTER_CTLIOCGINFO _IOWR('N', 3, struct aster_ctl_info)

// The bundled Libbox header declares this public bridge, but some gomobile
// builds omit the generated C symbol when the Go helper is dead-stripped.
// Keep the resolver in the extension target so the bridge remains available
// without touching NetworkExtension private implementation details.
int32_t LibboxGetTunnelFileDescriptor(void) {
    struct aster_ctl_info controlInfo;
    memset(&controlInfo, 0, sizeof(controlInfo));
    strlcpy(controlInfo.ctl_name, "com.apple.net.utun_control", sizeof(controlInfo.ctl_name));

    for (int fd = 0; fd < 1024; fd += 1) {
        struct aster_sockaddr_ctl address;
        socklen_t addressLength = sizeof(address);
        memset(&address, 0, sizeof(address));
        if (getpeername(fd, (struct sockaddr *)&address, &addressLength) != 0) {
            continue;
        }
        if (address.sc_family != AF_SYSTEM || address.ss_sysaddr != AF_SYS_CONTROL) {
            continue;
        }
        if (controlInfo.ctl_id == 0 && ioctl(fd, ASTER_CTLIOCGINFO, &controlInfo) != 0) {
            continue;
        }
        if (address.sc_id == controlInfo.ctl_id) {
            return fd;
        }
    }
    return -1;
}
