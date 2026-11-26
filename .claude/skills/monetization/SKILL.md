---
name: monetization
description: Заработок во Flutter-приложении — реклама AdMob (google_mobile_ads, согласие UMP/GDPR, app-ads.txt, частота показа) и покупки/подписки через in_app_purchase (Google Play Billing). Использовать, когда в ТЗ есть реклама, платные функции или подписка.
---
# Монетизация (Flutter, Android)

Решение «реклама или покупки» — на этапе ТЗ (при сомнениях — `architect`). Работать в `projects/<slug>/`.

## Что выбрать
| Модель | Когда | Сложность |
|---|---|---|
| Реклама (AdMob) | бесплатное приложение, частое использование | низкая |
| Разовая покупка «убрать рекламу / Pro» | простые утилиты | средняя |
| Подписка | постоянная ценность (контент, синхронизация) | высокая, нужен сервер для проверки |

## Реклама: AdMob
1. Аккаунт AdMob — Дамир (admob.google.com). Создать приложение → **App ID** и **ad unit ID**.
2. `flutter pub add google_mobile_ads`.
3. `android/app/src/main/AndroidManifest.xml`, внутри `<application>`:
   ```xml
   <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID"
              android:value="ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY"/>
   ```
4. Разработка — ТОЛЬКО тестовые ID Google (клики по своей боевой рекламе = бан):
   - баннер `ca-app-pub-3940256099942544/6300978111`
   - межстраничная `ca-app-pub-3940256099942544/1033173712`
   - с вознаграждением `ca-app-pub-3940256099942544/5224354917`
   Боевые ID — через `--dart-define=ADMOB_BANNER_ID=...` в сборке выпуска (GitHub Secrets), не в коде.
5. Согласие (GDPR/UMP) — до первой рекламы:
   ```dart
   final params = ConsentRequestParameters();
   ConsentInformation.instance.requestConsentInfoUpdate(params, () async {
     await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
     if (await ConsentInformation.instance.canRequestAds()) {
       await MobileAds.instance.initialize();
     }
   }, (error) {});
   ```
   В AdMob → Privacy & messaging → создать сообщение GDPR.
6. `app-ads.txt` — на сайте разработчика (указан в Google Play): строка из AdMob → Apps → app-ads.txt.
7. Частота: баннер внизу, не перекрывает кнопки; межстраничная — не чаще 1 раза в 2–3 мин, только на естественных паузах, не при запуске; без рекламы в детских приложениях без настроек Families.
8. Утилизация: `bannerAd.dispose()` в `dispose()`.

## Покупки и подписки: in_app_purchase
1. `flutter pub add in_app_purchase`.
2. Play Console → Монетизация → товары (`pro_unlock`, разовый) или подписки (`premium_monthly`). Сначала нужен загруженный AAB (внутреннее тестирование) с разрешением billing (добавляется пакетом).
3. Код — сервис `lib/services/purchase_service.dart`:
   - слушать `InAppPurchase.instance.purchaseStream` с запуска;
   - `queryProductDetails({'pro_unlock'})` → показать цену из стора (не хардкодить);
   - `buyNonConsumable` / подписка — `buyNonConsumable` с `GooglePlayPurchaseParam`;
   - после `PurchaseStatus.purchased` → выдать доступ → `completePurchase(p)` (иначе через 3 дня Google вернёт деньги);
   - кнопка «Восстановить покупки» → `restorePurchases()`.
4. Проверка покупки: разовая «Pro» — можно локально; подписки и ценное — на сервере (Google Play Developer API, `backend-architect`).
5. Тест: тестировщики-лицензиаты в Play Console, внутренний трек.

## Правила Google Play
- Цифровые товары — только через Google Play Billing (не свои платёжки).
- Цена, период и условия подписки — видны до оплаты; отмена — понятно как.
- Реклама не мешает функциям, не имитирует кнопки, не появляется вне приложения.
- В Data safety указать: AdMob собирает рекламный ID (см. `privacy-policy`).
- Политика конфиденциальности обязательна при рекламе.

## Проверка перед ✅
Тестовые ID в отладке, боевые — только из секретов; окно согласия показывается; покупка/восстановление работают на внутреннем треке; `flutter analyze`/`flutter test` чисто.
