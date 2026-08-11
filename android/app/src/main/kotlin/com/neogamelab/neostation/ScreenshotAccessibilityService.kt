package com.neogamelab.neostation

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Build
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityWindowInfo

/**
 * Accessibility service with two jobs:
 *  1. Fire a system screenshot on request (the genuine OS screenshot of the main
 *     display), triggered from [MainActivity] via the static reference below.
 *  2. Watch window changes so the secondary "Now Playing" panel can be restored
 *     the instant a dock-launched app is dismissed (back press) on the bottom
 *     display — Android gives normal apps no other signal for this.
 */
class ScreenshotAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile
        private var instance: ScreenshotAccessibilityService? = null

        /** True when the service is connected and able to take a screenshot. */
        val isConnected: Boolean
            get() = instance != null

        /**
         * Invoked when the service connects (the user just enabled it). Lets the
         * app re-push accessibility state to the secondary display while a game
         * is running — the main engine is backgrounded then, so it can't observe
         * the grant via its own lifecycle.
         */
        @Volatile
        var onConnected: (() -> Unit)? = null

        // --- Dock app-close watch ---
        @Volatile
        private var watchedPackage: String? = null
        @Volatile
        private var watchedDisplayId: Int = -1
        @Volatile
        private var onWatchedAppClosed: (() -> Unit)? = null
        @Volatile
        private var watchedRequireHome: Boolean = true

        /**
         * Starts watching [displayId] for the dismissal of [packageName].
         *
         * When [requireHome] is true (the dock-app default), [onClosed] fires
         * only once the display has gone back to its launcher/home — the
         * back-out case for a normal dock-launched app. A game launched via
         * "open on second screen" has no home screen to fall back to on that
         * display, so its callers pass false: [onClosed] fires as soon as
         * [packageName] is no longer the topmost application window, however
         * the display got there.
         */
        fun startWatch(
            packageName: String,
            displayId: Int,
            requireHome: Boolean = true,
            onClosed: () -> Unit
        ) {
            watchedPackage = packageName
            watchedDisplayId = displayId
            watchedRequireHome = requireHome
            onWatchedAppClosed = onClosed
        }

        /** Cancels any in-progress app-close watch. */
        fun stopWatch() {
            watchedPackage = null
            watchedDisplayId = -1
            onWatchedAppClosed = null
        }

        /**
         * Performs a system screenshot via the global action. Returns false when
         * the service is not connected (user hasn't granted access).
         */
        fun takeScreenshot(): Boolean {
            val service = instance ?: return false
            return service.performGlobalAction(GLOBAL_ACTION_TAKE_SCREENSHOT)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        onConnected?.invoke()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        stopWatch()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        stopWatch()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val watched = watchedPackage ?: return
        val displayId = watchedDisplayId
        if (displayId < 0) return
        try {
            val top = topAppPackageOnDisplay(displayId) ?: return
            // Dock apps: restore only once the display has gone back to its
            // home/launcher (the back-out case), not when a transient dialog
            // appears over the app. Games (requireHome = false): the display has
            // no home to fall back to, so any other topmost package means the
            // game is gone.
            if (top != watched && (!watchedRequireHome || isHomePackage(top))) {
                val cb = onWatchedAppClosed
                stopWatch()
                cb?.invoke()
            }
        } catch (e: Exception) {
            // Window introspection is best-effort; ignore transient failures.
        }
    }

    /** Package of the topmost application window on [displayId], or null. */
    private fun topAppPackageOnDisplay(displayId: Int): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val list = windowsOnAllDisplays.get(displayId) ?: return null
        val top = list
            .filter { it.type == AccessibilityWindowInfo.TYPE_APPLICATION }
            .maxByOrNull { it.layer }
            ?: return null
        return top.root?.packageName?.toString()
    }

    /** Whether [pkg] is a home/launcher (covers the device's secondary launcher). */
    private fun isHomePackage(pkg: String): Boolean {
        val homeIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val homePkg = packageManager.resolveActivity(homeIntent, 0)?.activityInfo?.packageName
        return pkg == homePkg || pkg.contains("launcher", ignoreCase = true)
    }

    override fun onInterrupt() {}
}
