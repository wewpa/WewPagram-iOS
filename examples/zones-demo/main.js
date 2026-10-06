wew.on('start', function () {
  wew.ui.banner({id: 'login', zone: 'login', text: 'WewPagram: плагины работают и здесь', position: 'top'});
  wew.ui.banner({id: 'gifts', zone: 'gifts', text: 'Раздел подарков', color: '#B0397A'});
  wew.ui.banner({id: 'market', zone: 'market', text: 'Маркет', color: '#2B7A4B'});
  wew.ui.banner({id: 'stars', zone: 'stars', text: 'Звёзды', color: '#8A6D00'});
  wew.ui.button({id: 'hi', zone: 'chats', text: 'Привет', key: 'hi'});
});
wew.on('button', function (key) {
  if (key === 'hi') { wew.app.haptic(); wew.translate('Hello, world', 'ru', function (t) { wew.toast(t || 'нет сети'); }); }
});
