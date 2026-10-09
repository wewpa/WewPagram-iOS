// Плагин "Точное время" - показывает время отправки сообщения при долгом нажатии
// Демонстрирует возможности: контекстное меню, окна, форматирование времени

wew.on("start", function () {
  wew.log("Плагин 'Точное время' загружен");
});

// Добавляем кнопку в контекстное меню сообщения
wew.contextMenu.add({ 
  id: 'exact_time', 
  title: 'Открыть точное время' 
});

// Обработчик нажатия на кнопку в контекстном меню
wew.on("contextmenu", function (id, msg) {
  if (id === "exact_time") {
    // Логируем объект для дебага
    wew.log("Message object:", JSON.stringify(msg));
    
    // Пытаемся получить время - проверяем разные поля
    var timestamp = msg.date || msg.timestamp || msg.time || msg.sentTime || 0;
    
    if (!timestamp || timestamp === 0) {
      wew.alert("Ошибка: время не найдено в объекте сообщения");
      return;
    }
    
    // Преобразуем в дату
    var date = new Date(timestamp * 1000);
    
    // Форматируем время
    var year = date.getFullYear();
    var month = String(date.getMonth() + 1).padStart(2, '0');
    var day = String(date.getDate()).padStart(2, '0');
    var hours = String(date.getHours()).padStart(2, '0');
    var minutes = String(date.getMinutes()).padStart(2, '0');
    var seconds = String(date.getSeconds()).padStart(2, '0');
    
    var formattedTime = day + "." + month + "." + year + " " + hours + ":" + minutes + ":" + seconds;
    
    // Показываем окно с точным временем
    wew.alert(
      "Точное время отправки:\n\n" + formattedTime + "\n\nUnix: " + timestamp
    );
  }
});
