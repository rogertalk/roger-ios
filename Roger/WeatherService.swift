import Foundation

class WeatherService {
    static let instance = WeatherService()

    /// The currently tracked account id (for weather events). Setting this will request weather if not known.
    var trackedAccountId: Int64? {
        didSet {
            if self.trackedAccountId == oldValue {
                return
            }
            guard let id = self.trackedAccountId else {
                // Not tracking any account.
                self.weatherChanged.emit(nil)
                return
            }
            // Emit whatever weather we currently have for this account id.
            self.weatherChanged.emit(self.weather[id])
            if let date = self.lastFetch[id] , (date as NSDate).minutesAgo() < 1 {
                // The data we have is recent enough.
                return
            }
            self.updateWeatherData([id])
        }
    }
    var trackedWeather: Weather? {
        guard let id = self.trackedAccountId else {
            return nil
        }
        return self.weather[id]
    }
    // This maps to optional weather because knowing a user doesn't have weather vs. not knowing carries significance.
    fileprivate(set) var weather = [Int64: Weather]()
    /// Emits when the UI needs to update its weather based on what account id it's tracking.
    let weatherChanged = Event<Weather?>()

    deinit {
        BackendClient.instance.sessionChanged.removeListener(self)
    }

    init() {
        BackendClient.instance.sessionChanged.addListener(self, method: WeatherService.handleSessionChange)
    }

    func updateWeatherData() {
        guard let sessionId = BackendClient.instance.session?.id else {
            return
        }
        // Create a list of all account ids that we're interested in.
        var uniqueIds = Set(StreamService.instance.streams.flatMap { $0.value.otherParticipants.map { $0.id } })
        uniqueIds.insert(sessionId)
        if let id = self.trackedAccountId {
            uniqueIds.insert(id)
        }
        // Order is important, so use an array instead of a set when requesting the weather data.
        let accountIds = Array(uniqueIds)
        self.updateWeatherData(accountIds)
    }

    func updateWeatherData(_ accountIds: [Int64]) {
        let now = Date()
        // Filter out accounts that were updated very recently.
        let accountIds = accountIds.filter {
            if let session = BackendClient.instance.session , $0 == session.id && !session.hasLocation {
                // Don't try to get weather for current account if we know it'll fail.
                return false
            }
            guard let fetched = self.lastFetch[$0] else {
                return true
            }
            return (fetched as NSDate).minutesAgo() >= 1
        }
        if accountIds.count == 0 {
            return
        }
        // Indicate that we have requested data for these account ids just now.
        accountIds.forEach { self.lastFetch[$0] = now }
        // Retrieve the weather data from the backend.
        Intent.getWeather(accountIds: accountIds).perform(BackendClient.instance) {
            guard let result = $0.data , $0.successful else {
                return
            }
            for (id, data) in zip(accountIds, result["data"] as! [AnyObject]) {
                let weather = (data as? DataType).flatMap { Weather(data: $0) }
                self.weather[id] = weather
                if id == self.trackedAccountId {
                    // TODO: Only if the weather changed visually.
                    self.weatherChanged.emit(weather)
                }
            }
        }
    }

    // MARK: - Private

    func handleSessionChange() {
        // Update weather data when the session changes (in case location settings changed).
        self.updateWeatherData()
    }

    /// When the weather data was last fetched for a particular account id.
    fileprivate var lastFetch = [Int64: Date]()
}
