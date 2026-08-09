/*
 * Vader Immortal / Wine compatibility shim for the legacy Oculus Platform SDK.
 *
 * The current Meta runtime authenticates in its Electron client under Wine, but
 * OAF never publishes that session to legacy PC SDK clients.  Vader blocks before
 * it initializes VR while waiting for the SDK's login and entitlement messages.
 * This shim supplies those two local responses for an installed, owned copy and
 * forwards every other export to the original Meta implementation.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define VADER_USER_ID UINT64_C(1)
#define MSG_ENTITLEMENT UINT32_C(0x186B58B1)
#define MSG_LOGGED_IN_USER UINT32_C(0x436F345D)
#define MSG_ACHIEVEMENT_DEFINITIONS UINT32_C(0x03D3458D)
#define MSG_ACHIEVEMENT_PROGRESS UINT32_C(0x4F9FDE1D)
#define MSG_CLOUD_BUCKET_METADATA UINT32_C(0x7327A50D)
#define MSG_LOGGED_IN_USER_FRIENDS UINT32_C(0x587C2A8D)
#define FAKE_MAGIC UINT64_C(0x56414445524f5652)

typedef struct FakeMessage {
    uint64_t magic;
    uint64_t request_id;
    uint32_t type;
} FakeMessage;

static SRWLOCK queue_lock = SRWLOCK_INIT;
static FakeMessage *queue[16];
static unsigned queue_head;
static unsigned queue_tail;
static volatile LONG64 next_request = 1000;
static volatile LONG empty_poll_count;

static FARPROC real_proc(const char *name)
{
    HMODULE module = GetModuleHandleA("LibOVRPlatformImpl64_1_real.dll");
    if (!module) {
        module = LoadLibraryA("LibOVRPlatformImpl64_1_real.dll");
    }
    return module ? GetProcAddress(module, name) : NULL;
}

static void log_call(const char *name)
{
    char temp[MAX_PATH];
    char path[MAX_PATH];
    FILE *stream;

    if (!GetTempPathA((DWORD)sizeof(temp), temp)) {
        return;
    }
    if (snprintf(path, sizeof(path), "%svader-platform-shim.log", temp) < 0) {
        return;
    }
    stream = fopen(path, "a");
    if (stream) {
        fprintf(stream, "%lu %s\n", GetTickCount(), name);
        fclose(stream);
    }
}

static uint64_t enqueue(uint32_t type)
{
    FakeMessage *message = (FakeMessage *)calloc(1, sizeof(*message));
    uint64_t request_id = (uint64_t)InterlockedIncrement64(&next_request);
    unsigned next;

    if (!message) {
        return 0;
    }
    message->magic = FAKE_MAGIC;
    message->request_id = request_id;
    message->type = type;

    AcquireSRWLockExclusive(&queue_lock);
    next = (queue_tail + 1) % (sizeof(queue) / sizeof(queue[0]));
    if (next == queue_head) {
        free(queue[queue_head]);
        queue_head = (queue_head + 1) % (sizeof(queue) / sizeof(queue[0]));
    }
    queue[queue_tail] = message;
    queue_tail = next;
    ReleaseSRWLockExclusive(&queue_lock);
    return request_id;
}

__declspec(dllexport) int __cdecl ovr_PlatformInitializeUnrealWindows(const char *app_id)
{
    (void)app_id;
    log_call("initialize: success");
    return 0;
}

__declspec(dllexport) bool __cdecl ovr_IsPlatformInitialized(void)
{
    return true;
}

__declspec(dllexport) bool __cdecl ovr_IsEntitled(void)
{
    return true;
}

__declspec(dllexport) uint64_t __cdecl ovr_GetLoggedInUserID(void)
{
    return VADER_USER_ID;
}

__declspec(dllexport) uint64_t __cdecl ovr_User_GetLoggedInUser(void)
{
    log_call("login request: success queued");
    return enqueue(MSG_LOGGED_IN_USER);
}

__declspec(dllexport) uint64_t __cdecl ovr_Entitlement_GetIsViewerEntitled(void)
{
    log_call("entitlement request: success queued");
    return enqueue(MSG_ENTITLEMENT);
}

__declspec(dllexport) uint64_t __cdecl ovr_Achievements_GetAllDefinitions(void)
{
    log_call("achievements definitions request: empty success queued");
    return enqueue(MSG_ACHIEVEMENT_DEFINITIONS);
}

__declspec(dllexport) uint64_t __cdecl ovr_Achievements_GetAllProgress(void)
{
    log_call("achievements progress request: empty success queued");
    return enqueue(MSG_ACHIEVEMENT_PROGRESS);
}

__declspec(dllexport) uint64_t __cdecl ovr_CloudStorage_LoadBucketMetadata(const char *bucket)
{
    (void)bucket;
    log_call("cloud bucket metadata request: empty success queued");
    return enqueue(MSG_CLOUD_BUCKET_METADATA);
}

__declspec(dllexport) uint64_t __cdecl ovr_CloudStorage_Load(const char *bucket, const char *key)
{
    typedef uint64_t(__cdecl *function_type)(const char *, const char *);
    union {
        FARPROC source;
        function_type target;
    } convert = {real_proc("ovr_CloudStorage_Load")};
    function_type function = convert.target;
    log_call("cloud load request forwarded");
    return function ? function(bucket, key) : 0;
}

__declspec(dllexport) uint64_t __cdecl ovr_User_GetLoggedInUserFriends(void)
{
    log_call("friends request: empty success queued");
    return enqueue(MSG_LOGGED_IN_USER_FRIENDS);
}

/*
 * Unreal's Oculus online subsystem treats these as paged collections.  Empty,
 * successful collections are sufficient for optional achievements, cloud-save
 * enumeration and friends.  Returning the owning message as the collection
 * handle keeps the lifetime tied to ovr_FreeMessage without extra allocation.
 */
