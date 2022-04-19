//
//  main.m
//  SXObjcDebug
//
//  Created by Allin on 2022/4/13.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <malloc/malloc.h>

@interface Person : NSObject

@end
@implementation Person

@end


int main(int argc, const char * argv[]) {
    @autoreleasepool {
        
        Person *per1 = [[Person alloc] init];
        
        Person *per2 = [Person new];
        
        
    }
    return 0;
}
