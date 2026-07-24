//
//  InputController.swift
//  smart pinyin
//
//  Created by xingjunyang on 2026/7/24.
//

import InputMethodKit

class InputController: IMKInputController {
    override func inputText(_ string: String!, client sender: Any!) -> Bool {
        NSLog("🔵 inputText called: %@", string ?? "nil")
        return false
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        NSLog("🔵 handle event called: %@", event?.description ?? "nil")
        return false
    }

    override func activateServer(_ sender: Any!) {
        NSLog("🟢 activateServer called")
        super.activateServer(sender)
    }

    override func deactivateServer(_ sender: Any!) {
        NSLog("🔴 deactivateServer called")
        super.deactivateServer(sender)
    }
}

