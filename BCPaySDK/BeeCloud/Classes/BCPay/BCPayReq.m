//
//  BCPayReq.m
//  BCPaySDK
//
//  Created by Ewenlong03 on 15/7/27.
//  Copyright (c) 2015年 BeeCloud. All rights reserved.
//

#import "BCPayReq.h"
#import "BCPayUtil.h"
#import "BeeCloudAdapter.h"
#import "PaySandboxViewController.h"

#pragma mark pay request

@implementation BCPayReq

- (instancetype)init {
    self = [super init];
    if (self) {
        self.type = BCObjsTypePayReq;
        self.billTimeOut = 0;
    }
    return self;
}

- (void)payReq {
    [BCPayCache sharedInstance].bcResp = [[BCPayResp alloc] initWithReq:self];
    
    if (![self checkParametersForReqPay]) return;
    
    NSString *cType = [BCPayUtil getChannelString:self.channel];
    
    NSMutableDictionary *parameters = [BCPayUtil prepareParametersForRequest];
    if (parameters == nil) {
        [BCPayUtil doErrorResponse:@"请检查是否全局初始化"];
        return;
    }
    
    parameters[@"channel"] = cType;
    parameters[@"total_fee"] = [NSNumber numberWithInteger:[self.totalFee integerValue]];
    parameters[@"bill_no"] = self.billNo;
    parameters[@"title"] = self.title;
    
    if (self.billTimeOut > 0) {
        parameters[@"bill_timeout"] = @(self.billTimeOut);
    }
    
    if (self.optional) {
        parameters[@"optional"] = self.optional;
    }
    
    if ([BeeCloud getSandboxMode]) {
        [self payInSandbox:parameters];
    } else {
        [self payInLiveMode:parameters];
    }
}

- (void)payInLiveMode:(NSMutableDictionary *)parameters {
    
    AFHTTPRequestOperationManager *manager = [BCPayUtil getAFHTTPRequestOperationManager];
    __weak BCPayReq *weakSelf = self;
    
    [manager POST:[BCPayUtil getBestHostWithFormat:kRestApiPay] parameters:parameters
          success:^(AFHTTPRequestOperation *operation, id response) {
              if ([response integerValueForKey:kKeyResponseResultCode defaultValue:BCErrCodeCommon] != 0) {
                  [BCPayUtil getErrorInResponse:(NSDictionary *)response];
              } else {
                  [weakSelf doPayAction:(NSDictionary *)response];
              }
          } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
              [BCPayUtil doErrorResponse:kNetWorkError];
          }];
}

#pragma mark - Pay Action

- (BOOL)doPayAction:(NSDictionary *)response {
    BOOL bSendPay = NO;
    if (response) {
        NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithDictionary:
                                    (NSDictionary *)response];
        if (self.channel == PayChannelAliApp) {
            [dic setObject:self.scheme forKey:@"scheme"];
        } else if (self.channel == PayChannelUnApp) {
            [dic setObject:self.viewController forKey:@"viewController"];
        }
        [BCPayCache sharedInstance].bcResp.bcId = [dic objectForKey:@"id"];
        switch (self.channel) {
            case PayChannelWxApp:
                bSendPay = [BeeCloudAdapter beeCloudWXPay:dic];
                break;
            case PayChannelAliApp:
                bSendPay = [BeeCloudAdapter beeCloudAliPay:dic];
                break;
            case PayChannelUnApp:
                bSendPay = [BeeCloudAdapter beeCloudUnionPay:dic];
                break;
            case PayChannelBaiduApp:
                bSendPay = [BeeCloudAdapter beeCloudBaiduPay:dic].isValid;
                break;
            default:
                break;
        }
    }
    return bSendPay;
}

- (void)payInSandbox:(NSMutableDictionary *)parameters {
    
    AFHTTPRequestOperationManager *manager = [BCPayUtil getAFHTTPRequestOperationManager];
    __weak BCPayReq *weakSelf = self;
    
    [manager POST:[BCPayUtil getBestHostWithFormat:kRestApiSandboxBill] parameters:parameters
          success:^(AFHTTPRequestOperation *operation, id response) {
              if ([response integerValueForKey:kKeyResponseResultCode defaultValue:BCErrCodeCommon] != 0) {
                  [BCPayUtil getErrorInResponse:(NSDictionary *)response];
              } else {
                  [weakSelf doPayActionInSandbox:(NSDictionary *)response];
              }
          } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
              [BCPayUtil doErrorResponse:kNetWorkError];
          }];
}

- (BOOL)doPayActionInSandbox:(NSDictionary *)response {
    
    if (response) {
        NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithDictionary:
                                    (NSDictionary *)response];
        [BCPayCache sharedInstance].bcResp.bcId = [dic objectForKey:@"id"];
        [BeeCloudAdapter beecloudSandboxPay];
    }
    
    return YES;
}

- (BOOL)checkParametersForReqPay {
    if (!self.title.isValid || [BCPayUtil getBytes:self.title] > 32) {
        [BCPayUtil doErrorResponse:@"title 必须是长度不大于32个字节,最长16个汉字的字符串的合法字符串"];
        return NO;
    } else if (!self.totalFee.isValid || !self.totalFee.isPureInt) {
        [BCPayUtil doErrorResponse:@"totalfee 以分为单位，必须是只包含数值的字符串"];
        return NO;
    } else if (!self.billNo.isValid || !self.billNo.isValidTraceNo || (self.billNo.length < 8) || (self.billNo.length > 32)) {
        [BCPayUtil doErrorResponse:@"billno 必须是长度8~32位字母和/或数字组合成的字符串"];
        return NO;
    } else if ((self.channel == PayChannelAliApp) && !self.scheme.isValid) {
        [BCPayUtil doErrorResponse:@"scheme 不是合法的字符串，将导致无法从支付宝钱包返回应用"];
        return NO;
    } else if ((self.channel == PayChannelUnApp || [BeeCloud getSandboxMode]) && (self.viewController == nil)) {
        [BCPayUtil doErrorResponse:@"viewController 不合法，将导致无法正常执行银联支付"];
        return NO;
    } else if (self.channel == PayChannelWxApp && ![BeeCloudAdapter beeCloudIsWXAppInstalled]) {
        [BCPayUtil doErrorResponse:@"未找到微信客户端，请先下载安装"];
        return NO;
    }
    return YES;
}

@end
