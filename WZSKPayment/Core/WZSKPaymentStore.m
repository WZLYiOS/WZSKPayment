//
//  WZSKPaymentStore.m
//  wzly
//
//  Created by 牛胖胖 on 2019/7/5.
//  Copyright © 2019 福州市鼓楼区我主良缘婚姻服务有限公司. All rights reserved.
//


#import "WZSKPaymentStore.h"
#import "WZKeychain.h"
#import <StoreKit/StoreKit.h>
#define WZSKPaymentStoreKeyTransId @"WZSKPaymentStoreKeyTransIds" // 内购订单key
#define WZSKPaymentTradeNoId @"WZSKPaymentStoreKeyTradeNoIds"     // 服务内购订单key
#define WZProductIdentifier @"WZProductIdentifier"                // 苹果产品id
#define WZSKPaymentService @"com.wzly.payment.service"            // 钥匙串账号


/// 购买状态
typedef NS_ENUM(NSInteger, WZSKPaymentStoreErrorCode) {
    WZSKPaymentStoreErrorCodeSucess = 1000000,               // 订单支付成功
    WZSKPaymentStoreErrorCodeNoCanMakePayments = 10000,      // 未开启支付功能
    WZSKPaymentStoreErrorCodeOrderNull = 10001,              // 产品id、订单为空
    WZSKPaymentStoreErrorCodeNotFoundProductId = 10002,      // 苹果服务器未找到产品id
    WZSKPaymentStoreErrorCodeRestored = 10003,               // 此单已经完成
    WZSKPaymentStoreErrorCodeNull   = 10004,                 // 当前没有订单需要补单
    WZSKPaymentStoreErrorCodeResupplyIng  = 10005,           // 当前有历史订单尚未补完
};


typedef void(^WZSKPaymentStorerequestRroductsBlock)(SKProductsResponse * _Nullable response);

@interface WZSKPaymentStore ()<SKPaymentTransactionObserver,SKProductsRequestDelegate>
@property (copy,nonatomic) WZSKPaymentStorerequestRroductsBlock rroductsBlock; // 产品id请求回调
@property (copy,nonatomic) void(^compleSucess)(NSString *tradeNoId, NSString *transactionIdentifier, NSString *receiptData); // 正常购买成功回调
@property (copy,nonatomic) void(^complePayFail)(NSString *msg); // 购买失败
@property (copy,nonatomic) void(^compleRestoreApple)(NSArray <NSString *>*restoreds); /// 苹果服务器补单：苹果订单编号
@property (copy,nonatomic) void(^compleRepair)(NSString *_Nullable tradeNoId, NSString *transactionIdentifier, NSString *receiptData); // 补单回调

@end

@implementation WZSKPaymentStore

// data 转 dic
- (NSDictionary *)getDictionaryWithData:(NSData *)data
{
    if (!data) {
        return [NSDictionary dictionary];
    }
    NSDictionary *dictFromData = [NSJSONSerialization JSONObjectWithData:data
                                                                 options:NSJSONReadingAllowFragments
                                                                   error:nil];
    return dictFromData;
}

// dic 转data
- (NSData *)getDataWithDictionary:(NSDictionary *)dic
{
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dic options:kNilOptions error:nil];
    return jsonData;
}

- (NSString *)accessItem
{
    NSString *bundleID = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
    NSString *tmp = [NSString stringWithFormat:@"com.ApplePay_%@",bundleID];
    return tmp;
}

// 获取购买的凭证
- (NSString *)getReceiptData{
    
    NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptURL];
    NSString *encodeStr = [receiptData base64EncodedStringWithOptions:0];
    return encodeStr;
}

/// 创建单利
static WZSKPaymentStore *_sharedInstance = nil;
static dispatch_once_t predicate;
+ (instancetype)shareInstance {
    dispatch_once(&predicate, ^{
        _sharedInstance = [[WZSKPaymentStore alloc] init];
    });
    return _sharedInstance;
}

// 销毁单利
+ (void)destorySharedInstance{
    _sharedInstance = nil;
    predicate = 0;
}

