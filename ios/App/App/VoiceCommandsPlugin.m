#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

// Must match your @objc(...) name from VoiceCommands.swift
CAP_PLUGIN(VoiceCommands, "VoiceCommands",
  CAP_PLUGIN_METHOD(start, CAPPluginReturnPromise);
  CAP_PLUGIN_METHOD(stop, CAPPluginReturnPromise);
)
