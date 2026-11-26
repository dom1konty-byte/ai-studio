---
name: landing-page
description: Быстрый адаптивный лендинг — структура блоков, тексты, SEO-основа, форма заявки, проверка. Использовать для проектов типа «сайт», одностраничников, визиток и промо-страниц.
---
# Лендинг

Основа: `templates/web-landing` (HTML + CSS + JS, без сборки). Работать в `projects/<slug>/`.

## Структура (по умолчанию, убрать лишнее)
1. Шапка: логотип, якорное меню, кнопка CTA.
2. Hero: заголовок-выгода ≤8 слов, подзаголовок, CTA, картинка.
3. Проблема → решение (3 пункта).
4. Преимущества / услуги (3–6 карточек).
5. Как это работает (3–4 шага).
6. Отзывы / кейсы / цифры.
7. Цены (если есть).
8. FAQ (4–6 вопросов, `<details>`).
9. Форма заявки: имя, телефон/почта, сообщение, согласие на обработку данных.
10. Подвал: контакты, соцсети, политика.

## Кто делает
- Тексты — `copywriter`. Дизайн/цвета — `ui-designer` (+ навык `frontend-design`). Вёрстка — `web-developer`. SEO — `seo-specialist`. Приём заявок — `backend-architect`.

## Форма
- Валидация в браузере (`required`, `type=email|tel`) + JS-сообщения на русском.
- Скрытое поле-ловушка (honeypot) против спама.
- Отправка: `action` в `site.config.json` → `formEndpoint` (Formspree / Telegram-бот / свой API). Пусто → форма показывает «Отправлено (демо)».
- Без ключей в коде.

## SEO-основа
title, description, OG-теги, `lang="ru"`, canonical, `sitemap.xml`, `robots.txt`, JSON-LD.

## Проверка (навык `webapp-testing`)
- 360px и 1280px, без горизонтальной прокрутки.
- Все якоря работают, форма — ошибки и успех.
- Консоль без ошибок. Картинки с `alt`, WebP.

## Деплой (Cloudflare Pages, бесплатно)
Репозиторий приватный → GitHub Pages бесплатно недоступен. Используем Cloudflare Pages: бесплатно, много сайтов, адрес `https://<slug>.pages.dev`, свой домен подключается бесплатно.
- Публикация идёт сама из workflow проекта при push в `main` = после «да» на Выпуске (`merge-to-main`).
- Один раз (Дамир): dash.cloudflare.com → регистрация → My Profile → API Tokens → Create Token → шаблон «Edit Cloudflare Workers» (или Custom: Account → Cloudflare Pages → Edit) → скопировать токен. Account ID — на главной странице аккаунта справа.
- GitHub → Settings → Secrets and variables → Actions: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.
- Нет секретов → workflow пишет notice и пропускает публикацию (сборка не падает).
- Свой домен: Cloudflare → Workers & Pages → проект → Custom domains.
- После первой публикации: заменить `https://example.com/` в `index.html`, `robots.txt`, `sitemap.xml` на реальный адрес.
