import Foundation

/// Hands native events to a Dart stream sink, holding them while no Dart listener is attached.
///
/// Events that arrive with no sink are queued (oldest dropped past `capacity`) and flushed, in
/// order, to the next sink that attaches. The queue lives only for the app process. With
/// `keepLastOnly` the relay keeps just the latest value (used for attribution). Main thread only.
final class EventRelay<T> {
  private let capacity: Int
  private let keepLastOnly: Bool
  private var pending: [T] = []
  private var sink: ((T) -> Void)?

  init(capacity: Int = 10, keepLastOnly: Bool = false) {
    self.capacity = capacity
    self.keepLastOnly = keepLastOnly
  }

  func send(_ event: T) {
    if let sink {
      sink(event)
      return
    }
    if keepLastOnly { pending.removeAll() }
    pending.append(event)
    if pending.count > capacity { pending.removeFirst(pending.count - capacity) }
  }

  func attach(_ newSink: @escaping (T) -> Void) {
    sink = newSink
    let queued = pending
    pending.removeAll()
    queued.forEach(newSink)
  }

  func detach() { sink = nil }
}
