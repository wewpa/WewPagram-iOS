// Локальная правка сообщений. Собеседник ничего не видит, ничего не отправляется.
// Пометку «Отредактировано в WewPagram» добавляет само приложение, плагин её не контролирует.

wew.contextMenu.add({ id: 'edit', title: 'Изменить локально' });

wew.on('contextmenu', function (id, msg) {
  if (id !== 'edit') { return; }
  wew.prompt({
    title: 'Изменить локально',
    subtitle: 'Видно только на этом устройстве. К тексту добавится пометка «Отредактировано в WewPagram».',
    value: msg.text
  }, function (text) {
    if (text === null || !String(text).trim()) { return; }
    wew.messages.editLocal(msg.key, text);
    wew.toast('Изменено локально');
  });
});
