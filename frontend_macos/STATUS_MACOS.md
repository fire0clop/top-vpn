# SplitVPN — порт под macOS: статус

**✅ РАБОТАЕТ (2026-06-04).** Приложение запускается, туннель поднимается, split tunneling
функционирует: проверено вживую — YouTube/Instagram грузятся через прокси (0.98с, ~1.9 МБ/с
на загрузке), ya.ru идёт напрямую. Запуск — через Xcode (⌘R), нужна автоподпись из GUI.

Копия iOS-проекта (`frontend/`), переведённая под macOS. Компилируется полностью
(приложение + расширение + Libbox).

## Что НЕ так с iOS-версией (важно для понимания)
iOS-Libbox — кастомная сборка с API/форматом конфига, которого нет в чистых релизах.
Для macOS взяли **чистый релиз sing-box 1.11.15** и адаптировали под него:
- **Интеграция туннеля** переписана под `LibboxNewService` + `LibboxNewCommandServer(handler,maxLines)`
  + `setService` (pause/wake/resetNetwork на сервисе). Файлы: `PacketTunnelProvider.swift`,
  `BoxPlatformInterface.swift` (packageNameByUid, findConnectionOwner+ret0_, writeLog),
  `Runtime/LogCollector.swift` (лог строками, options.command).
- **Формат конфига** под 1.11: DNS через `address` (не `type`/`server`), убран
  `default_domain_resolver` (поле 1.12+). Проверено `sing-box check`.
- **Известная мелочь:** `box.log` на macOS пишет только «collector started» — лог-поток
  движка к командному клиенту в новой архитектуре цепляется иначе (некритично).

## Что сделано (итог)
- macOS-Libbox собран из релиза **sing-box v1.11.15** (gomobile), универсальный слайс.
- Интеграция туннеля **переписана под новый API libbox** (модель `LibboxNewService` +
  отдельный command-server `LibboxNewCommandServer(handler, maxLines)` + `setService`;
  pause/wake/resetNetwork на сервисе; платформенный протокол — packageNameByUid,
  findConnectionOwner с ret0_, writeLog; лог-клиент — строки через `LibboxStringIterator`).
  Затронуты: `PacketTunnelProvider.swift`, `BoxPlatformInterface.swift`,
  `Runtime/LogCollector.swift`.
- SwiftUI: `.topBarTrailing` → `.primaryAction` (кроссплатформенно).
- `xcodebuild ... CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED**.

## Чтобы ЗАПУСТИТЬ (один раз, через Xcode GUI)
1. Открыть `SplitVPN.xcodeproj`, выбрать схему **SplitVPN** и destination **My Mac**.
2. Target SplitVPN и PacketTunnel → Signing & Capabilities → Team = Z3PM3LR5FF,
   «Automatically manage signing» включено.
3. **⌘R** — Xcode зарегистрирует Mac, создаст профили (App Groups + Network Extension),
   соберёт, подпишет и запустит. При первом включении VPN macOS попросит разрешить
   конфигурацию (System Settings → разрешить).

## Прежний блокер (решён)
Версия Libbox: оказалось, интеграцию проще переписать под чистый релиз (1.11.15), чем
искать кастомный коммит iOS-сборки. Сделано.

## ✅ Сделано

- Скопирован iOS-проект как шаблон.
- `project.yml` → платформа **macOS** (XcodeGen 2.45.4), deployment target 13.0, hardened runtime.
- `SplitVPN/Info.plist` → убрана iOS-специфика (ориентации, launch screen, scene manifest),
  добавлены macOS-ключи (LSMinimumSystemVersion, категория Utilities, copyright).
- Энтайтлменты (`SplitVPN/SplitVPN.entitlements`, `PacketTunnel/PacketTunnel.entitlements`) →
  добавлены **App Sandbox + network client/server**, app-group с префиксом Team ID
  (`$(TeamIdentifierPrefix)group.com.splitvpn.app`).
- `Shared/AppGroup.swift` → на macOS контейнер берётся как `Z3PM3LR5FF.group.com.splitvpn.app`
  (через `#if os(macOS)`).
- Весь UI — чистый SwiftUI, без UIKit → переносится без правок.
- Проект **генерируется** командой `xcodegen generate` без ошибок.
- **macOS-сборка Libbox через gomobile отлажена** — рецепт ниже, собирается универсальный
  `macos-arm64_x86_64` слайс.

## ⛔ Блокер: версия Libbox

iOS-проект использует **кастомную сборку Libbox** (из конкретного коммита sing-box):
её API — «объединённая» архитектура `LibboxNewCommandServer(platform, platform, error)` +
`startOrReloadService` + `pause/wake/closeService` на command-server, с neighbor-монитором,
`LibboxLogIterator`, `addCommand`, `oomKillerEnabled`. Такого сочетания **нет ни в одном
чистом релизе** sing-box (проверены 1.11.15, 1.12.0 — у них другой API: отдельный
`LibboxBoxService` + `setService`, `packageNameByUid`, лог строками и т.д.).

Поэтому собранный мной из релиза macOS-Libbox **не совместим** с кодом
`PacketTunnel/` (BoxPlatformInterface, LogCollector, PacketTunnelProvider, SingBoxConfig).

### Два пути доделать
1. **Взять ТОТ ЖЕ Libbox-коммит**, что в iOS, и собрать его под macOS-таргет → код не менять.
   (Нужно узнать точный коммит/флаги, которыми собран `frontend/Vendor/Libbox.xcframework`.)
2. **Переписать интеграцию туннеля** под актуальный релиз sing-box (модель `LibboxBoxService`):
   адаптировать `PacketTunnelProvider.startService`, `BoxPlatformInterface` (платформенный
   протокол + command-server-handler), `LogCollector` (command-client-handler, лог строками).
   Объём — средний, но требует тестирования на Mac.

## Рецепт сборки macOS-Libbox (рабочий)

```bash
# нужен Go + форк gomobile от sagernet
go install github.com/sagernet/gomobile/cmd/gomobile@latest
go install github.com/sagernet/gomobile/cmd/gobind@latest
export PATH="$PATH:$(go env GOPATH)/bin"
export GOPROXY="https://goproxy.io,https://proxy.golang.org,direct"   # goproxy.io — если googleapis недоступен
export GOSUMDB=off

git clone --depth 1 -b <ТЕГ_или_КОММИТ> https://github.com/sagernet/sing-box.git sb
cd sb
gomobile bind -target=macos -libname=box \
  -tags "with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_dhcp" \
  -o Libbox.xcframework ./experimental/libbox
# важно: имя выходного файла = имя модуля. Для import Libbox он должен быть Libbox.xcframework
```

Затем положить `Libbox.xcframework` в `Vendor/`, `xcodegen generate`, собрать.

## Прочее
- Подпись: для macOS-сборки нужно зарегистрировать bundle ID `com.splitvpn.app` /
  `com.splitvpn.app.PacketTunnel` и Mac-устройство в аккаунте разработчика; для App Store —
  одобрение Apple на entitlement `networkextension` (правило 5.4, желательно аккаунт-организация).
- Базовая связность (DPI домашнего провайдера) на Mac будет той же, что на iOS — отдельная задача.
