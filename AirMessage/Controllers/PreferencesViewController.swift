//
//  ViewControllerPreferences.swift
//  AirMessage
//
//  Created by Cole Feuer on 2021-07-03.
//

import Foundation
import AppKit

class PreferencesViewController: NSViewController {
	//Keep in memory for older versions of OS X
	private static var preferencesWindowController: NSWindowController?
	
	@IBOutlet weak var groupPort: NSStackView!
	@IBOutlet weak var inputPort: NSTextField!
	
	@IBOutlet weak var checkboxAutoUpdate: NSButton!
	@IBOutlet weak var checkboxBetaUpdate: NSButton!
	
	@IBOutlet weak var groupFaceTime: NSStackView!
	@IBOutlet weak var checkboxFaceTime: NSButton!
	
    @IBOutlet weak var checkboxPingBerry: NSButton!
    @IBOutlet weak var inputPingBerryEmail: NSTextField!
    @IBOutlet weak var linkConfigurePingBerry: NSTextField!
    
	@IBOutlet weak var buttonSignOut: NSButton!
	@IBOutlet weak var labelSignOut: NSTextField!
	
	private var isShowingPort, isShowingFaceTime: Bool!
	
	static func open() {
		//If we're already showing the window, just focus it
		if let window = preferencesWindowController?.window, window.isVisible {
			window.makeKeyAndOrderFront(self)
			NSApp.activate(ignoringOtherApps: true)
			return
		}
		
		let storyboard = NSStoryboard(name: "Main", bundle: nil)
		let windowController = storyboard.instantiateController(withIdentifier: "Preferences") as! NSWindowController
		windowController.showWindow(nil)
		preferencesWindowController = windowController
		NSApp.activate(ignoringOtherApps: true)
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
		preferredContentSize = view.fittingSize
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		//Load control values
		if PreferencesManager.shared.accountType == .direct {
			inputPort.stringValue = String(PreferencesManager.shared.serverPort)
			inputPort.formatter = PortFormatter()
			isShowingPort = true
		} else {
			groupPort.removeFromSuperview()
			isShowingPort = false
		}
		
		checkboxAutoUpdate.state = PreferencesManager.shared.checkUpdates ? .on : .off
		
		checkboxBetaUpdate.state = PreferencesManager.shared.betaUpdates ? .on : .off
		
		if FaceTimeHelper.isSupported {
			checkboxFaceTime.state = PreferencesManager.shared.faceTimeIntegration ? .on : .off
			isShowingFaceTime = true
		} else {
			groupFaceTime.removeFromSuperview()
			isShowingFaceTime = false
		}
        
        checkboxPingBerry.state = PreferencesManager.shared.pingberryEnabled ? .on : .off
        
        inputPingBerryEmail.stringValue = String(PreferencesManager.shared.pingberryEmail)
		
		//Update "sign out" button text
		if PreferencesManager.shared.accountType == .direct {
			buttonSignOut.title = NSLocalizedString("action.switch_to_account", comment: "")
			labelSignOut.stringValue = NSLocalizedString("message.preference.account_manual", comment: "")
		} else if PreferencesManager.shared.accountType == .connect {
			buttonSignOut.title = NSLocalizedString("action.sign_out", comment: "")
			labelSignOut.stringValue = String(format: NSLocalizedString("message.preference.account_connect", comment: ""), PreferencesManager.shared.connectEmailAddress ?? "nil")
		}
        
        inputPingBerryEmail.isHidden = !PreferencesManager.shared.pingberryEnabled
        
        let text = "Learn how to configure PingBerry on your BlackBerry 10 Device"
        let url = URL(string: "https://github.com/andreytakhtamirov/pingberry?tab=readme-ov-file#-pingberry")!
        
        let attributedString = NSMutableAttributedString(string: text)
        
        attributedString.addAttributes([
            .link: url,
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ], range: NSMakeRange(0, text.count))
        
        linkConfigurePingBerry.allowsEditingTextAttributes = true
        linkConfigurePingBerry.isSelectable = true
        linkConfigurePingBerry.attributedStringValue = attributedString
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		
		//Set the window title
		view.window!.title = NSLocalizedString("label.preferences", comment: "")
		
		//Focus app
		NSApp.activate(ignoringOtherApps: true)
	}
    
    @IBAction func checkboxPingBerryClicked(_ sender: NSButton) {
        inputPingBerryEmail.isHidden = checkboxPingBerry.state == .off
    }
	
	@IBAction func onClickClose(_sender: NSButton) {
		//Close window
		view.window!.close()
	}
	
