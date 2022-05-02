//
//  LGPerson.m
//  ObjcDebug
//
//  Created by zs on 2021/9/24.
//

#import "LGPerson.h"

@implementation LGPerson

static NSString *_nickName = @"";

+ (void)setNickName:(NSString *)name {
    _nickName = name;
}

+ (NSString *)nickName {
    return _nickName;
}

- (instancetype)init {
    if (self = [super init]) {
        self.name = @"Logic";
    }
    return self;
}

- (void)saySomething {
    NSLog(@"%s", __func__);
}

@end
