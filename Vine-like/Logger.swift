//
//  Logger.swift
//  Vine-like
//
//  Created by Yuki Ishii on 2015/08/04.
//  Copyright (c) 2015年 Yuki Ishii. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import AssetsLibrary

class Logger{
	class func log(message: String,
		function: String = __FUNCTION__,
		file: String = __FILE__,
		line: Int = __LINE__) {
			var filename = file
			if let match = filename.rangeOfString("[^/]*$", options: .RegularExpressionSearch) {
				filename = filename.substringWithRange(match)
			}
			println("\(NSDate().timeIntervalSince1970):\(filename):L\(line):\(function) \"\(message)\"")
	}
}
