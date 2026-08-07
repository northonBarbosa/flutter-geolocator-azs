//
//  PermissionHandler.h
//  Pods
//
//  Created by Maurits van Beusekom on 26/06/2020.
//

#ifndef PermissionHandler_h
#define PermissionHandler_h

#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>

typedef void (^PermissionConfirmation)(CLAuthorizationStatus status);
typedef void (^PermissionError)(NSString *errorCode, NSString *errorDiscription);

@interface PermissionHandler : NSObject

- (CLAuthorizationStatus) checkPermission;
- (BOOL) hasPermission;
- (void) requestPermission:(PermissionConfirmation)confirmationHandler
              errorHandler:(PermissionError)errorHandler;

/// Implementa o fluxo obrigatório em dois passos do iOS: se a permissão
/// ainda não foi determinada, pede "When In Use" primeiro e só então pede
/// "Always" — o iOS não mostra o prompt de Always se o app nunca teve When
/// In Use. Se já for "When In Use", pula direto pro segundo passo.
- (void) requestAlwaysPermission:(PermissionConfirmation)confirmationHandler
                     errorHandler:(PermissionError)errorHandler;

@end

#endif /* PermissionHandler_h */
