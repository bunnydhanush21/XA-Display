/* Original MIT helper. Local IPC only. The only power-source write is IsCharging. */
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <grp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

static const char *kSocketPath = "/var/run/xadisplay-battery.sock";
static const char *kTokenPath = "/var/mobile/Library/XADisplay/battery-care.token";
static const char *kKillPath = "/var/mobile/Library/XADisplay/battery-care.disabled";
static volatile sig_atomic_t gStop = 0;
static int gPaused = 0;
static time_t gLastCommand = 0;

static void on_signal(int signal_number) {
    (void)signal_number;
    gStop = 1;
}

static int tokens_match(const char *given, const char *expected) {
    size_t given_length = strlen(given);
    size_t expected_length = strlen(expected);
    unsigned difference = (unsigned)(given_length ^ expected_length);
    size_t limit = given_length > expected_length ? given_length : expected_length;
    for (size_t index = 0; index < limit; index++) {
        unsigned char left = index < given_length ? (unsigned char)given[index] : 0;
        unsigned char right = index < expected_length ? (unsigned char)expected[index] : 0;
        difference |= (unsigned)(left ^ right);
    }
    return difference == 0 && expected_length > 0;
}

static int read_token(char *buffer, size_t capacity) {
    FILE *file = fopen(kTokenPath, "r");
    if (!file) return 0;
    if (!fgets(buffer, (int)capacity, file)) {
        fclose(file);
        return 0;
    }
    fclose(file);
    size_t length = strlen(buffer);
    while (length > 0 && (buffer[length - 1] == '\n' || buffer[length - 1] == '\r')) {
        buffer[--length] = 0;
    }
    return length > 0;
}

static io_service_t battery_service(void) {
    const char *names[] = {"AppleARMPMUCharger", "IOPMPowerSource", "AppleSmartBattery"};
    for (size_t index = 0; index < 3; index++) {
        CFMutableDictionaryRef matching = IOServiceMatching(names[index]);
        if (!matching) continue;
        io_service_t service = IOServiceGetMatchingService(0, matching);
        if (service) return service;
    }
    return 0;
}

static int write_is_charging(int on) {
    if (!on && access(kKillPath, F_OK) == 0) on = 1;
    io_service_t service = battery_service();
    if (!service) return 0;
    int value = on ? 1 : 0;
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &value);
    CFMutableDictionaryRef properties = CFDictionaryCreateMutable(kCFAllocatorDefault, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(properties, CFSTR("IsCharging"), number);
    kern_return_t result = IORegistryEntrySetCFProperties(service, properties);
    CFRelease(number);
    CFRelease(properties);
    IOObjectRelease(service);
    if (result == KERN_SUCCESS) gPaused = on ? 0 : 1;
    return result == KERN_SUCCESS;
}

static int apply_command(const char *command) {
    if (strcmp(command, "status") == 0) return 1;
    if (strcmp(command, "charge-on") == 0 || strcmp(command, "restore") == 0) return write_is_charging(1);
    if (strcmp(command, "charge-off") == 0) return write_is_charging(0);
    return 0;
}

static void handle_client(int client) {
    char buffer[256];
    memset(buffer, 0, sizeof(buffer));
    ssize_t count = read(client, buffer, sizeof(buffer) - 1);
    if (count <= 0) return;
    char expected[128];
    if (!read_token(expected, sizeof(expected))) {
        (void)write(client, "err\n", 4);
        return;
    }
    char *newline = strchr(buffer, '\n');
    if (!newline) return;
    *newline = 0;
    char *command = newline + 1;
    char *command_end = strchr(command, '\n');
    if (command_end) *command_end = 0;
    if (!tokens_match(buffer, expected)) {
        (void)write(client, "err\n", 4);
        return;
    }
    gLastCommand = time(NULL);
    if (!apply_command(command)) {
        (void)write(client, "err\n", 4);
        return;
    }
    char response[64];
    snprintf(response, sizeof(response), "ok paused=%d kill=%d\n", gPaused, access(kKillPath, F_OK) == 0);
    (void)write(client, response, strlen(response));
}

static int listen_socket(void) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    unlink(kSocketPath);
    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    strncpy(address.sun_path, kSocketPath, sizeof(address.sun_path) - 1);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0) return -1;
    struct group *group = getgrnam("mobile");
    if (group) (void)chown(kSocketPath, 0, group->gr_gid);
    (void)chmod(kSocketPath, 0660);
    if (listen(fd, 2) != 0) return -1;
    return fd;
}

int main(void) {
    signal(SIGTERM, on_signal);
    signal(SIGINT, on_signal);
    int server = listen_socket();
    if (server < 0) return 1;
    gLastCommand = time(NULL);
    while (!gStop) {
        fd_set reads;
        FD_ZERO(&reads);
        FD_SET(server, &reads);
        struct timeval timeout = {1, 0};
        int ready = select(server + 1, &reads, NULL, NULL, &timeout);
        if (gPaused && time(NULL) - gLastCommand > 45) write_is_charging(1);
        if (ready > 0 && FD_ISSET(server, &reads)) {
            int client = accept(server, NULL, NULL);
            if (client >= 0) {
                handle_client(client);
                close(client);
            }
        }
    }
    write_is_charging(1);
    close(server);
    unlink(kSocketPath);
    return 0;
}