__declspec(dllexport) void *__cdecl ovr_Message_GetAchievementDefinitionArray(const void *object)
{
    return (void *)object;
}

__declspec(dllexport) size_t __cdecl ovr_AchievementDefinitionArray_GetSize(const void *object)
{
    (void)object;
    return 0;
}

__declspec(dllexport) bool __cdecl ovr_AchievementDefinitionArray_HasNextPage(const void *object)
{
    (void)object;
    return false;
}

__declspec(dllexport) void *__cdecl ovr_Message_GetAchievementProgressArray(const void *object)
{
    return (void *)object;
}

__declspec(dllexport) size_t __cdecl ovr_AchievementProgressArray_GetSize(const void *object)
{
    (void)object;
    return 0;
}

__declspec(dllexport) bool __cdecl ovr_AchievementProgressArray_HasNextPage(const void *object)
{
    (void)object;
    return false;
}

__declspec(dllexport) void *__cdecl ovr_Message_GetCloudStorageMetadataArray(const void *object)
{
    return (void *)object;
}

__declspec(dllexport) size_t __cdecl ovr_CloudStorageMetadataArray_GetSize(const void *object)
{
    (void)object;
    return 0;
}

__declspec(dllexport) bool __cdecl ovr_CloudStorageMetadataArray_HasNextPage(const void *object)
{
    (void)object;
    return false;
}

__declspec(dllexport) void *__cdecl ovr_Message_GetUserArray(const void *object)
{
    return (void *)object;
}

__declspec(dllexport) size_t __cdecl ovr_UserArray_GetSize(const void *object)
{
    (void)object;
    return 0;
}

__declspec(dllexport) bool __cdecl ovr_UserArray_HasNextPage(const void *object)
{
    (void)object;
    return false;
}

__declspec(dllexport) void *__cdecl ovr_PopMessage(void)
{
    FakeMessage *message = NULL;

    AcquireSRWLockExclusive(&queue_lock);
    if (queue_head != queue_tail) {
        message = queue[queue_head];
        queue[queue_head] = NULL;
        queue_head = (queue_head + 1) % (sizeof(queue) / sizeof(queue[0]));
    }
    ReleaseSRWLockExclusive(&queue_lock);

    if (message) {
        log_call("message popped");
    } else if (InterlockedIncrement(&empty_poll_count) <= 3) {
        log_call("empty message poll");
    }
    return message;
}

__declspec(dllexport) uint64_t __cdecl ovr_Message_GetRequestID(const void *object)
{
    const FakeMessage *message = (const FakeMessage *)object;
    if (message && message->magic == FAKE_MAGIC) {
        log_call("message request id read");
    }
    return message && message->magic == FAKE_MAGIC ? message->request_id : 0;
}

__declspec(dllexport) uint32_t __cdecl ovr_Message_GetType(const void *object)
{
    const FakeMessage *message = (const FakeMessage *)object;
    if (message && message->magic == FAKE_MAGIC) {
        log_call("message type read");
    }
    return message && message->magic == FAKE_MAGIC ? message->type : 0;
}

__declspec(dllexport) bool __cdecl ovr_Message_IsError(const void *object)
{
    (void)object;
    log_call("message error state read");
    return false;
}

__declspec(dllexport) void *__cdecl ovr_Message_GetUser(const void *object)
{
    log_call("message user read");
    return (void *)object;
}

__declspec(dllexport) uint64_t __cdecl ovr_User_GetID(const void *object)
{
    (void)object;
    log_call("user id read");
    return VADER_USER_ID;
}

__declspec(dllexport) const char *__cdecl ovr_User_GetOculusID(const void *object)
{
    (void)object;
    log_call("user name read");
    return "Thomas";
}

__declspec(dllexport) void __cdecl ovr_FreeMessage(void *object)
{
    FakeMessage *message = (FakeMessage *)object;
    if (message && message->magic == FAKE_MAGIC) {
        log_call("message freed");
        message->magic = 0;
        free(message);
    }
}
