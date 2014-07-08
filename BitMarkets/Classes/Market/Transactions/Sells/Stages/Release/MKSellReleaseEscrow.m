//
//  MKSellReleaseEscrow.m
//  BitMarkets
//
//  Created by Steve Dekorte on 5/6/14.
//  Copyright (c) 2014 voluntary.net. All rights reserved.
//

#import "MKSellReleaseEscrow.h"
#import "MKSell.h"
#import <BitnashKit/BitnashKit.h>
#import "MKRootNode.h"

@implementation MKSellReleaseEscrow

- (id)init
{
    self = [super init];
    
    self.nodeViewClass = NavMirrorView.class;
    
    NavActionSlot *slot = [self.navMirror newActionSlotWithName:@"acceptRefundRequest"];
    [slot setVisibleName:@"Send Refund"];
    
    return self;
}

- (void)updateActions
{
    BOOL enabled = self.buyRequestRefundMsg != nil && !self.sellAcceptRefundRequestMsg;
    
    NavActionSlot *slot = [self.navMirror newActionSlotWithName:@"acceptRefundRequest"];
    [slot setIsActive:enabled];
    [slot setIsVisible:enabled];
}

- (NSString *)nodeSubtitle
{
    // note: that buyer posts to blockchain
    
    if (self.buyRequestRefundMsg)
    {
        if(self.sellAcceptRefundRequestMsg)
        {
            if (self.sellRejectRefundRequestMsg)
            {
                return @"Rejected refund request.";
            }
            
            if (self.confirmRefundMsg)
            {
                return @"Refunded buyer.";
            }
            else
            {
                return @"Refund sent, awaiting confirm.";
            }
        }
        
        return @"Buyer requests refund.";
    }
    
    if (self.buyPaymentMsg)
    {
        if(self.sellAcceptPaymentMsg)
        {
            if (self.confirmPaymentMsg)
            {
                return @"Buyer payment confirmed. Transaction complete.";
            }
            
            return @"Buyer payment signed. Awaiting confirmation.";
        }
        
        return @"Buyer initiated payment.";
    }
    
    if (self.isActive)
    {
        return @"Waiting for buyer to make payment or request refund.";
    }
    
    if (self.sell.isCanceled)
    {
        return nil;
    }
    
    if (!self.runningWallet)
    {
        return @"Waiting for wallet...";
    }
    
    return nil;
}

- (BOOL)isActive
{
    if (!self.sell.delivery.isComplete)
    {
        return NO;
    }
    
    return self.sell.lockEscrow.isComplete && !self.isComplete;
    //return (self.buyPaymentMsg || self.buyRequestRefundMsg) && !self.isComplete;
}

- (BOOL)isComplete
{
    return (self.confirmPaymentMsg || self.confirmRefundMsg);
}

- (NSString *)nodeNote
{
    if (self.isComplete)
    {
        return @"✓";
    }
    
    if (self.isActive)
    {
        return @"●";
    }
    
    /*
     if (self.wasRejected)
     {
     return @"✗";
     }
     */
    
    return nil;
}

// actions

- (NSArray *)modelActions
{
    return @[];
}

// update

- (BOOL)handleMsg:(MKMsg *)msg
{
    if ([msg isKindOfClass:MKBuyPaymentMsg.class] ||
        [msg isKindOfClass:MKBuyRefundRequestMsg.class])
    {
        [self addChild:msg];
        [self update];
        [self updateActions];
        [self postParentChainChanged];
        return YES;
    }
    
    return NO;
}

- (void)update
{
    if (self.buyPaymentMsg && !self.sellAcceptPaymentMsg)
    {
        [self acceptPayment];
    }
    
    if (self.buyRequestRefundMsg)
    {
        // refund action is available and
        // user must use it to refund
    }
    
    [self lookForConfirmsIfNeeded];
    [self updateActions];
}



// actions

- (void)acceptPayment // automatic
{
    BNWallet *wallet = self.runningWallet;
    
    if (!wallet)
    {
        return;
    }
    
    BNTx *escrowTx = [self.sell.lockEscrow.payloadToConfirm asObjectFromJSONObject];
    
    BNTx *releaseTx = [self.buyPaymentMsg.payload asObjectFromJSONObject];
    releaseTx.wallet = wallet;
    
    [releaseTx addPayToAddressOutputWithValue:[NSNumber numberWithLongLong:2*escrowTx.firstOutput.value.longLongValue/3]];
    
    [releaseTx subtractFee];
    [releaseTx sign];
    
    MKSellAcceptPaymentMsg *msg = [[MKSellAcceptPaymentMsg alloc] init];
    [msg copyThreadFrom:self.sell.acceptedBidMsg];
    [msg setPayload:releaseTx.asJSONObject];
    [self addChild:msg];
    [msg sendToBuyer];
    [self postSelfChanged];
    [self postParentChainChanged];
}

- (void)acceptRefundRequest
{
    BNWallet *wallet = self.runningWallet;
    
    if (!wallet)
    {
        return;
    }
    
    BNTx *escrowTx = [self.sell.lockEscrow.payloadToConfirm asObjectFromJSONObject];
    
    BNTx *refundTx = [self.buyRequestRefundMsg.payload asObjectFromJSONObject];
    refundTx.wallet = wallet;
    
    [refundTx addPayToAddressOutputWithValue:[NSNumber numberWithLongLong:escrowTx.firstOutput.value.longLongValue/3]];
    
    [refundTx subtractFee];
    [refundTx sign];
    
    MKSellAcceptRefundRequestMsg *msg = [[MKSellAcceptRefundRequestMsg alloc] init];
    [msg copyThreadFrom:self.sell.acceptedBidMsg];
    [msg setPayload:refundTx.asJSONObject];
    [self addChild:msg];
    [msg sendToBuyer];
    [self postSelfChanged];
    [self postParentChainChanged];
    [self updateActions];
}

- (void)rejectRefund
{
    BNWallet *wallet = self.runningWallet;
    
    if (!wallet)
    {
        return;
    }
    
    MKSellRejectRefundRequestMsg *msg = [[MKSellRejectRefundRequestMsg alloc] init];
    [msg copyThreadFrom:self.sell.acceptedBidMsg];
    [self addChild:msg];
    [msg sendToBuyer];
    [self postParentChainChanged];
}


@end
