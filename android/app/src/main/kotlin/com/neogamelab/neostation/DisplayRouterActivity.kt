package com.neogamelab.neostation

import android.app.Activity
import android.app.ActivityOptions
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.view.Display
import java.io.File

/**
 * Launcher activity that places NeoStation's primary UI on the display chosen
 * in Secondary Screen settings. Android owns the default display, so swapping
 * the interface means launching a separate activity on the other display.
 */
class DisplayRouterActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val secondaryDisplay = (getSystemService(Context.DISPLAY_SERVICE) as DisplayManager)
            .displays
            .firstOrNull { it.displayId != Display.DEFAULT_DISPLAY }

        if (PrimaryScreenPreference.isBottomSelected(this) && secondaryDisplay != null) {
            launchBottomPrimary(secondaryDisplay)
        } else {
            startActivity(Intent(this, MainActivity::class.java))
        }
        finish()
    }

    private fun launchBottomPrimary(display: Display) {
        // The default display hosts the Now Playing/secondary interface unless
        // the user has disabled that interface in Secondary Screen settings.
        if (!PrimaryScreenPreference.isSecondaryHidden(this)) {
            startActivity(
                Intent(this, SecondaryScreenActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
            )
        }

        val options = ActivityOptions.makeBasic().setLaunchDisplayId(display.displayId)
        startActivity(
            Intent(this, PrimaryScreenActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK),
            options.toBundle(),
        )
    }
}

/** Main Flutter activity when the user selects the bottom display. */
class PrimaryScreenActivity : MainActivity()

/** Reads the small preference directly so routing can happen before Flutter starts. */
object PrimaryScreenPreference {
    private fun read(context: Context): Pair<Boolean, Boolean> = try {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val customPath = prefs.getString("flutter.custom_user_data_path", null)
        val userDataDir = if (!customPath.isNullOrEmpty()) {
            File(customPath)
        } else {
            File(context.getExternalFilesDir(null), "user-data")
        }
        val dbFile = File(userDataDir, "data.sqlite")
        if (!dbFile.exists()) return false to false

        val db = android.database.sqlite.SQLiteDatabase.openDatabase(
            dbFile.absolutePath,
            null,
            android.database.sqlite.SQLiteDatabase.OPEN_READONLY,
        )
        val cursor = db.rawQuery(
            "SELECT primary_screen, hide_bottom_screen FROM user_config WHERE id = 1",
            null,
        )
        val hasConfig = cursor.moveToFirst()
        val selected = hasConfig && cursor.getString(0) == "bottom"
        val secondaryHidden = hasConfig && cursor.getInt(1) == 1
        cursor.close()
        db.close()
        selected to secondaryHidden
    } catch (_: Exception) {
        false to false
    }

    fun isBottomSelected(context: Context) = read(context).first

    fun isSecondaryHidden(context: Context) = read(context).second
}
