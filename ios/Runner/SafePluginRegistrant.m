#import "SafePluginRegistrant.h"

#import <objc/runtime.h>

@implementation SafePluginRegistrant

+ (void)_registerPlugin:(NSString *)pluginClassName
             withRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  if (pluginClassName.length == 0) return;

  NSObject<FlutterPluginRegistrar>* registrar = [registry registrarForPlugin:pluginClassName];
  if (registrar == nil) {
    NSLog(@"[SafePluginRegistrant] registrarForPlugin returned nil for %@", pluginClassName);
    return;
  }

  Class cls = NSClassFromString(pluginClassName);
  if (cls == nil) {
    NSLog(@"[SafePluginRegistrant] plugin class not found: %@", pluginClassName);
    return;
  }

  SEL sel = NSSelectorFromString(@"registerWithRegistrar:");
  if (![cls respondsToSelector:sel]) {
    NSLog(@"[SafePluginRegistrant] %@ does not respond to registerWithRegistrar:", pluginClassName);
    return;
  }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  [cls performSelector:sel withObject:registrar];
#pragma clang diagnostic pop
}

+ (void)registerWith:(NSObject<FlutterPluginRegistry>*)registry {
  // Keep this list small and explicit. Add plugins here if you see a startup crash
  // in plugin registration on certain iOS versions/devices.
  NSArray<NSString *> *plugins = @[
    @"AppLinksIosPlugin",
    @"OneSignalPlugin",
    @"PathProviderPlugin",
    @"SharedPreferencesPlugin",
    @"URLLauncherPlugin",
  ];

  for (NSString *plugin in plugins) {
    [self _registerPlugin:plugin withRegistry:registry];
  }
}

@end

