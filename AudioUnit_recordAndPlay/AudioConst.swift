//
//  AudioConst.swift
//  AudioUnit_pitch
//
//  Created by 苏刁 on 2021/1/19.
//

import Foundation
import AudioUnit

struct AudioConst {
    static let SampleRate: Int = 44100
    
    static let Channels: UInt32 = 1
    
    static let InputBus: AudioUnitElement = 1
    
    static let OutputBus: AudioUnitElement = 0
    
    static let BufferDuration: Int = 20
    
    static let mDataByteSize: Int = 4096
}
