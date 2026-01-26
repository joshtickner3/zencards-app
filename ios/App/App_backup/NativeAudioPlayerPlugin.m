#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

CAP_PLUGIN(NativeAudioPlayer, "NativeAudioPlayer",
  CAP_PLUGIN_METHOD(setQueue, CAPPluginReturnPromise);
  CAP_PLUGIN_METHOD(enqueue, CAPPluginReturnPromise);
  CAP_PLUGIN_METHOD(play, CAPPluginReturnPromise);
  CAP_PLUGIN_METHOD(pause, CAPPluginReturnPromise);
  CAP_PLUGIN_METHOD(skipToNext, CAPPluginReturnPromise);
);
