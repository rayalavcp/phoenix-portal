package me.jxl.kiosk_satellite

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Phoenix Portal's app store installer: installs another app's APK through a
 * PackageInstaller session and Android's own confirmation screen. Separate
 * from [ApkInstaller], which is built around replacing this app itself (its
 * session names this package, its outcome relaunches the kiosk).
 *
 * On a Gen-1 Portal the confirmation screen is only usable once provisioning
 * has disabled Meta's white-on-white overlay (phoenix-provision.sh does).
 *
 * Channel "phoenix/store":
 *  - install {path, package} -> true once committed; the outcome follows as
 *    a "status" call {package, state: confirm|installed|failed, message}
 *  - versions {packages} -> {package: versionName or null}
 */
class StoreInstaller(private val context: Context, messenger: BinaryMessenger) {
    companion object {
        private const val TAG = "StoreInstaller"
        private const val ACTION_STATUS = "me.jxl.kiosk_satellite.STORE_INSTALL_STATUS"
        private const val EXTRA_PACKAGE = "phoenix.package"
    }

    private val channel = MethodChannel(messenger, "phoenix/store")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            if (intent.action != ACTION_STATUS) return
            val pkg = intent.getStringExtra(EXTRA_PACKAGE) ?: ""
            when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
                PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                    @Suppress("DEPRECATION")
                    val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                    if (confirm != null) {
                        confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        try {
                            context.startActivity(confirm)
                            notify(pkg, "confirm", null)
                        } catch (e: Exception) {
                            notify(pkg, "failed", "Android's install screen could not open: ${e.message}")
                        }
                    } else {
                        notify(pkg, "failed", "Android asked for a confirmation it did not provide")
                    }
                }
                PackageInstaller.STATUS_SUCCESS -> notify(pkg, "installed", null)
                else -> {
                    val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "status $status"
                    Log.w(TAG, "install of $pkg failed: $message")
                    notify(pkg, "failed", message)
                }
            }
        }
    }

    init {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, IntentFilter(ACTION_STATUS), Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, IntentFilter(ACTION_STATUS))
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "install" -> {
                    val path = call.argument<String>("path")
                    val pkg = call.argument<String>("package")
                    if (path == null || pkg == null) {
                        result.error("args", "path and package are required", null)
                        return@setMethodCallHandler
                    }
                    worker.execute {
                        try {
                            install(File(path), pkg)
                            main.post { result.success(true) }
                        } catch (e: Exception) {
                            Log.w(TAG, "could not start the install of $pkg", e)
                            main.post { result.error("install", e.message, null) }
                        }
                    }
                }
                "versions" -> {
                    val packages = call.argument<List<String>>("packages") ?: emptyList()
                    result.success(packages.associateWith { versionOf(it) })
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun versionOf(pkg: String): String? = try {
        context.packageManager.getPackageInfo(pkg, 0).versionName ?: ""
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }

    private fun install(apk: File, pkg: String) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(pkg)
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            session.openWrite("base.apk", 0, apk.length()).use { out ->
                apk.inputStream().use { it.copyTo(out) }
                session.fsync(out)
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val status = PendingIntent.getBroadcast(
                context, sessionId,
                Intent(ACTION_STATUS).setPackage(context.packageName).putExtra(EXTRA_PACKAGE, pkg),
                flags,
            )
            session.commit(status.intentSender)
        }
        // The APK has been copied into the session; the download is no longer needed.
        apk.delete()
    }

    private fun notify(pkg: String, state: String, message: String?) {
        main.post {
            channel.invokeMethod("status", mapOf("package" to pkg, "state" to state, "message" to message))
        }
    }
}
