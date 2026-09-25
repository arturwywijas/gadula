#import "AudioTapGuard.h"

BOOL VTInstallAudioTap(AVAudioNode *node, AVAudioNodeBus bus,
                       AVAudioFrameCount bufferSize, AVAudioFormat *format,
                       AVAudioNodeTapBlock block) {
    @try {
        [node installTapOnBus:bus bufferSize:bufferSize format:format block:block];
        return YES;
    } @catch (NSException *exception) {
        // Wyścig ze zmianą trasy HAL może wystąpić po sprawdzeniu formatu w Swift.
        // Zwracamy kontrolowany wynik zamiast przepuszczać NSException przez Swift.
        return NO;
    }
}
