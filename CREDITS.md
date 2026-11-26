# Авторство и лицензии

Студия собрана из открытых проектов. Чужие навыки лежат со своими файлами лицензий (`LICENSE` / `LICENSE.txt` в папке навыка). Изменения отмечены в `NOTICE-ai-studio.txt`.

## Взято с изменениями
| Что | Откуда | Лицензия | Изменения |
|---|---|---|---|
| Навыки `brainstorming`, `writing-plans`, `test-driven-development`, `systematic-debugging`, `verification-before-completion` | [obra/superpowers](https://github.com/obra/superpowers) — Jesse Vincent | MIT | сужены триггеры, пути документов → `projects/<slug>/docs/`, убраны ссылки на не взятые навыки |
| Навыки `frontend-design`, `webapp-testing`, `skill-creator` | [anthropics/skills](https://github.com/anthropics/skills) — Anthropic | Apache-2.0 | без изменений |
| Навык `shadcn` | [shadcn-ui/ui](https://github.com/shadcn-ui/ui) — shadcn | MIT | без изменений |
| Навыки `flutter-apply-architecture-best-practices`, `flutter-build-responsive-layout`, `flutter-fix-layout-issues`, `flutter-setup-declarative-routing`, `flutter-use-http-package`, `flutter-implement-json-serialization`, `flutter-setup-localization`, `flutter-add-widget-test`, `flutter-add-integration-test` | [flutter/agent-plugins](https://github.com/flutter/agent-plugins) — The Flutter Authors | BSD-3-Clause | пометка «Dart/Flutter MCP не установлен» (где упоминается MCP) |
| Навыки `dart-add-unit-test`, `dart-generate-test-mocks`, `dart-run-static-analysis`, `dart-resolve-package-conflicts` | [dart-lang/skills](https://github.com/dart-lang/skills) — the Dart project authors | BSD-3-Clause | то же |
| Навык `app-store-optimization` | [alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills) — Alireza Rezvani | MIT | описание сужено под Google Play, пометка об офлайн-оценках, добавлен `scripts/check_listing.py` (у оригинальных скриптов нет командной строки), убраны примеры JSON |
| Навыки `aso`, `copywriting`, `copy-editing`, `cro`, `competitor-profiling`, `customer-research`, `churn-prevention` | [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills) — Corey Haines | MIT | контекст продукта → `projects/<slug>/docs/`, убраны evals |

## Основа для агентов (переписаны на русском под Flutter и веб)
| Агент студии | Источник |
|---|---|
| flutter-developer, windows-developer | `flutter-expert` — [wshobson/agents](https://github.com/wshobson/agents) (MIT, Seth Hobson); идеи `mobile-app-builder` — contains-studio |
| web-developer | `frontend-developer` — wshobson/agents; contains-studio |
| backend-architect | `backend-architect` — wshobson/agents |
| ui-designer | `ui-ux-designer` — wshobson/agents; `ui-designer` — contains-studio |
| seo-specialist | `seo-meta-optimizer`, `seo-structure-architect` — wshobson/agents |
| test-engineer | `test-automator` — wshobson/agents; `test-writer-fixer` — contains-studio |
| code-reviewer, debugger, security-auditor | `code-reviewer`, `debugger`, `security-auditor` — wshobson/agents |
| release-engineer | `deployment-engineer` — wshobson/agents; `project-shipper` — contains-studio |
| product-manager, copywriter | `sprint-prioritizer`, `feedback-synthesizer`, `content-creator`, `app-store-optimizer` — contains-studio |
| studio-director | `studio-producer` — contains-studio |
| market-researcher | `trend-researcher` — contains-studio (идея) |
| client-manager | `support-responder` — contains-studio (идея) |
| growth-analyst | `analytics-reporter`, `feedback-synthesizer` — contains-studio (идея) |
| bot-developer | написан заново; навык `telegram-bot` — свой, по документации grammY |
| architect | `backend-architect` — wshobson/agents (подход «решение → компромиссы → задачи»); написан заново |

[contains-studio/agents](https://github.com/contains-studio/agents) не указывает лицензию, поэтому его тексты не копировались — взяты только идеи (разделение на отделы, роли). Агенты написаны заново.

## Экономия токенов (идеи, код не копировался)
| Что в студии | Источник идеи | Лицензия источника |
|---|---|---|
| Навык `kratko` | `token-efficiency` — [rohitg00/pro-workflow](https://github.com/rohitg00/pro-workflow); `response-compression` — [athola/claude-night-market](https://github.com/athola/claude-night-market) | MIT / MIT |
| Сжатый стиль `CLAUDE.md` и агентов | `caveman-compress` — [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) | Apache-2.0 |
| `/econ` (`scripts/econ.py`) | `caveman-stats` — JuliusBrussee/caveman | Apache-2.0 |

`caveman-compress` не установлен: он отправляет файл во внешний API и даёт «пещерный» стиль, плохо читаемый на русском. Сжатие сделано вручную по его принципам.
