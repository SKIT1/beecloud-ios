//
//  BeeCloud.m
//  BeeCloud
//
//  Created by Ewenlong03 on 15/9/7.
//  Copyright (c) 2015年 BeeCloud. All rights reserved.
//
#import "BeeCloud.h"

#import "BCPayUtil.h"
#import "BCPayCache.h"
#import "BeeCloudAdapter.h"

@interface BeeCloud ()

@property (nonatomic, assign) BOOL registerStatus;
@property (nonatomic, weak) id<BeeCloudDelegate> delegate;

@end


@implementation BeeCloud

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static BeeCloud *instance = nil;
    dispatch_once(&onceToken, ^{
        instance = [[BeeCloud alloc] init];
    });
    return instance;
}

+ (void)initWithAppID:(NSString *)appId andAppSecret:(NSString *)appSecret {
    BCPayCache *instance = [BCPayCache sharedInstance];
    instance.appId = appId;
    instance.appSecret = appSecret;
}

+ (BOOL)initWeChatPay:(NSString *)wxAppID {
    return [BeeCloudAdapter beeCloudRegisterWeChat:wxAppID];
}

+ (void)initPayPal:(NSString *)clientID secret:(NSString *)secret sanBox:(BOOL)isSandBox {
    
    if(clientID.isValid && secret.isValid) {
        BCPayCache *instance = [BCPayCache sharedInstance];
        instance.payPalClientID = clientID;
        instance.payPalSecret = secret;
        instance.isPayPalSandBox = isSandBox;
        
        [BeeCloudAdapter beeCloudRegisterPayPal:clientID secret:secret sanBox:isSandBox];
    }
}

+ (void)setBeeCloudDelegate:(id<BeeCloudDelegate>)delegate {
    [BeeCloud sharedInstance].delegate = delegate;
    [BeeCloudAdapter beeCloud:kAdapterWXPay doSetDelegate:delegate];
    [BeeCloudAdapter beeCloud:kAdapterAliPay doSetDelegate:delegate];
    [BeeCloudAdapter beeCloud:kAdapterUnionPay doSetDelegate:delegate];
    [BeeCloudAdapter beeCloud:kAdapterPayPal doSetDelegate:delegate];
}

+ (BOOL)handleOpenUrl:(NSURL *)url {
    if (BCPayUrlWeChat == [BCPayUtil getUrlType:url]) {
        return [BeeCloudAdapter beeCloud:kAdapterWXPay handleOpenUrl:url];
    } else if (BCPayUrlAlipay == [BCPayUtil getUrlType:url]) {
        return [BeeCloudAdapter beeCloud:kAdapterAliPay handleOpenUrl:url];
    }
    return NO;
}

+ (NSString *)getBCApiVersion {
    return kApiVersion;
}

+ (void)setWillPrintLog:(BOOL)flag {
    [BCPayCache sharedInstance].willPrintLogMsg = flag;
}

+ (void)setNetworkTimeout:(NSTimeInterval)time {
    [BCPayCache sharedInstance].networkTimeout = time;
}

+ (void)sendBCReq:(BCBaseReq *)req {
    BeeCloud *instance = [BeeCloud sharedInstance];
    switch (req.type) {
        case BCObjsTypePayReq:
            [instance reqPay:(BCPayReq *)req];
            break;
        case BCObjsTypeQueryReq:
            [instance reqQueryOrder:(BCQueryReq *)req];
            break;
        case BCObjsTypeQueryRefundReq:
            [instance reqQueryOrder:(BCQueryRefundReq *)req];
            break;
        case BCObjsTypeRefundStatusReq:
            [instance reqRefundStatus:(BCRefundStatusReq *)req];
            break;
        case BCObjsTypePayPal:
            [instance  reqPayPal:(BCPayPalReq *)req];
            break;
        case BCObjsTypePayPalVerify:
            [instance reqPayPalVerify:(BCPayPalVerifyReq *)req];
            break;
        case BCObjsTypeOfflinePayReq:
            [instance reqOfflinePay:(BCOfflinePayReq *)req];
            break;
        case BCObjsTypeOfflineBillStatusReq:
            [instance reqOfflineBillStatus:(BCOfflineStatusReq *)req];
            break;
        case BCObjsTypeOfflineRevertReq:
            [instance reqOfflineBillRevert:(BCOfflineRevertReq *)req];
            break;
        default:
            break;
    }
}

