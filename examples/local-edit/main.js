// Визуальные правки сообщений. Видны только на этом устройстве, собеседник ничего не получает.
// Пометку «Отредактировано в WewPagram» добавляет само приложение, плагин её не контролирует,
// а оригинал текста хранит приложение: «Вернуть оригинал» всегда возвращает настоящий текст.

wew.contextMenu.add({ id: 'edit', title: 'Изменить локально' });
wew.contextMenu.add({ id: 'restore', title: 'Вернуть оригинал', when: 'edited' });

wew.on('contextmenu', function (id, msg) {
  if (id === 'edit') {
    wew.prompt({
      title: 'Изменить локально',
      subtitle: 'Видно только на этом устройстве. К тексту добавится пометка «Отредактировано в WewPagram».',
      value: msg.text
    }, function (text) {
      if (text === null || !String(text).trim()) { return; }
      wew.messages.editLocal(msg.key, text);
      wew.toast('Изменено локально');
    });
  } else if (id === 'restore') {
    wew.messages.restoreLocal(msg.key);
    wew.toast('Оригинал возвращён');
  }
});
