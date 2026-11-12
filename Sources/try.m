#import <Foundation/Foundation.h>

BOOL LogoCatch(void (^block)(void)) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}
