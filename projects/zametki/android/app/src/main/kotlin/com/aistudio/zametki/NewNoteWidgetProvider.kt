package com.aistudio.zametki

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/** «+ Новая заметка»: открывает пустой редактор. Данных из приложения не нужно. */
class NewNoteWidgetProvider : HomeWidgetProvider() {
    private companion object {
        const val LABEL_MIN_WIDTH_DP = 110
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.widget_new)
            // В 1×1 (уже ~110dp) остаётся только значок.
            val showLabel = WidgetUtil.widthDp(appWidgetManager, id) >= LABEL_MIN_WIDTH_DP
            views.setViewVisibility(R.id.label, if (showLabel) View.VISIBLE else View.GONE)
            views.setInt(R.id.plus, "setColorFilter", context.getColor(R.color.widget_on_primary_container))
            views.setOnClickPendingIntent(R.id.root, WidgetUtil.launch(context, "zametki://new"))
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
