//
//  openGLManager.h
//  录制+拍照+二维码
//
//  Created by mac on 2020/2/27.
//  Copyright © 2020 cc. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface openGLManager : UIView

+(instancetype)initWithFilterView:(UIView*)filterView;
//设置滤镜
- (void)setupFilter:(NSString*)filterName;
//渲染
- (void)renderBuffer:(CVPixelBufferRef)pixelBuffer;

@end

NS_ASSUME_NONNULL_END
