import Foundation

private class Invoker<EventData> {
    weak var listener: AnyObject?
    let closure: (EventData) -> Bool

    init<Listener: AnyObject>(listener: Listener, method: @escaping (Listener) -> (EventData) -> Void) {
        self.listener = listener
        self.closure = {
            [weak listener] (data: EventData) in
            guard let listener = listener else {
                return false
            }
            method(listener)(data)
            return true
        }
    }
}

class Event<EventData> {
    fileprivate var invokers = [Invoker<EventData>]()

    /// Adds an event listener, notifying the provided method when the event is emitted.
    func addListener<Listener: AnyObject>(_ listener: Listener, method: @escaping (Listener) -> (EventData) -> Void) {
        invokers.append(Invoker(listener: listener, method: method))
    }

    /// Removes the object from the list of objects that get notified of the event.
    func removeListener(_ listener: AnyObject) {
        invokers = invokers.filter {
            guard let current = $0.listener else {
                return false
            }
            return current !== listener
        }
    }

    /// Publishes the specified data to all listeners via the main queue.
    func emit(_ data: EventData) {
        let queue = DispatchQueue.main
        for invoker in invokers {
            queue.async {
                // TODO: If this returns false, we should remove the invoker from the list.
                _ = invoker.closure(data)
            }
        }
    }
}
