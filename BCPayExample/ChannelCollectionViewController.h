//
//  ChannelCollectionViewController.h
//  BCPay
//
//  Created by Ewenlong03 on 16/2/23.
//  Copyright © 2016年 BeeCloud. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "BeeCloud.h"

@interface ChannelCollectionViewController : UICollectionViewController

@property (strong, nonatomic) BCBaseResp *orderList;

@property  (assign, nonatomic) NSInteger actionType;//0:pay;1:query;

@end