	@IBAction func onClickOK(_ sender: NSButton) {
		if isShowingPort {
			//Validate port input
			guard let inputPortValue = Int(inputPort.stringValue),
				  inputPortValue >= 1024 && inputPortValue <= 65535 else {
				let alert = NSAlert()
				alert.alertStyle = .critical
				if inputPort.stringValue.isEmpty {
					alert.messageText = NSLocalizedString("message.enter_server_port", comment: "")
				} else {
					alert.messageText = String(format: NSLocalizedString("message.invalid_server_port", comment: ""), inputPort.stringValue)
				}
				alert.beginSheetModal(for: view.window!)
				return
			}
			
			let originalPort = PreferencesManager.shared.serverPort
			
			//Save change to disk
			PreferencesManager.shared.serverPort = inputPortValue
			
			//Restart the server if the port changed
			if originalPort != inputPortValue {
				//Make sure the server is running
				if (NSApplication.shared.delegate as! AppDelegate).currentServerState == .running {
					//Restart the server
					ConnectionManager.shared.stop()
					ConnectionManager.shared.setProxy(DataProxyTCP(port: inputPortValue))
					ConnectionManager.shared.start()
				}
			}
		}
		
		//Save update changes to disk
		PreferencesManager.shared.checkUpdates = checkboxAutoUpdate.state == .on
		PreferencesManager.shared.betaUpdates = checkboxBetaUpdate.state == .on
		
		//Start or stop update check timer
		if checkboxAutoUpdate.state == .on {
			UpdateHelper.startUpdateTimer()
		} else {
			UpdateHelper.stopUpdateTimer()
		}
		
		//Apply FaceTime updates
		if isShowingFaceTime {
			let originalFaceTime = PreferencesManager.shared.faceTimeIntegration
			
			//Get FaceTime integration state
			let faceTimeIntegration = checkboxFaceTime.state == .on
			
			//Save change to disk
			PreferencesManager.shared.faceTimeIntegration = faceTimeIntegration
			
			//Start or stop the FaceTime manager (as long as we're in a position where it could be running)
			if originalFaceTime != faceTimeIntegration &&
				!(NSApplication.shared.delegate as! AppDelegate).isSetupMode &&
				AppleScriptBridge.shared.checkPermissionsAutomation() {
				if faceTimeIntegration {
					FaceTimeHelper.startIncomingCallTimer()
				} else {
					FaceTimeHelper.stopIncomingCallTimer()
				}
			}
		}

        if checkboxPingBerry.state == .on {
                let email = inputPingBerryEmail.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !isValidEmail(email) {
                    let alert = NSAlert()
                    alert.alertStyle = .critical
                    alert.messageText = "Please enter a valid email address."
                    alert.beginSheetModal(for: view.window!)
                    return
                }
                
                PreferencesManager.shared.pingberryEmail = email
        } else {
            PreferencesManager.shared.pingberryEmail = ""
        }
        
        PreferencesManager.shared.pingberryEnabled = checkboxPingBerry.state == .on
        
		//Close window
		view.window!.close()
	}
	
	@IBAction func onClickSignOut(_ sender: NSButton) {
		let alert = NSAlert()
		if PreferencesManager.shared.accountType == .direct {
			alert.messageText = NSLocalizedString("message.reset.title.direct", comment: "")
			alert.addButton(withTitle: NSLocalizedString("action.switch_to_account", comment: ""))
		} else {
			alert.messageText = NSLocalizedString("message.reset.title.connect", comment: "")
			alert.addButton(withTitle: NSLocalizedString("action.sign_out", comment: ""))
		}
		alert.informativeText = NSLocalizedString("message.reset.subtitle", comment: "")
		alert.addButton(withTitle: NSLocalizedString("action.cancel", comment: ""))
		alert.beginSheetModal(for: view.window!) { response in
			if response != .alertFirstButtonReturn {
				return
			}
			
			//Reset the server
			resetServer()
			
			//Close the preferences window
			self.view.window!.close()
			
			//Show the onboarding window
            OnboardingViewController.open()
		}
	}
	
	@IBAction func onClickReceiveBetaUpdates(_ sender: NSButton) {
		if sender.state == .on {
			let alert = NSAlert()
			alert.messageText = NSLocalizedString("message.beta_enrollment.title", comment: "")
			alert.informativeText = NSLocalizedString("message.beta_enrollment.description", comment: "")
			alert.addButton(withTitle: NSLocalizedString("action.receive_beta_updates", comment: ""))
			alert.addButton(withTitle: NSLocalizedString("action.cancel", comment: ""))
			alert.beginSheetModal(for: view.window!) { response in
				if response == .alertSecondButtonReturn {
					sender.state = .off
				}
			}
		} else {
			let alert = NSAlert()
			alert.messageText = NSLocalizedString("message.beta_unenrollment.title", comment: "")
			alert.informativeText = NSLocalizedString("message.beta_unenrollment.description", comment: "")
			alert.beginSheetModal(for: view.window!)
		}
	}
	
	override func shouldPerformSegue(withIdentifier identifier: NSStoryboardSegue.Identifier, sender: Any?) -> Bool {
		if identifier == "PasswordEntry" {
			//Make sure Keychain is initialized
			do {
				try PreferencesManager.shared.initializeKeychain()
			} catch {
				KeychainManager.getErrorAlert(error).beginSheetModal(for: self.view.window!)
				return false
			}
			
			return true
		} else {
			return super.shouldPerformSegue(withIdentifier: identifier, sender: sender)
		}
	}
	
	override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
		if segue.identifier == "PasswordEntry" {
			let passwordEntry = segue.destinationController as! PasswordEntryViewController
			
			//Password is required for manual setup, but not for AirMessage Cloud
			passwordEntry.isRequired = PreferencesManager.shared.accountType == .direct
			passwordEntry.onSubmit = { password in
				//Save password
				do {
					try PreferencesManager.shared.setPassword(password)
				} catch {
					KeychainManager.getErrorAlert(error).beginSheetModal(for: self.view.window!)
				}
			}
		}
	}
    
    func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}

private class PortFormatter: NumberFormatter {
	override func isPartialStringValid(_ partialString: String, newEditingString newString: AutoreleasingUnsafeMutablePointer<Optional<NSString>>?, errorDescription error: AutoreleasingUnsafeMutablePointer<Optional<NSString>>?) -> Bool {
		if partialString.isEmpty || //Allow empty string
				(Int(partialString) != nil && partialString.count <= 5) {
			return true
		} else {
			NSSound.beep()
			return false
		}
	}
}
