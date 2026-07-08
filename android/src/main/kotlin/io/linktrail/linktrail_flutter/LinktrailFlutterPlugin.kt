package io.linktrail.linktrail_flutter

import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import io.linktrail.LinkTrail
import io.linktrail.LinkTrailError
import io.linktrail.LinkTrailLogLevel
import io.linktrail.LinkTrailOptions
import io.linktrail.LinkTrailRetryPolicy
import io.linktrail.model.LinkTrailAttribution
import io.linktrail.model.LinkTrailDeepLink
import io.linktrail.model.LinkTrailEventResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** Flutter plugin wrapping the native `io.linktrail:sdk` Android SDK. */
class LinktrailFlutterPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.NewIntentListener {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var onLinkChannel: EventChannel
    private lateinit var onAttributionChannel: EventChannel
    private lateinit var onErrorChannel: EventChannel

    private var onLinkSink: EventChannel.EventSink? = null
    private var onAttributionSink: EventChannel.EventSink? = null
    private var onErrorSink: EventChannel.EventSink? = null

    private var activityBinding: ActivityPluginBinding? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // On a cold start the launch intent is read (in onAttachedToActivity) before Dart has called
    // configure(), so LinkTrail.shared is still null and the link would be lost. Buffer it here and
    // replay it once configure() runs. Warm starts (app already configured) handle links directly.
    private var pendingLaunchUri: Uri? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        val messenger: BinaryMessenger = binding.binaryMessenger

        channel = MethodChannel(messenger, "linktrail_flutter")
        channel.setMethodCallHandler(this)