- (instancetype)init{
    if ([super init]) {
        
        /// 因为回调的时候block还没有赋值，所以要异步添加监听
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
           [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
        });
    }return self;
}

- (void)dealloc
{
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

/// 获取DB里的订单编号
- (NSDictionary *)getDicFromDB{
   return [self getDictionaryWithData:[WZKeychain passDataForAccount:[self accessItem]].lastObject];
}

/// 保存数据到钥匙串
- (BOOL)setDicToDBWith:(NSDictionary *)dic{
    return [WZKeychain setPasswordData:[self getDataWithDictionary:dic] forService:WZSKPaymentService account:[self accessItem]];
}

///  购买商品
- (void)addPayment:(NSString *)productId
      withTradeNos:(NSString *)tradeNoId
        withSucess:(void(^)(NSString *tradeNoId, NSString *transactionIdentifier, NSString *receiptData))sucessBlok
          withFail:(void(^)(NSString *msg))failBlock{
    self.compleSucess = sucessBlok;
    self.complePayFail = failBlock;
    
    /// 0、是否已经有丢单的, 如果有告诉外部本地有订单尚未补完，请稍后购买
    if ([self restoreTransaction]) {
        [self failWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:WZSKPaymentStoreErrorCodeResupplyIng userInfo:nil]];
        return;
    }
    
    /// 1、订单编号未空，购买失败
    if (productId.length== 0 || tradeNoId.length == 0) {
        [self failWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:WZSKPaymentStoreErrorCodeOrderNull userInfo:nil]];
        return;
    }
    
    /// 2、 是否开启支付功能
    if (![SKPaymentQueue canMakePayments]) {
        [self failWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:WZSKPaymentStoreErrorCodeNoCanMakePayments userInfo:nil]];
        return;
    }

    /// 3、向苹果服务器申请产品id
    __weak __typeof(self) weakSelf = self;
    [self requestRroducts:@[productId] withComple:^(SKProductsResponse * _Nullable response) {
        /// 4、把订单缓存钥匙串
        NSMutableDictionary *saveDic = [NSMutableDictionary dictionary];
        [saveDic setValue:tradeNoId forKey:WZSKPaymentTradeNoId];
        [saveDic setValue:productId forKey:WZProductIdentifier];
        [weakSelf setDicToDBWith:saveDic];
       
        /// 5、开始向苹果服务器申请购买
        SKProduct *requestProduct = response.products.firstObject;
        SKMutablePayment * payment = [SKMutablePayment paymentWithProduct:requestProduct];
        [[SKPaymentQueue defaultQueue] addPayment:payment];
    }];
}

/// 找苹果恢复订单，等本地订单补单完成
- (void)restoreTransactionsFromApple:(void(^)(NSArray <NSString *>*restoreds))restoreBlok{
    self.compleRestoreApple = restoreBlok;
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

/// 判断db是否有订单
- (BOOL)restoreTransaction{
    /// -1、查看历史是否有遗留的单
    NSDictionary *dic = [self getDicFromDB];
    if ([dic valueForKey:WZSKPaymentTradeNoId] && [dic valueForKey:WZSKPaymentStoreKeyTransId]) {
        [self callBackRepairwithTradeId:[dic valueForKey:WZSKPaymentTradeNoId] withTransactionId:[dic valueForKey:WZSKPaymentStoreKeyTransId] withProductId:[dic valueForKey:WZProductIdentifier]];
        return YES;
    }
    return NO;
}

/// 从本地补单
- (BOOL)restoreTransactionsFromDB:(void(^)(NSString *_Nullable tradeNoId, NSString *transactionIdentifier, NSString *receiptData))compleBlock{
    self.compleRepair = compleBlock;
    return [self restoreTransaction];
}


/// 向服务器请求产品id
- (void)requestRroducts:(NSArray *)products withComple:(WZSKPaymentStorerequestRroductsBlock)compleBlock{
    self.rroductsBlock = compleBlock;
    // 2、向苹果服务器请求产品id
    NSSet *nsset = [NSSet setWithArray:products];
    SKProductsRequest *request = [[SKProductsRequest alloc] initWithProductIdentifiers:nsset];
    request.delegate = self;
    [request start];
}

// 10.接收到产品的返回信息,然后用返回的商品信息进行发起购买请求
- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response
{
    NSArray *product = response.products;
    //如果服务器没有产品
    if([product count] == 0){
        [self failWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:WZSKPaymentStoreErrorCodeNotFoundProductId userInfo:nil]];
        return;
    }
    
    if (self.rroductsBlock) {
        self.rroductsBlock(response);
    }
}

