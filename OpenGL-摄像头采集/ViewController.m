//
//  ViewController.m
//  OpenGL-摄像头采集
//
//  Created by mac on 2020/2/28.
//  Copyright © 2020 cc. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "openGLManager.h"
#import "ccCollectionView.h"
#import "ccCollectionViewCell.h"

@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate>

@property (strong, nonatomic) AVCaptureDeviceInput       *cameraInput;//摄像头输入
@property (strong, nonatomic) AVCaptureDeviceInput       *audioMicInput;//麦克风输入
@property (strong, nonatomic) AVCaptureSession           *recordSession;//捕获视频的会话
@property (copy  , nonatomic) dispatch_queue_t           captureQueue;//录制的队列
@property (strong, nonatomic) AVCaptureConnection        *audioConnection;//音频录制连接
@property (strong, nonatomic) AVCaptureConnection        *videoConnection;//视频录制连接
@property (strong, nonatomic) AVCaptureVideoDataOutput   *videoOutput;//视频输出
@property (strong, nonatomic) AVCaptureAudioDataOutput   *audioOutput;//音频输出


@property (atomic, assign) BOOL isCapturing;//正在录制
@property (atomic, assign) CGFloat currentRecordTime;//当前录制时间

@property (nonatomic,strong) openGLManager *glManager;


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
        
    self.glManager = [[openGLManager alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:self.glManager];
    
    [self recordSession];
    [self sessionLayerRunning];
    
    [self initCollectionView];
}

-(void)initCollectionView{
    
    
    NSString *jsonPath = [[NSBundle mainBundle] pathForResource:@"filter.json" ofType:nil];
    NSData *jsonData = [[NSFileManager defaultManager] contentsAtPath:jsonPath];
    NSArray *jsonArray = [NSJSONSerialization JSONObjectWithData:jsonData options:1 error:nil];
    
    ccCollectionView* _collectionView = [[ccCollectionView alloc] initCollectionViewWithItemClass:[ccCollectionViewCell class] headClass:nil footClass:nil];
    _collectionView.frame = CGRectMake(0, self.view.frame.size.height - 100, self.view.frame.size.width, 100);
    
    _collectionView.cc_sizeForItemAtIndexPath(^CGSize(UICollectionViewLayout * _Nonnull layout, NSIndexPath * _Nonnull indexPath) {
        
        return CGSizeMake(40, 40);
        
    }).cc_CollectionDidSelectRowAtIndexPath(^(NSIndexPath * _Nonnull indexPath, UICollectionView * _Nonnull collectionView) {
        
        NSString* name = jsonArray[indexPath.item][@"filter"];
        [self.glManager setupFilter:name];
        
    }).cc_CollectionNumberOfRows(^NSInteger(NSInteger section, UICollectionView * _Nonnull collectionView) {
        return jsonArray.count;
    }).cc_CollectionViewForCell(^UICollectionViewCell * _Nonnull(NSIndexPath * _Nonnull indexPath, UICollectionView * _Nonnull collectionView) {
        ccCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:NSStringFromClass([ccCollectionViewCell class]) forIndexPath:indexPath];
        cell.label.text = jsonArray[indexPath.item][@"title"];
        return cell;
    });
    [self.view addSubview:_collectionView];
}

- (void)sessionLayerRunning{
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self.recordSession isRunning]) {
            [self.recordSession startRunning];
        }
    });
}

- (void)sessionLayerStop{
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.recordSession isRunning]) {
            [self.recordSession stopRunning];
        }
    });
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    
    if (connection == self.videoConnection) {
        CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        [self.glManager renderBuffer:pixelBuffer];
    }
}

//捕获视频的会话
- (AVCaptureSession *)recordSession {
    if (_recordSession == nil) {
        _recordSession = [[AVCaptureSession alloc] init];
        //添加后置摄像头的输出
        if ([_recordSession canAddInput:self.cameraInput]) {
            [_recordSession addInput:self.cameraInput];
        }
        //添加后置麦克风的输出
        if ([_recordSession canAddInput:self.audioMicInput]) {
            [_recordSession addInput:self.audioMicInput];
        }
        //添加视频输出
        if ([_recordSession canAddOutput:self.videoOutput]) {
            [_recordSession addOutput:self.videoOutput];
        }
        //添加音频输出
        if ([_recordSession canAddOutput:self.audioOutput]) {
            [_recordSession addOutput:self.audioOutput];
        }
        
        //设置视频录制的方向
        self.videoConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
        
        //分辨率
        if ([self.recordSession canSetSessionPreset:AVCaptureSessionPreset1280x720]){
            self.recordSession.sessionPreset = AVCaptureSessionPreset1280x720;
        }
        
        //自动白平衡
        if ([self.cameraInput.device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeAutoWhiteBalance]) {
            [self.cameraInput.device setWhiteBalanceMode:AVCaptureWhiteBalanceModeAutoWhiteBalance];
        }
        
    }
    return _recordSession;
}

//摄像头设备
- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position {
    //返回和视频录制相关的所有默认设备
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    //遍历这些设备返回跟position相关的设备
    for (AVCaptureDevice *device in devices) {
        if ([device position] == position) {
            return device;
        }
    }
    return nil;
}

//摄像头输入
- (AVCaptureDeviceInput *)cameraInput {
    if (_cameraInput == nil) {
        NSError *error;
        _cameraInput = [[AVCaptureDeviceInput alloc] initWithDevice:[self cameraWithPosition:AVCaptureDevicePositionBack] error:&error];
    }
    return _cameraInput;
}

//麦克风输入
- (AVCaptureDeviceInput *)audioMicInput {
    if (_audioMicInput == nil) {
        AVCaptureDevice *mic = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
        NSError *error;
        _audioMicInput = [AVCaptureDeviceInput deviceInputWithDevice:mic error:&error];
    }
    return _audioMicInput;
}


//录制的队列
- (dispatch_queue_t)captureQueue {
    if (_captureQueue == nil) {
        _captureQueue = dispatch_queue_create(0, 0);
    }
    return _captureQueue;
}

//视频输出
//kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange格式 无法渲染 使用
- (AVCaptureVideoDataOutput *)videoOutput {
    if (!_videoOutput) {
        _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
        [_videoOutput setSampleBufferDelegate:self queue:self.captureQueue];
        NSDictionary* setcapSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithInt:kCVPixelFormatType_32BGRA], kCVPixelBufferPixelFormatTypeKey,
                                        nil];
        _videoOutput.videoSettings = setcapSettings;
        _videoOutput.alwaysDiscardsLateVideoFrames = YES;
    }
    return _videoOutput;
}

//音频输出
- (AVCaptureAudioDataOutput *)audioOutput {
    if (_audioOutput == nil) {
        _audioOutput = [[AVCaptureAudioDataOutput alloc] init];
        [_audioOutput setSampleBufferDelegate:self queue:self.captureQueue];
    }
    return _audioOutput;
}

//视频连接
- (AVCaptureConnection *)videoConnection {
    if (!_videoConnection) {
        _videoConnection = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
    }
    return _videoConnection;
}

//音频连接
- (AVCaptureConnection *)audioConnection {
    if (_audioConnection == nil) {
        _audioConnection = [self.audioOutput connectionWithMediaType:AVMediaTypeAudio];
    }
    return _audioConnection;
}

@end
