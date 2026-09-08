# Официальные обновления BatteryScope

Механизм повторяет архитектуру [Video_editor](https://github.com/Coloded/Video_editor): официальный [Sparkle 2](https://sparkle-project.org/documentation/), подписанный DMG, appcast в GitHub и GitHub Releases. Закреплена версия Sparkle 2.9.6 с проверкой SHA-256. Приватный ключ хранится в Keychain в отдельной записи `BatteryScope`; на GitHub публикуется только открытый ключ.

## На другом Mac

1. Скачать `BatteryScope-stable.dmg` из последнего [релиза](https://github.com/Coloded/batteryScope/releases/latest).
2. Скопировать BatteryScope в «Программы» и запустить.
3. Использовать «Проверить обновления…» в меню BatteryScope, меню значка возле часов или в настройках. Автоматическая проверка включена по умолчанию, установка требует подтверждения пользователя.

DMG содержит универсальное приложение arm64 + x86_64 для macOS 13+. Для чтения iPhone/iPad нужен `brew install libimobiledevice` на соответствующем Mac. На Intel используется Homebrew `/usr/local`, на Apple Silicon — `/opt/homebrew`. Само приложение и Sparkle не зависят от Homebrew.

Сборки 0.3.x и старше не содержат Sparkle: их нужно один раз вручную заменить на 0.4.0 или новее. Данные SQLite и настройки остаются в профиле пользователя, вне `.app`. История между разными компьютерами не синхронизируется.

## Подготовка следующего релиза

1. Увеличить `CFBundleShortVersionString` и числовой `CFBundleVersion` в `Info.plist`.
2. Обновить `updates/release-notes.md`.
3. Выполнить `bash scripts/prepare-release.sh` на Mac с ключом `BatteryScope` в Keychain. Скрипт собирает обе архитектуры, создаёт DMG, подписывает его Sparkle и обновляет appcast.
4. Запустить `bash scripts/test.sh` и `python3 scripts/validate-release.py`.
5. Закоммитить исходники, appcast и два DMG из `dist/`; отправить коммит в `main`.
6. Создать тег `v<версия>` и отправить его в origin. Workflow проверит исходники/бандл/подпись и опубликует релиз автоматически.

Архивы сохранены в git, как в Video_editor, чтобы Actions публиковал именно проверенные и подписанные локально байты. Лента ссылается на конкретный тег релиза, чтобы кэшированная старая подпись не применялась к новому `latest`-архиву. Имя `BatteryScope-stable.dmg` остаётся постоянным для ручного скачивания через `/releases/latest/download/`.

Проверка релиза сверяет манифест исходников, версии и bundle identifier, наличие обеих архитектур, подпись кода, Ed25519-подпись DMG и отклонение изменённого архива. Секретный ключ не нужен GitHub Actions. Не теряйте Keychain: новым ключом нельзя незаметно заменить существующий ключ в установленных приложениях.

## Подписи

Подпись Sparkle подтверждает происхождение обновления. Она не заменяет Apple Developer ID и нотарификацию Gatekeeper. Текущая сборка подписана ad-hoc, как референс; сертификата Developer ID на этом Mac не обнаружено. Для нотарифицированной дистрибуции потребуется отдельная настройка сертификата и Apple notary service.

Сборка `.app` хранится во временной папке macOS, чтобы сохранить symlink-структуру Sparkle. На внешний том переносится DMG, а не распакованный framework. После сборки путь приложения выводит `scripts/build.sh`.
