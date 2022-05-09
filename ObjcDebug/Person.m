//
//  LGPerson.m
//  ObjcDebug
//
//  Created by zs on 2021/9/24.
//

#import "Person.h"

@implementation Person

//static NSString *_nickName = @"";

//+ (void)setNickName:(NSString *)name {
//    _nickName = name;
//}
//
//+ (NSString *)nickName {
//    return _nickName;
//}
//
//- (instancetype)init {
//    if (self = [super init]) {
//        self.name = @"Logic";
//    }
//    return self;
//}
//
//- (void)saySomething {
//    NSLog(@"%s", __func__);
//}

- (void)instanceMethod {
    NSLog(@"%s", __func__);
}
+ (void)classMethod {
    NSLog(@"%s", __func__);
}

@end
