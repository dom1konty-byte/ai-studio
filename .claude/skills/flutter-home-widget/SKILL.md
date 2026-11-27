---
name: flutter-home-widget
description: Виджет Flutter-приложения на главном экране Android (и позже iOS) через пакет home_widget — данные из приложения в виджет, разметка виджета, обновление, нажатие открывает приложение. Использовать, когда в ТЗ есть виджет на главном экране.
---
# Виджет на главном экране (home_widget)

Пакет: `home_widget` (pub.dev). Виджет рисует сама система (Android — XML-разметка, iOS — SwiftUI/WidgetKit), Flutter только передаёт данные.

## Android (делать сразу)
1. `flutter pub add home_widget`.
2. Данные из приложения → виджет (после каждого изменения):
   ```dart
   await HomeWidget.saveWidgetData<String>('notes', jsonEncode(lastNotes)); // или текст
   await HomeWidget.updateWidget(androidName: 'NotesWidgetProvider');
   ```
3. `android/app/src/main/res/layout/notes_widget.xml` — разметка (LinearLayout + TextView; для списка — ListView + RemoteViewsService).
4. `android/app/src/main/res/xml/notes_widget_info.xml` — `appwidget-provider`: minWidth/minHeight (2×2 = 110dp), `updatePeriodMillis="0"` (обновляем сами), `initialLayout`, `previewLayout`, `resizeMode="horizontal|vertical"`, `widgetCategory="home_screen"`.
5. `android/app/src/main/kotlin/<package path>/NotesWidgetProvider.kt`:
   ```kotlin
   class NotesWidgetProvider : HomeWidgetProvider() {
     override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
       appWidgetIds.forEach { id ->
         val views = RemoteViews(context.packageName, R.layout.notes_widget).apply {
           setTextViewText(R.id.notes_text, widgetData.getString("notes", "Нет заметок"))
           setOnClickPendingIntent(R.id.root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
         }
         appWidgetManager.updateAppWidget(id, views)
       }
     }
   }
   ```
6. `AndroidManifest.xml` → внутри `<application>`: `<receiver android:name=".NotesWidgetProvider" android:exported="true">` с `intent-filter` `android.appwidget.action.APPWIDGET_UPDATE` и `meta-data android:name="android.appwidget.provider" android:resource="@xml/notes_widget_info"`.
7. Кнопка «быстрая заметка» на виджете → `HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("zametki://new"))`, в приложении `HomeWidget.initiallyLaunchedFromHomeWidget()` / `widgetClicked` → открыть экран новой заметки.
- Папка `android/` должна быть закоммичена (CI создаёт её только если нет) — виджет живёт в ней.
- Проверка: сборка APK в CI; на телефоне — долгое нажатие на экран → Виджеты → приложение.

## iOS (второй версией)
Нужна цель Widget Extension в Xcode (Swift, WidgetKit) и App Group для общих данных — без Mac настраивается вручную в `ios/Runner.xcodeproj`, сложно и хрупко. Делать отдельной задачей, когда Android-версия готова.
