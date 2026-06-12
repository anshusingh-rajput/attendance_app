package com.hr360flow.hr360flow

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.annotation.NonNull
import androidx.core.content.ContextCompat
import com.google.android.gms.auth.api.identity.GetPhoneNumberHintIntentRequest
import com.google.android.gms.auth.api.identity.Identity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.hr360flow.hr360flow/sim"
    private val PHONE_HINT_REQUEST = 7341
    private var phoneHintResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSimCards" -> result.success(getSimCards())
                    "requestPhoneNumberHint" -> requestPhoneNumberHint(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestPhoneNumberHint(result: MethodChannel.Result) {
        // Only one in-flight request at a time.
        phoneHintResult?.success(null)
        phoneHintResult = result

        val request = GetPhoneNumberHintIntentRequest.builder().build()
        Identity.getSignInClient(this)
            .getPhoneNumberHintIntent(request)
            .addOnSuccessListener { pendingIntent ->
                try {
                    startIntentSenderForResult(
                        pendingIntent.intentSender,
                        PHONE_HINT_REQUEST,
                        null, 0, 0, 0
                    )
                } catch (e: IntentSender.SendIntentException) {
                    phoneHintResult?.success(null)
                    phoneHintResult = null
                }
            }
            .addOnFailureListener {
                // No Play Services / no numbers available on this device.
                phoneHintResult?.success(null)
                phoneHintResult = null
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PHONE_HINT_REQUEST) return
        val pending = phoneHintResult
        phoneHintResult = null
        if (pending == null) return
        if (resultCode == Activity.RESULT_OK && data != null) {
            try {
                val number = Identity.getSignInClient(this)
                    .getPhoneNumberFromIntent(data)
                pending.success(number)
            } catch (e: Exception) {
                pending.success(null)
            }
        } else {
            // User dismissed the picker.
            pending.success(null)
        }
    }

    private fun getSimCards(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val hasPhoneState = ContextCompat.checkSelfPermission(
            this, Manifest.permission.READ_PHONE_STATE
        ) == PackageManager.PERMISSION_GRANTED
        // READ_PHONE_STATE is enough to LIST the SIMs (carrier/slot).
        // The phone number additionally needs READ_PHONE_NUMBERS, but we must
        // still return the SIM entries (with empty number) when that is missing,
        // otherwise the picker shows nothing at all on some devices.
        if (!hasPhoneState) return out

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP_MR1) {
            // Single SIM fallback for very old Android
            val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            try {
                val number = tm.line1Number
                if (!number.isNullOrEmpty()) {
                    out.add(
                        mapOf(
                            "slotIndex" to 0,
                            "carrierName" to (tm.networkOperatorName ?: ""),
                            "number" to number
                        )
                    )
                }
            } catch (_: SecurityException) {
            }
            return out
        }

        val sm = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
            as SubscriptionManager
        val subs: List<SubscriptionInfo>? = try {
            sm.activeSubscriptionInfoList
        } catch (e: SecurityException) {
            null
        }
        if (subs == null) return out

        for (sub in subs) {
            var number: String? = null
            try {
                // SubscriptionInfo.getNumber() requires READ_PHONE_NUMBERS
                number = sub.number
            } catch (_: SecurityException) {
            }
            // If number not available via SubscriptionInfo, fall back to TelephonyManager
            if (number.isNullOrEmpty() &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
            ) {
                try {
                    val baseTm =
                        getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                    val perSubTm = baseTm.createForSubscriptionId(sub.subscriptionId)
                    number = perSubTm.line1Number
                } catch (_: SecurityException) {
                } catch (_: Exception) {
                }
            }

            out.add(
                mapOf(
                    "slotIndex" to sub.simSlotIndex,
                    "carrierName" to (sub.carrierName?.toString() ?: ""),
                    "displayName" to (sub.displayName?.toString() ?: ""),
                    "number" to (number ?: "")
                )
            )
        }
        return out
    }
}
