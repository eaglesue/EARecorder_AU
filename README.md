##Audio Unit详解
###本篇博客有何不同
Audio Unit（以下称AU）是iOS底层的音频框架，对于进阶开发者AU是必需掌握的框架之一，因为面向当下，掌握底层的音频框架可以让你与其他初级开发者区别开，如果面向未来，随着网络带宽的增加，音视频技术的应用范围一定会更广，应用频率也会更高。

我看了不少关于AU的技术博客，可能出于项目机密的原因，大多数只讲原理，而且只讲某一个应用方向的原理，比如录音、播放、录音同时播放，对于api的讲解也不够全面，比如同样实现录音，大多数博客讲的两种不同方式，却没有说清楚原因。对于实现功能的代码也不是很完整，大多都是从各自项目里面摘抄的部分代码，导致我们在实际使用的时候找不到完整的例子，今天这篇博客就是站在巨人的肩上，从原理到demo统统给你讲清楚，希望对你有所帮助。

###框架层级
![1.1.png](https://i.loli.net/2021/02/02/G6cxqXh7H5y4IKS.png)

从上图可见，AU处于距离硬件最近的底层，几乎就是直接和硬件打交道了，所以如果使用这一层的api，你能得到最多的自由度和最低的延迟，但副作用就是最高的复杂度，这一层的很多api不是很直观，也有的概念会出现重叠和歧义，再加上直接使用这层api的应用不多见，所以相关的资料比较少。
如果只是录音或者播放音频，完全没有必要使用AU，直接使用AVKit或者Audio Queue简单得多。
那么AU能实现哪些功能呢？或者说什么样的需求才犯得上我们直接啃AU的硬骨头呢？有这些

* 低延时同步音频输入输出，例如 VoIP 应用
* 响应回放合成声音，例如音乐游戏或合成乐器
* 使用特定的 audio unit 特征，例如回声消除，混音，色调均衡
* 处理链结构让你可以将音频处理模块组装到灵活的网络中。这是 iOS 中唯一提供此功能的音频 API。（这句话是从其他博客抄的，用人话说，就是你需要链式处理音频单元时就会用到，比如依次进行录音-回声消除-美音-混音-输出到设备）

##工作原理
这里用三个图来举例比较形象生动。

1、采集音频-播放音频

![1.2.png](https://i.loli.net/2021/02/02/W7CKPsf6gorIBkF.png)

在AU中有三个基本的Element，分别是Element0、Element1和Global（下面会说），有的地方把Element叫做bus，就是总线，很多关于Audio Unit的教程里面说的bus通常就是这玩意。

bus就是硬件管道在软件上的抽象概念，在上图中AU里面音频数据的流动被抽象为从Element1流向Element0，即从硬件话筒到APP处理，再到硬件麦克风。scope表示在一个Element上输入或输出。而APP能影响的范围，就是从Element1的output scope到Element0的input scope。
****

2、多个音频单元链式处理

![1.3.jpeg](https://i.loli.net/2021/02/02/tpFWrbmwZHKhJPv.jpg)

在AU中一个unit被称为一个音频处理单元，通常一种单元只能做一种固定的事情，比如连接硬件（remote i/o, VP i/o）、效果器(effect)、混音（mix）、转换器（Format），每种unit可能有一个或多个输入，比如remote i/o只有一个输入， mix可有多个输入，但每种unit通常只有一个输出。

多个unit可以并行或串行进行处理，上图中就是两个效果器unit（EQ unit）的输出连接到一个混音unit（Mixer unit）的输入上，最后输出到硬件（I/O unit）。
****

3、音频数据控制流

![1.4.png](https://i.loli.net/2021/02/02/P9adzGRjpLb8yxS.png)

在实际处理音频数据时，音频数据虽然是按照顺序在处理链中流动，但数据控制流却是相反的，有点像Cocoa Touch中事件传递链和响应链的关系，这么说大概懂了吧。

举个栗子，考试的时候学霸坐在第一排，后边的都是学渣，最后一排的学渣想要小抄就去问前面一排的学渣，前面一排的学渣说我也没有，又去问再前一排的学渣，直到问到第一排的学霸，学霸才把答案写好往后传，每一排的学渣抄一遍答案后就把小抄往下传，直到最后一名学渣得到答案。

真实的流程就是这样，当启动每个unit后，每个unit都在等待获取数据，于是可以在回调函数中调用AudioUnitRender，来向上一级unit申请数据（上一级unit的回调函数就会响应），就算你不使用AudioUnitRender，系统也会根据Unit的连接顺序pull上一个unit的输出。如果上一级也没有，再向上一级申请。当第一级unit处理好数据后，就把数据从当前Unit的output输出，这样下一级unit就可以继续处理了。


****

### 数字信号基础知识

1、信号的编码与解码

编码过程-信号的数字化

![1.5.jpeg](https://i.loli.net/2021/02/02/NfM8EL6sqRnu1wp.jpg)

<center>图1.5</center>

信号的数字化就是将连续的模拟信号转换成离散的数字信号， 一般需要完成采样、量化和编码三个步骤，如图 1.5 所示。采样是指用每隔一定时间间隔的信号样本值序列来代替原来在时间上连续的信号。量化是用有限个幅度近似表示原来在时间上连续变化的幅度值，把模拟信号的连续幅度变为有限数量、有一定时间间隔的离散值。编码则是按照一定的规律，把量化后的离散值用二进制数码表示。上述数字化的过程又称为脉冲编码调制(Pulse Code Modulation) ，通常由 A/D 转换器来实现。
****

解码过程
音频解码及编码的逆过程，通过使用与编码方式对应的解码器，对数字信号进行模拟化。

数字信号编解码的特有难点在于压缩算法，压缩算法决定了带宽的利用率、声音的还原程度和延迟等，这里会根据具体的应用场景去静态或动态地选择不同的压缩算法，即选择不同的音频格式。由于篇幅有限，这里涵盖的内容又很多，等我研究清楚了再展开讨论。
****

###Audio Unit的基本使用方法

与AU相关的api通常有两套，一套是直接使用Audio Unit，另一套是使用AUGraph，但是AUGraph已经被声明为Deprecated，目前主推的是AudioEngine，AudioEngine位于AVFoundation中，用起来像是被封装过的AUGraph，本文仅讨论Audio Unit的使用方法。

AU的使用步骤大概是这样：

* 创建需要的Unit
* 给每个Unit设置对应的属性，声明每个Unit的output格式
* 初始化Unit
* 开启Unit
* 关闭Unit

AU包含的Unit有7种：

1. Effect - iPod Equalizer 效果器，比如均衡、延迟、回响等
1. Mixing - 3D Mixer 和OpenAl相关的混音
1. Mixing - Multichannel Mixer 多路混音，我们一般用这个
1. I/O - Remote I/O 连接硬件的io
1. I/O - Voice-Processing I/O 在硬件io的基础上增加了回声消除、自动增益校正、语音质量调整、静音等功能
1. I/O - Generic Output 脱离音频硬件的io通道，可以从文件中获取音频源
1. Format conversion - Format Converter 格式转换。注意了，变调timePitch是这个类型里面的子类

每种Unit可用的属性都不同，但是这些属性的名字又都在一个Enum里面，用的时候要小心，建议先了解清楚你需要的每种Unit的用法。
****

###撸起袖子开始写demo

接下来会先分析Audio Unit中的各种api，完整的Demo在最后面。

#### 使用Audio Unit实现录音耳返
使用AU进行录音有两种方式，一、直接使用Audio Unit，二、使用AUGraphic连接音频输入输出单元。这里我们分开讲，但是他们有些共同的地方。

##### 一、直接使用Audio Unit
1.设置AudioSession

```c
func setupAudioSession() {
        let session: AVAudioSession = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.overrideOutputAudioPort(.none)
            try session.setPreferredSampleRate(Double(AudioConst.SampleRate))
            //每次处理的buffer大小
            try session.setPreferredIOBufferDuration(Double(AudioConst.BufferDuration) / 1000.0)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch  {
            print(error.localizedDescription)
        }
    }
```

2.创建ioUnit

```c
var ioDes: AudioComponentDescription = AudioComponentDescription.init(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_RemoteIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0)
        guard let inputComp: AudioComponent = AudioComponentFindNext(nil, &ioDes) else {
            print("outputComp init error")
            return false
        }
        if AudioComponentInstanceNew(inputComp, &ioUnit) != noErr {
            print("io AudioComponentInstanceNew error")
            return false
        }
```

3.设置ioUnit参数

```c
//是否打开输入、输出
var value: UInt32 = 1
        if AudioUnitSetProperty(self.ioUnit!, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, AudioConst.InputBus, &value, UInt32(MemoryLayout.size(ofValue: value))) != noErr {
            print("can't enable input io")
            return false
        }
        
        value = 1 //如果不需要从硬件输出 就把value设置为0
        if AudioUnitSetProperty(self.ioUnit!, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, AudioConst.OutputBus, &value, UInt32(MemoryLayout.size(ofValue: value))) != noErr {
            print("can't enable output io")
            return false
        }
        
        //设置最大切片，就是连接两个unit的管道有多粗，这个参数和第一步setPreferredIOBufferDuration的大小有关，太小的话会报错，最好设置大一些，
        var maxSlice: Int32 = 4096
        if AudioUnitSetProperty(self.ioUnit!, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, AudioConst.OutputBus, &maxSlice, UInt32(MemoryLayout.size(ofValue: maxSlice))) != noErr {
            print("set MaximumFramesPerSlice error")
            return false
        }
        
        //设置Unit输出格式
        var ioFormat: AudioStreamBasicDescription = AudioStreamBasicDescription.init(
            mSampleRate: Float64(AudioConst.SampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket:  UInt32(2 * AudioConst.Channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(2 * AudioConst.Channels),
            mChannelsPerFrame: UInt32(AudioConst.Channels),
            mBitsPerChannel: 16,
            mReserved: 0)
        if AudioUnitSetProperty(self.ioUnit!, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, AudioConst.InputBus, &ioFormat, UInt32(MemoryLayout.size(ofValue: ioFormat))) != noErr {
            print("set StreamFormat error")
            return false
        }

        if AudioUnitSetProperty(self.ioUnit!, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, AudioConst.OutputBus, &ioFormat, UInt32(MemoryLayout.size(ofValue: ioFormat))) != noErr {
            print("set StreamFormat error")
            return false
        }
        
        //设置回调，下一级unit取数据的时候回到这里来取，具体回调定义在demo里面
        if AudioUnitSetProperty(self.ioUnit!, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, AudioConst.OutputBus, &recordCallback, UInt32(MemoryLayout.size(ofValue: recordCallback))) != noErr {
            print("SetRenderCallback error")
            return false
        }
```
3.启动、关闭Unit

```c
	//启动
	public func startRecord() {
        
        var error = AudioUnitInitialize(self.ioUnit!)
        if error != noErr  {
            print("AudioUnitInitialize error: \(error)")
        }
        error = AudioOutputUnitStart(self.ioUnit!)
        if  error != noErr {
            print("AudioOutputUnitStart error")
        }

    }
    
    //关闭
    public func stopRecord() {
        AudioUnitUninitialize(self.ioUnit!)
        AudioOutputUnitStop(self.ioUnit!)
    }
```
tips：AU的每个api都会返回错误码，如果遇到不是noErr，即0的结果，可以到[这里](https://www.osstatus.com/search/results?platform=all&framework=all&search=-50)去查一下错误码的定义，可以有效地帮助你排查问题原因

[demo地址](https://github.com/eaglesue/EARecorder_AU)

二、使用AUGraphic实现录音

1.设置AudioSession

```c
func setupSession() {
        let session: AVAudioSession = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.overrideOutputAudioPort(.none)
            try session.setPreferredSampleRate(Double(AudioConst.SampleRate))
            try session.setPreferredIOBufferDuration(Double(AudioConst.BufferDuration) / 1000.0)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch  {
            print(error.localizedDescription)
        }
    }
```

2.获取ioUnit

```c
	var ioDes: AudioComponentDescription =	 	AudioComponentDescription.init(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_RemoteIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0)
        var status: OSStatus = noErr
        status = NewAUGraph(&process)
        if status != noErr {
            print("NewAUGraph error")
            return
        }
        
        status = AUGraphOpen(self.process!)
        if status != noErr {
            print("AUGraphOpen error")
            return
        }
        
        	//获取node
        var ioNode: AUNode = 0
        status = AUGraphAddNode(self.process!, &ioDes, &ioNode)
        if status != noErr {
            print("AUGraphAddNode error")
            return
        }
        
        //从node获取unit引用
        AUGraphNodeInfo(self.process!, ioNode, &ioDes, &ioUnit)
      
```

2.设置unit参数，同单独使用Unit一样

```c
//是否打开输入、输出
var value: UInt32 = 1
        if AudioUnitSetProperty(self.ioUnit!, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, AudioConst.InputBus, &value, UInt32(MemoryLayout.size(ofValue: value))) != noErr {
            print("can't enable input io")
            return false
        }
        
        value = 1 //如果不需要从硬件输出 就把value设置为0
        if AudioUnitSetProperty(self.ioUnit!, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, AudioConst.OutputBus, &value, UInt32(MemoryLayout.size(ofValue: value))) != noErr {
            print("can't enable output io")
            return false
        }
        
        //设置最大切片，就是连接两个unit的管道有多粗，这个参数和第一步setPreferredIOBufferDuration的大小有关，太小的话会报错，最好设置大一些，
        var maxSlice: Int32 = 4096
        if AudioUnitSetProperty(self.ioUnit!, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, AudioConst.OutputBus, &maxSlice, UInt32(MemoryLayout.size(ofValue: maxSlice))) != noErr {
            print("set MaximumFramesPerSlice error")
            return false
        }
        
        //设置Unit输出格式
        var ioFormat: AudioStreamBasicDescription = AudioStreamBasicDescription.init(
            mSampleRate: Float64(AudioConst.SampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket:  UInt32(2 * AudioConst.Channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(2 * AudioConst.Channels),
            mChannelsPerFrame: UInt32(AudioConst.Channels),
            mBitsPerChannel: 16,
            mReserved: 0)
        if AudioUnitSetProperty(self.ioUnit!, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, AudioConst.InputBus, &ioFormat, UInt32(MemoryLayout.size(ofValue: ioFormat))) != noErr {
            print("set StreamFormat error")
            return false
        }

        if AudioUnitSetProperty(self.ioUnit!, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, AudioConst.OutputBus, &ioFormat, UInt32(MemoryLayout.size(ofValue: ioFormat))) != noErr {
            print("set StreamFormat error")
            return false
        }
        
        //设置回调，下一级unit取数据的时候回到这里来取，具体回调定义在demo里面
        if AudioUnitSetProperty(self.ioUnit!, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, AudioConst.OutputBus, &recordCallback, UInt32(MemoryLayout.size(ofValue: recordCallback))) != noErr {
            print("SetRenderCallback error")
            return false
        }
```

3.连接node

```c
//连接node, 把ioNode的bus1 连接在ioNode的bus0，即硬件的输入连到硬件输出上
        status = AUGraphConnectNodeInput(self.process!, ioNode, 1, ioNode, 0)
        if status != noErr {
            print("AUGraphConnectNodeInput error")
            return
        }
        
        //初始化AUGraphic流程，如果前面哪些步骤有问题，这里也会报错
        status = AUGraphInitialize(self.process!)
        if status != noErr {
            print("AUGraphInitialize error: \(status)")
        }
```

4.开启和停止

```c
public func start() {
    
        AUGraphStart(self.process!)
    }
    
    
    
    public func stop() {
        AUGraphStop(self.process!)
    }
```


****
#### 使用Audio Unit实现实时变调
实现音频变调有多种方式，这里只讲通过Audio Unit中的timePitch来实现变调。

先讲一个结论，经过我多种尝试和国内外论坛中摸爬滚打，始终没能通过Audio Unit直接实现变调，尝试过程中要么是报错要么没有声音，最终是通过AUGraphic来实现实时变调功能。

以下是实现过程，这里只讲重点哈，因为大部分内容和上述耳返过程相同。
1.获取pitchUnit，并设置参数

```c
//经过多方尝试，发现一旦使用了pitch这个unit，就不能设置ioUnit的输入格式，所以需要把设置ioUnit输入格式的地方注释掉
//        if AudioUnitSetProperty(self.ioUnit!, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, AudioConst.InputBus, &ioFormat, UInt32(MemoryLayout.size(ofValue: ioFormat))) != noErr {
//            print("set StreamFormat error")
//            return
//        }

//如果需要获取变调后的音频数据，即设置了renderCallback，
//使用pitchUnit的时候setPreferredIOBufferDuration的值要大一些，具体多大，我设置了1s。发现超过200ms以后效果就有明显改善
//如果没有设置renderCallback，setPreferredIOBufferDuration设置10ms就够了，耳返效果完美。
//这里也是本项目未能完美解决的地方，如有更好的方案，请与我分享。

var pitchDes: AudioComponentDescription = AudioComponentDescription.init(
            componentType: kAudioUnitType_FormatConverter,
            componentSubType: kAudioUnitSubType_NewTimePitch,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0)
        
        var pitchNode: AUNode = 0
        status = AUGraphAddNode(self.process!, &pitchDes, &pitchNode)
        if status != noErr {
            print("AUGraphAddNode error")
            return
        }
        
        
        status = AUGraphNodeInfo(self.process!, pitchNode, &pitchDes, &pitchUnit)
        if status != noErr {
            print("AUGraphNodeInfo error")
            return
        }
        
        
        if AudioUnitSetProperty(self.pitchUnit!, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, AudioConst.OutputBus, &maxSlice, UInt32(MemoryLayout.size(ofValue: maxSlice))) != noErr {
            print("set MaximumFramesPerSlice error")
            return
        }
```

2.连接Unit

```c
//连接node
        status = AUGraphConnectNodeInput(self.process!, ioNode, 1, pitchNode, 0)
        if status != noErr {
            print("AUGraphConnectNodeInput error")
            return
        }
        
        status = AUGraphConnectNodeInput(self.process!, pitchNode, 0, ioNode, 0)
        if status != noErr {
            print("AUGraphConnectNodeInput error")
            return
        }
        
        status = AUGraphInitialize(self.process!)
        if status != noErr {
            print("AUGraphInitialize error: \(status)")
        }
```

3.启动和停止

```c
	public func start() {
    
        AUGraphStart(self.process!)
    }
    
    
    
    public func stop() {
        AUGraphStop(self.process!)
    }
```

4.设置变调参数

```c
public func setPitch(pValue: Float) {
        
        //取值范围 -2000 ~ 2000
        var value: Float32 = Float32((pValue - 0.5) * 2 * 2000)
        if AudioUnitSetParameter(self.pitchUnit!, kNewTimePitchParam_Pitch, kAudioUnitScope_Global, AudioConst.OutputBus, AudioUnitParameterValue(value), 0) != noErr {
            print("set kNewTimePitchParam_Pitch error")
        }
    }
```


[项目demo地址](https://github.com/eaglesue/EARecorder_pitch)
*****


####引用文摘
https://blog.csdn.net/alwaysrun/article/details/108476785
https://www.cnblogs.com/wangyaoguo/p/8392660.html
https://blog.csdn.net/chenhande1990chenhan/article/details/78770452