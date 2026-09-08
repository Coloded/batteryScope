# Встроенные мобильные утилиты

В BatteryScope встроены только idevice_id, ideviceinfo и idevicediagnostics. Они запускаются отдельными процессами из Contents/Helpers/MobileDevice. Личные данные и ключи сопряжения в пакет не копируются; используется системный usbmuxd macOS и доверие, которое пользователь устанавливает на своём Mac.

Версии, upstream URL и SHA-256 закреплены в mobile-lock.json. scripts/build-mobile.py собирает обе архитектуры из этих архивов с минимальной macOS 13, объединяет через lipo, меняет абсолютные install names на @loader_path и подписывает каждый файл ad-hoc. Никаких изменений исходного C-кода библиотек нет. Динамические библиотеки остаются отдельными заменяемыми файлами; hardened library validation не включена. После замены файлов потребуется повторная локальная подпись приложения.

Полные тексты лицензий включены в Contents/Resources/MobileDevice-Licenses.txt. Соответствующие оригинальные исходники всех зависимостей и точный скрипт сборки доступны в каждом релизе в BatteryScope-mobile-sources.tar. Его содержимое проверяется по SHA-256 перед публикацией.

Для воспроизведения: macOS с Command Line Tools, Python 3.12+ и pkgconf; выполнить python3 scripts/build-mobile.py. Скрипт скачивает и проверяет архивы, если они отсутствуют. Для автономной сборки распаковать исходный tar в /tmp/batteryscope-mobile-sources. Полная сборка приложения: bash scripts/build.sh.