#pragma mark private class functions

#pragma mark Pay Request

- (void)reqPay:(BCPayReq *)req {
    if (![self checkParameters:req]) return;
    
    NSString *cType = [BCPayUtil getChannelString:req.channel];
    
    NSMutableDictionary *parameters = [BCPayUtil prepareParametersForPay];
    if (parameters == nil) {
        [self doErrorResponse:@"请检查是否全局初始化"];
        return;
    }
    
    parameters[@"channel"] = cType;
    parameters[@"total_fee"] = [NSNumber numberWithInteger:[req.totalfee integerValue]];
    parameters[@"bill_no"] = req.billno;
    parameters[@"title"] = req.title;
    if (req.optional) {
        parameters[@"optional"] = req.optional;
    }
    
    AFHTTPRequestOperationManager *manager = [BCPayUtil getAFHTTPRequestOperationManager];
    __weak BeeCloud *weakSelf = self;
    [manager POST:[BCPayUtil getBestHostWithFormat:kRestApiPay] parameters:parameters
          success:^(AFHTTPRequestOperation *operation, id response) {
              
              BCBaseResp *resp = [weakSelf getErrorInResponse:response];
              if (resp.result_code != 0) {
                  if (_delegate && [_delegate respondsToSelector:@selector(onBeeCloudResp:)]) {
                      [_delegate onBeeCloudResp:resp];
                  }
              } else {
                  BCPayLog(@"channel=%@,resp=%@", cType, response);
                  NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithDictionary:
                                              (NSDictionary *)response];
                  if (req.channel == PayChannelAliApp) {
                      [dic setObject:req.scheme forKey:@"scheme"];
                  } else if (req.channel == PayChannelUnApp) {
                      [dic setObject:req.viewController forKey:@"viewController"];
                  }
                  [weakSelf doPayAction:req.channel source:dic];
              }
          } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
              [weakSelf doErrorResponse:kNetWorkError];
          }];
}

#pragma mark - Pay Action

- (void)doPayAction:(PayChannel)channel source:(NSMutableDictionary *)dic {
    if (dic) {
        BCPayLog(@"payment====%@", dic);
        switch (channel) {
            case PayChannelWxApp:
                [BeeCloudAdapter beeCloudWXPay:dic];
                break;
            case PayChannelAliApp:
                [BeeCloudAdapter beeCloudAliPay:dic];
                break;
            case PayChannelUnApp:
                [BeeCloudAdapter beeCloudUnionPay:dic];
                break;
            default:
                break;
        }
    }
}

#pragma mark - Offline Pay

- (void)reqOfflinePay:(BCOfflinePayReq *)req {
    
    if (![self checkParameters:req]) return;
    
    NSString *cType = [BCPayUtil getChannelString:req.channel];
    
    NSMutableDictionary *parameters = [BCPayUtil prepareParametersForPay];
    if (parameters == nil) {
        [self doErrorResponse:@"请检查是否全局初始化"];
        return;
    }
    
    parameters[@"channel"] = cType;
    parameters[@"total_fee"] = [NSNumber numberWithInteger:[req.totalfee integerValue]];
    parameters[@"bill_no"] = req.billno;
    parameters[@"title"] = req.title;
    if (req.channel == PayChannelWxSCan || req.channel == PayChannelAliScan) {
        parameters[@"auth_code"] = req.authcode;
    }
    if (req.channel == PayChannelAliScan) {
        if (req.terminalid.isValid) {
            parameters[@"terminal_id"] = req.terminalid;
        }
        if (req.storeid.isValid) {
            parameters[@"store_id"] = req.storeid;
        }
    }
    if (req.optional) {
        parameters[@"optional"] = req.optional;
    }
    
    AFHTTPRequestOperationManager *manager = [BCPayUtil getAFHTTPRequestOperationManager];
    __weak BeeCloud *weakSelf = self;
    [manager POST:[BCPayUtil getBestHostWithFormat:kRestApiOfflinePay] parameters:parameters
          success:^(AFHTTPRequestOperation *operation, id response) {
              
              BCBaseResp *resp = [self getErrorInResponse:response];
              if (resp.result_code != 0) {
                  [weakSelf doBeeCloudResp:resp];
              } else {
                  BCPayLog(@"channel=%@,resp=%@", cType, response);
                  [weakSelf doOfflinePayResp:req source:(NSDictionary *)response];
              }
          } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
              [weakSelf doErrorResponse:kNetWorkError];
          }];
}

