//
//  BufferStreamHandler.h
//  geolocator_apple
//
//  FlutterStreamHandler do EventChannel de contagem do buffer de
//  background tracking. Puramente UX (docs/PLANO_BACKGROUND_IOS.md §3.3):
//  a corretude do tracking não depende da engine Flutter estar viva pra
//  receber isso, é só pro app saber na hora que tem dado novo.
//

#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@interface BufferStreamHandler : NSObject <FlutterStreamHandler>

@end

NS_ASSUME_NONNULL_END
