//
//  DSAudioEngine.h
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 31/12/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

@import Foundation;
@import AudioToolbox;

typedef void (*DSAudioEngineRenderCallback)(__unsafe_unretained id playable, const AudioTimeStamp *time, AudioBufferList *ioData, UInt32 inNumberFrames);

@protocol DSAudioEngineAudioProvider <NSObject>
@property (nonatomic, readonly) DSAudioEngineRenderCallback renderCallback;
@end

@interface DSAudioEngine : NSObject
-(instancetype)initWithAudioProvider:(id<DSAudioEngineAudioProvider>)provider;

-(BOOL)start;
-(BOOL)stop;
@end

