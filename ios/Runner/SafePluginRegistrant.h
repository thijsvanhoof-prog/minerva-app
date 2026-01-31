#import <Flutter/Flutter.h>
#import <Foundation/Foundation.h>

@interface SafePluginRegistrant : NSObject

+ (void)registerWith:(NSObject<FlutterPluginRegistry>*)registry;

@end

