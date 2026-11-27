package com.aistudio.zametki

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/** «Закреплённая заметка»: самая свежая из закреплённых (выбирает приложение). */
class PinnedNoteWidgetProvider : HomeWidgetProvider() {
    private companion object {
        const val PADDING_DP = 24
        const val HEAD_DP = 44
        const val LINE_DP = 19
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val raw = widgetData.getString("pinned", "") ?: ""
        val note = try {
            if (raw.isEmpty()) null else JSONObject(raw)
        } catch (e: Exception) {
            null
        }
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.widget_pinned)
            if (note == null) {
                views.setInt(R.id.bg, "setColorFilter", context.getColor(R.color.widget_surface))
                views.setViewVisibility(R.id.head, View.GONE)
                views.setViewVisibility(R.id.body, View.GONE)
                views.setViewVisibility(R.id.empty, View.VISIBLE)
                views.setOnClickPendingIntent(R.id.root, WidgetUtil.launch(context, null))
            } else {
                val h = WidgetUtil.heightDp(appWidgetManager, id)
                val lines = ((h - PADDING_DP - HEAD_DP) / LINE_DP).coerceAtLeast(1)
                views.setInt(R.id.bg, "setColorFilter", WidgetUtil.noteColor(context, note.optInt("color")))
                views.setInt(R.id.pin, "setColorFilter", context.getColor(R.color.widget_primary))
                views.setViewVisibility(R.id.head, View.VISIBLE)
                views.setViewVisibility(R.id.empty, View.GONE)
                views.setViewVisibility(R.id.body, View.VISIBLE)
                views.setTextViewText(R.id.title, note.optString("title"))
                views.setTextViewText(R.id.body, note.optString("text"))
                views.setInt(R.id.body, "setMaxLines", lines)
                val noteId = note.optInt("id", -1)
                views.setOnClickPendingIntent(
                    R.id.root,
                    WidgetUtil.launch(context, if (noteId < 0) null else "zametki://note/$noteId"),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId))
    }
}
