---
name: dependency-updates
description: Проверка и слияние автообновлений Dependabot (пакеты Flutter, npm, шаги сборок) — только после «да» Дамира. Использовать, когда Дамир пишет «проверь обновления» или пришло сообщение 🔄 в Telegram.
---
# Автообновления (Dependabot)

Dependabot раз в неделю (понедельник утром) открывает PR в `main` с новыми версиями. Дамиру приходит 🔄 в Telegram. Только в сессии «Офис студии».

1. Список: `gh api "repos/dom1konty-byte/ai-studio/pulls?state=open" --jq '.[]|select(.user.login=="dependabot[bot]")|[.number,.title]|@tsv'`.
2. Проверки PR: `gh api repos/dom1konty-byte/ai-studio/commits/<sha>/check-runs` (sha — `.head.sha` PR) — все зелёные? Упало → не сливать; кратко объяснить Дамиру причину (обычно новая версия несовместима), предложить закрыть PR — Dependabot предложит снова при следующей версии.
3. Крупные обновления (major, напр. 2.x → 3.x) — посмотреть, что сломалось бы: changelog пакета; при сомнении — не сливать, сказать Дамиру.
4. Показать Дамиру (≤5 строк): что обновляется, проверки зелёные, риск. ✅ Ждать «да».
5. После «да»: слияние PR Dependabot — `gh api -X PUT repos/dom1konty-byte/ai-studio/pulls/<N>/merge -f merge_method=merge` (merge_pr.py работает с текущей веткой и здесь не подходит). Отчёт: «Слито: PR #N».
6. Ветки проектов получат обновление сами: директор вливает `origin/main` в начале каждой сессии.
