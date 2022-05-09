//
//  LGPerson.h
//  ObjcDebug
//
//  Created by zs on 2021/9/24.
//

#import <Foundation/Foundation.h>

@protocol TestProtocol <NSObject>



@end


NS_ASSUME_NONNULL_BEGIN

@interface Person : NSObject<TestProtocol>

//@property (nonatomic, strong, class) NSString *nickName;
//
@property (nonatomic, copy) NSString *name;
@property (nonatomic) int age;
//@property (nonatomic, strong) NSString *hobby;
//
//
//@property (nonatomic, copy) NSString *nickName_nc;  // objc_setProperty
//@property (nonatomic)       NSString *nickName_n;
//@property (atomic, copy)    NSString *nickName_ac;  // objc_setProperty / objc_getProperty
//@property (atomic)          NSString *nickName_a;
//
//
//- (void)saySomething;


- (void)instanceMethod;
+ (void)classMethod;

@end

NS_ASSUME_NONNULL_END