- (void)doOfflinePayResp:(BCOfflinePayReq *)req source:(NSDictionary *)source {
    switch (req.channel) {
        case PayChannelWxNative:
        case PayChannelAliOfflineQrCode:
        {
            BCOfflinePayResp *resp = [[BCOfflinePayResp alloc] init];
            resp.result_code = [[source objectForKey:kKeyResponseResultCode] intValue];
            resp.result_msg = [source objectForKey:kKeyResponseResultMsg];
            resp.err_detail = [source objectForKey:kKeyResponseErrDetail];
            resp.codeurl = [source objectForKey:kKeyResponseCodeUrl];
            resp.request = req;
            [self doBeeCloudResp:resp];
        }
            break;
        default:
        {
            BCBaseResp *resp = [[BCBaseResp alloc] init];
            resp.result_code = [[source objectForKey:kKeyResponseResultCode] intValue];
            resp.result_msg = [source objectForKey:kKeyResponseResultMsg];
            resp.err_detail = [source objectForKey:kKeyResponseErrDetail];
            [self doBeeCloudResp:resp];
        }
            break;
    }
}

#pragma mark - OffLine BillStatus

- (void)reqOfflineBillStatus:(BCOfflineStatusReq *)req {
    if (req == nil) {
        [self doErrorResponse:@"请求结构体不合法"];
        return;
    } else if (!req.billno.isValid || !req.billno.isValidTraceNo || (req.billno.length < 8) || (req.billno.length > 32)) {
        [self doErrorResponse:@"billno 必须是长度8~32位字母和/或数字组合成的字符串"];
        return;
    }
    
    NSString *cType = [BCPayUtil getChannelString:req.channel];
    
    NSMutableDictionary *parameters = [BCPayUtil prepareParametersForPay];
    if (parameters == nil) {
        [self doErrorResponse:@"请检查是否全局初始化"];
        return;
    }
    
    parameters[@"channel"] = cType;
    parameters[@"bill_no"] = req.billno;
    
    AFHTTPRequestOperationManager *manager = [BCPayUtil getAFHTTPRequestOperationManager];
    __weak BeeCloud *weakSelf = self;
    [manager POST:[BCPayUtil getBestHostWithFormat:kRestApiOfflineBillStatus] parameters:parameters
          success:^(AFHTTPRequestOperation *operation, id response) {
              
              BCBaseResp *resp = [self getErrorInResponse:response];
              if (resp.result_code != 0) {
                  [weakSelf doBeeCloudResp:resp];
              } else {
                  BCPayLog(@"channel=%@,resp=%@", cType, response);
                  BCOfflineStatusResp *resp = [[BCOfflineStatusResp alloc] init];
                  resp.result_code = [[response objectForKey:kKeyResponseResultCode] intValue];
                  resp.result_msg = [response objectForKey:kKeyResponseResultMsg];
                  resp.err_detail = [response objectForKey:kKeyResponseErrDetail];
                  resp.payResult = [[response objectForKey:KKeyResponsePayResult] boolValue];
                  resp.request = req;
                  [weakSelf doBeeCloudResp:resp];
              }
          } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
              [weakSelf doErrorResponse:kNetWorkError];
          }];
}

#pragma mark - OffLine BillRevert

