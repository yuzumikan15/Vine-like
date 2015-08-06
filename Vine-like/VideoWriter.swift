//
//  VideoWriter.swift
//  Vine-like
//
//  Created by Yuki Ishii on 2015/08/04.
//  Copyright (c) 2015年 Yuki Ishii. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import AssetsLibrary

class VideoWriter: NSObject {
	lazy var fileWriter = AVAssetWriter()
	lazy var videoInput = AVAssetWriterInput()
	lazy var audioInput = AVAssetWriterInput()
	
	init(fileUrl: NSURL, height: Int, width: Int, channels: Int, samples: Float64){
		super.init()
		
		fileWriter = AVAssetWriter(URL: fileUrl, fileType: AVFileTypeQuickTimeMovie, error: nil)
		
		let videoOutputSettings: Dictionary<String, AnyObject> = [
			AVVideoCodecKey : AVVideoCodecH264,
			AVVideoWidthKey : width,
			AVVideoHeightKey : height,
			AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
			AVVideoCompressionPropertiesKey: [
				AVVideoProfileLevelKey: AVVideoProfileLevelH264Main41
			],
		]
		videoInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoOutputSettings)
		videoInput.expectsMediaDataInRealTime = true
		
		// 動画のときカメラは横向きなので90度回転させる
		// 今回は動画アスペクト比が正方形なので回転させるだけ
		// 任意のアスペクト比にするときは回転させたあとさらに中心座標の再設定が必要っぽい (回転させるとずれるので)
		videoInput.transform = CGAffineTransformMakeRotation(CGFloat(90.0 * M_PI / 180.0))
		fileWriter.addInput(videoInput)
		
		let audioOutputSettings: Dictionary<String, AnyObject> = [
			AVFormatIDKey : kAudioFormatMPEG4AAC,
			AVNumberOfChannelsKey : channels,
			AVSampleRateKey : samples,
			AVEncoderBitRateKey : 128000
		]
		audioInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: audioOutputSettings)
		audioInput.expectsMediaDataInRealTime = true
		fileWriter.addInput(audioInput)
	}
	
	func write(sample: CMSampleBufferRef, isVideo: Bool){
		if CMSampleBufferDataIsReady(sample) != 0 {
			if fileWriter.status == AVAssetWriterStatus.Unknown {
				Logger.log("Start writing, isVideo = \(isVideo), status = \(fileWriter.status.rawValue)")
				let startTime = CMSampleBufferGetPresentationTimeStamp(sample)
				fileWriter.startWriting()
				fileWriter.startSessionAtSourceTime(startTime)
			}
			if fileWriter.status == AVAssetWriterStatus.Failed {
				Logger.log("Error occured, isVideo = \(isVideo), status = \(fileWriter.status.rawValue), \(self.fileWriter.error.localizedDescription)")
				return
			}
			if isVideo {
				if self.videoInput.readyForMoreMediaData {
					self.videoInput.appendSampleBuffer(sample)
				}
			}
			else{
				if audioInput.readyForMoreMediaData {
					audioInput.appendSampleBuffer(sample)
				}
			}
		}
	}
	
	func finish(callback: Void -> Void){
		fileWriter.finishWritingWithCompletionHandler(callback)
	}
}

