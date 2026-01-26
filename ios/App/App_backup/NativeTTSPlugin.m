#import <Capacitor/Capacitor.h>

CAP_PLUGIN(NativeTTS, "NativeTTS",
  CAP_PLUGIN_METHOD(speak, CAPPluginReturnPromise);
  CAP_PLUGIN_METHOD(stop, CAPPluginReturnPromise);
)
