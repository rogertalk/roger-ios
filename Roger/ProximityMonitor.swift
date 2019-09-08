import CoreMotion
import UIKit

/// Monitors whether the phone is against the user's ear (unless headphones are connected).
class ProximityMonitor: NSObject {
    static let instance = ProximityMonitor()

    /// Event that triggers whenever the proximity state changes. The event value is a `Bool` indicating whether the phone is against the ear or not.
    let changed = Event<Bool>()

    /// Whether to actively monitor if the phone is against the ear.
    var active: Bool = false {
        didSet {
            if oldValue != self.active {
                self.updateProximityStatus()
            }
        }
    }

    /// The currently reported proximity state.
    fileprivate(set) var againstEar: Bool = false {
        didSet {
            if oldValue != self.againstEar {
                self.changed.emit(self.againstEar)
            }
        }
    }

    /// Whether this device has a proximity monitor or not.
    let supported: Bool

    /// Whether the phone is being held (as opposed to lying down on a surface).
    fileprivate(set) var vertical: Bool = true {
        didSet {
            if oldValue != self.vertical {
                self.updateProximityStatus()
            }
        }
    }

    override init() {
        // Detect if this device supports proximity monitoring.
        let device = UIDevice.current
        let wasEnabled = device.isProximityMonitoringEnabled
        device.isProximityMonitoringEnabled = true
        self.supported = device.isProximityMonitoringEnabled
        device.isProximityMonitoringEnabled = wasEnabled
        super.init()
        if !self.supported {
            return
        }
        // Listen for changes to proximity state.
        NotificationCenter.default.addObserver(self, selector: #selector(ProximityMonitor.updateProximityStatus), name: NSNotification.Name.UIDeviceProximityStateDidChange, object: nil)
        // Monitor the physical orientation of the device.
        self.motionManager.deviceMotionUpdateInterval = 0.1
        self.motionManager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: self.deviceQueue) {
            motion, error in
            guard let motion = motion else {
                return
            }
            self.vertical = motion.gravity.z > -0.6 && motion.gravity.z < 0.6
        }
    }

    deinit {
        if self.supported {
            NotificationCenter.default.removeObserver(self)
        }
    }

    dynamic func updateProximityStatus() {
        if !self.supported {
            return
        }
        let device = UIDevice.current
        let alreadyMonitoring = device.isProximityMonitoringEnabled
        let proximityOn = device.proximityState
        if proximityOn && !alreadyMonitoring {
            NSLog("[ProximityMonitor] Detected stuck state, fixing...")
            device.isProximityMonitoringEnabled = true
            return
        }
        // Check if the monitoring state needs to change AND the screen is not currently dark due to proximity.
        // This works around a bug where turning off monitoring while the screen is dark will get the state stuck.
        let shouldMonitor = self.active && self.vertical
        if shouldMonitor != alreadyMonitoring && !proximityOn {
            device.isProximityMonitoringEnabled = shouldMonitor
            if shouldMonitor {
                // Re-poll for the latest proximity state after a delay.
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(0.1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)) {
                    self.updateProximityStatus()
                }
            }
        }
        self.againstEar = shouldMonitor && proximityOn
    }

    // MARK: Private
    fileprivate let deviceQueue = OperationQueue()
    fileprivate let motionManager = CMMotionManager()
}
