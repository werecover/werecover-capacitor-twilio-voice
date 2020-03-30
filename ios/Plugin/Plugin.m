#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

// Define the plugin using the CAP_PLUGIN Macro, and
// each method the plugin supports using the CAP_PLUGIN_METHOD macro.
CAP_PLUGIN(TwilioVoicePlugin, "TwilioVoicePlugin",
           CAP_PLUGIN_METHOD(initPlugin, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(call, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(endCall, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(toggleMute, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(toggleSpeaker, CAPPluginReturnPromise);
)
