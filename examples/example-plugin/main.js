// Пример плагина WewPagram. Полное описание API: docs/PLUGINS.md

// 1. Страница в меню WewPagram (иконка берётся из архива)
wew.menu.add({
  id: "main",
  title: "Подпись",
  icon: "icon.png",
  page: [
    { type: "header", title: "Подпись к сообщениям" },
    { type: "switch", key: "enabled", title: "Добавлять подпись", default: false },
    { type: "input", key: "text", title: "Текст", placeholder: "— отправлено через WewPagram", default: "— отправлено через WewPagram" },
    { type: "header", title: "Действия" },
    { type: "button", key: "ghost_on", title: "Включить режим призрака" },
    { type: "button", key: "files", title: "Показать файлы плагина" },
    { type: "info", title: "Картинки из архива (png/jpg) доступны как wew.assets.path('photo.jpg')." }
  ]
});

// 2. Правка исходящего текста (нужно разрешение "send")
wew.on("message.send", function (text) {
  if (!wew.storage.get("enabled", false)) { return text; }
  if (text.charAt(0) === "/") { return text; }          // команды ботов не трогаем
  var tail = wew.storage.get("text", "— отправлено через WewPagram");
  return text + "\n" + tail;
});

// 3. Кнопки на странице
wew.on("button", function (id) {
  if (id === "ghost_on") {
    wew.ghost.set(true);                                // нужно разрешение "ghost"
    wew.alert("Режим призрака включён");
  }
  if (id === "files") {
    wew.alert(wew.assets.list().join(", "));
  }
});

wew.log("плагин запущен, версия", wew.plugin.version);
