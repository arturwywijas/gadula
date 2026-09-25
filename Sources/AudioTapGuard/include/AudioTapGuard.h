#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN
// NO oznacza wyjątek podczas instalacji. Nie ujawniamy reason ani userInfo.
BOOL VTInstallAudioTap(AVAudioNode *node, AVAudioNodeBus bus,
                       AVAudioFrameCount bufferSize, AVAudioFormat * _Nullable format,
                       AVAudioNodeTapBlock block);
NS_ASSUME_NONNULL_END