- (void)reqOfflineBillRevert:(BCOfflineRevertReq *)req {
    if (req == nil) {
        [self doErrorResponse:@"请求结构体不合法"];
        return;
    } else if (!req.billno.isValid || !req.billno.isValidTraceNo || (req.billno.length < 8) || (req.billno.length > 32)) {
        [self doErrorResponse:@"billno 必须是长度8~32位字母和/或数字组合成的字符串"];
        return;
    }
    
    NSString *cType = [BCPayUtil getChannelString:req.channel];
    
    NSMutableDictionary *parameters = [BCPayUtil prepareParametersForPay];
    if (parameters == nil) {
        [self doErrorResponse:@"请检查是否全局初始化"];
        return;
    }
    
    parameters[@"channel"] = cType;
    parameters[@"method"] = @"REVERT";
    
    AFHTTPRequestOperationManager *manager = [BCPayUtil getAFHTTPRequestOperationManager];
    __weak BeeCloud *weakSelf = self;
    [manager POST:[[BCPayUtil getBestHostWithFormat:kRestApiOfflineBillRevert] stringByAppendingString:req.billno] parameters:parameters
          success:^(AFHTTPRequestOperation *operation, id response) {
              
              BCBaseResp *resp = [weakSelf getErrorInResponse:response];
              if (resp.result_code != 0) {
                  [weakSelf doBeeCloudResp:resp];
              } else {
                  BCPayLog(@"channel=%@,resp=%@", cType, response);
                  BCOfflineRevertResp *resp = [[BCOfflineRevertResp alloc] init];
                  resp.result_code = [[response objectForKey:kKeyResponseResultCode] intValue];
                  resp.result_msg = [response objectForKey:kKeyResponseResultMsg];
                  resp.err_detail = [response objectForKey:kKeyResponseErrDetail];
                  resp.revertStatus = [[response objectForKey:kKeyResponseRevertResult] boolValue];
                  resp.request = req;
                  [weakSelf doBeeCloudResp:resp];
              }
          } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
              [weakSelf doErrorResponse:kNetWorkError];
          }];
}

#pragma mark PayPal

- (void)reqPayPal:(BCPayPalReq *)req {
    [BeeCloudAdapter beeCloudPayPal:[NSMutableDictionary dictionaryWithObjectsAndKeys:req, @"PayPal",nil]];
}

- (void)reqPayPalVerify:(BCPayPalVerifyReq *)req {
    [self reqPayPalAccessToken:req];
}

- (void)reqPayPalAccessToken:(BCPayPalVerifyReq *)req {
    
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    manager.securityPolicy.allowInvalidCertificates = NO;
    manager.requestSerializer = [AFHTTPRequestSerializer serializer];
    
    [manager.requestSerializer setAuthorizationHeaderFieldWithUsername:[BCPayCache sharedInstance].payPalClientID password:[BCPayCache sharedInstance].payPalSecret];
    [manager.requestSerializer setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObject:@"client_credentials" forKey:@"grant_type"];
    __weak BeeCloud *weakSelf = self;
    [manager POST:[BCPayCache sharedInstance].isPayPalSandBox?kPayPalAccessTokenSandBox:kPayPalAccessTokenProduction parameters:params success:^(AFHTTPRequestOperation *operation, id response) {
        BCPayLog(@"token %@", response);
        NSDictionary *dic = (NSDictionary *)response;
        [weakSelf doPayPalVerify:req accessToken:[NSString stringWithFormat:@"%@ %@", [dic objectForKey:@"token_type"],[dic objectForKey:@"access_token"]]];
    }  failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        [weakSelf doErrorResponse:kNetWorkError];
    }];
}

- (void)doPayPalVerify:(BCPayPalVerifyReq *)req accessToken:(NSString *)accessToken {
    
    [BeeCloudAdapter beeCloudPayPalVerify:[NSMutableDictionary dictionaryWithObjectsAndKeys:req,@"PayPalVerify",accessToken, @"access_token",nil]];
}

#pragma mark Query Bills/Refunds

