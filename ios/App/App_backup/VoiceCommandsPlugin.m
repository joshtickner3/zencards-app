#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

CAP_PLUGIN(VoiceCommands, "VoiceCommands",
  CAP_PLUGIN_METHOD(start, CAPPluginReturnPromise);
  CAP_PLUGIN_METHOD(stop, CAPPluginReturnPromise);
  CAP_PLUGIN_METHOD(isAvailable, CAPPluginReturnPromise);
);
