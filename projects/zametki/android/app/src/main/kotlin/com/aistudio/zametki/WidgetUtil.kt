package com.aistudio.zametki

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.net.Uri
import es.antonborri.home_widget.HomeWidgetLaunchIntent

object WidgetUtil {
    private val noteColors = intArrayOf(
        R.color.note_0, R.color.note_1, R.color.note_2, R.color.note_3,
        R.color.note_4, R.color.note_5, R.color.note_6, R.color.note_7,
    )

    fun noteColor(context: Context, index: Int): Int =
        context.getColor(noteColors[index.coerceIn(0, noteColors.size - 1)])

    /** Нажатие открывает приложение по ссылке zametki://new или zametki://note/<id>. */
    fun launch(context: Context, link: String?): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            link?.let { Uri.parse(it) },
        )

    /** Размер виджета (dp), как его видит launcher сейчас. */
    fun heightDp(manager: AppWidgetManager, id: Int): Int =
        manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)

    fun widthDp(manager: AppWidgetManager, id: Int): Int =
        manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 180)
}
