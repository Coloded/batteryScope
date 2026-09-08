> Реализация 0.6.0: накопленные изменения включены в исходники и сборку. Результаты и ограничения проверки — в VALIDATION.md. OpenSSL обновлён до 4.0.2; входная мощность, нагрузка системы и поток батареи разделены. Для iCloud добавлены стандартная папка, состояние доставки и подтверждения участников. Описания прежнего состояния ниже сохранены как история исследования.

# Аудит зависимостей и возможностей платформы · 8 сентября 2026

Проверена BatteryScope 0.5.1 (7). Исследование без изменения зависимостей, сборки, установки или нового релиза. Версии сверены с releases/latest официальных репозиториев GitHub (prerelease=false). Это проверка доступных версий, а не полный аудит всех CVE.

## Зависимости

| Компонент | Встроен | Последний стабильный релиз upstream |
|---|---|---|
| openssl@3 | 3.6.4 | [openssl-4.0.2](https://github.com/openssl/openssl/releases/tag/openssl-4.0.2) |
| libplist | 2.7.0 | [2.7.0](https://github.com/libimobiledevice/libplist/releases/tag/2.7.0) |
| libimobiledevice-glue | 1.3.2 | [1.3.2](https://github.com/libimobiledevice/libimobiledevice-glue/releases/tag/1.3.2) |
| libusbmuxd | 2.1.1 | [2.1.1](https://github.com/libimobiledevice/libusbmuxd/releases/tag/2.1.1) |
| libtatsu | 1.0.5 | [1.0.5](https://github.com/libimobiledevice/libtatsu/releases/tag/1.0.5) |
| libimobiledevice | 1.4.0 | [1.4.0](https://github.com/libimobiledevice/libimobiledevice/releases/tag/1.4.0) |
| Sparkle | 2.9.6 | [2.9.6](https://github.com/sparkle-project/Sparkle/releases/tag/2.9.6) |

OpenSSL 4.0.2 — новая основная версия относительно встроенной 3.6.4. Использование 3.6.4 было закреплено через формулу openssl@3; она не показывает новейший major всей библиотеки. Перед переходом нужны проверка release notes/API, совместимости libimobiledevice и TLS-сопряжения с реальными устройствами. Само наличие 4.x не доказывает уязвимость текущей сборки. Проверку исправлений и поддержки ветки нужно проводить отдельно перед выпуском.

## Что приложение уже использует

Нативный универсальный SwiftUI-код arm64/x86_64, IOKit/IOPowerSources для батареи, system_profiler для основных характеристик аппаратуры и ОС, SQLite для истории, отдельные процессы libimobiledevice, строку меню, Sparkle и выборочную синхронизацию снимков через папку iCloud Drive. Опрос сейчас раз в минуту; расширенные характеристики читаются по запросу и кэшируются.

## Полезные возможности, которые пока не использованы

1. **Обновление по событиям питания.** IOPSNotificationCreateRunLoopSource сообщает об изменениях источников питания. Можно обновлять карточку Mac сразу, оставив резервный таймер и отдельный более редкий опрос USB/Bluetooth. Это проектная рекомендация; экономию энергии нужно измерить, а не обещать заранее. [Apple](https://developer.apple.com/documentation/iokit/1523868-iopsnotificationcreaterunloopsou).
2. **Тепловое состояние и энергосбережение.** ProcessInfo.thermalState и isLowPowerModeEnabled позволят показать системное состояние и уменьшать необязательную работу в экономном режиме. ThermalState — качественная оценка системы, не температура CPU в градусах и не процент троттлинга. [Apple](https://developer.apple.com/documentation/foundation/processinfo).
3. **Подробности CPU.** Дополнить system_profiler документированными sysctl: количество физических/логических ядер, уровни производительности hw.perflevelN, размеры кэшей. Различия P/E описывать только по доступным данным, с обработкой отсутствующих ключей на Intel/старых ОС. Не выдавать максимальную частоту из справочника за текущую. [Apple](https://developer.apple.com/documentation/kernel/1387446-sysctlbyname/determining_system_capabilities).
4. **Возможности GPU и памяти.** MTLDevice позволяет проверять семейства GPU и функции через supportsFamily, общую память через hasUnifiedMemory, рекомендуемый бюджет ресурсов через recommendedMaxWorkingSetSize. Последнее — бюджет GPU, а не объём установленной или свободной RAM. Сами GPU-вычисления для чтения батареи практической пользы сейчас не дают. [Семейства GPU](https://developer.apple.com/documentation/Metal/improving-your-games-graphics-performance-and-settings), [память](https://developer.apple.com/documentation/metal/mtldevice/recommendedmaxworkingsetsize).
5. **Автозапуск по желанию пользователя.** SMAppService доступен с macOS 13; поможет не прерывать накопление истории после нового входа в систему. Нужен видимый переключатель, а не скрытая установка фонового сервиса. [Apple](https://developer.apple.com/documentation/servicemanagement/smappservice).
6. **Самодиагностика приложения.** Оценить MetricKit для поддерживаемых версий macOS, чтобы находить зависания/сбои и лишнюю нагрузку самого BatteryScope. Доступные отчёты зависят от ОС и API; это не универсальный монитор всех процессов и не источник температур датчиков. Новые интерфейсы, требующие более свежей ОС, включать с проверкой доступности. [Apple](https://developer.apple.com/documentation/metrickit).

Рекомендуемый порядок: события питания и энергосбережение → автозапуск → CPU/GPU-характеристики → измерение накладных расходов. OpenSSL 4.x проверять отдельной задачей совместимости. Не требуются Neural Engine/Metal-ускорение для нынешнего объёма данных, недокументированные датчики не должны становиться обязательной основой приложения.

Прямую доставку iCloud на двух физических Mac и живое чтение iPhone встроенными утилитами 0.5.1 всё ещё нужно проверить. Новые SDK и зависимости не заменяют эти проверки.
