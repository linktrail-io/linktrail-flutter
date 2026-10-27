package io.linktrail.linktrail_flutter

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

internal class EventRelayTest {
    @Test
    fun buffersUntilFirstListenerThenFlushesInOrderOnce() {
        val relay = EventRelay<String>()
        relay.send("a")
        relay.send("b")
        val first = mutableListOf<String>()
        relay.attach { first += it }
        assertEquals(listOf("a", "b"), first)

        relay.send("c")
        assertEquals(listOf("a", "b", "c"), first)

        val second = mutableListOf<String>()
        relay.attach { second += it }
        assertTrue(second.isEmpty(), "later listeners get no replay")
    }

    @Test
    fun capsBufferAtTenDroppingOldest() {
        val relay = EventRelay<Int>()
        (1..12).forEach(relay::send)
        val got = mutableListOf<Int>()
        relay.attach { got += it }
        assertEquals((3..12).toList(), got)
    }

    @Test
    fun keepsEventsArrivingWhileDetached() {
        val relay = EventRelay<String>()
        relay.attach { }
        relay.detach()
        relay.send("claimed-while-detached")
        val got = mutableListOf<String>()
        relay.attach { got += it }
        assertEquals(listOf("claimed-while-detached"), got)
    }

    @Test
    fun keepLastOnlyReplaysLatestValue() {
        val relay = EventRelay<String>(keepLastOnly = true)
        relay.send("old")
        relay.send("new")
        val got = mutableListOf<String>()
        relay.attach { got += it }
        assertEquals(listOf("new"), got)
    }
}
