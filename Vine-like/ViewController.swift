//
//  ViewController.swift
//  Vine-like
//
//  Created by Yuki Ishii on 2015/08/04.
//  Copyright (c) 2015年 Yuki Ishii. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import AssetsLibrary

class ViewController: UIViewController {
	/* for positioning */
	let width = UIScreen.mainScreen().bounds.width
	let height = UIScreen.mainScreen().bounds.height
	
	/* for video layer */
	lazy var videoLayer = AVCaptureVideoPreviewLayer()
	lazy var videoView = UIView()
	
	/* buttons */
	lazy var recordButton = UIButton()
	
	/* for progress bar */
	lazy var progress = UIProgressView()
	lazy var progressFrame = CGRectMake(0, 0, 0, 0)
	let progressAffinScale = 20.0
	lazy var progressH: CGFloat = 0.0
	
	/* camera engine */
	lazy var isRecording = false
	let cameraEngine = CameraEngine()
	
	/* for timer */
	lazy var timer = NSTimer()
	lazy var count = 0.0
	
	override func viewDidLoad() {
		super.viewDidLoad()
		self.restorationIdentifier = "ViewController"
		
		self.view.backgroundColor = UIColor.blackColor()
		cameraEngine.startup()
		// setting ProgressBar is the first, then VideoLayer.
		setupProgressBar()
		resetProgressBar()
		setupVideoLayer()
		setupRecordButton()
	}
	
	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		resetProgressBar()
		count = 0.0
	}
	
	override func viewDidAppear(animated: Bool) {
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}
	
	override func viewWillDisappear(animated: Bool) {
		super.viewWillDisappear(animated)
	}
	
	func setupVideoLayer () {
		let videoWidth = width
		let videoHeight = width
		let videoFrame = CGRectMake(0, 0, videoWidth, videoHeight)
		let videoY = progressFrame.origin.y + (progressFrame.height * CGFloat(progressAffinScale)) + (videoFrame.height / 2)
		let videoPosition = CGPointMake(width / 2, videoY)
		
		videoLayer = AVCaptureVideoPreviewLayer.layerWithSession(self.cameraEngine.captureSession) as? AVCaptureVideoPreviewLayer
		if let validVideoLayer = videoLayer {
			validVideoLayer.frame = videoFrame
			videoView = UIView(frame: videoLayer.frame)
			validVideoLayer.position = videoPosition
			validVideoLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
			validVideoLayer.connection.videoOrientation = AVCaptureVideoOrientation.Portrait
			self.view.layer.addSublayer(validVideoLayer)
		}
		else {
			println("MovieVC setupVideo(): videoLayer is nil.")
		}
	}
	
	func setupProgressBar () {
		progressFrame = CGRectMake(0, 20, width, 2)
		progress = UIProgressView(frame: progressFrame)
		progress.transform = CGAffineTransformMakeScale(1.0, CGFloat(progressAffinScale))
		progressH = progressFrame.height * CGFloat(progressAffinScale)
		// modify the position of the progress bar
		progress.layer.position = CGPointMake(width / 2, 20 + (progressH / 2))
		progress.progressTintColor = UIColor.cyanColor()
		progress.trackTintColor = UIColor.clearColor()
		self.view.addSubview(progress)
		
	}
	
	func resetProgressBar () {
		progress.progress = 0.0
	}
	
	func setupRecordButton(){
		recordButton = UIButton(frame: videoLayer.frame)
		recordButton.layer.masksToBounds = true
		recordButton.layer.position = videoLayer.position
		recordButton.addTarget(self, action: "clickedButton:", forControlEvents: .TouchDown)
		recordButton.addTarget(self, action: "pauseRecording:", forControlEvents: .TouchUpInside)
		recordButton.addTarget(self, action: "pauseRecording:", forControlEvents: .TouchUpOutside)
		self.view.addSubview(recordButton)
		
	}
	
	func setupTimer () {
		timer = NSTimer.scheduledTimerWithTimeInterval(0.1, target: self, selector: "onUpdate", userInfo: nil, repeats: true)
		
	}
	
	func onUpdate () {
		if count < 7 {
			// start progression
			progress.setProgress(progress.progress, animated: true)
			progress.progress += 0.014285
			count += 0.1
		}
		else {
			onClickStopButton(nil)
		}
	}
	
	
	func clickedButton (sender: UIButton) {
		if !cameraEngine.isCapturing { // if not have been started recording
			onClickStartButton()
		}
		else { // have been started before
			if cameraEngine.isPaused && count < 7 { // resume recording
				resumeRecording()
			}
			
		}
	}
	
	func onClickStartButton(){
		if !self.cameraEngine.isCapturing {
			self.cameraEngine.start()
			// fire timer
			setupTimer()
			timer.fire()
		}
	}
	
	func resumeRecording () {
		cameraEngine.resume()
		setupTimer()
		timer.fire()
	}
	
	func pauseRecording (sender: UIButton) {
		if !cameraEngine.isPaused {
			cameraEngine.pause()
			progress.setProgress(progress.progress, animated: false)
			timer.invalidate()
		}
	}
	
	func stopRecording (sender: UIButton) {
		onClickStopButton(nil)
	}
	
	func onClickStopButton(callback: (() -> ())?){
		if self.cameraEngine.isCapturing {
			self.cameraEngine.stop(callback)
			progress.setProgress(progress.progress, animated: false)
			timer.invalidate()
		}
	}
}
