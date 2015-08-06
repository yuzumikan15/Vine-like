//
//  CameraEngine.swift
//  Vine-like
//
//  Created by Yuki Ishii on 2015/08/04.
//  Copyright (c) 2015年 Yuki Ishii. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import AssetsLibrary

class CameraEngine : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate{
	
	let width = UIScreen.mainScreen().bounds.width
	let height = UIScreen.mainScreen().bounds.height
	
	let captureSession = AVCaptureSession()
	let videoDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
	let audioDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeAudio)
	var videoWriter : VideoWriter?
	
	lazy var isCapturing = false
	lazy var isPaused = false
	lazy var isDiscontinue = false
	lazy var fileIndex = 0
	
	lazy var timeOffset = CMTimeMake(0, 0)
	var lastAudioPts: CMTime?
	
	let lockQueue = dispatch_queue_create("vine-like", nil)
	let recordingQueue = dispatch_queue_create("vine-like-RecordingQueue", DISPATCH_QUEUE_SERIAL)
	
	let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
	
	func startup(){
		// orientation of the caputure session
		captureSession
		
		// video input
		videoDevice.activeVideoMinFrameDuration = CMTimeMake(1, 30)
		let videoInput = AVCaptureDeviceInput.deviceInputWithDevice(videoDevice, error: nil) as! AVCaptureDeviceInput
		captureSession.addInput(videoInput)
		
		// audio input
		let audioInput = AVCaptureDeviceInput.deviceInputWithDevice(audioDevice, error: nil) as! AVCaptureDeviceInput
		captureSession.addInput(audioInput);
		
		// video output
		var videoDataOutput = AVCaptureVideoDataOutput()
		videoDataOutput.setSampleBufferDelegate(self, queue: recordingQueue)
		videoDataOutput.alwaysDiscardsLateVideoFrames = true
		videoDataOutput.videoSettings = [
			kCVPixelBufferPixelFormatTypeKey : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
		]
		
		captureSession.addOutput(videoDataOutput)
		
		// audio output
		var audioDataOutput = AVCaptureAudioDataOutput()
		audioDataOutput.setSampleBufferDelegate(self, queue: recordingQueue)
		captureSession.addOutput(audioDataOutput)
		
		captureSession.startRunning()
	}
	
	func start(){
		dispatch_sync(lockQueue) {
			if !self.isCapturing{
				self.isPaused = false
				self.isDiscontinue = false
				self.isCapturing = true
				self.timeOffset = CMTimeMake(0, 0)
			}
		}
	}
	
	func stop(callback: (() -> ())?){
		dispatch_sync(lockQueue) {
			self.isCapturing = false
			dispatch_async(dispatch_get_main_queue()) {
				if let validVideoWriter = self.videoWriter {
					validVideoWriter.finish {
						self.videoWriter = nil
						let assetsLib = ALAssetsLibrary()
						assetsLib.writeVideoAtPathToSavedPhotosAlbum(self.filePathUrl(), completionBlock: {
							(nsurl, error) in
							if error != nil { // error occurred
								println("An error occurred during saving recorded movie (CameraEngine.stop): \(error)")
							}
							else { // no error
								self.fileIndex++
								if let _ = callback {
									callback!()
								}
							}
						})
					}
				}
				else {
					println("videoWriter is nil. Recording has already been stopped")
				}
			}
		}
	}
	
	func pause(){
		dispatch_sync(lockQueue) {
			if self.isCapturing{
				self.isPaused = true
				self.isDiscontinue = true
			}
		}
	}
	
	func resume(){
		dispatch_sync(lockQueue) {
			if self.isCapturing{
				self.isPaused = false
			}
		}
	}
	
	func filePath() -> String {
		let paths = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)
		let documentsDirectory = paths[0] as! String
		let filePath : String = "\(documentsDirectory)/video\(fileIndex).mp4"
		let fileURL : NSURL = NSURL(fileURLWithPath: filePath)!
		return filePath
	}
	
	func filePathUrl() -> NSURL? {
		return NSURL(fileURLWithPath: filePath())
	}
	
	func ajustTimeStamp(sample: CMSampleBufferRef, offset: CMTime) -> CMSampleBufferRef {
		var count: CMItemCount = 0
		CMSampleBufferGetSampleTimingInfoArray(sample, 0, nil, &count);
		var info = [CMSampleTimingInfo](count: count, repeatedValue: CMSampleTimingInfo(duration: CMTimeMake(0, 0), presentationTimeStamp: CMTimeMake(0, 0), decodeTimeStamp: CMTimeMake(0, 0)))
		CMSampleBufferGetSampleTimingInfoArray(sample, count, &info, &count);
		
		for i in 0..<count {
			info[i].decodeTimeStamp = CMTimeSubtract(info[i].decodeTimeStamp, offset);
			info[i].presentationTimeStamp = CMTimeSubtract(info[i].presentationTimeStamp, offset);
		}
		
		var out: Unmanaged<CMSampleBuffer>?
		CMSampleBufferCreateCopyWithNewTiming(nil, sample, count, &info, &out);
		return out!.takeRetainedValue()
	}
}

extension CameraEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
	func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!){
		dispatch_sync(lockQueue) {
			if !self.isCapturing || self.isPaused {
				return
			}
			
			let isVideo = captureOutput is AVCaptureVideoDataOutput
			let filePath = self.filePath()
			if self.videoWriter == nil && !isVideo {
				let fileManager = NSFileManager()
				if fileManager.fileExistsAtPath(filePath) {
					fileManager.removeItemAtPath(filePath, error: nil)
				}
				
				let fmt = CMSampleBufferGetFormatDescription(sampleBuffer)
				let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)
				
				if let filePathUrl = self.filePathUrl() {
					self.videoWriter = VideoWriter(
						fileUrl: filePathUrl,
						height: Int(self.width), width: Int(self.width),
						channels: Int(asbd.memory.mChannelsPerFrame),
						samples: asbd.memory.mSampleRate
					)
				}
			}
			
			if self.isDiscontinue {
				if isVideo {
					return
				}
				
				var pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
				
				let isAudioPtsValid = self.lastAudioPts!.flags & CMTimeFlags.Valid
				if isAudioPtsValid.rawValue != 0 {
					let isTimeOffsetPtsValid = self.timeOffset.flags & CMTimeFlags.Valid
					if isTimeOffsetPtsValid.rawValue != 0 {
						pts = CMTimeSubtract(pts, self.timeOffset);
					}
					let offset = CMTimeSubtract(pts, self.lastAudioPts!);
					
					if (self.timeOffset.value == 0)
					{
						self.timeOffset = offset;
					}
					else
					{
						self.timeOffset = CMTimeAdd(self.timeOffset, offset);
					}
				}
				self.lastAudioPts!.flags = CMTimeFlags.allZeros
				self.isDiscontinue = false
			}
			
			var buffer = sampleBuffer
			if self.timeOffset.value > 0 {
				buffer = self.ajustTimeStamp(sampleBuffer, offset: self.timeOffset)
			}
			
			if !isVideo {
				var pts = CMSampleBufferGetPresentationTimeStamp(buffer)
				let dur = CMSampleBufferGetDuration(buffer)
				if (dur.value > 0)
				{
					pts = CMTimeAdd(pts, dur)
				}
				self.lastAudioPts = pts
			}
			
			self.videoWriter?.write(buffer, isVideo: isVideo)
		}
	}
}
