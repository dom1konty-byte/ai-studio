package com.aistudio.zametki

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/** «Последние заметки»: до 5 строк (3 при низком виджете). */
class RecentNotesWidgetProvider : HomeWidgetProvider() {
    private companion object {
        const val HEIGHT_3_ROWS_DP = 150
        const val HEIGHT_4_ROWS_DP = 210
    }

    private val rows = intArrayOf(R.id.r1, R.id.r2, R.id.r3, R.id.r4, R.id.r5)
    private val bars = intArrayOf(R.id.bar1, R.id.bar2, R.id.bar3, R.id.bar4, R.id.bar5)
    private val titles = intArrayOf(R.id.t1, R.id.t2, R.id.t3, R.id.t4, R.id.t5)
    private val previews = intArrayOf(R.id.p1, R.id.p2, R.id.p3, R.id.p4, R.id.p5)

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val notes = try {
            JSONArray(widgetData.getString("recent", "[]"))
        } catch (e: Exception) {
            JSONArray()
        }
        appWidgetIds.forEach { id ->
            val h = WidgetUtil.heightDp(appWidgetManager, id)
            val maxRows = when {
                h < HEIGHT_3_ROWS_DP -> 3
                h < HEIGHT_4_ROWS_DP -> 4
                else -> 5
            }
            val count = minOf(notes.length(), maxRows)
            val views = RemoteViews(context.packageName, R.layout.widget_recent)
            views.setOnClickPendingIntent(R.id.root, WidgetUtil.launch(context, null))
            views.setOnClickPendingIntent(R.id.add, WidgetUtil.launch(context, "zametki://new"))
            views.setViewVisibility(R.id.empty, if (count == 0) View.VISIBLE else View.GONE)
            for (i in rows.indices) {
                val n = if (i < count) notes.optJSONObject(i) else null
                if (n != null) {
                    val noteId = n.optInt("id", -1)
                    views.setViewVisibility(rows[i], View.VISIBLE)
                    views.setInt(bars[i], "setBackgroundColor", WidgetUtil.noteColor(context, n.optInt("color")))
                    views.setTextViewText(titles[i], n.optString("title"))
                    views.setTextViewText(previews[i], n.optString("preview"))
                    views.setViewVisibility(previews[i], if (n.optString("preview").isEmpty()) View.GONE else View.VISIBLE)
                    views.setOnClickPendingIntent(
                        rows[i],
                        WidgetUtil.launch(context, if (noteId < 0) null else "zametki://note/$noteId"),
                    )
                } else {
                    views.setViewVisibility(rows[i], View.GONE)
                }
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
