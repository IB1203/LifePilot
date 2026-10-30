package com.lifepilot.app.lifepilot_ai

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen summary. The Flutter app writes the text values (see
 * lib/services/home_widget_service.dart); this only displays them.
 */
class LifePilotWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.lifepilot_widget).apply {
                setTextViewText(R.id.widget_date, widgetData.getString("lp_date", "LifePilot"))
                setTextViewText(R.id.widget_tasks, widgetData.getString("lp_tasks", "Open the app to load your day"))
                setTextViewText(R.id.widget_next, widgetData.getString("lp_next", ""))
                setTextViewText(R.id.widget_money, widgetData.getString("lp_money", ""))
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
