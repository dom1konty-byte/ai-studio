/// Быстрые кнопки над полем ввода: текст уходит директору сразу.
const projectQuickReplies = [
  'Что сейчас по проекту?',
  'Продолжай',
  'Выпускай',
  'Покажи скриншот',
];

/// У Офиса свой набор.
const officeQuickReplies = [
  'Какие проекты ждут меня?',
  'Статус всех проектов',
];

List<String> quickRepliesFor({required bool office}) =>
    office ? officeQuickReplies : projectQuickReplies;
