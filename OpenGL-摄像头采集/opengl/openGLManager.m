//
//  openGLManager.m
//  录制+拍照+二维码
//
//  Created by mac on 2020/2/27.
//  Copyright © 2020 cc. All rights reserved.
//

#import "openGLManager.h"
#import <GLKit/GLKit.h>
#import <OpenGLES/ES3/glext.h>


@interface openGLManager (){
    // 渲染缓冲区、帧缓冲区对象
    GLuint renderBuffer, frameBuffer;
    //缓冲宽高
    GLint backingWidth, backingHeight;

    CVOpenGLESTextureRef texture;

    CVOpenGLESTextureCacheRef textureCache;//视频缓冲区
    
    //着色器数据
    GLuint positionSlot,textureSlot,textureCoordSlot;
    
    GLuint         vertShader, fragShader;
    
    NSMutableArray  *attributes;
    NSMutableArray  *uniforms;

}

@property (nonatomic, strong) EAGLContext *context;

@property (nonatomic, strong) CAEAGLLayer* myLayer;

// 开始的时间戳
@property (nonatomic, assign) NSTimeInterval startTimeInterval;
// 着色器程序
@property (nonatomic, assign) GLuint program;
// 顶点缓存
@property (nonatomic, assign) GLuint vertexBuffer;
// 纹理 ID
@property (nonatomic, assign) GLuint textureID;

@property(readwrite, copy, nonatomic) NSString *vertexShaderLog;
@property(readwrite, copy, nonatomic) NSString *fragmentShaderLog;

@end

@implementation openGLManager

+ (Class)layerClass {
    return [CAEAGLLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self initFilter];
    }
    return self;
}

- (void)initFilter{
    [self setupContext];
    [self setupLayer];
    [self setupCoreVideoTextureCache];
    [self loadShaders:@"Normal"];
    [self bindRender];
}

- (void)setupFilter:(NSString*)filterName{
    [self loadShaders:filterName];
}

- (void)renderBuffer:(CVPixelBufferRef)pixelBuffer {
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    if ([EAGLContext currentContext] != self.context) {
        [EAGLContext setCurrentContext:self.context];
    }
    
    glUseProgram(self.program);

    [self setDisplayFramebuffer];
    
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    
    [self cleanUpTexture];
    
    glActiveTexture(GL_TEXTURE4);
    // Create a CVOpenGLESTexture from the CVImageBuffer
    size_t frameWidth = CVPixelBufferGetWidth(pixelBuffer);
    size_t frameHeight = CVPixelBufferGetHeight(pixelBuffer);
    CVReturn ret = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                textureCache,
                                                                pixelBuffer,
                                                                NULL,
                                                                GL_TEXTURE_2D,
                                                                GL_RGBA,
                                                                (GLsizei)frameWidth,
                                                                (GLsizei)frameHeight,
                                                                GL_BGRA,
                                                                GL_UNSIGNED_BYTE,
                                                                0,
                                                                &texture);
    if (ret) {
        NSLog(@"CVOpenGLESTextureCacheCreateTextureFromImage ret: %d", ret);
    }
    glBindTexture(CVOpenGLESTextureGetTarget(texture), CVOpenGLESTextureGetName(texture));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glUniform1i(textureSlot, 4);


    static const GLfloat imageVertices[] = {
        -1.0f, -1.0f,
        1.0f, -1.0f,
        -1.0f,  1.0f,
        1.0f,  1.0f,
    };
    
    static const GLfloat noRotationTextureCoordinates[] = {
        0.0f, 1.0f,
        1.0f, 1.0f,
        0.0f, 0.0f,
        1.0f, 0.0f,
    };
    
    glVertexAttribPointer(positionSlot, 2, GL_FLOAT, 0, 0, imageVertices);
    glVertexAttribPointer(textureCoordSlot, 2, GL_FLOAT, 0, 0, noRotationTextureCoordinates);
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    [self presentFramebuffer];
        
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
}

- (void)destroyDisplayFramebuffer {
    if ([EAGLContext currentContext] != self.context) {
        [EAGLContext setCurrentContext:self.context];
    }
    
    if (frameBuffer) {
        glDeleteFramebuffers(1, &frameBuffer);
        frameBuffer = 0;
    }
    
    if (renderBuffer) {
        glDeleteRenderbuffers(1, &renderBuffer);
        renderBuffer = 0;
    }
}

- (void)cleanUpTexture {
    if(texture) {
        CFRelease(texture);
        texture = NULL;
    }
    CVOpenGLESTextureCacheFlush(textureCache, 0);
}

- (void)setDisplayFramebuffer {
    if (!frameBuffer) {
        [self bindRender];
    }
    glBindFramebuffer(GL_FRAMEBUFFER, frameBuffer);
    glViewport(0, 0, backingWidth, backingHeight);
}

- (void)presentFramebuffer {
    glBindRenderbuffer(GL_RENDERBUFFER, renderBuffer);
    
    [self.context presentRenderbuffer:GL_RENDERBUFFER];
}

