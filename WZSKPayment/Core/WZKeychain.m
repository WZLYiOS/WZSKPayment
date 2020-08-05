//
//  WZKeychain.m
//  WZKeychain
//
//  Created by 牛胖胖 on 2019/7/7.
//  Copyright © 2019 我主良缘. All rights reserved.
//

#import "WZKeychain.h"

@implementation WZKeychain

// 获取钥匙串里的单
+ (NSMutableDictionary *)getKeychainQuery:(NSString *)serviceName account:(NSString *)account
{
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                       (__bridge id)kSecClassGenericPassword,(__bridge id)kSecClass,
                                       (__bridge id)kSecAttrAccessibleAfterFirstUnlock,(__bridge id)kSecAttrAccessible,
                                       nil];
    if (serviceName.length>0){
        [dictionary setObject:serviceName forKey:(__bridge id)kSecAttrService];
    }
    
    if (account.length>0) {
        [dictionary setObject:account forKey:(__bridge id)kSecAttrAccount];
    }
    return dictionary;
}

// 获取钥匙串里的data
+ (nullable NSData *)passwordDataForService:(NSString *)serviceName account:(NSString *)account
{
    if (serviceName.length<=0 || account.length<=0) {
        return nil;
    }
    CFTypeRef result = NULL;
    NSMutableDictionary *query = [self getKeychainQuery:serviceName account:account];
    [query setObject:@YES forKey:(__bridge id)kSecReturnData];
    [query setObject:(__bridge id)kSecMatchLimitOne forKey:(__bridge id)kSecMatchLimit];
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess) {
        return nil;
    }
    return (__bridge_transfer NSData *)result;
}

//  更新钥匙串里的数据
+ (BOOL)setPasswordData:(NSData *)password forService:(NSString *)serviceName account:(NSString *)account
{
    if (!serviceName || !account || !password) return NO;
    NSMutableDictionary *searchQuery = [self getKeychainQuery:serviceName account:account];
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)searchQuery, nil);
    if (status == errSecSuccess){
        NSMutableDictionary *query = [[NSMutableDictionary alloc]init];
        [query setObject:password forKey:(__bridge id)kSecValueData];
        status = SecItemUpdate((__bridge CFDictionaryRef)(searchQuery), (__bridge CFDictionaryRef)(query));
    }else if (status == errSecItemNotFound){
        [searchQuery setObject:password forKey:(__bridge id)kSecValueData];
        status = SecItemAdd((__bridge CFDictionaryRef)searchQuery, NULL);
    }
    if (status != errSecSuccess) return NO;
    return (status == errSecSuccess);
}

// 删除钥匙串里的数据
+ (BOOL)deletePasswordForService:(NSString *)serviceName account:(NSString *)account
{
    if (!serviceName || !account) return NO;
    OSStatus status = -1001;
    NSMutableDictionary *query = [self getKeychainQuery:serviceName account:account];
#if TARGET_OS_IPHONE
    status = SecItemDelete((__bridge CFDictionaryRef)query);
#else
    // On Mac OS, SecItemDelete will not delete a key created in a different
    // app, nor in a different version of the same app.
    //
    // To replicate the issue, save a password, change to the code and
    // rebuild the app, and then attempt to delete that password.
    //
    // This was true in OS X 10.6 and probably later versions as well.
    //
    // Work around it by using SecItemCopyMatching and SecKeychainItemDelete.
    CFTypeRef result = NULL;
    [query setObject:@YES forKey:(__bridge id)kSecReturnRef];
    status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecSuccess) {
        status = SecKeychainItemDelete((SecKeychainItemRef)result);
        CFRelease(result);
    }
#endif
    
    if (status != errSecSuccess) {
        return NO;
    }
    
    return (status == errSecSuccess);
}

// 获取这个账号下所有的
+ (nullable NSArray<NSString *> *)serviceForAccount:(nullable NSString *)account
{
    NSMutableDictionary *query = [self getKeychainQuery:nil account:account];
    [query setObject:@YES forKey:(__bridge id)kSecReturnAttributes];
    [query setObject:(__bridge id)kSecMatchLimitAll forKey:(__bridge id)kSecMatchLimit];
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess) {
        return nil;
    }
    NSArray *serviceNameArr = (__bridge_transfer NSArray *)result;
    NSMutableArray *tmpArr = [NSMutableArray array];
    for (NSMutableDictionary *dic in serviceNameArr) {
        NSString *text = [dic valueForKey:(__bridge id)kSecAttrService];
        if (text) {
            [tmpArr addObject:text];
        }
    }
    return tmpArr;
}

+ (nullable NSArray<NSData *> *)passDataForAccount:(nullable NSString *)account
{
    NSMutableDictionary *query = [self getKeychainQuery:nil account:account];
    [query setObject:@YES forKey:(__bridge id)kSecReturnAttributes];
    [query setObject:(__bridge id)kSecMatchLimitAll forKey:(__bridge id)kSecMatchLimit];
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess) {
        return nil;
    }
    NSArray *serviceNameArr = (__bridge_transfer NSArray *)result;
    NSMutableArray *tmpArr = [NSMutableArray array];
    for (NSMutableDictionary *dic in serviceNameArr) {
        NSString *serviceName = [dic valueForKey:(id)kSecAttrService];
        NSData *data = [self passwordDataForService:serviceName account:account];
        if (data) {
            [tmpArr addObject:data];
        }
    }
    return tmpArr;
}

@end
