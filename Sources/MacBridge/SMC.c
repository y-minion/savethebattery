#include "MacBridge.h"
#include <IOKit/IOKitLib.h>
#include <string.h>
// The AppleSMC user-client layout used by every public SMC tool. Only 1-byte
// unsigned keys are handled, and each call checks the key's type and size first.
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } VBSMCVersion;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, mem; } VBSMCLimit;
typedef struct { uint32_t size, type; uint8_t attributes; } VBSMCKeyInfo;
typedef struct {
    uint32_t key; VBSMCVersion vers; VBSMCLimit limit; VBSMCKeyInfo info;
    uint8_t result, status, command; uint32_t data32; uint8_t bytes[32];
} VBSMCData;
_Static_assert(sizeof(VBSMCData)==80,"AppleSMC struct layout");
enum { kVBSMCSelector=2, kVBSMCRead=5, kVBSMCWrite=6, kVBSMCKeyInfo=9 };
static uint32_t fourcc(const char *s) { return (uint32_t)s[0]<<24|(uint32_t)s[1]<<16|(uint32_t)s[2]<<8|(uint32_t)s[3]; }
static int smc_call(io_connect_t c,VBSMCData *in,VBSMCData *out) {
    size_t size=sizeof(*out);memset(out,0,sizeof(*out));
    kern_return_t r=IOConnectCallStructMethod(c,kVBSMCSelector,in,sizeof(*in),out,&size);
    return r==KERN_SUCCESS && out->result==0 ? 0:-3;
}
// Opens AppleSMC and confirms the key is a 1-byte "ui8 ". 0 ok, -1 open failed, -2 wrong type/size, -3 SMC call failed.
static int smc_open_u8(const char *key,io_connect_t *c) {
    if (!key || strlen(key)!=4) return -2;
    io_service_t s=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMC"));
    if (!s) return -1;
    kern_return_t r=IOServiceOpen(s,mach_task_self(),0,c);IOObjectRelease(s);
    if (r!=KERN_SUCCESS) return -1;
    VBSMCData in={0},out;in.key=fourcc(key);in.command=kVBSMCKeyInfo;
    int e=smc_call(*c,&in,&out);
    if (e==0 && (out.info.type!=fourcc("ui8 ") || out.info.size!=1)) e=-2;
    if (e) IOServiceClose(*c);
    return e;
}
int vb_smc_read_u8(const char *key,uint8_t *out) {
    io_connect_t c;int e=smc_open_u8(key,&c);if (e) return e;
    VBSMCData in={0},o;in.key=fourcc(key);in.info.size=1;in.command=kVBSMCRead;
    e=smc_call(c,&in,&o);if (e==0) *out=o.bytes[0];
    IOServiceClose(c);return e;
}
int vb_smc_write_u8(const char *key,uint8_t value) {
    io_connect_t c;int e=smc_open_u8(key,&c);if (e) return e;
    VBSMCData in={0},o;in.key=fourcc(key);in.info.size=1;in.command=kVBSMCWrite;in.bytes[0]=value;
    e=smc_call(c,&in,&o);
    IOServiceClose(c);return e;
}
