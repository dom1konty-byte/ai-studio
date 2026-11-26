(async () => {
  const form = document.querySelector('.form');
  if (!form) return;
  const msg = form.querySelector('.form__msg');
  let endpoint = '';
  try { endpoint = (await (await fetch('site.config.json')).json()).formEndpoint || ''; } catch (_) {}
  const show = (text, cls) => { msg.textContent = text; msg.className = 'form__msg ' + cls; };
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (form.website.value) return; // ловушка для ботов
    if (!form.checkValidity()) { show('Заполните имя, контакт и отметьте согласие.', 'error'); return; }
    if (!endpoint) { show('Заявка отправлена (демо-режим).', 'ok'); form.reset(); return; }
    try {
      const r = await fetch(endpoint, { method: 'POST', headers: { Accept: 'application/json' }, body: new FormData(form) });
      if (!r.ok) throw new Error(r.status);
      show('Спасибо! Мы скоро свяжемся.', 'ok'); form.reset();
    } catch (_) { show('Не получилось отправить. Попробуйте ещё раз.', 'error'); }
  });
})();
