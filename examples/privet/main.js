// Тестовый плагин «Привет».
// Проверяет: запуск плагина, события по всему приложению, баннер, окно, страницу в меню, хранилище.

var ZONES = {
  chats: "Чаты",
  chat: "Чат",
  profile: "Профиль",
  contacts: "Контакты",
  calls: "Звонки",
  settings: "Настройки"
};

var greeted = {};   // в каждом разделе здороваемся один раз за запуск приложения

function enabled() { return wew.storage.get("enabled", true); }

// 1. Плагин загружен (запуск приложения, установка, включение)
wew.on("start", function () {
  wew.log("Привет! Плагин запущен, версия", wew.plugin.version);
  if (enabled()) { wew.toast("Привет! 👋 Плагин «Привет» запущен"); }
});

// 2. Пользователь зашёл в любой раздел приложения
wew.on("zone.open", function (zone, className) {
  if (!enabled() || greeted[zone]) { return; }
  greeted[zone] = true;
  wew.log("раздел:", zone, "(" + className + ")");
  wew.toast("Привет из раздела «" + (ZONES[zone] || zone) + "»");
});

// 3. Возврат в приложение из фона
wew.on("app.foreground", function () {
  if (enabled()) { wew.toast("С возвращением! 👋"); }
});

// 4. Вход в меню WewPagram
wew.on("menu.open", function () {
  if (enabled()) { wew.alert("Привет! Ты в меню WewPagram 👋"); }
});

// 5. Страница плагина
wew.menu.add({
  id: "main",
  title: "Привет",
  icon: "icon.png",
  page: [
    { type: "header", title: "Приветствия" },
    { type: "switch", key: "enabled", title: "Здороваться", default: true },
    { type: "button", key: "hello", title: "Сказать привет сейчас" },
    { type: "button", key: "reset", title: "Сбросить разделы (поздороваться заново)" }
  ]
});

wew.on("button", function (id) {
  if (id === "hello") { wew.alert("Привет! 👋"); }
  if (id === "reset") { greeted = {}; wew.toast("Готово: поздороваюсь в каждом разделе заново"); }
});
