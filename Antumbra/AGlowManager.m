//
//  AGlowManager.m
//  Antumbra
//
//  Created by Nicholas Peretti on 2/18/15.
//  Copyright (c) 2015 Antumbra. All rights reserved.
//

#import "AGlowManager.h"

static vDSP_Length const FFTViewControllerFFTWindowSize = 4096;

@implementation AGlowManager{
    AnCtx *context;
    BOOL mirroring;
    BOOL canMirror;
    NSTimer *timer;
    AGlowFade *currentFade;
    AVAudioRecorder *recorder;
    NSTimer *levelTimer;
    double lowPassResults;
    double amplitudes[43];
}

@synthesize glows;
@synthesize targetFPS;

-(instancetype)init{
    self = [super init];
    if (self) {
        mirroring =NO;
        canMirror =YES;
        glows = [[NSMutableArray alloc]init];
        targetFPS = 30.0;
        currentFade = nil;
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(stopedMirroring) name:@"doneMirroring" object:nil];
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(fadeTick) name:@"fadeTick" object:nil];
        
        // Meter audio
        [self setupAudio];
        levelTimer = [NSTimer scheduledTimerWithTimeInterval: 0.01 target: self selector: @selector(meterAudio) userInfo: nil repeats: YES];
        
        
        [self scanForGlows];
        
    }
    return self;
}




- (void)setupAudio

{
    /*
    NSURL *url = [NSURL fileURLWithPath:@"/dev/null"];
    
    NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithFloat: 44100.0],                 AVSampleRateKey,
                              [NSNumber numberWithInt: kAudioFormatAppleLossless], AVFormatIDKey,
                              [NSNumber numberWithInt: 1],                         AVNumberOfChannelsKey,
                              [NSNumber numberWithInt: AVAudioQualityMax],         AVEncoderAudioQualityKey,
                              nil];
    
    NSError *error;
    
    recorder = [[AVAudioRecorder alloc] initWithURL:url settings:settings error:&error];
    
    if (recorder) {
        [recorder prepareToRecord];
        recorder.meteringEnabled = YES;
        [recorder record];
    } else
        NSLog([error description]);
     */
    self.microphone = [EZMicrophone microphoneWithDelegate:self];
    self.microphone.microphoneOn = YES;
    //EZAudioDevice *currentOutputDevice = [EZAudioDevice currentOutputDevice];
    [self.microphone setDevice:[[EZAudioDevice inputDevices] firstObject]];
    self.fft = [EZAudioFFTRolling fftWithWindowSize:FFTViewControllerFFTWindowSize
                                         sampleRate:[EZMicrophone sharedMicrophone].audioStreamBasicDescription.mSampleRate
                                           delegate:self];
    [self.microphone startFetchingAudio];

    
    
}

-(void)   microphone:(EZMicrophone *)microphone
    hasAudioReceived:(float **)buffer
      withBufferSize:(UInt32)bufferSize
withNumberOfChannels:(UInt32)numberOfChannels
{
    __weak typeof (self) weakSelf = self;
    [self.fft computeFFTWithBuffer:buffer[0] withBufferSize:bufferSize];

    // Getting audio data as an array of float buffer arrays that can be fed into the
    // EZAudioPlot, EZAudioPlotGL, or whatever visualization you would like to do with
    // the microphone data.
    dispatch_async(dispatch_get_main_queue(),^{
        // Visualize this data brah, buffer[0] = left channel, buffer[1] = right channel
        //[weakSelf.audioPlot updateBuffer:buffer[0] withBufferSize:bufferSize];
    });
}

