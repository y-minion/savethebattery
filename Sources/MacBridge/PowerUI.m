#import <Foundation/Foundation.h>
#include "MacBridge.h"
// Private client behind System Settings' Charge Limit. Selectors were confirmed on
// macOS 27.0.1 (26A434); each call re-checks that the selector still exists.
@protocol VBSmartChargeClient
- (instancetype)initWithClientName:(NSString *)name;
- (BOOL)isMCLSupported;
- (unsigned long long)isMCLCurrentlyEnabled:(NSError **)error;
- (unsigned char)getMCLLimitWithError:(NSError **)error;
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)error;
- (BOOL)temporarilyDisableMCL:(NSError **)error;
- (BOOL)enableMCL:(NSError **)error;
- (BOOL)disableMCL:(NSError **)error;
@end
static id<VBSmartChargeClient> vb_client(SEL selector) {
    static id<VBSmartChargeClient> client=nil; static dispatch_once_t once;
    dispatch_once(&once,^{
        if (![[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/PowerUI.framework"] load]) return;
        Class type=NSClassFromString(@"PowerUISmartChargeClient");
        if (type && [type instancesRespondToSelector:@selector(initWithClientName:)])
            client=[(id<VBSmartChargeClient>)[type alloc] initWithClientName:@"io.github.y-minion.vibebattery"];
    });
    return [(id)client respondsToSelector:selector] ? client : nil;
}
int vb_mcl_read(VBChargeLimit *out) {
    out->supported=out->enabled=out->limit=-1;
    id<VBSmartChargeClient> c=vb_client(@selector(isMCLSupported));
    if (!c) return -1;
    out->supported=[c isMCLSupported]?1:0;
    if (!out->supported) return 0;
    NSError *e=nil;
    if ([(id)c respondsToSelector:@selector(isMCLCurrentlyEnabled:)]) { unsigned long long v=[c isMCLCurrentlyEnabled:&e]; if (!e) out->enabled=v?1:0; }
    e=nil;
    if ([(id)c respondsToSelector:@selector(getMCLLimitWithError:)]) { unsigned char v=[c getMCLLimitWithError:&e]; if (!e && v>0 && v<=100) out->limit=v; }
    return 0;
}
int vb_mcl_set_limit(int32_t percent) {
    // PowerUI crashes below 80; lower limits go through the root helper.
    if (percent<80 || percent>100) return -3;
    id<VBSmartChargeClient> c=vb_client(@selector(setMCLLimit:error:));
    if (!c) return -1;
    NSError *e=nil; return [c setMCLLimit:(unsigned char)percent error:&e] && !e ? 0 : -2;
}
int vb_mcl_top_up(void) {
    id<VBSmartChargeClient> c=vb_client(@selector(temporarilyDisableMCL:)); if (!c) return -1;
    NSError *e=nil; return [c temporarilyDisableMCL:&e] && !e ? 0 : -2;
}
int vb_mcl_enable(void) {
    id<VBSmartChargeClient> c=vb_client(@selector(enableMCL:)); if (!c) return -1;
    NSError *e=nil; return [c enableMCL:&e] && !e ? 0 : -2;
}
int vb_mcl_disable(void) {
    id<VBSmartChargeClient> c=vb_client(@selector(disableMCL:)); if (!c) return -1;
    NSError *e=nil; return [c disableMCL:&e] && !e ? 0 : -2;
}
