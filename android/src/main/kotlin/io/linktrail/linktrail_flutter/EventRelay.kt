package io.linktrail.linktrail_flutter

/**
 * Hands native events to a Dart stream sink, holding them while no Dart listener is attached.
 *
 * Events that arrive with no sink are queued (oldest dropped past [capacity]) and flushed, in order,
 * to the next sink that attaches. The queue lives only for the app process. With [keepLastOnly] the
 * relay keeps just the latest value (used for attribution).
 */
internal class EventRelay<T>(
    private val capacity: Int = 10,
    private val keepLastOnly: Boolean = false,
) {
    private val pending = ArrayDeque<T>()
    private var sink: ((T) -> Unit)? = null

    val hasListener: Boolean get() = sink != null

    fun send(event: T) {
        val current = sink
        if (current != null) {
            current(event)
            return
        }
        if (keepLastOnly) pending.clear()
        pending.addLast(event)
        while (pending.size > capacity) pending.removeFirst()
    }

    fun attach(newSink: (T) -> Unit) {
        sink = newSink
        while (pending.isNotEmpty()) newSink(pending.removeFirst())
    }

    fun detach() {
        sink = null
    }
}