        onLinkChannel = EventChannel(messenger, "linktrail_flutter/onLink")
        onLinkChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    onLinkSink = events
                    attachHooks()
                }

                override fun onCancel(arguments: Any?) {
                    onLinkSink = null
                }
            },
        )

        onAttributionChannel = EventChannel(messenger, "linktrail_flutter/onAttribution")
        onAttributionChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    onAttributionSink = events
                    attachHooks()
                }

                override fun onCancel(arguments: Any?) {
                    onAttributionSink = null
                }
            },
        )

        onErrorChannel = EventChannel(messenger, "linktrail_flutter/onError")
        onErrorChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    onErrorSink = events
                    attachHooks()
                }

                override fun onCancel(arguments: Any?) {
                    onErrorSink = null
                }
            },
        )
    }

    /** (Re)registers the native callback hooks on the current `LinkTrail.shared` instance. */
    private fun attachHooks() {
        val sdk = LinkTrail.shared ?: return
        sdk.onLink { link, source ->
            onLinkSink?.success(mapOf("link" to link.toMap(), "source" to source.name.lowercase()))
        }
        sdk.onAttribution { attribution -> onAttributionSink?.success(attribution.toMap()) }
        sdk.onError { throwable -> onErrorSink?.success(throwable.toErrorMap()) }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "configure" -> {
                val apiKey = call.argument<String>("apiKey")
                if (apiKey == null) {
                    result.error("missingApiKey", "An API key is required to configure LinkTrail.", null)
                    return
                }
                try {
                    @Suppress("UNCHECKED_CAST")
                    val optionsMap = call.argument<Map<String, Any?>>("options")
                    LinkTrail.configure(context, apiKey, parseOptions(optionsMap))
                    attachHooks()
                    // Replay a deep link that launched the app cold, before the SDK was configured.
                    pendingLaunchUri?.let { uri ->
                        pendingLaunchUri = null
                        LinkTrail.shared?.handleDeepLink(uri)
                    }
                    result.success(null)
                } catch (e: Throwable) {
                    result.error(e)
                }
            }

            "handleDeepLink" -> {
                val urlString = call.argument<String>("url")
                val sdk = LinkTrail.shared
                if (urlString == null || sdk == null) {
                    result.success(false)
                    return
                }
                result.success(sdk.handleDeepLink(Uri.parse(urlString)))
            }

            "trackInstall" -> {
                val force = call.argument<Boolean>("force") ?: false
                val sdk = LinkTrail.shared ?: return result.errorNotConfigured()
                scope.launch {
                    try {
                        result.success(sdk.trackInstallAsync(force).toMap())
                    } catch (e: Throwable) {
                        result.error(e)
                    }
                }
            }

            "trackEvent" -> {
                val name = call.argument<String>("name")
                val value = call.argument<Double>("value")
                val currency = call.argument<String>("currency")
                val sdk = LinkTrail.shared ?: return result.errorNotConfigured()
                if (name == null) {
                    result.error("invalidArgument", "trackEvent requires a name.", null)
                    return
                }
                scope.launch {
                    try {
                        result.success(sdk.trackEventAsync(name, value, currency).toMap())
                    } catch (e: Throwable) {
                        result.error(e)
                    }
                }
            }

            "getLastAttribution" -> result.success(LinkTrail.shared?.lastAttribution?.toMap())
            "getLastDeepLink" -> result.success(LinkTrail.shared?.lastDeepLink?.toMap())

            // ATT / SKAdNetwork are iOS-only concepts; no-ops on Android.
            "requestTrackingAuthorization" -> result.success(true)
            "registerForSKAdAttribution" -> result.success(null)
            "updateConversionValue" -> result.success(null)

            "resetForTesting" -> {
                LinkTrail.resetForTesting(context)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun Result.errorNotConfigured() {
        error("notConfigured", "LinkTrail.configure() must be called before this method.", null)
    }

    private fun Result.error(e: Throwable) {
        val map = e.toErrorMap()
        error(map["code"] as String, map["message"] as String?, map["details"])
    }

    private fun parseOptions(map: Map<String, Any?>?): LinkTrailOptions {
        if (map == null) return LinkTrailOptions()
        @Suppress("UNCHECKED_CAST")
        val retryMap = map["retryPolicy"] as? Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val linkDomains = (map["linkDomains"] as? List<String>) ?: emptyList()
        return LinkTrailOptions(
            logEnabled = map["logEnabled"] as? Boolean ?: false,
            logLevel = LinkTrailLogLevel.valueOf((map["logLevel"] as? String ?: "info").uppercase()),
            requestTimeoutMillis = (map["requestTimeoutMillis"] as? Number)?.toLong() ?: 15_000L,
            retryPolicy =
                LinkTrailRetryPolicy(
                    maxAttempts = (retryMap?.get("maxAttempts") as? Number)?.toInt() ?: 3,
                    baseDelayMillis = (retryMap?.get("baseDelayMillis") as? Number)?.toLong() ?: 500L,
                    maxDelayMillis = (retryMap?.get("maxDelayMillis") as? Number)?.toLong() ?: 8_000L,
                ),
            linkDomains = linkDomains,
            autoTrackInstall = map["autoTrackInstall"] as? Boolean ?: true,
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        onLinkChannel.setStreamHandler(null)
        onAttributionChannel.setStreamHandler(null)
        onErrorChannel.setStreamHandler(null)
    }

    // -- ActivityAware: auto-capture incoming deep links, no consumer boilerplate required. --

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        binding.activity.intent?.data?.let(::handleOrBufferLaunchUri)
    }

    /** Handle the launch URI now if the SDK is configured, otherwise buffer it for replay after configure(). */
    private fun handleOrBufferLaunchUri(uri: Uri) {
        val sdk = LinkTrail.shared
        if (sdk != null) sdk.handleDeepLink(uri) else pendingLaunchUri = uri
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() = detachActivity()

    private fun detachActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    override fun onNewIntent(intent: Intent): Boolean {
        intent.data?.let { uri -> LinkTrail.shared?.handleDeepLink(uri) }
        return false
    }
}

private fun LinkTrailDeepLink.toMap(): Map<String, Any?> =
    mapOf(
        "slug" to slug,
        "url" to url,
        "deepLinkPath" to deepLinkPath,
        "iosUrl" to iosUrl,
        "androidUrl" to androidUrl,
        "fallbackUrl" to fallbackUrl,
        "campaign" to campaign,
        "channel" to channel,
        "utm" to utm,
        "customData" to customData,
    )

private fun LinkTrailAttribution.toMap(): Map<String, Any?> =
    mapOf("id" to id, "attributed" to attributed, "deepLink" to deepLink?.toMap())

private fun LinkTrailEventResult.toMap(): Map<String, Any?> = mapOf("id" to id, "attributed" to attributed)

/** Maps a caught native error to `{code, message, details}`, matching the Dart `LinkTrailException` codes. */
private fun Throwable.toErrorMap(): Map<String, Any?> {
    val noDetails = emptyMap<String, Any?>()
    val (code, details) =
        when (this) {
            is LinkTrailError.InvalidUrl -> "invalidUrl" to mapOf<String, Any?>("url" to url)
            is LinkTrailError.Transport -> "transport" to noDetails
            is LinkTrailError.Server -> "server" to mapOf<String, Any?>("statusCode" to statusCode, "body" to body)
            is LinkTrailError.Decoding -> "decoding" to noDetails
            is LinkTrailError.EmptyResponse -> "emptyResponse" to noDetails
            is LinkTrailError.NotALinkTrailUrl -> "notALinkTrailUrl" to noDetails
            is LinkTrailError.MissingApiKey -> "missingApiKey" to noDetails
            is LinkTrailError.InvalidApiKey -> "invalidApiKey" to noDetails
            else -> "unknown" to noDetails
        }
    return mapOf("code" to code, "message" to (message ?: code), "details" to details)
}
