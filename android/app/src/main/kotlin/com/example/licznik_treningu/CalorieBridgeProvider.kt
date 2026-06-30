package com.example.licznik_treningu

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import org.json.JSONArray

/**
 * Udostępnia aplikacji Licznik Kalorii spalone kcal z treningów Trainera.
 *
 * Dane pochodzą z mostu zapisywanego przez Flutter (SharedPreferences) i są tylko
 * do ODCZYTU. Dostęp chroni uprawnienie o poziomie `signature` — odczytać może
 * wyłącznie aplikacja podpisana tym samym kluczem co Trainer.
 *
 * URI:  content://com.example.licznik_treningu.calorie_bridge/impacts
 * Kolumny: dedup_key, session_id, session_name, date_key, date, kcal,
 *          duration_min, activity_type, source, payload (pełny JSON).
 *
 * WAŻNE dla Licznika: nie dubluj aktywności — używaj `dedup_key` jako klucza,
 * a `source`/`activity_type` do opisania, że wpis pochodzi z treningu Trainera.
 */
class CalorieBridgeProvider : ContentProvider() {

    companion object {
        private const val PREFS = "FlutterSharedPreferences"
        // shared_preferences (Flutter) prefiksuje klucze "flutter."
        private const val QUEUE_KEY = "flutter.trainer_calorie_bridge_training_impacts_v1"
        private val COLUMNS = arrayOf(
            "dedup_key", "session_id", "session_name", "date_key", "date",
            "kcal", "duration_min", "activity_type", "source", "payload"
        )
    }

    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor {
        val cursor = MatrixCursor(COLUMNS)
        val ctx = context ?: return cursor
        try {
            val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val raw = prefs.getString(QUEUE_KEY, null) ?: return cursor
            val array = JSONArray(raw)
            for (i in 0 until array.length()) {
                val obj = array.optJSONObject(i) ?: continue
                cursor.addRow(
                    arrayOf<Any?>(
                        obj.optString("deduplicationKey"),
                        obj.optString("sessionId"),
                        obj.optString("sessionName"),
                        obj.optString("dateKey"),
                        obj.optString("date"),
                        obj.optInt("estimatedBurnedKcal"),
                        obj.optInt("durationMin"),
                        obj.optString("activityType", "strength_training"),
                        obj.optString("source", "Trainer"),
                        obj.toString()
                    )
                )
            }
        } catch (e: Exception) {
            // Bez crasha — przy błędzie zwracamy pusty kursor.
        }
        return cursor
    }

    override fun getType(uri: Uri): String =
        "vnd.android.cursor.dir/vnd.com.example.licznik_treningu.calorie_bridge"

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
