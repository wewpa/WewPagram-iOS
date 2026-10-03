# Плагины WewPagram

Плагин — обычный `.zip` с файлами. Устанавливается без пересборки приложения:
**WewPagram → Плагины → Установить плагин (.zip)**, выбрать файл — плагин запускается сразу.

Язык плагинов — **JavaScript** (встроенный в iOS движок JavaScriptCore). Python/Swift/ObjC на iPhone
нельзя выполнить «на лету»: нативный код требует компиляции и подписи, а JS iOS разрешает.

## Содержимое архива
```
my-plugin.zip
├── plugin.json     обязательно
├── main.js         код (имя можно поменять через "entry")
├── icon.png        любые картинки .png / .jpg / .jpeg
└── photo.jpg
```
Файлы могут лежать в корне архива или в единственной папке верхнего уровня.
Разрешены расширения: `js json png jpg jpeg txt md`. Лимиты: файл до 8 МБ, архив до 24 МБ, до 400 файлов.

### plugin.json
```json
{
  "id": "my.plugin",
  "name": "Мой плагин",
  "version": "1.0.0",
  "author": "я",
  "description": "Что делает плагин",
  "icon": "icon.png",
  "logo": "logo.png",
  "entry": "main.js",
  "permissions": ["send", "ghost", "profile", "deleted", "http"]
}
```
| Поле | Назначение |
|---|---|
| `id` | уникальный идентификатор (`A–Z a–z 0–9 . _ -`); повторная установка с тем же `id` обновляет плагин |
| `icon` | картинка плитки в списке плагинов и в меню |
| `logo` | если задан — **заменяет аватарку мода** в шапке меню WewPagram |
| `permissions` | что плагину разрешено (см. ниже); без разрешения вызов игнорируется и пишется в журнал |

## Разрешения
| Разрешение | Даёт |
|---|---|
| `send` | менять текст исходящих сообщений (`message.send`) |
| `ghost` | `wew.ghost.set()` |
| `profile` | `wew.profile.set()` |
| `deleted` | `wew.deleted.setEnabled()` |
| `http` | `wew.http.get()` (только `https://`) |

## API
```js
wew.log(...)                          // запись в журнал плагина (виден в карточке плагина)
wew.alert("текст")                    // окно с сообщением
wew.plugin                            // {id, name, version}

wew.storage.get(key, default)         // хранилище плагина (значения — любой JSON)
wew.storage.set(key, value)
wew.storage.remove(key)

wew.assets.path("photo.jpg")          // абсолютный путь к файлу из архива или null
wew.assets.list()                     // все png/jpg архива

wew.ghost.get() / wew.ghost.set(bool)           // режим призрака           [ghost]
wew.deleted.setEnabled(bool)                    // сохранение удалённых     [deleted]
wew.profile.get()                               // {phone, ratingEnabled, ratingLevel, ratingPoints}
wew.profile.set({phone, ratingEnabled, ratingLevel, ratingPoints})   // [profile]

wew.http.get("https://...", function (status, body) { ... })          // [http]

wew.menu.add({ id, title, icon, page: [ ...элементы... ] })
```

### Страница плагина
`wew.menu.add` добавляет строку в меню WewPagram (раздел «Плагины») и страницу из элементов:

| `type` | Поля | Поведение |
|---|---|---|
| `header` | `title` | заголовок секции |
| `info` | `title` | поясняющий текст |
| `switch` | `key`, `title`, `default` | значение хранится в `wew.storage` под `key` |
| `input` | `key`, `title`, `placeholder`, `default` | то же, строка |
| `button` | `key`, `title` | вызывает событие `button` с `key` |

### События
```js
wew.on("start", function () {})                          // плагин запущен / перезагружен
wew.on("setting", function (key, value) {})              // изменён switch или input на странице
wew.on("button", function (key) {})                      // нажата кнопка на странице
wew.on("message.send", function (text) { return text; }) // правка исходящего текста [send]
```
`message.send`: вернуть строку — она заменит текст; ничего не вернуть — текст не меняется. Обработчик
ограничен 0,5 с, при превышении сообщение уходит без изменений. Если текст изменён, форматирование
(жирный, ссылки) в этом сообщении сбрасывается. Ошибки в обработчике не ломают цепочку — они пишутся в журнал.

## Пример
Готовый пример — `examples/example-plugin` (и архив `wewpagram-example-plugin.zip`): страница с переключателем,
полем и кнопками, подпись к исходящим сообщениям, иконка из архива.

## Безопасность
Плагин — это код, который работает внутри приложения с доступом ко всем перечисленным выше функциям.
Ставьте только плагины, которым доверяете, и смотрите список разрешений в карточке плагина.

## Что плагины пока не умеют
Менять входящие сообщения и внешний вид чатов, добавлять собственные экраны сложнее страницы из элементов выше,
запускать нативный код. Это можно добавить следующими версиями API.