//渲染上下文
- (void)setupContext{
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (!self.context) {
        self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    }
    
    [EAGLContext setCurrentContext:self.context];
}
//设置图层(CAEAGLLayer)
- (void)setupLayer{
    
    self.contentScaleFactor = [[UIScreen mainScreen] scale];
    self.myLayer = (CAEAGLLayer *)self.layer;
    self.myLayer.opaque = YES; //CALayer默认是透明的，透明的对性能负荷大，故将其关闭
    self.myLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                   // 由应用层来进行内存管理
                                   @(NO),kEAGLDrawablePropertyRetainedBacking,
                                   kEAGLColorFormatRGBA8,kEAGLDrawablePropertyColorFormat,
                                   nil];
        
}
//视频纹理渲染的高效纹理缓冲区
- (void)setupCoreVideoTextureCache
{
    CVReturn result = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, self.context, NULL, &textureCache);
    if (result != kCVReturnSuccess) {
        NSLog(@"CVOpenGLESTextureCacheCreate fail %d",result);
    }
    
}
//绑定渲染缓冲区
- (void)bindRender{
    
    if ([EAGLContext currentContext] != self.context) {
        [EAGLContext setCurrentContext:self.context];
    }
    
    glGenFramebuffers(1, &frameBuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, frameBuffer);
    
    glGenRenderbuffers(1, &renderBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, renderBuffer);
    
    [self.context renderbufferStorage:GL_RENDERBUFFER fromDrawable:self.myLayer];
    
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &backingHeight);
    
    if ( (backingWidth == 0) || (backingHeight == 0) ) {
        NSLog(@"Backing width: 0 || height: 0");

        [self destroyDisplayFramebuffer];
        return;
    }
    
    NSLog(@"Backing width: %d, height: %d", backingWidth, backingHeight);
    
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, renderBuffer);
    
}

//设置默认着色器
- (void)loadShaders:(NSString*)shaderFilename{
    if ([EAGLContext currentContext] != self.context) {
        [EAGLContext setCurrentContext:self.context];
    }
    
    
    self.program = glCreateProgram();
    attributes = [[NSMutableArray alloc] init];
    uniforms = [[NSMutableArray alloc] init];
    
    NSString *vertShaderPathname = [[NSBundle mainBundle] pathForResource:shaderFilename ofType:@"vsh"];
    NSString *vertexShaderString = [NSString stringWithContentsOfFile:vertShaderPathname encoding:NSUTF8StringEncoding error:nil];

    NSString *fragShaderPathname = [[NSBundle mainBundle] pathForResource:shaderFilename ofType:@"fsh"];
    NSString *fragmentShaderString = [NSString stringWithContentsOfFile:fragShaderPathname encoding:NSUTF8StringEncoding error:nil];

    if (![self compileShader:&vertShader type:GL_VERTEX_SHADER string:vertexShaderString]) {
        NSLog(@"Failed to compile vertex shader");
    }
    
    // Create and compile fragment shader
    if (![self compileShader:&fragShader  type:GL_FRAGMENT_SHADER string:fragmentShaderString]) {
        NSLog(@"Failed to compile fragment shader");
    }
    
    glAttachShader(self.program, vertShader);
    glAttachShader(self.program, fragShader);
    
    [self addAttribute:@"Position"];
    [self addAttribute:@"textureCoordinate"];
    
    if (![self link]) {
        NSString *fragLog = [self fragmentShaderLog];
        NSLog(@"Fragment shader compile log: %@", fragLog);
        NSString *vertLog = [self vertexShaderLog];
        NSLog(@"Vertex shader compile log: %@", vertLog);
        NSAssert(NO, @"Filter shader link failed");
    }
    
    positionSlot = [self attributeIndex:@"Position"];
    textureCoordSlot = [self attributeIndex:@"textureCoordinate"];
    textureSlot = [self uniformIndex:@"Texture"]; // This does assume a name of "inputTexture" for the fragment shader
    
    glUseProgram(self.program);

    glEnableVertexAttribArray(positionSlot);
    glEnableVertexAttribArray(textureCoordSlot);
}

- (GLuint)attributeIndex:(NSString *)attributeName {
    return (GLuint)[attributes indexOfObject:attributeName];
}
- (GLuint)uniformIndex:(NSString *)uniformName {
    return glGetUniformLocation(self.program, [uniformName UTF8String]);
}

- (BOOL)link {

    GLint status;
    glLinkProgram(self.program);
    glGetProgramiv(self.program, GL_LINK_STATUS, &status);
    if (status == GL_FALSE)
        return NO;
    
    if (vertShader) {
        glDeleteShader(vertShader);
        vertShader = 0;
    }
    if (fragShader) {
        glDeleteShader(fragShader);
        fragShader = 0;
    }
    return YES;
}

- (void)addAttribute:(NSString *)attributeName {
    if (![attributes containsObject:attributeName]) {
        [attributes addObject:attributeName];
        glBindAttribLocation(self.program, (GLuint)[attributes indexOfObject:attributeName], [attributeName UTF8String]);
    }
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type string:(NSString *)shaderString {
//    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();

    GLint status;
    const GLchar *source;
    
    source = (GLchar *)[shaderString UTF8String];
    if (!source) {
        NSLog(@"Failed to load vertex shader");
        return NO;
    }
    
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
    
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);

    if (status != GL_TRUE) {
        GLint logLength;
        glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
        if (logLength > 0) {
            GLchar *log = (GLchar *)malloc(logLength);
            glGetShaderInfoLog(*shader, logLength, &logLength, log);
            if (shader == &vertShader) {
                self.vertexShaderLog = [NSString stringWithFormat:@"%s", log];
            } else {
                self.fragmentShaderLog = [NSString stringWithFormat:@"%s", log];
            }

            free(log);
        }
    }
    return status == GL_TRUE;
}

@end
