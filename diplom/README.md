# Dota 2 Stats

Flutter приложение для просмотра статистики Dota 2.

## Установка на устройство

1. Скачайте APK файл из папки `build/app/outputs/flutter-apk/app-debug.apk`
2. Включите "Установку из неизвестных источников" в настройках Android
3. Установите APK файл

## Тестирование Deep Links

Для тестирования входа через Steam на реальном устройстве используйте:

```bash
# Тест deep link через ADB
adb shell am start \
  -W -a android.intent.action.VIEW \
  -d "dotastats://auth/steam/callback?openid.claimed_id=https://steamcommunity.com/openid/id/76561198000000000" \
  com.example.diplom
```

## Как работает аутентификация

1. Пользователь нажимает "Войти через Steam"
2. Открывается браузер с URL: `https://steamcommunity.com/openid/login`
3. После входа Steam перенаправляет на: `dotastats://auth/steam/callback`
4. Android запускает приложение через deep link
5. Приложение извлекает Steam ID из URL параметров
6. Пользователь автоматически входит в приложение

## Требования

- Flutter SDK
- Steam API ключ (получить на https://steamcommunity.com/dev/apikey)
