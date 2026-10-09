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
| `theme` | `wew.theme.*` — оформление меню WewPagram |
| `ui` | `wew.ui.*` (плашки и кнопки поверх любого экрана), `wew.app.haptic()`, `wew.app.openURL()` |
| `gifts` | `wew.gifts.*` — визуальные подарки (без оплаты и отправки) |
| `clipboard` | `wew.app.copy()`, `wew.clipboard.get()`, `wew.clipboard.paste()` |

## API
```js
wew.log(...)                          // запись в журнал плагина (виден в карточке плагина)
wew.alert("текст")                    // окно с сообщением — показывается в любом разделе приложения
wew.toast("текст")                    // короткий баннер сверху на 2–3 секунды, не блокирует экран
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

wew.theme.get()                                                       // текущее оформление меню
wew.theme.set({ dark, accent, background, card, text, fontSize, sakura })   // [theme]
wew.theme.reset()                                                     // вернуть стандартное

wew.menu.add({ id, title, icon, page: [ ...элементы... ] })
```

### Оформление меню (`wew.theme`)
Меняет внешний вид **всех экранов WewPagram**. Любое поле можно не указывать (останется как есть) или
передать `null` (сбросить). Применяется сразу и плавно.

| Поле | Значение |
|---|---|
| `dark` | `true` — тёмное, `false` — светлое, `null` — как в приложении |
| `accent` | цвет акцента, `"#RRGGBB"` |
| `background` | цвет `"#RRGGBB"` **или имя картинки из архива** (`"bg.jpg"`, `"bg.png"`) |
| `card` | цвет карточек со строками |
| `text` | цвет основного текста |
| `fontSize` | `small`, `regular`, `medium`, `large`, `xlarge` |
| `sakura` | `true` / `false` — падающая сакура |

Если задана картинка, она показывается под списком, а карточки становятся чуть прозрачными.
Шрифт (гарнитуру) сменить нельзя: системные списки Telegram используют только системный шрифт, доступен размер.
Пример — `examples/theme-demo` (архив `theme-plugin.zip`).

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
События приходят из **любой части приложения**, а не только из меню WewPagram.
```js
wew.on("start", function () {})                          // плагин загружен: запуск приложения, установка, включение
wew.on("app.open", function () {})                       // приложение открыто (через 1,5 с после запуска)
wew.on("app.foreground", function () {})                 // возврат в приложение из фона
wew.on("zone.open", function (zone, className) {})       // пользователь зашёл в раздел приложения
wew.on("menu.open", function () {})                      // открыто меню WewPagram
wew.on("setting", function (key, value) {})              // изменён switch или input на странице плагина
wew.on("button", function (key) {})                      // нажата кнопка на странице плагина
wew.on("message.send", function (text) { return text; }) // правка исходящего текста [send]
```
Значения `zone`: `login` (экран входа), `chats`, `chat`, `profile`, `contacts`, `calls`, `settings` (любые экраны настроек, включая WewPagram),
`gifts`, `market` (магазин/аукцион подарков), `stars`, `premium`, `stories`, `camera`, `gallery`, `share`, `stickers`, `media` (выбор вложений), `miniapps`, `folders`, а все остальные экраны приходят как `other`
(второй аргумент — имя экрана, по нему можно отличить любой экран). Повторный вход в тот же раздел в пределах 1,5 с не считается.
`className` — имя экрана внутри Telegram, пригодится для отладки.

`message.send`: вернуть строку — она заменит текст; ничего не вернуть — текст не меняется. Обработчик
ограничен 0,5 с, при превышении сообщение уходит без изменений. Если текст изменён, форматирование
(жирный, ссылки) в этом сообщении сбрасывается. Ошибки в обработчике не ломают цепочку — они пишутся в журнал.

