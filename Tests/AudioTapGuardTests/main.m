#import "AudioTapGuard.h"
#include <assert.h>
#include <stdio.h>

// Atrapa odpowiada na selektor instalacji bez tworzenia silnika i używania mikrofonu.
@interface AtrapaWezla : NSObject
@property BOOL rzuca;
@property NSUInteger wywolania;
- (void)installTapOnBus:(AVAudioNodeBus)bus bufferSize:(AVAudioFrameCount)size
                 format:(AVAudioFormat *)format block:(AVAudioNodeTapBlock)block;
@end
@implementation AtrapaWezla
- (void)installTapOnBus:(AVAudioNodeBus)bus bufferSize:(AVAudioFrameCount)size
                 format:(AVAudioFormat *)format block:(AVAudioNodeTapBlock)block {
    assert(bus == 0 && size == 4096 && format == nil && block != nil);
    self.wywolania += 1;
    if (self.rzuca) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                      reason:@"syntetyczna zmiana formatu podczas instalacji" userInfo:nil];
    }
}
@end

int main(void) {
    @autoreleasepool {
        AtrapaWezla *atrapa = [AtrapaWezla new];
        AVAudioNodeTapBlock block = ^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {};
        // Wcześniejsze sprawdzenie formatu nie zapobiega wyjątkowi w samej instalacji.
        atrapa.rzuca = YES;
        assert(!VTInstallAudioTap((AVAudioNode *)atrapa, 0, 4096, nil, block));
        assert(atrapa.wywolania == 1);
        atrapa.rzuca = NO;
        assert(VTInstallAudioTap((AVAudioNode *)atrapa, 0, 4096, nil, block));
        assert(atrapa.wywolania == 2);
        puts("PASS AudioTapGuard: NSException zwraca NO; proces kontynuuje; zwykla instalacja zwraca YES");
    }
    return 0;
}
