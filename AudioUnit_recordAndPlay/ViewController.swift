//
//  ViewController.swift
//  AudioUnit_recordAndPlay
//
//  Created by 苏刁 on 2021/1/30.
//

import UIKit
import AudioUnit

class ViewController: UIViewController {
    
    let recorder: AudioRecorder = AudioRecorder.init()
    
    
    @IBOutlet weak var volumeLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        self.recorder.delegate = self
    }

    @IBAction func startAction(_ sender: Any) {
        self.recorder.startRecord()
    }
    
    
    @IBAction func stopAciton(_ sender: Any) {
        self.recorder.stopRecord()
    }
    
}

extension ViewController: AudioRecordDelegate {
    func audioRecorder(recorder: AudioRecorder?, didUpdate volume: Double) {
        //从这里获得到电平，可能不准，此处仅做演示
        DispatchQueue.main.async {
//            self.volumeLabel.text = "音量:\(Int(volume))"
        }
    }
}

