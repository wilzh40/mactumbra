//
//  ScreenColor.h
//  Antumbra
//
//  Created by Nick Peretti on 8/13/14.
//  Copyright (c) 2014 Antumbra. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GPUImage/GPUImage.h>
#import "AGlow.h"


extern NSString * const kScreenDidFinishProcessingNotification;

@interface ScreenColor : NSObject


+(void)colorFromRect:(NSRect)rect;
+(void)augmentColorFromRect:(NSRect)rect;

+(float)width;
+(float)height;


//(;
@end
