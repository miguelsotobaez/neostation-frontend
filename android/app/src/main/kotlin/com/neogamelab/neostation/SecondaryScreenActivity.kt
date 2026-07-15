package com.neogamelab.neostation

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.lang.ref.WeakReference

/** Hosts the Now Playing UI on the top display when the main UI is below. */
class SecondaryScreenActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.neogamelab.neostation/secondary_apps"
        private var activeInstance: WeakReference<SecondaryScreenActivity>? = null

        fun closeForDisplayRestart() {
            activeInstance?.get()?.finishAndRemoveTask()
            activeInstance = null
        }
    }

    override fun getDartEntrypointFunctionName() = "subDisplay"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        activeInstance = WeakReference(this)
    }

    override fun onDestroy() {
        if (activeInstance?.get() === this) activeInstance = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstalledApps" -> getInstalledApps(result)
                    "getAppIcon" -> {
                        val packageName = call.argument<String>("packageName")
                        if (packageName == null) result.error("INVALID_ARGUMENTS", "Package name is required", null)
                        else getAppIcon(packageName, result)
                    }
                    "launchAppOnSecondary" -> {
                        val packageName = call.argument<String>("packageName")
                        if (packageName == null) result.error("INVALID_ARGUMENTS", "Package name is required", null)
                        else launchAppOnThisDisplay(packageName, result)
                    }
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getInstalledApps(result: MethodChannel.Result) {
        Thread {
            try {
                val launcherIntent = Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_LAUNCHER) }
                val processed = mutableSetOf<String>()
                val apps = mutableListOf<Map<String, Any>>()
                for (resolveInfo in packageManager.queryIntentActivities(launcherIntent, 0)) {
                    val activityInfo = resolveInfo.activityInfo
                    val packageName = activityInfo.packageName
                    if (!processed.add(packageName) || packageName == this.packageName) continue
                    val appInfo = activityInfo.applicationInfo
                    val packageInfo = try { packageManager.getPackageInfo(packageName, 0) } catch (_: Exception) { null }
                    val version = packageInfo?.versionName.orEmpty()
                    apps.add(mapOf(
                        "name" to resolveInfo.loadLabel(packageManager).toString(),
                        "package" to packageName,
                        "isSystemApp" to ((appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                        "isGame" to false,
                        "firstInstallTime" to (packageInfo?.firstInstallTime ?: 0L),
                        "version" to version,
                        "description" to "Android Application ($version)",
                    ))
                }
                apps.sortBy { it["name"].toString().lowercase() }
                runOnUiThread { result.success(apps) }
            } catch (e: Exception) {
                runOnUiThread { result.error("FETCH_FAILED", e.message, null) }
            }
        }.start()
    }

    private fun getAppIcon(packageName: String, result: MethodChannel.Result) {
        Thread {
            try {
                val drawable = packageManager.getApplicationIcon(packageName)
                val bitmap = if (drawable is BitmapDrawable) drawable.bitmap else Bitmap.createBitmap(
                    drawable.intrinsicWidth.coerceAtLeast(1), drawable.intrinsicHeight.coerceAtLeast(1), Bitmap.Config.ARGB_8888,
                ).also { drawable.setBounds(0, 0, it.width, it.height); drawable.draw(Canvas(it)) }
                val bytes = ByteArrayOutputStream().use { stream ->
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                    stream.toByteArray()
                }
                runOnUiThread { result.success(bytes) }
            } catch (e: Exception) {
                runOnUiThread { result.error("ICON_ERROR", e.message, null) }
            }
        }.start()
    }

    private fun launchAppOnThisDisplay(packageName: String, result: MethodChannel.Result) {
        try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            if (intent == null) {
                result.error("LAUNCH_FAILED", "Could not find launch intent for package", null)
                return
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            val options = android.app.ActivityOptions.makeBasic().setLaunchDisplayId(windowManager.defaultDisplay.displayId)
            startActivity(intent, options.toBundle())
            result.success(true)
        } catch (e: Exception) {
            result.error("LAUNCH_FAILED", e.message, null)
        }
    }
}
