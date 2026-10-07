// Визуальные подарки.
// Пока режим включён, экран подарка не оплачивается и не отправляется: подарок только
// запоминается на этом устройстве. Получатель ничего не видит, звёзды не списываются.

var ZONES = ['stars', 'gifts', 'market'];

function isOn() { return wew.storage.get('on', false) === true; }

function drawButtons() {
  var on = isOn();
  for (var i = 0; i < ZONES.length; i++) {
    wew.ui.button({
      id: 'toggle-' + ZONES[i],
      zone: ZONES[i],
      text: on ? 'Визуальные подарки: ВКЛ' : 'Визуальные подарки: ВЫКЛ',
      color: on ? '#8E7BFF' : '#555B66',
      key: 'toggle',
      position: 'bottom'
    });
  }
  // Честная пометка: пока режим включён, на экранах подарков это видно всегда.
  if (on) {
    wew.ui.banner({ id: 'note-gifts', zone: 'gifts', text: 'Визуальный режим: подарок не отправляется', color: '#5B4BC4' });
    wew.ui.banner({ id: 'note-market', zone: 'market', text: 'Визуальный режим: покупка не совершается', color: '#5B4BC4' });
  } else {
    wew.ui.remove('note-gifts');
    wew.ui.remove('note-market');
  }
}

function apply(value) {
  wew.storage.set('on', value);
  wew.gifts.setFake(value);
  drawButtons();
}

wew.menu.add({
  id: 'main',
  title: 'Визуальные подарки',
  icon: 'icon.png',
  page: [
    { type: 'header', title: 'Режим' },
    { type: 'switch', key: 'on', title: 'Дарить визуально', default: false },
    { type: 'info', title: 'Подарок из магазина или маркета не оплачивается и не отправляется. Он остаётся только в списке на этом устройстве; получатель его не увидит.' },
    { type: 'header', title: 'Список' },
    { type: 'button', key: 'list', title: 'Показать последние подарки' },
    { type: 'button', key: 'clear', title: 'Очистить список' }
  ]
});

wew.on('start', function () {
  wew.gifts.setFake(isOn());
  drawButtons();
});

wew.on('setting', function (key, value) {
  if (key === 'on') { apply(!!value); }
});

wew.on('button', function (key) {
  if (key === 'toggle') {
    var next = !isOn();
    apply(next);
    wew.app.haptic();
    wew.toast(next ? 'Визуальные подарки включены' : 'Визуальные подарки выключены');
  } else if (key === 'list') {
    var list = wew.gifts.list();
    if (!list.length) { wew.alert('Список пуст'); return; }
    var lines = [];
    for (var i = Math.max(0, list.length - 10); i < list.length; i++) {
      var g = list[i];
      lines.push((g.title || 'Подарок') + ' — ' + g.price + ' ★');
    }
    wew.alert('Всего: ' + list.length + '\n' + lines.join('\n'));
  } else if (key === 'clear') {
    wew.gifts.clear();
    wew.toast('Список очищен');
  }
});

wew.on('gift.fake', function (title, price) {
  wew.toast('«' + title + '» (' + price + ' ★) — только визуально');
});
