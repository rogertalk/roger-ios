import UIKit

// TODO: This enum doesn't make sense.
enum Timespan { case unknown, dawn, day, dusk, night, dayRain, daySnow }

/// All the information needed to get a glimpse of a location.
struct GlimpseInfo {
    static let clearDay = GlimpseInfo(fixedTime: NSDate(year: 2015, month: 7, day: 31, hour: 13, minute: 0, second: 0) as Date, weather: .Clear)
    static let clearNight = GlimpseInfo(fixedTime: NSDate(year: 2015, month: 7, day: 31) as Date, weather: .Clear)
    static let snowNight = GlimpseInfo(fixedTime: NSDate(year: 2015, month: 7, day: 31) as Date, weather: .Snow)
    static let defaultState = GlimpseInfo(fixedTime: Date.distantFuture, weather: nil)

    let location: String
    let timeZone: String
    let weather: Weather.Phenomenon?

    init(fixedTime: Date, weather: Weather.Phenomenon?) {
        self.location = "New York"
        self.timeZone = "America/New_York"
        self.weather = weather
        self.fixedTime = fixedTime
    }

    init(location: String, timeZone: String) {
        self.location = location
        self.timeZone = timeZone
        self.weather = nil
        self.fixedTime = nil
    }

    init(location: String, timeZone: String, weather: Weather.Phenomenon?) {
        self.location = location
        self.timeZone = timeZone
        self.weather = weather
        self.fixedTime = nil
    }

    /// Density of clouds, from 0 to 1.
    var cloudDensity: Double {
        guard let weather = self.weather else {
            return 0
        }
        switch weather {
        case .Cloudy: return 1
        case .PartlyCloudy: return 1
        case .Fog: return 0.8
        case .Clear: return 0.8
        default: return 0
        }
    }

    /// The date and time adjusted for the time zone.
    var localTime: Date {
        if let time = self.fixedTime {
            return time
        }
        return Date().forTimeZone(self.timeZone)!
    }

    var hasClouds: Bool {
        guard let weather = self.weather else {
            return false
        }
        switch weather {
        case .Cloudy: return true
        case .PartlyCloudy: return true
        case .Fog: return true
        case .Clear: return true
        default: return false
        }
    }

    var hasHotAirBalloons: Bool {
        guard let weather = self.weather , self.localTime.isDaytime else {
            return false
        }
        switch weather {
        case .Clear: return true
        default: return false
        }
    }

    var hasShootingStar: Bool {
        guard let weather = self.weather , self.localTime.isNight else {
            return false
        }
        switch weather {
        case .Clear: return true
        default: return false
        }
    }

    var hasStars: Bool {
        guard let weather = self.weather , self.localTime.isNight else {
            return false
        }
        switch weather {
        case .Cloudy: return true
        case .PartlyCloudy: return true
        case .Clear: return true
        case .Wind: return true
        default: return false
        }
    }

    var isRaining: Bool {
        guard let weather = self.weather else {
            return false
        }
        switch weather {
        case .Rain: return true
        case .Sleet: return true
        default: return false
        }
    }

    var isSnowing: Bool {
        guard let weather = self.weather else {
            return false
        }
        switch weather {
        case .Snow: return true
        case .Sleet: return true
        default: return false
        }
    }


    var timespanDisplayInfo: (current: Timespan, incoming: Timespan, incomingAlpha: CGFloat) {
        var current = Timespan.unknown
        var incoming = Timespan.unknown
        var incomingSkyOpacity: CGFloat = 0
        let hour = CGFloat((self.localTime as NSDate).hour())
        let minute = CGFloat((self.localTime as NSDate).minute())

        if self.weather == nil {
            current = .unknown
            incoming = .unknown
            incomingSkyOpacity = 0
        } else if self.localTime.isDawn {
            // Dawn, 6AM - 8AM
            current = .dawn
            incoming = .day
            incomingSkyOpacity = hour < 7 ? 0 : minute / 60
        } else if self.localTime.isDaytime {
            // Day, 8AM - 6PM
            current = .day
            incoming = .dusk
            incomingSkyOpacity = hour < 17 ? 0 : minute / 60
        } else if self.localTime.isDusk {
            // Dusk, 6PM - 8PM
            current = .dusk
            incoming = .night
            incomingSkyOpacity = hour < 19 ? 0 : minute / 60
        } else {
            // Night, 8PM - 6AM
            current = .night
            incoming = .dawn
            incomingSkyOpacity = hour >= 20 || hour < 5 ? 0 : minute / 60
        }

        if self.isRaining {
            if hour >= 6 && hour < 19 {
                current = .dayRain
                incomingSkyOpacity = 0.0
            }
        } else if self.isSnowing {
            if hour >= 6 && hour < 19 {
                current = .daySnow
                incomingSkyOpacity = 0.0
            }
        }

        return (current, incoming, incomingSkyOpacity)
    }

    // MARK: - Private

    fileprivate let fixedTime: Date?
}