- (void)reqQueryOrder:(BCQueryReq *)req {
    if (req == nil) {
        [self doErrorResponse:@"请求结构体不合法"];
        return;
    }
    
    NSString *cType = [BCPayUtil getChannelString:req.channel];
    
    NSMutableDictionary *parameters = [BCPayUtil prepareParametersForPay];
    if (parameters == nil) {
        [self doErrorResponse:@"请检查是否全局初始化"];
        return;
    }
    NSString *reqUrl = [BCPayUtil getBestHostWithFormat:kRestApiQueryBills];
    
    if (req.billno.isValid) {
        parameters[@"bill_no"] = req.billno;
    }
    if (req.starttime.isValid) {
        parameters[@"start_time"] = [NSNumber numberWithLongLong:[BCPayUtil dateStringToMillisencond:req.starttime]];
    }
    if (req.endtime.isValid) {
        parameters[@"end_time"] = [NSNumber numberWithLongLong:[BCPayUtil dateStringToMillisencond:req.endtime]];
    }
    if (req.type == BCObjsTypeQueryRefundReq) {
        BCQueryRefundReq *refundReq = (BCQueryRefundReq *)req;
        if (refundReq.refundno.isValid) {
            parameters[@"refund_no"] = refundReq.refundno;
        }
        reqUrl = [BCPayUtil getBestHostWithFormat:kRestApiQueryRefunds];
    }
    if (cType.isValid) {
        parameters[@"channel"] = cType;
    }
    parameters[@"skip"] = [NSNumber numberWithInteger:req.skip];
    parameters[@"limit"] = [NSNumber numberWithInteger:req.limit];
    
    NSMutableDictionary *preparepara = [BCPayUtil getWrappedParametersForGetRequest:parameters];
    
    AFHTTPRequestOperationManager *manager = [BCPayUtil getAFHTTPRequestOperationManager];
    __weak BeeCloud *weakSelf = self;
    [manager GET:reqUrl parameters:preparepara
         success:^(AFHTTPRequestOperation *operation, id response) {
             BCPayLog(@"resp = %@", response);
             [weakSelf doQueryResponse:(NSDictionary *)response];
         } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
             [weakSelf doErrorResponse:kNetWorkError];
         }];
}

- (void)doQueryResponse:(NSDictionary *)dic {
    BCQueryResp *resp = [[BCQueryResp alloc] init];
    resp.result_code = [dic[kKeyResponseResultCode] intValue];
    resp.result_msg = dic[kKeyResponseResultMsg];
    resp.err_detail = dic[kKeyResponseErrDetail];
    resp.count = [[dic objectForKey:@"count"] integerValue];
    resp.results = [self parseResults:dic];
    [self doBeeCloudResp:resp];
}

- (NSMutableArray *)parseResults:(NSDictionary *)dic {
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:10];
    if ([[dic allKeys] containsObject:@"bills"]) {
        for (NSDictionary *result in [dic objectForKey:@"bills"]) {
            [array addObject:[self parseQueryResult:result]];
        } ;
    } else if ([[dic allKeys] containsObject:@"refunds"]) {
        for (NSDictionary *result in [dic objectForKey:@"refunds"]) {
            [array addObject:[self parseQueryResult:result]];
        } ;
    }
    return array;
}

- (BCBaseResult *)parseQueryResult:(NSDictionary *)dic {
    if (dic) {
        if ([[dic allKeys] containsObject:@"spay_result"]) {
            BCQueryBillResult *qResp = [[BCQueryBillResult alloc] init];
            for (NSString *key in [dic allKeys]) {
                [qResp setValue:[dic objectForKey:key] forKey:key];
            }
            return qResp;
        } else if ([[dic allKeys] containsObject:@"refund_no"]) {
            BCQueryRefundResult *qResp = [[BCQueryRefundResult alloc] init];
            for (NSString *key in [dic allKeys]) {
                [qResp setValue:[dic objectForKey:key] forKey:key];
            }
            return qResp;
        }
    }
    return nil;
}

#pragma mark Refund Status

- (void)reqRefundStatus:(BCRefundStatusReq *)req {
    if (req == nil) {
        [self doErrorResponse:@"请求结构体不合法"];
        return;
    }
    
    NSMutableDictionary *parameters = [BCPayUtil prepareParametersForPay];
    if (parameters == nil) {
        [self doErrorResponse:@"请检查是否全局初始化"];
        return;
    }
    
    if (req.refundno.isValid) {
        parameters[@"refund_no"] = req.refundno;
    }
    parameters[@"channel"] = @"WX";
    
    NSMutableDictionary *preparepara = [BCPayUtil getWrappedParametersForGetRequest:parameters];
    
    AFHTTPRequestOperationManager *manager = [BCPayUtil getAFHTTPRequestOperationManager];
    __weak BeeCloud *weakSelf = self;
    [manager GET:[BCPayUtil getBestHostWithFormat:kRestApiRefundState] parameters:preparepara
         success:^(AFHTTPRequestOperation *operation, id response) {
             [weakSelf doQueryRefundStatus:(NSDictionary *)response];
         } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
             [weakSelf doErrorResponse:kNetWorkError];
         }];
}

