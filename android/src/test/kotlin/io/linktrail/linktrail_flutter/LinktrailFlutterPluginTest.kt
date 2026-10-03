package io.linktrail.linktrail_flutter

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test

internal class LinktrailFlutterPluginTest {
    // Android has no ATT-style gate: requestTrackingAuthorization is "not applicable" and resolves true.
    @Test
    fun onMethodCall_requestTrackingAuthorization_resolvesTrue() {
        val plugin = LinktrailFlutterPlugin()

        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall("requestTrackingAuthorization", null), mockResult)

        Mockito.verify(mockResult).success(true)
    }
}
