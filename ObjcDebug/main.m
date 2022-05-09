//
//  main.m
//  ObjcDebug
//
//  Created by Zions Jen.
//
/**
 重磅提示 调试工程很重要 源码直观就是爽
 ⚠️编译调试不能过: 请你检查以下几小点⚠️
 ①: enable hardened runtime -> NO
 ②: build phase -> denpendenice -> objc
 ③: team 选择 None
 iOS进阶内容重磅分享 认准：逻辑教育
 */

// void _objc_autoreleasePoolPrint(void);
#import <Foundation/Foundation.h>
#import "Person.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
//        NSLog(@"Hello, World!");
        //0x007ffffffffffff8ULL   0x00007ffffffffff8ULL
        // class_data_bits_t
        Person *p = [Person alloc];
        NSLog(@"%@", p);
//        NSLog(@"%@-%@", p.nickName_nc, p.nickName_ac);
//        [p release]; /* 如果报错允许ARC使用方法,在setting中设置
//          ObjcDebug -> Build Settings -> Objective-C Automatic Reference Counting : NO
//          */
        
//        Class pClass = [Person class];
//        Person.nickName = @"Logic";
//        NSLog(@"%@", pClass);
        
        
        
        
        
        
        
    }
    return 0;
}
