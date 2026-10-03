package io.linktrail.linktrail_flutter

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result

/**
 * User identity (setUserId / logout) persistence + best-effort forwarding to the wrapped native
 * SDK. The pinned `io.linktrail:sdk` release predates user identity, so the SDK call is made via
 * reflection and silently skipped when the method does not exist. Dart validates the id and owns
 * consent gating; this class only persists and forwards.
 */
internal object UserIdentityBridge {
    private const val PREFS = "linktrail_flutter_identity"
    private const val KEY = "user_id"

    /** Returns true if [call] was an identity call and has been answered. */
    fun handle(context: Context, sdk: Any?, call: MethodCall, result: Result): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        when (call.method) {
            "getUserId" -> result.success(prefs.getString(KEY, null))
            "setUserId" -> {
                val userId = call.argument<String?>("userId")
                val consented = call.argument<Boolean>("consented") ?: false
                if (userId == null) prefs.edit().remove(KEY).apply() else prefs.edit().putString(KEY, userId).apply()
                if (sdk != null) forward(sdk, userId, consented)
                result.success(null)
            }
            else -> return false
        }
        return true
    }

    private fun forward(sdk: Any, userId: String?, consented: Boolean) {
        try {
            if (userId == null) {
                sdk.javaClass.getMethod("logout").invoke(sdk)
            } else if (consented) {
                sdk.javaClass.getMethod("setUserId", String::class.java).invoke(sdk, userId)
            }
        } catch (_: Throwable) {
            // Native SDK without identity support (or a failure): best-effort, never surfaced.
        }
    }
}
