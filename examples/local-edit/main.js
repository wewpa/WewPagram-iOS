// Визуальные правки сообщений. Видны только на этом устройстве, собеседник ничего не получает.
// Оригинал текста хранит приложение: «Вернуть оригинал» всегда возвращает настоящий текст.

wew.contextMenu.add({ id: 'edit', title: 'Изменить локально' });
wew.contextMenu.add({ id: 'restore', title: 'Вернуть оригинал', when: 'edited' });

wew.on('contextmenu', function (id, msg) {
  if (id === 'edit') {
    wew.prompt({
      title: 'Изменить локально',
      subtitle: 'Видно только на этом устройстве.',
      value: msg.text
    }, function (text) {
      if (text === null || !String(text).trim()) { return; }
      wew.messages.editLocal(msg.key, text);
    });
  } else if (id === 'restore') {
    wew.messages.editLocal(msg.key, msg.originalText);
  }
});