- (void)        fft:(EZAudioFFT *)fft
 updatedWithFFTData:(float *)fftData
         bufferSize:(vDSP_Length)bufferSize
{
    
    __weak typeof (self) weakSelf = self;
    float factor = 100000;
    float averageBass = 0;
    for (int i = 0; i < bufferSize/3; i++) {
        averageBass += fftData[i]/bufferSize/3*factor;
    }
    
    double peakPowerForChannel =  averageBass;//[recorder peakPowerForChannel:0];//pow(10, (0.05 * [recorder peakPowerForChannel:1]));
    int frameSize = 43;
    double average = 0;
    double threshold = 1.3;
    bool filled = true;
    
    //double amplitudes[43];
    //shift all
    
    for (int i = frameSize; i >= 1; i--) {
        amplitudes[i] = amplitudes [i-1];
        if (amplitudes[i] == 0)
            false;
    }
    amplitudes[0] = peakPowerForChannel;
    
    if (filled) {
        
        for (int i = 1; i < frameSize; i++) {
            average += amplitudes[i]/frameSize;
            
        }
        if (peakPowerForChannel > average*threshold) {
            // [self brightness: peakPowerForChannel];
            [self brightness:1];
            
        } else {
            [self brightness:0.1];
        }
    }
    
    
    
    NSLog(@"Current input: %f Average: %f Low pass results: %f", averageBass, average, threshold);
    
}

- (void)scanForGlows
{
    for (AGlow *g in glows) {
        AnDevice_Close(g.context, g.device);
    }
    
    [glows removeAllObjects];
    if (context) {
        AnCtx_Deinit(context);
        context = nil;
    }
    if (AnCtx_Init(&context)) {
        fputs("ctx init failed\n", stderr);
    }
    AnDeviceInfo **devs;
    size_t nDevices;
    
    AnDevice_GetList(context, &devs, &nDevices);
    if (nDevices>=1) {
        for (int i =0; i<nDevices; i++) {
            AnDeviceInfo *inf = devs[i];
            AnDevice *newDevice;
            AnError er = AnDevice_Open(context, inf, &newDevice);
            if (er) {
                //error deal with it
                NSLog(@"%s",AnError_String(er));
            }else{
                [glows addObject:[[AGlow alloc] initWithAntumbraDevice:newDevice andContext:context]];
            }
        }
        AnDevice_FreeList(devs);
    }else{
        NSLog(@"no antumbras found");
    }
}

-(void)colorFromGlow:(AGlow *)glow{
    if (!mirroring) {
        [[NSNotificationCenter defaultCenter]postNotificationName:@"doneMirroring" object:nil];
        return;
    }
    NSLog(@"mirror");
    CGDirectDisplayID disp = (CGDirectDisplayID) [[[glow.mirrorAreaWindow.screen deviceDescription]objectForKey:@"NSScreenNumber"] intValue];
    CGImageRef first = CGDisplayCreateImageForRect(disp, glow.mirrorAreaWindow.frame);
    GPUImagePicture *pic = [[GPUImagePicture alloc]initWithCGImage:first];
    GPUImageAverageColor *average = [[GPUImageAverageColor alloc]init];
    [pic addTarget:average];
    [average setColorAverageProcessingFinishedBlock:^(CGFloat r, CGFloat g, CGFloat b, CGFloat a, CMTime time) {
        [glow updateSetColor:[NSColor colorWithRed:r green:g blue:b alpha:a] smooth:NO];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0/targetFPS * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self colorFromGlow:glow];
        });
    }];
    [pic processImage];
    CFRelease(first);
}

-(void)augmentFromGlow:(AGlow *)glow{
    if (!mirroring) {
        [[NSNotificationCenter defaultCenter]postNotificationName:@"doneMirroring" object:nil];
        return;
    }
    NSLog(@"augmenting");
    CGDirectDisplayID disp = (CGDirectDisplayID) [[[glow.mirrorAreaWindow.screen deviceDescription]objectForKey:@"NSScreenNumber"] intValue];
    CGImageRef first = CGDisplayCreateImageForRect(disp, glow.mirrorAreaWindow.frame);
    GPUImagePicture *pic = [[GPUImagePicture alloc]initWithCGImage:first];
    GPUImageSaturationFilter *sat = [[GPUImageSaturationFilter alloc]init];
    sat.saturation = 2.0;
    GPUImageAverageColor *average = [[GPUImageAverageColor alloc]init];
    [pic addTarget:sat];
    [sat addTarget:average];
    [average setColorAverageProcessingFinishedBlock:^(CGFloat r, CGFloat g, CGFloat b, CGFloat a, CMTime time) {
        [glow updateSetColor:[NSColor colorWithRed:r green:g blue:b alpha:a] smooth:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0/targetFPS * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self augmentFromGlow:glow];
        });
    }];
    [pic processImage];
    CFRelease(first);
}


