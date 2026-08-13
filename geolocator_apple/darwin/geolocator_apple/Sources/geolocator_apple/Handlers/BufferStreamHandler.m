//
//  BufferStreamHandler.m
//  geolocator_apple
//

#import "../include/geolocator_apple/Handlers/BufferStreamHandler.h"
#import "../include/geolocator_apple/Handlers/BackgroundTrackingHandler.h"

@implementation BufferStreamHandler {
  FlutterEventSink _eventSink;
}

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments
                                        eventSink:(FlutterEventSink)events {
  _eventSink = events;
  [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(bufferDidGrow:)
                                                name:GeolocatorBufferDidGrowNotification
                                              object:nil];
  return nil;
}

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  _eventSink = nil;
  return nil;
}

- (void)bufferDidGrow:(NSNotification *)notification {
  if (_eventSink == nil) {
    return;
  }
  NSNumber *count = notification.userInfo[kBufferCountUserInfoKey];
  _eventSink(count ?: @0);
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
