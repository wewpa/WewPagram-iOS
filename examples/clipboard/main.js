// Буфер обмена: иконка над клавиатурой в чате.
// Нажатие запоминает то, что сейчас скопировано, и открывает список для вставки.
// Системный буфер читается только по нажатию (iOS может спросить разрешение).
// История хранится на устройстве, в хранилище плагина.

var MAX_ITEMS = 30;
var MAX_LENGTH = 2000;

function load() { var h = wew.storage.get('history', []); return Array.isArray(h) ? h : []; }
function save(h) { wew.storage.set('history', h.slice(0, MAX_ITEMS)); }
function remember() { return wew.storage.get('remember', true) !== false; }

function label(text) {
  var s = String(text).replace(/\s+/g, ' ').trim();
  return s.length > 60 ? s.substr(0, 60) + '…' : s;
}

function drawIcon() {
  wew.ui.button({ id: 'clip', zone: 'chat', icon: 'clipboard', position: 'input', key: 'open' });
}

wew.menu.add({
  id: 'main',
  title: 'Буфер обмена',
  icon: 'icon.png',
  page: [
    { type: 'header', title: 'История' },
    { type: 'switch', key: 'remember', title: 'Запоминать скопированное', default: true },
    { type: 'info', title: 'Иконка в чате над клавиатурой. История остаётся только на этом устройстве; не копируйте пароли, пока она включена, или выключите запоминание.' },
    { type: 'button', key: 'clear', title: 'Очистить историю' }
  ]
});

wew.on('start', drawIcon);

wew.on('button', function (key) {
  if (key === 'clear') {
    save([]);
    wew.toast('История очищена');
    return;
  }
  if (key !== 'open') { return; }

  var history = load();
  if (remember()) {
    var current = wew.clipboard.get();
    if (current && current.length <= MAX_LENGTH && history.indexOf(current) === -1) {
      history.unshift(current);
      save(history);
    }
  }
  if (!history.length) { wew.toast('История буфера пуста'); return; }

  var labels = [];
  for (var i = 0; i < history.length; i++) { labels.push(label(history[i])); }
  wew.choose({ title: 'Буфер обмена', items: labels }, function (index) {
    if (index < 0 || index >= history.length) { return; }
    wew.clipboard.paste(history[index], function (pasted) {
      wew.toast(pasted ? 'Вставлено' : 'Скопировано, откройте поле ввода и нажмите «Вставить»');
    });
  });
});

wew.on('setting', function (key, value) {
  if (key === 'remember') { wew.storage.set('remember', !!value); }
});
