import CoreTelephony
import UIKit

class VoicemailStream: Stream {
    override var autoplayChangeable: Bool {
        return false
    }

    override var callToAction: String? {
        return NSLocalizedString("Set a greeting", comment: "Voicemail microphone tooltip")
    }

    override var canTalk: Bool {
        return VoicemailStream.config != nil
    }

    override var instructions: Instructions? {
        if !self.available {
            return (
                NSLocalizedString("Voicemail in Roger", comment: "Voicemail instructions title"),
                NSLocalizedString("Sorry, we don't currently\nsupport your operator.", comment: "Voicemail instructions; not supported")
            )
        }
        if !SettingsManager.didSetUpVoicemail {
            return (
                NSLocalizedString("Voicemail in Roger", comment: "Voicemail instructions title"),
                NSLocalizedString("Get your voicemail in Roger.\nTalk here to set a greeting.", comment: "Voicemail instructions; not configured")
            )
        }
        return (
            NSLocalizedString("Voicemail in Roger", comment: "Voicemail instructions title"),
            NSLocalizedString("Talk here to set a greeting.\nPress the button below for options.", comment: "Voicemail instructions; already configured")
        )
    }

    override var instructionsAction: String? {
        guard self.available else {
            return nil
        }
        if SettingsManager.didSetUpVoicemail {
            return NSLocalizedString("Configure", comment: "Voicemail instructions button; already configured")
        } else {
            return NSLocalizedString("Set up", comment: "Voicemail instructions button; not configured")
        }
    }

    override var statusText: String {
        return ""
    }

    override func instructionsActionTapped() -> InstructionsActionResult {
        guard let
            config = VoicemailStream.config,
            let prefix = config["all_conditional_prefix"],
            let suffix = config["all_conditional_suffix"]
            // TODO: If the prefix is empty, we need to do individual conditionals instead.
            , prefix != ""
        else {
            return .showAlert(
                title: NSLocalizedString("Voicemail in Roger", comment: "Voicemail instructions title"),
                message: NSLocalizedString("Sorry, we don't currently\nsupport your operator.", comment: "Voicemail instructions; not supported"),
                action: NSLocalizedString("Okay", comment: "Alert action"))
        }
        let number = "\(prefix)6468876437\(suffix)"
        UIPasteboard.general.string = number
        if SettingsManager.didSetUpVoicemail {
            var message = String.localizedStringWithFormat(
                NSLocalizedString("To set up voicemail again, dial this phone number:\n\n%@", comment: "Voicemail alert text; value is a number"),
                number)
            if let deactivation = config["all_conditional_deactivation"] {
                message = String.localizedStringWithFormat(
                    NSLocalizedString("To disable voicemail, dial this number:\n\n%@\n\n%@", comment: "Voicemail alert text; first value is a number, second value is the setup message"),
                    deactivation,
                    message)
            }
            return .showAlert(
                title: NSLocalizedString("Set Up Voicemail", comment: "Voicemail alert title"),
                message: message,
                action: NSLocalizedString("Copy Number", comment: "Voicemail alert action")
            )
        }
        SettingsManager.didSetUpVoicemail = true
        return .showAlert(
            title: NSLocalizedString("Set Up Voicemail", comment: "Voicemail alert title"),
            message: String.localizedStringWithFormat(
                NSLocalizedString("Dial this phone number by copying and pasting it on the blank space above your phone's keypad:\n\n%@", comment: "Voicemail alert text; value is a number"),
                number),
            action: NSLocalizedString("Copy Number", comment: "Voicemail alert action")
        )
    }

    // MARK: - Private

    fileprivate var available: Bool {
        if let config = VoicemailStream.config, let prefix = config["all_conditional_prefix"] {
            return prefix != ""
        }
        return false
    }

    fileprivate static var config: [String: String]? = {
        let info = CTTelephonyNetworkInfo()
        guard let
            carrier = info.subscriberCellularProvider,
            let mcc = carrier.mobileCountryCode,
            let mnc = carrier.mobileNetworkCode,
            let path = Bundle.main.path(forResource: "VoicemailConfig", ofType: "json"),
            let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
            let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
            let country = json[mcc] as? [String: Any],
            let network = country[mnc] as? [String: String]
        else {
            return nil
        }
        return network
    }()
}
