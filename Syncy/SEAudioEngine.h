//
//  SEAudioEngine.h
//  The Spectacular Sync Engine
//
//  Created by Michael Tyson on 31/12/2014.
//  Copyright (c) 2015 A Tasty Pixel. All rights reserved.
//

@import Foundation;
@import AudioToolbox;

typedef void (*SEAudioEngineRenderCallback)(__unsafe_unretained id playable, const AudioTimeStamp *time, AudioBufferList *ioData, UInt32 inNumberFrames);

@protocol SEAudioEngineAudioProvider <NSObject>
@property (nonatomic, readonly) SEAudioEngineRenderCallback renderCallback;
@end

@interface SEAudioEngine : NSObject
-(instancetype)initWithAudioProvider:(id<SEAudioEngineAudioProvider>)provider;

-(BOOL)start;
-(BOOL)stop;
@end

