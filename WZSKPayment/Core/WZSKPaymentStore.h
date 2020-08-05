//
//  WZSKPaymentStore.h
//  wzly
//
//  Created by 牛胖胖 on 2019/7/5.
//  Copyright © 2019 福州市鼓楼区我主良缘婚姻服务有限公司. All rights reserved.
//  苹果支付SDK

/* 经反复验证，苹果支付SDK不能走事务队列类型，而是只能每次购买1单，如果本地订单未结单，需补单完才能下新的订单
 * 逻辑：
 * 0、判断db是否有服务器订单、苹果订单-> 有：此次下单失败，走补单逻辑 无：正常下单逻辑
 * 1、获取产品id成功、把服务器订单、产品订单存入DB(钥匙串)
 * 2、苹果支付成功：判断db和tran 产品id是否相同，服务器订单是否不为空，db苹果订单是否为空 -> 是：走下单流程，把服务器订单和苹果订单捆绑存入db 否：走上报流程
 * 3、支付失败需清除刚刚存入db的服务器订单
 * 4、上报服务器成功，需删除本地服务器订单
 * 5、需要调苹果服务器恢复订单接口，把苹果订单全部发给服务端校验
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WZSKPaymentStore : NSObject

+ (instancetype)shareInstance;
+ (void)destorySharedInstance;

/// 补单回调、注意：必须实现，否则可能会丢单
/// @param compleBlock 回调需补单的凭证
- (BOOL)restoreTransactionsFromDB:(void(^)(NSString *_Nullable tradeNoId, NSString *transactionIdentifier, NSString *receiptData))compleBlock;

/// 购买商品
/// @param productId 内购产品id
/// @param tradeNoId 本服务器商品Id
/// @param sucessBlok 购买成功
/// @param failBlock 购买失败
- (void)addPayment:(NSString *)productId
      withTradeNos:(NSString *)tradeNoId
        withSucess:(void(^)(NSString *tradeNoId, NSString *transactionIdentifier, NSString *receiptData))sucessBlok
          withFail:(void(^)(NSString *msg))failBlock;

/// 刷新苹果订单记录
/// @param restoreBlok 所有的订单记录
- (void)restoreTransactionsFromApple:(void(^)(NSArray <NSString *>*restoreds))restoreBlok;

/// 上报成功删除本地订单
/// @param tradeNoId 服务器订单
- (void)deleteWith:(NSString * _Nullable)tradeNoId;

@end

NS_ASSUME_NONNULL_END
