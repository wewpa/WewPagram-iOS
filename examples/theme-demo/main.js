// Демо-плагин: оформление меню WewPagram.
// Работает через wew.theme (нужно разрешение "theme").

function apply() {
  wew.theme.set({
    dark: true,
    accent: "#FF7AB6",
    background: "bg.jpg",      // картинка из этого архива; можно и цвет: "#101820"
    card: "#2A1730",
    text: "#FFEAF4",
    fontSize: "medium",
    sakura: true
  });
}

wew.menu.add({
  id: "main",
  title: "Ночная сакура",
  icon: "icon.png",
  page: [
    { type: "header", title: "Оформление меню" },
    { type: "switch", key: "on", title: "Включить тему", default: false },
    { type: "button", key: "apply", title: "Применить сейчас" },
    { type: "button", key: "reset", title: "Вернуть стандартное" }
  ]
});

wew.on("start", function () {
  if (wew.storage.get("on", false)) { apply(); }
});

wew.on("setting", function (key, value) {
  if (key === "on") { if (value) { apply(); } else { wew.theme.reset(); } }
});

wew.on("button", function (id) {
  if (id === "apply") { apply(); wew.toast("Тема применена"); }
  if (id === "reset") { wew.theme.reset(); wew.toast("Оформление сброшено"); }
});
