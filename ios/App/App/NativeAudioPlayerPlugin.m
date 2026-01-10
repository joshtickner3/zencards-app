// NativeAudioPlayerPlugin.m

#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

// Declare the Capacitor plugin and its methods
CAP_PLUGIN(NativeAudioPlayerPlugin, "NativeAudioPlayer",
    CAP_PLUGIN_METHOD(setQueue, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(enqueue, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(play, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(pause, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(skipToNext, CAPPluginReturnPromise);
)
