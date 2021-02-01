//
//  PointerConvert.swift
//  AudioUnit_pitch
//
//  Created by 苏刁 on 2021/1/19.
//

import Foundation


func bridge<T : AnyObject>(ptr : UnsafeRawPointer) -> T {
    return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()}

func bridge<T : AnyObject>(obj : T) -> UnsafeRawPointer {
    return UnsafeRawPointer(Unmanaged.passUnretained(obj).toOpaque())}