//请求失败
- (void)request:(SKRequest *)request didFailWithError:(NSError *)error{
    [self failWithError:error];
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions{
    
    /// 历史购买的订单
    NSMutableArray *restoredArray = [NSMutableArray array];
    
    for (SKPaymentTransaction *tran in transactions) {
        switch (tran.transactionState) {
            case SKPaymentTransactionStatePurchased:
            {
                [self setSKPaymentTransactionStatePurchased:tran];
                [[SKPaymentQueue defaultQueue] finishTransaction:tran];
            }
                break;
            case SKPaymentTransactionStateRestored:
            {
                [restoredArray addObject:tran.transactionIdentifier];
                [[SKPaymentQueue defaultQueue] finishTransaction:tran];
            }
                break;
            case SKPaymentTransactionStateFailed:
            {
                /// 支付失败清楚本地订单、产品id 需相同
                if ([tran.payment.productIdentifier isEqualToString:[[self getDicFromDB] valueForKey:WZProductIdentifier]]) {
                    [WZKeychain deletePasswordForService:WZSKPaymentService account:[self accessItem]];
                }
                [self failWithError:tran.error];
                [[SKPaymentQueue defaultQueue]finishTransaction:tran];
            }
                break;
            default:
                break;
        }
    }
    
    if (restoredArray.count > 0) {
        if (self.compleRestoreApple) {
            self.compleRestoreApple(restoredArray);
        }
    }
}

/// 苹果支付订单已经完成
- (void)setSKPaymentTransactionStatePurchased:(SKPaymentTransaction *)tran{
    
    /// 问题：已订阅过期，重新购买，会返回已经订阅逻辑
    NSDictionary *dic = [self getDicFromDB];
    /// 服务器订单
    NSString *tradeNoId = [dic valueForKey:WZSKPaymentTradeNoId];
    
    /// db苹果订单
    NSString *tranId = [dic valueForKey:WZSKPaymentStoreKeyTransId];
    
    /// 苹果产品id
    NSString *productIdentifier = [dic valueForKey:WZProductIdentifier];
        
    /// 是否订阅
//    BOOL isRenew = tran.originalTransaction? YES:NO;
    
    /// 判断是否正常下单逻辑
    ///1、 本地没有服务器订单编号，直接上报不再走缓存路线
    ///2、本地有苹果订单、返回的苹果订单跟db缓存订单对应不上，走直接上报
    ///3、db产品id跟苹果返回的不一致、走直接上报
    BOOL isNormal = (tradeNoId.length > 0 && [tran.payment.productIdentifier isEqualToString:productIdentifier] && tranId.length == 0) ? YES:NO;
    
    /// 正常下单逻辑：有服务器订单
    if (isNormal) {
        NSMutableDictionary *saveDic = [NSMutableDictionary dictionaryWithDictionary:dic];
        [saveDic setObject:tran.transactionIdentifier>0?tran.transactionIdentifier:@"" forKey:WZSKPaymentStoreKeyTransId];
        [self setDicToDBWith:saveDic];
        [self callBackSuceeswithTradeId:tradeNoId withTransactionId:tran.transactionIdentifier withProductId:tran.payment.productIdentifier];
    }else{
        [self callBackRepairwithTradeId:nil withTransactionId:tran.transactionIdentifier withProductId:tran.payment.productIdentifier];
    }
}

/// 错误接收、告诉外部购买失败
- (void)failWithError:(NSError *)error{
    if (self.complePayFail) {
        self.complePayFail([self failedTransaction:error.code]);
    }
}

/// 删除订单
- (void)deleteTransaction{
    
    NSDictionary *dic = [self getDicFromDB];
    if ([dic valueForKey:WZSKPaymentTradeNoId] && [dic valueForKey:WZSKPaymentStoreKeyTransId]) {
        BOOL isDelete = [WZKeychain deletePasswordForService:WZSKPaymentService account:[self accessItem]];
        if (!isDelete) {
            NSLog(@"最后一步订单删除失败");
        }
    }
}

/// 支付成功回调给外部
/// @param tradeId 服务器订单编号
/// @param transactionId 苹果订单
/// @param productId  产品id
- (void)callBackSuceeswithTradeId:(NSString *)tradeId withTransactionId:(NSString *)transactionId withProductId:(NSString *)productId {
    
    __weak typeof(self) weakSelf = self;
    [self threadComple:^{
        if (weakSelf.compleSucess) {
            weakSelf.compleSucess(tradeId, transactionId, [self getReceiptData]);
        }else{
            [weakSelf callBackRepairwithTradeId:tradeId withTransactionId:transactionId withProductId:productId];
        }
    }];
}

/// 补单回调给外部
/// @param tradeId 服务器订单编号
/// @param transactionId 苹果订单
/// @param productId  产品id
- (void)callBackRepairwithTradeId:(NSString *)tradeId withTransactionId:(NSString *)transactionId withProductId:(NSString *)productId {
    
    __weak typeof(self) weakSelf = self;
    [self threadComple:^{
        if (weakSelf.compleRepair) {
            weakSelf.compleRepair(tradeId, transactionId, [self getReceiptData]);
        }
    }];
}

/// 通知外部完成订单, 阿三可能返回子线程，需要手动添加主线程
- (void)threadComple:(void(^)(void))comple {
    
    if ([NSThread currentThread].isMainThread) {
        if (comple) {
            comple();
        }
       } else {
           dispatch_async(dispatch_get_main_queue(), ^{
              if (comple) {
                  comple();
              }
           });
    }
}

/// 上报成功删除本地订单
- (void)deleteWith:(NSString *)tradeNoId{
    
    NSDictionary *dic = [self getDicFromDB];
    if (tradeNoId.length > 0 && [[dic valueForKey:WZSKPaymentTradeNoId] isEqualToString:tradeNoId]) {
        BOOL isDelete = [WZKeychain deletePasswordForService:WZSKPaymentService account:[self accessItem]];
        if (!isDelete) {
            NSLog(@"上报成功删除本地订单");
        }
    }
}

/// 错误内购提示
- (NSString *)failedTransaction:(NSInteger)code{
    
    NSString * error = @"";
    switch (code) {
        case SKErrorUnknown:
            error = @"发生未知或意外错误。";
            break;
        case SKErrorPaymentCancelled:
            error = @"购买失败，您取消了付款请求";
            break;
        case SKErrorCloudServiceRevoked:
            error = @"您已撤消使用此云服务的权限";
            break;
        case SKErrorPaymentInvalid:
            error = @"App Store无法识别付款参数";
            break;
        case SKErrorPaymentNotAllowed:
            error = @"请开启授权付款权限";
            break;
        case SKErrorStoreProductNotAvailable:
            error = @"所请求的产品在商店中不可用。";
            break;
        case SKErrorCloudServicePermissionDenied:
            error = @"不允许访问云服务信息";
            break;
        case SKErrorCloudServiceNetworkConnectionFailed:
            error = @"设备无法连接到网络";
            break;
        case WZSKPaymentStoreErrorCodeNotFoundProductId:
            error = @"未查询到该产品，请联系客服";
            break;
        case WZSKPaymentStoreErrorCodeNoCanMakePayments:
            error = @"未开启支付功能";
            break;
        case WZSKPaymentStoreErrorCodeOrderNull:
            error = @"返回的订单id丢失";
            break;
        case WZSKPaymentStoreErrorCodeNull:
            error = @"当前无未完成的订单";
            break;
        case WZSKPaymentStoreErrorCodeResupplyIng:
            error = @"历史订单还在补单中，请稍后/联系客服";
            break;
        default:
            error = @"购买失败";
            break;
    }
    return error;
}

@end

