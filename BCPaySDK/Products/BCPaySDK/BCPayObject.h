//
//  BCPayObject.h
//  BCPaySDK
//
//  Created by Ewenlong03 on 15/7/14.
//  Copyright (c) 2015年 BeeCloud. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, PayChannel) {
    None  = 0,
    WX    = 1 << 0,
    Ali   = 1 << 1,
    Union = 1 << 2
};

enum  BCErrCode {
    BCSuccess           = 0,    /**< 成功    */
    BCErrCodeCommon     = -1,   /**< 参数错误类型    */
    BCErrCodeUserCancel = -2,   /**< 用户点击取消并返回    */
    BCErrCodeSentFail   = -3,   /**< 发送失败    */
    BCErrCodeUnsupport  = -4,   /**< BeeCloud不支持 */
};

/**
 *  Result block for pay result.
 *
 *  @param strMsg Pay result, success\fail\cancel\invalid
 *  @param error  Error
 */
typedef void (^BCPayBlock)(BOOL success, NSString *strMsg, NSError *error);

#pragma mark BCBaseReq
/**
 *  BCPay 所有请求的基类
 */
@interface BCBaseReq : NSObject
/**
 *  //1:Pay;2:queryBills;3:queryRefunds;
 */
@property (nonatomic, assign) NSInteger type;

@end

#pragma mark BCBaseResp
/**
 *  BCPay所有响应的基类
 */
@interface BCBaseResp : NSObject

/** 响应码 */
@property (nonatomic, assign) int result_code;
/** 响应提示字符串 */
@property (nonatomic, retain) NSString *result_msg;
/** 错误详情 */
@property (nonatomic, retain) NSString *err_detail;

@end

#pragma mark BCPayReq
/**
 *  Pay 请求结构体
 */
@interface BCPayReq : BCBaseReq
/**
 *  支付渠道(WX,Ali,Union)
 */
@property (nonatomic, assign) PayChannel channel;
/**
 *  订单描述,32个字节内,最长16个汉字
 */
@property (nonatomic, retain) NSString *title;
/**
 *  支付金额,以分为单位,必须为整数,100表示1元
 */
@property (nonatomic, retain) NSString *totalfee;
/**
 *  商户系统内部的订单号,8~32位数字和/或字母组合,确保在商户系统中唯一
 */
@property (nonatomic, retain) NSString *billno;
/**
 *  调用支付的app注册在info.plist中的scheme,支付宝支付需要
 */
@property (nonatomic, retain) NSString *scheme;
/**
 *  调起银联支付的页面，银联支付需要
 */
@property (nonatomic, retain) UIViewController *viewController;
/**
 *  扩展参数,可以传入任意数量的key/value对来补充对业务逻辑的需求
 */
@property (nonatomic, retain) NSMutableDictionary *optional;

@end


#pragma mark BCPayResp
/**
 *  Pay 响应结构体
 */
@interface BCPayResp : BCBaseResp

@property (nonatomic, retain) NSDictionary *paySource;

@end


#pragma mark BCBillsResp
/**
 *  queryBills 响应结构体
 */
@interface BCBillsResp : BCBaseResp
/**
 *  查询到得结果数量
 */
@property (nonatomic, assign) NSInteger count;

@property (nonatomic, retain) NSArray *bills;

@end

#pragma mark BCBillsReq
/**
 *  queryBills 请求结构体
 */
@interface BCBillsReq : BCBaseReq

@property (assign) PayChannel channel;
@property (strong, nonatomic) NSString *billno;
@property (assign) long long  starttime;
@property (assign) long long endtime;
@property (assign) NSUInteger skip;
@property (assign) NSUInteger limit;

+ (BCBillsResp *)reqQuerybills;

+ (void)reqQueryBillsAsync:(BCPayBlock)block;

@end









