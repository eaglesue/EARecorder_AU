//
//  AudioRecorder.swift
//  AudioUnit_pitch
//
//  Created by 苏刁 on 2021/1/25.
//

import Foundation
import AudioUnit
import AVKit

@objc protocol AudioRecordDelegate: NSObjectProtocol {
    
    func audioRecorder(recorder: AudioRecorder?, didUpdate volume: Double)
    
    @objc optional func audioRecorder(recorder: AudioRecorder, didRecieve buffer: AudioBufferList)
}

class AudioRecorder: NSObject {
    
    var ioUnit: AudioComponentInstance? = nil
    
    
    weak var delegate: AudioRecordDelegate? = nil
    
    private var bufferList: AudioBufferList = AudioBufferList.init(mNumberBuffers: 1, mBuffers: AudioBuffer.init(mNumberChannels: UInt32(AudioConst.Channels), mDataByteSize: 4096, mData: UnsafeMutableRawPointer.allocate(byteCount: 4096, alignment: 1)))
    
    override init() {
        super.init()
        self.setupAudioSession()
        self.setupIoUnit()
    }
    
    func setupAudioSession() {
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
    

    func setupIoUnit() -> Bool {
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
        
        var maxSlice: Int32 = 4096
        if AudioUnitSetProperty(self.ioUnit!, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, AudioConst.OutputBus, &maxSlice, UInt32(MemoryLayout.size(ofValue: maxSlice))) != noErr {
            print("set MaximumFramesPerSlice error")
            return false
        }
        
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
        
        var recordCallback: AURenderCallbackStruct = AURenderCallbackStruct.init(inputProc:  { (inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData) -> OSStatus in
            
            let bridgeSelf: AudioRecorder = bridge(ptr: UnsafeRawPointer.init(inRefCon))
            
            var error: OSStatus = AudioUnitRender(bridgeSelf.ioUnit!, ioActionFlags, inTimeStamp, AudioConst.InputBus, inNumberFrames, ioData!)
            if error == noErr {
                
                let bufferData: AudioBuffer = ioData!.pointee.mBuffers
                let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: Int(bufferData.mDataByteSize), alignment: 1)

                if let mData = bufferData.mData {
                    rawPointer.copyMemory(from: mData, byteCount: Int(bufferData.mDataByteSize))
                    let tempBuf = AudioBuffer.init(mNumberChannels: bufferData.mNumberChannels, mDataByteSize: bufferData.mDataByteSize, mData: rawPointer)
                    bridgeSelf.updateVolumeValue(buffer: tempBuf)
                }
                
                
                bridgeSelf.delegate?.audioRecorder?(recorder: bridgeSelf, didRecieve: bridgeSelf.bufferList)
                rawPointer.deallocate()
            }
            
            //如果需要静音，在ioData中放入空数据即可
//            let mdata = ioData!.pointee.mBuffers.mData
//            memset(mdata, 0, Int(ioData!.pointee.mBuffers.mDataByteSize))
//            ioData?.pointee.mBuffers.mData = mdata
            
            return noErr
        }, inputProcRefCon: UnsafeMutableRawPointer(mutating: bridge(obj: self)))
        
        
        if AudioUnitSetProperty(self.ioUnit!, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, AudioConst.OutputBus, &recordCallback, UInt32(MemoryLayout.size(ofValue: recordCallback))) != noErr {
            print("SetRenderCallback error")
            return false
        }
        
        //用下面的方法可以获得到录音数据，稍有不同
        
//        var recordCallback1: AURenderCallbackStruct = AURenderCallbackStruct.init(inputProc:  { (inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData) -> OSStatus in
//
//            let bridgeSelf: AudioRecorder = bridge(ptr: UnsafeRawPointer.init(inRefCon))
//
//            var bufferList: AudioBufferList = AudioBufferList.init(mNumberBuffers: 1, mBuffers: AudioBuffer.init(mNumberChannels: UInt32(AudioConst.Channels), mDataByteSize: UInt32(Int(inNumberFrames) * MemoryLayout<Int16>.stride * Int(AudioConst.Channels)), mData: UnsafeMutableRawPointer.allocate(byteCount: Int(inNumberFrames) * MemoryLayout<Int16>.stride * Int(AudioConst.Channels), alignment: MemoryLayout<Int16>.alignment)))
//
//            var error: OSStatus = AudioUnitRender(bridgeSelf.ioUnit!, ioActionFlags, inTimeStamp, AudioConst.InputBus, inNumberFrames, &bufferList)
//            if error == noErr {
//
//                let bufferData: AudioBuffer = bridgeSelf.bufferList.mBuffers
//                let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: Int(bufferData.mDataByteSize), alignment: 1)
//
//                if let mData = bufferData.mData {
//                    rawPointer.copyMemory(from: mData, byteCount: Int(bufferData.mDataByteSize))
//                    let tempBuf = AudioBuffer.init(mNumberChannels: bufferData.mNumberChannels, mDataByteSize: bufferData.mDataByteSize, mData: rawPointer)
//                    bridgeSelf.updateVolumeValue(buffer: tempBuf)
//                }
//
//
//                bridgeSelf.delegate?.audioRecorder?(recorder: bridgeSelf, didRecieve: bridgeSelf.bufferList)
//                rawPointer.deallocate()
//            }
//
//            bufferList.mBuffers.mData?.deallocate()
//
//            return noErr
//        }, inputProcRefCon: UnsafeMutableRawPointer(mutating: bridge(obj: self)))
//
//
//        if AudioUnitSetProperty(self.ioUnit!, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, AudioConst.InputBus, &recordCallback1, UInt32(MemoryLayout.size(ofValue: recordCallback1))) != noErr {
//            print("SetRenderCallback error")
//            return false
//        }
        

        return true
        
    }
    
    private func updateVolumeValue(buffer: AudioBuffer) {
        var pcmAll: Int = 0
        
        let bufferPoint = UnsafeMutableBufferPointer<Int8>.init(buffer)
        
        let bufferArray = Array(bufferPoint)
        

        let len = bufferArray.count
        for index in 0..<len {
            let value = bufferArray[index]
            pcmAll += (Int(value) * Int(value))

        }
        let mean: Double = Double(pcmAll) / Double(bufferArray.count)
        let volume: Double = 10 * log(mean)

        self.delegate?.audioRecorder(recorder: self, didUpdate: volume)
    }
    
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
    
    public func stopRecord() {
        AudioUnitUninitialize(self.ioUnit!)
        AudioOutputUnitStop(self.ioUnit!)
    }
    
    
}
