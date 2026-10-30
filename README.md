# 🎮 Eastrica Windows Gaming Kiosk (Детский Игровой Киоск)

![Windows](https://img.shields.io/badge/OS-Windows%2010%20%7C%2011-blue?style=flat-square&logo=windows)
![PowerShell](https://img.shields.io/badge/Script-PowerShell-5391FE?style=flat-square&logo=powershell&logoColor=white)
![Version](https://img.shields.io/badge/Version-1.0.0-brightgreen?style=flat-square)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)

*🇷🇺 Выберите язык / 🇬🇧 Choose your language:*

* [🇷🇺 Русская версия (Russian)](#-русская-версия)
* [🇬🇧 English version (English)](#-english-version)
* [📄 Лицензия / License](#-лицензия--license)

## 🇷🇺 Русская версия

Набор продвинутых PowerShell-скриптов для превращения обычного компьютера на Windows 10/11 в защищенную игровую консоль (киоск) для ребенка. Система блокирует доступ к настройкам ОС, заменяет стандартную оболочку Windows на игровой лаунчер ([Playnite](https://playnite.link/)) и защищает компьютер от вирусов и случайных поломок.

### ✨ Основные возможности

* **Замена оболочки (Shell):** Заменяет стандартный `explorer.exe` на скрытый C#-модуль (Watchdog), который следит за тем, чтобы Playnite и игры работали без черных экранов.
* **Тотальная блокировка ОС:** Отключает Диспетчер задач, CMD, PowerShell, Реестр, Панель управления, Настройки, а также меню Пуск и Панель задач.
* **Защита файловой системы:** Блокирует запуск любых `.exe` файлов из папок "Загрузки", "Рабочий стол" и "Документы" (отличная защита от вирусов).
* **Безопасный веб-серфинг:** Позволяет пользоваться браузерами Edge и Brave, но жестко блокирует доступ к их настройкам, расширениям и режиму инкогнито.
* **Родительский контроль и ограничения:** Автоматическое выключение ПК (комендантский час), ограничение времени работы и принудительное включение безопасного DNS.
* **Удобные горячие клавиши:** Специальные комбинации для управления громкостью, закрытия зависших игр и экстренного выхода родителя.

### 📋 Требования

1. Windows 10 или 11 (Pro/Enterprise предпочтительно, но работает и на Home).
2. Права Администратора для выполнения скрипта.
3. Установленный **Playnite** в профиле пользователя-ребенка.

### 🚀 Установка (Настройка Киоска)

1. Войдите в учетную запись Администратора.
2. Скачайте скрипт `Eastrica_SetupKiosk_for_Childs.ps1`.
3. Нажмите по файлу правой кнопкой мыши и выберите **"Выполнить с помощью PowerShell"** (или запустите из консоли от имени Администратора).
4. Следуйте инструкциям на экране (скрипт попросит ввести имя пользователя-ребенка и позволит снять запрос прав администратора с определенных игр).
5. После завершения ПК будет автоматически перезагружен.

### 🗑️ Удаление (Откат настроек)

Скрипт отката вернет систему в первоначальное состояние, сняв все блокировки.

1. Нажмите `Ctrl+Alt+L`, чтобы выйти из режима киоска на экран логина.
2. Войдите в учетную запись Администратора.
3. Запустите `Eastrica_DeleteKiosk_for_Childs.ps1` от имени Администратора.
4. Введите имя пользователя-ребенка, для которого был создан киоск.
5. Дождитесь завершения очистки реестра и перезагрузки.

### ⌨️ Горячие клавиши (Watchdog)

Когда киоск активен, работают следующие системные комбинации:

* `Ctrl+Alt+Up` — Прибавить громкость 🔊
* `Ctrl+Alt+Down` — Убавить громкость 🔉
* `Ctrl+Alt+M` — Выключить/Включить звук (Mute) 🔇
* `Ctrl+Alt+K` — Принудительно закрыть активную (зависшую) игру ❌
* `Ctrl+Alt+P` — Перезапустить Playnite (если черный экран) 🔄
* `Ctrl+Alt+L` — Выйти из учетной записи (Доступ для родителя) 👤
* `Ctrl+Alt+R` — Перезагрузить ПК 🔁
* `Ctrl+Alt+S` — Выключить ПК 🛑

### ⚠️ Важное предупреждение

Скрипт вносит глубокие изменения в реестр пользователя и системные политики. **Настоятельно рекомендуется создать точку восстановления системы** перед первым запуском. Не используйте скрипт на своем основном рабочем профиле!

---

## 🇬🇧 English version

A set of advanced PowerShell scripts to turn a standard Windows 10/11 PC into a secure gaming console (kiosk) for children. The system locks down OS settings, replaces the standard Windows shell with a gaming launcher ([Playnite](https://playnite.link/)), and protects the computer from malware and accidental damage.

### ✨ Key Features

* **Shell Replacement:** Replaces the standard `explorer.exe` with a custom hidden C# module (Watchdog) that ensures Playnite and games run smoothly without black screens.
* **Total OS Lockdown:** Disables Task Manager, CMD, PowerShell, Registry, Control Panel, Settings, as well as the Start Menu and Taskbar.
* **File System Protection:** Blocks the execution of any `.exe` files from "Downloads", "Desktop", and "Documents" folders (acting as a strong anti-malware barrier).
* **Safe Browsing:** Allows the use of Edge and Brave browsers but strictly blocks access to their settings, extensions, and incognito mode.
* **Parental Controls:** Includes automatic PC shutdown (curfew), time limits, and forced safe DNS routing.
* **Convenient Hotkeys:** Special combinations for volume control, killing frozen games, and emergency parent logout.

### 📋 Prerequisites

1. Windows 10 or 11 (Pro/Enterprise preferred, but works on Home).
2. Administrator privileges to run the scripts.
3. **Playnite** installed in the child user's profile.

### 🚀 Installation (Setup Kiosk)

1. Log into your Administrator account.
2. Download the `Eastrica_SetupKiosk_for_Childs.ps1` script.
3. Right-click the file and select **"Run with PowerShell"** (or run from an elevated console).
4. Follow the on-screen instructions (the script will ask for the child's username and allow you to bypass admin prompts for specific games).
5. The PC will automatically restart upon completion.

### 🗑️ Uninstallation (Rollback)

The rollback script will revert the system to its original state, removing all restrictions.

1. Press `Ctrl+Alt+L` to exit kiosk mode to the login screen.
2. Log in to the Administrator account.
3. Run `Eastrica_DeleteKiosk_for_Childs.ps1` as Administrator.
4. Enter the child's username for whom the kiosk was created.
5. Wait for the registry cleanup and reboot to finish.

### ⌨️ Hotkeys (Watchdog Module)

When the kiosk is active, the following system combinations are available:

* `Ctrl+Alt+Up` — Volume Up 🔊
* `Ctrl+Alt+Down` — Volume Down 🔉
* `Ctrl+Alt+M` — Mute/Unmute 🔇
* `Ctrl+Alt+K` — Force kill active (frozen) game ❌
* `Ctrl+Alt+P` — Restart Playnite (if screen is black) 🔄
* `Ctrl+Alt+L` — Sign out (Parental Access) 👤
* `Ctrl+Alt+R` — Restart PC 🔁
* `Ctrl+Alt+S` — Shutdown PC 🛑

### ⚠️ Important Warning

This script makes deep modifications to the user registry and system policies. **It is highly recommended to create a System Restore Point** before running it for the first time. Do not use this script on your primary work profile!

---

## 📄 Лицензия / License

Этот проект распространяется под лицензией MIT. Вы можете свободно использовать, изменять и распространять этот код. Подробности см. в файле [LICENSE](LICENSE).

This project is licensed under the MIT License. You are free to use, modify, and distribute this code. See the [LICENSE](LICENSE) file for details.
