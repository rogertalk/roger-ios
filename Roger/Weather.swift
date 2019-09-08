import Foundation

class Weather: CustomDebugStringConvertible {
    enum Phenomenon: String, CustomStringConvertible {
        case Clear = "clear"
        case Cloudy = "cloudy"
        case Fog = "fog"
        case PartlyCloudy = "partly-cloudy"
        case Rain = "rain"
        case Sleet = "sleet"
        case Snow = "snow"
        case Wind = "wind"

        var description: String {
            switch self {
            case .Clear:
                return NSLocalizedString("clear", comment: "Weather")
            case .Cloudy:
                return NSLocalizedString("cloudy", comment: "Weather")
            case .Fog:
                return NSLocalizedString("fog", comment: "Weather")
            case .PartlyCloudy:
                return NSLocalizedString("partly cloudy", comment: "Weather")
            case .Rain:
                return NSLocalizedString("rain", comment: "Weather")
            case .Sleet:
                return NSLocalizedString("sleet", comment: "Weather")
            case .Snow:
                return NSLocalizedString("snow", comment: "Weather")
            case .Wind:
                return NSLocalizedString("wind", comment: "Weather")
            }
        }
    }

    let cloudiness: Double
    let phenomenon: Phenomenon
    let precipitation: Double
    let temperature: Double
    let wind: Double

    var debugDescription: String {
        return "Roger.Weather(\(self.phenomenon.rawValue) (\(Int(self.cloudiness * 100))% cover), \(self.temperature)°C, \(self.precipitation) mm/h precip., \(self.wind) m/s wind)"
    }

    init(data: DataType) {
        self.cloudiness = data["cloudiness"] as! Double
        self.phenomenon = Phenomenon(rawValue: data["weather"] as! String)!
        self.precipitation = data["precipitation"] as! Double
        self.temperature = data["temperature"] as! Double
        self.wind = data["wind"] as! Double
    }
}