-(void)balancedFromGlow:(AGlow *)glow{
    if (!mirroring) {
        [[NSNotificationCenter defaultCenter]postNotificationName:@"doneMirroring" object:nil];
        return;
    }
    NSLog(@"balanced");
    CGDirectDisplayID disp = (CGDirectDisplayID) [[[glow.mirrorAreaWindow.screen deviceDescription]objectForKey:@"NSScreenNumber"] intValue];
    CGImageRef first = CGDisplayCreateImageForRect(disp, glow.mirrorAreaWindow.frame);
    GPUImagePicture *pic = [[GPUImagePicture alloc]initWithCGImage:first];
    GPUImageSaturationFilter *sat = [[GPUImageSaturationFilter alloc]init];
    sat.saturation = 1.5;
    GPUImageAverageColor *average = [[GPUImageAverageColor alloc]init];
    [pic addTarget:sat];
    [sat addTarget:average];
    [average setColorAverageProcessingFinishedBlock:^(CGFloat r, CGFloat g, CGFloat b, CGFloat a, CMTime time) {
        
        [glow updateSetColor:[NSColor colorWithRed:r green:g blue:b alpha:a] smooth:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0/targetFPS * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self balancedFromGlow:glow];
        });
    }];
    [pic processImage];
    CFRelease(first);
}



-(void)mirror{
    [self endFading];
    if (canMirror) {
        canMirror = false;
        mirroring = true;
        for (AGlow *gl in glows) {
            gl.smoothFactor = 0.1;
            [self colorFromGlow:gl];
        }
    }else {
        mirroring = false;
    }
}
-(void)augment{
    [self endFading];
    if(canMirror){
        canMirror = false;
        mirroring = true;
        for (AGlow *gl in glows) {
            gl.smoothFactor = 0.5;
            [self augmentFromGlow:gl];
        }
    }else{
        mirroring = false;
    }
}
-(void)balance{
    [self endFading];
    if (canMirror) {
        canMirror = false;
        mirroring = true;
        for (AGlow *gl in glows) {
            gl.smoothFactor = 0.1;
            [self balancedFromGlow:gl];
        }
    }else{
        mirroring =false;
        
    }
}

-(void)stopMirroring{
    mirroring = NO;
}
-(void)stopedMirroring{
    canMirror = YES;
    
}

-(void)manualColor:(NSColor *)color{
    [self endFading];
    if (mirroring) {
        mirroring = NO;
    } else {
        for (AGlow *g in glows) {
            [g updateSetColor:color smooth:NO];
        }
    }
}

-(void)fadeBlackAndWhite{
    [self endFading];
    currentFade = [[AGlowBlackAndWhiteFade alloc]init];
    [currentFade start];
    
}
-(void)fadeHSV{
    [self endFading];
    currentFade = [[AGlowHSVFade alloc]init];
    [currentFade start];
    
}
-(void)fadeNeon{
    [self endFading];
    currentFade = [[AGlowNeonFade alloc]init];
    [currentFade start];
}
-(void)endFading{
    mirroring = false;
    if (currentFade!=nil) {
        [currentFade stop];
    }
    currentFade = nil;
}

-(void)setFadeSpeed:(int)ticksPS{
    if (currentFade!=nil) {
        [currentFade stop];
        [currentFade setTicksPerSecond:ticksPS];
        [currentFade start];
    }
}

-(void)fadeTick{
    for (AGlow *g in glows) {
        [g fadeToColor:currentFade.currentColor inTime:1.0/currentFade.ticksPerSecond];
    }
}

-(void)showWindows{
    for (AGlow *g in glows) {
        [g openWindow];
    }
}

-(void)brightness:(float)bright{
    for (AGlow *g in glows) {
        [g setMaxBrightness:bright];
        [g updateSetColor:g.currentColor smooth:NO];
    }
}


@end
