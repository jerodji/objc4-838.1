//
//  LGTeacher.m
//  KCObjcBuild
//
//  Created by zs on 2021/9/24.
//

#import "LGTeacher.h"

@implementation LGTeacher

- (instancetype)init {
    if (self == [super init]) {
        NSLog(@"我来了: %@", self);
        return self;
    }
    return nil;
}

- (void)teacherSay {
    NSLog(@"%s", __func__);
}

@end
