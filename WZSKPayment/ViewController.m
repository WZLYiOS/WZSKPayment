//
//  ViewController.m
//  WZSKPayment
//
//  Created by 牛胖胖 on 2019/7/9.
//  Copyright © 2019 我主良缘. All rights reserved.
//

#import "ViewController.h"
#import "WZSKPaymentStore.h"
@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(100,100 , 50, 50);
    btn.backgroundColor = [UIColor redColor];
    [btn addTarget:self action:@selector(btnAction) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btn];
}

- (void)btnAction{
}

@end
