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
	
	var isCapturing = false
	var isPaused = false
	var isDiscontinue = false
	var fileIndex = 0
	
	var timeOffset = CMTimeMake(0, 0)
	var lastAudioPts: CMTime?
	
	let lockQueue = dispatch_queue_create("com.takecian.LockQueue", nil)
	let recordingQueue = dispatch_queue_create("com.takecian.RecordingQueue", DISPATCH_QUEUE_SERIAL)
	
	let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
	
	func startup(){
		// orientation of the caputure session
		captureSession
		
		// video input
		self.videoDevice.activeVideoMinFrameDuration = CMTimeMake(1, 30)
		let videoInput = AVCaptureDeviceInput.deviceInputWithDevice(self.videoDevice, error: nil) as! AVCaptureDeviceInput
		self.captureSession.addInput(videoInput)
		
		// audio input
		let audioInput = AVCaptureDeviceInput.deviceInputWithDevice(self.audioDevice, error: nil) as! AVCaptureDeviceInput
		self.captureSession.addInput(audioInput);
		
		// video output
		var videoDataOutput = AVCaptureVideoDataOutput()
		videoDataOutput.setSampleBufferDelegate(self, queue: self.recordingQueue)
		videoDataOutput.alwaysDiscardsLateVideoFrames = true
		videoDataOutput.videoSettings = [
			kCVPixelBufferPixelFormatTypeKey : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
		]
		
		self.captureSession.addOutput(videoDataOutput)
		
		// audio output
		var audioDataOutput = AVCaptureAudioDataOutput()
		audioDataOutput.setSampleBufferDelegate(self, queue: self.recordingQueue)
		self.captureSession.addOutput(audioDataOutput)
		
		self.captureSession.startRunning()
	}
	
	func start(){
		println("CameraEngine: start")
		dispatch_sync(self.lockQueue) {
			if !self.isCapturing{
				Logger.log("in")
				self.isPaused = false
				self.isDiscontinue = false
				self.isCapturing = true
				self.timeOffset = CMTimeMake(0, 0)
			}
		}
	}
	
	func stop(callback: (() -> ())?){
		dispatch_sync(self.lockQueue) {
			self.isCapturing = false
			dispatch_async(dispatch_get_main_queue()) {
				Logger.log("in")
				if let validVideoWriter = self.videoWriter {
					validVideoWriter.finish {
						Logger.log("Recording finished")
						self.videoWriter = nil
						let assetsLib = ALAssetsLibrary()
						assetsLib.writeVideoAtPathToSavedPhotosAlbum(self.filePathUrl(), completionBlock: {
							(nsurl, error) in
							if error != nil { // error occurred
								println("An error occurred during saving recorded movie (CameraEngine.stop): \(error)")
							}
							else { // no error
//								self.appDelegate.filePath = self.filePathUrl()
								Logger.log("Transfer video to library finished")
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
		dispatch_sync(self.lockQueue) {
			if self.isCapturing{
				Logger.log("in")
				self.isPaused = true
				self.isDiscontinue = true
			}
		}
	}
	
	func resume(){
		dispatch_sync(self.lockQueue) {
			if self.isCapturing{
				Logger.log("in")
				self.isPaused = false
			}
		}
	}
	
	func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!){
		dispatch_sync(self.lockQueue) {
			if !self.isCapturing || self.isPaused {
				return
			}
			
			let isVideo = captureOutput is AVCaptureVideoDataOutput
			
			if self.videoWriter == nil && !isVideo {
				let fileManager = NSFileManager()
				if fileManager.fileExistsAtPath(self.filePath()) {
					fileManager.removeItemAtPath(self.filePath(), error: nil)
				}
				
				let fmt = CMSampleBufferGetFormatDescription(sampleBuffer)
				let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)
				
				Logger.log("setup video writer")
				self.videoWriter = VideoWriter(
					fileUrl: self.filePathUrl(),
					height: Int(self.width), width: Int(self.width),
					channels: Int(asbd.memory.mChannelsPerFrame),
					samples: asbd.memory.mSampleRate
				)
			}
			
			if self.isDiscontinue {
				if isVideo {
					return
				}
				
				var pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
				
				let isAudioPtsValid = self.lastAudioPts!.flags & CMTimeFlags.Valid
				if isAudioPtsValid.rawValue != 0 {
					Logger.log("isAudioPtsValid is valid")
					let isTimeOffsetPtsValid = self.timeOffset.flags & CMTimeFlags.Valid
					if isTimeOffsetPtsValid.rawValue != 0 {
						Logger.log("isTimeOffsetPtsValid is valid")
						pts = CMTimeSubtract(pts, self.timeOffset);
					}
					let offset = CMTimeSubtract(pts, self.lastAudioPts!);
					
					if (self.timeOffset.value == 0)
					{
						Logger.log("timeOffset is \(self.timeOffset.value)")
						self.timeOffset = offset;
					}
					else
					{
						Logger.log("timeOffset is \(self.timeOffset.value)")
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
	
	func filePath() -> String {
		let paths = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)
		let documentsDirectory = paths[0] as! String
		let filePath : String = "\(documentsDirectory)/video\(self.fileIndex).mp4"
		let fileURL : NSURL = NSURL(fileURLWithPath: filePath)!
		return filePath
	}
	
	func filePathUrl() -> NSURL! {
		return NSURL(fileURLWithPath: self.filePath())!
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