- (void)doQueryRefundStatus:(NSDictionary *)dic {
    BCRefundStatusResp *resp = [[BCRefundStatusResp alloc] init];
    resp.result_code = [dic[kKeyResponseResultCode] intValue];
    resp.result_msg = dic[kKeyResponseResultMsg];
    resp.err_detail = dic[kKeyResponseErrDetail];
    resp.refundStatus = [dic objectForKey:@"refund_status"];
    [self doBeeCloudResp:resp];
}

#pragma mark Util Function

- (void)doBeeCloudResp:(BCBaseResp *)resp {
    if (_delegate && [_delegate respondsToSelector:@selector(onBeeCloudResp:)]) {
        [_delegate onBeeCloudResp:resp];
    }
}

- (void)doErrorResponse:(NSString *)errMsg {
    BCBaseResp *resp = [[BCBaseResp alloc] init];
    resp.result_code = BCErrCodeCommon;
    resp.result_msg = errMsg;
    resp.err_detail = errMsg;
    [self doBeeCloudResp:resp];
}

- (BCBaseResp *)getErrorInResponse:(id)response {
    NSDictionary *dic = (NSDictionary *)response;
    BCBaseResp *resp = [[BCBaseResp alloc] init];
    resp.result_code = [dic[kKeyResponseResultCode] intValue];
    resp.result_msg = dic[kKeyResponseResultMsg];
    resp.err_detail = dic[kKeyResponseErrDetail];
    return resp;
}

- (BOOL)checkParameters:(BCBaseReq *)request {
    
    if (request == nil) {
        [self doErrorResponse:@"请求结构体不合法"];
    } else if (request.type == BCObjsTypePayReq) {
        BCPayReq *req = (BCPayReq *)request;
        if (!req.title.isValid || [BCPayUtil getBytes:req.title] > 32) {
            [self doErrorResponse:@"title 必须是长度不大于32个字节,最长16个汉字的字符串的合法字符串"];
            return NO;
        } else if (!req.totalfee.isValid || !req.totalfee.isPureInt) {
            [self doErrorResponse:@"totalfee 以分为单位，必须是只包含数值的字符串"];
            return NO;
        } else if (!req.billno.isValid || !req.billno.isValidTraceNo || (req.billno.length < 8) || (req.billno.length > 32)) {
            [self doErrorResponse:@"billno 必须是长度8~32位字母和/或数字组合成的字符串"];
            return NO;
        } else if ((req.channel == PayChannelAliApp) && !req.scheme.isValid) {
            [self doErrorResponse:@"scheme 不是合法的字符串，将导致无法从支付宝钱包返回应用"];
            return NO;
        } else if ((req.channel == PayChannelUnApp) && (req.viewController == nil)) {
            [self doErrorResponse:@"viewController 不合法，将导致无法正常执行银联支付"];
            return NO;
        } else if (req.channel == PayChannelWxApp && ![BeeCloudAdapter beeCloudIsWXAppInstalled]) {
            [self doErrorResponse:@"未找到微信客户端，请先下载安装"];
            return NO;
        }
        return YES;
    } else if (request.type == BCObjsTypeOfflinePayReq) {
        BCOfflinePayReq *req = (BCOfflinePayReq *)request;
        if (!req.title.isValid || [BCPayUtil getBytes:req.title] > 32) {
            [self doErrorResponse:@"title 必须是长度不大于32个字节,最长16个汉字的字符串的合法字符串"];
            return NO;
        } else if (!req.totalfee.isValid || !req.totalfee.isPureInt) {
            [self doErrorResponse:@"totalfee 以分为单位，必须是只包含数值的字符串"];
            return NO;
        } else if (!req.billno.isValid || !req.billno.isValidTraceNo || (req.billno.length < 8) || (req.billno.length > 32)) {
            [self doErrorResponse:@"billno 必须是长度8~32位字母和/或数字组合成的字符串"];
            return NO;
        } else if ((req.channel == PayChannelAliScan || req.channel == PayChannelWxSCan) && !req.authcode.isValid) {
            [self doErrorResponse:@"authcode 不是合法的字符串"];
            return NO;
        } else if ((req.channel == PayChannelAliScan) && (!req.terminalid.isValid || !req.storeid.isValid)) {
            [self doErrorResponse:@"terminalid或storeid 不是合法的字符串"];
            return NO;
        }
        return YES;
    }
    return NO ;
}

@end
