package io.linktrail.linktrail_flutter

import io.linktrail.LinkTrailError
import kotlin.test.Test
import kotlin.test.assertEquals

internal class ErrorMapTest {
    @Test
    fun invalidEventMapsToInvalidEventWithReasonAndNativeMessage() {
        val map = LinkTrailError.InvalidEvent("name is blank").toErrorMap()
        assertEquals("invalidEvent", map["code"])
        assertEquals("Invalid event: name is blank", map["message"])
        assertEquals(mapOf("reason" to "name is blank"), map["details"])
    }

    @Test
    fun invalidEventReasonIsPassedThroughUnchanged() {
        val reason = "currency must be a 3-letter ISO 4217 code (got \"US\")"
        val map = LinkTrailError.InvalidEvent(reason).toErrorMap()
        assertEquals(mapOf("reason" to reason), map["details"])
        assertEquals("Invalid event: $reason", map["message"])
    }

    @Test
    fun serverKeepsStatusCodeAndBody() {
        val map = LinkTrailError.Server(503, "down").toErrorMap()
        assertEquals("server", map["code"])
        assertEquals(mapOf("statusCode" to 503, "body" to "down"), map["details"])
    }

    @Test
    fun nonLinkTrailErrorFallsBackToUnknown() {
        val map = IllegalStateException("boom").toErrorMap()
        assertEquals("unknown", map["code"])
        assertEquals("boom", map["message"])
    }
}
