package com.finn.flux

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class FluxWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout).apply {
                val title = widgetData.getString("title", "Flux Creation")
                val content = widgetData.getString("content", "Tap to open")
                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_content, content)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
