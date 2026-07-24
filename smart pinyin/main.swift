//
//  smart_pinyinApp.swift
//  smart pinyin
//
//  Created by xingjunyang on 2026/7/23.
//

import Cocoa
import InputMethodKit

var server: IMKServer!

let bundleID = Bundle.main.bundleIdentifier
server = IMKServer(
    name: Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String,
    bundleIdentifier: bundleID
)

NSApplication.shared.run()