### Визуальные подарки (`wew.gifts`, разрешение `gifts`)
```js
wew.gifts.setFake(true)      // экраны подарков и маркета не платят и ничего не отправляют
wew.gifts.isFake(); wew.gifts.list(); wew.gifts.clear()
wew.on('gift.fake', function (title, price, peerId) {})
```
Подарок запоминается только на этом устройстве, получатель его не видит. Готовый плагин: `examples/fake-gifts`.

### Элементы поверх экранов (`wew.ui`, разрешение `ui`)
Работают на любом экране без пересборки приложения. `zone` — id раздела из списка выше или `*` (все экраны).
```js
wew.ui.banner({id: 'b1', zone: 'login', text: 'Привет!', color: '#222222', textColor: '#ffffff', position: 'top'})
wew.ui.button({id: 'b2', zone: 'market', text: 'Мой плагин', key: 'open'})   // нажатие -> wew.on('button', function (key) {})
wew.ui.remove('b1')
wew.ui.tint('#8E7BFF')            // общий акцентный цвет окна ('' — сбросить)
wew.app.haptic(); wew.app.openURL('https://...'); wew.app.copy('текст')
wew.translate('Hello', 'ru', function (text) {})   // Google Translate [http]; null при ошибке
```
Не более 8 элементов на плагин и 12 действий за 10 секунд — остальное отбрасывается.

## Пример
Тестовый плагин «Привет» — `examples/privet` (архив `privet-plugin.zip`): здоровается при запуске, один раз в каждом разделе приложения, при входе в меню и при возврате из фона.

Пример со страницей настроек — `examples/example-plugin` (и архив `wewpagram-example-plugin.zip`): страница с переключателем,
полем и кнопками, подпись к исходящим сообщениям, иконка из архива.

## Безопасность
Что ограничено: `wew.http` и `wew.translate` — только `https://` и только публичные адреса (localhost и локальная сеть закрыты),
значения хранилища — до 256 КБ, количество элементов UI и сетевых запросов ограничено по частоте,
а архив плагина проверяется на выход за свою папку, типы файлов и размер.
Плагин — это код, который работает внутри приложения с доступом ко всем перечисленным выше функциям.
Ставьте только плагины, которым доверяете, и смотрите список разрешений в карточке плагина.

## Что плагины пока не умеют
Менять тексты входящих сообщений и пузыри чатов, добавлять собственные экраны сложнее страницы из элементов выше,
запускать нативный код. Это можно добавить следующими версиями API.

## Меню сообщения, окно ввода, локальная правка
```js
wew.contextMenu.add({id: 'edit', title: 'Изменить локально'})   // [contextmenu] до 4 пунктов на плагин
wew.on('contextmenu', function (id, msg) {})                    // msg: {key, text, outgoing}
wew.prompt({title, subtitle, value}, function (text) {})        // [ui] нативное окно с полем; null — отмена
wew.messages.editLocal(msg.key, 'новый текст')                  // [localedit]
```
`editLocal` меняет текст только в базе на этом устройстве, собеседник ничего не видит. Приложение само добавляет к тексту курсивную строку «✎ Отредактировано в WewPagram»: плагин не может её убрать или изменить. Пункты меню не показываются в чатах с защитой от копирования и на опросах. Готовый плагин: `examples/local-edit` (архив `local-edit.zip`).

## Иконка над клавиатурой, буфер обмена, список выбора
```js
wew.ui.button({id: 'clip', zone: 'chat', icon: 'clipboard', position: 'input', key: 'open'})  // круглая иконка над полем ввода, поднимается вместе с клавиатурой
wew.clipboard.get()                       // [clipboard] текст из системного буфера; iOS может спросить разрешение, вызывайте после нажатия
wew.clipboard.paste('текст', function (ok) {})   // [clipboard] кладёт в буфер и вставляет в активное поле ввода
wew.choose({title: 'Заголовок', items: ['a', 'b']}, function (index) {})   // [ui] нативный список; -1 — отмена
```
Готовый плагин: `examples/clipboard` (архив `clipboard.zip`).
