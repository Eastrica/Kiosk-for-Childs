# ==============================================================================
# EASTRICA: ОТКАТ ИГРОВОГО КИОСКА (ВОССТАНОВЛЕНИЕ СИСТЕМЫ)
# ==============================================================================

# ПРОВЕРКА ПРАВ АДМИНИСТРАТОРА
Write-Host "Проверка прав..." -ForegroundColor Gray
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "ОШИБКА: ЗАПУСТИТЕ СКРИПТ ОТ ИМЕНИ АДМИНИСТРАТОРА!"
    Start-Sleep -Seconds 5
    Exit
}

# ==============================================================================
# УДАЛЕНИЕ ИСКЛЮЧЕНИЙ DEFENDER
# ==============================================================================
Write-Host "Удаление исключений из Windows Defender..." -ForegroundColor Cyan
try {
    Remove-MpPreference -ExclusionPath "$env:PUBLIC\Watchdog.exe" -Force -ErrorAction SilentlyContinue
    Remove-MpPreference -ExclusionProcess "Watchdog.exe" -Force -ErrorAction SilentlyContinue
    Remove-MpPreference -ExclusionPath "$env:PUBLIC\Watchdog.ps1" -Force -ErrorAction SilentlyContinue
    Remove-MpPreference -ExclusionProcess "Playnite.DesktopApp.exe" -Force -ErrorAction SilentlyContinue
    Write-Host "Исключения Defender успешно удалены." -ForegroundColor Green
} catch {
    Write-Warning "Не удалось удалить исключения Defender."
}

# ==============================================================================
# УДАЛЕНИЕ ФАЙЛОВ WATCHDOG
# ==============================================================================
Write-Host "Удаление исполняемых файлов Watchdog..." -ForegroundColor Cyan
if (Test-Path "$env:PUBLIC\Watchdog.exe") { Remove-Item "$env:PUBLIC\Watchdog.exe" -Force -ErrorAction SilentlyContinue }
if (Test-Path "$env:PUBLIC\Watchdog.ps1") { Remove-Item "$env:PUBLIC\Watchdog.ps1" -Force -ErrorAction SilentlyContinue }

# ВЫБОР ЦЕЛЕВОГО ПОЛЬЗОВАТЕЛЯ
$CurrentUserName = $env:USERNAME
Write-Host " "
Write-Host "--- ОТКАТ НАСТРОЕК КИОСКА ---" -ForegroundColor Yellow
Write-Host "Введите точное имя пользователя-ребенка, для которого делали киоск."
Write-Host "(Нажмите Enter, если применяли к текущему: $CurrentUserName)"
$TargetUser = Read-Host "Имя пользователя"

if ([string]::IsNullOrWhiteSpace($TargetUser)) {
    $TargetUser = $CurrentUserName
}

try {
    $UserObj = New-Object System.Security.Principal.NTAccount($TargetUser)
    $SID = $UserObj.Translate([System.Security.Principal.SecurityIdentifier]).Value
    Write-Host "Пользователь '$TargetUser' найден. SID: $SID" -ForegroundColor Green
} catch {
    Write-Warning "ОШИБКА: Пользователь '$TargetUser' не найден!"
    Pause
    Exit
}

# ==============================================================================
# ЧАСТЬ 1: ПОДКЛЮЧЕНИЕ РЕЕСТРА ПОЛЬЗОВАТЕЛЯ
# ==============================================================================
Write-Host "Подключение реестра пользователя..." -ForegroundColor Cyan

$HiveDrive = "HKU_Kiosk"
$ManualLoad = $false

$Prof = "$env:SystemDrive\Users\$TargetUser\NTUSER.DAT"
if (Test-Path $Prof) {
    Write-Host "Загрузка куста реестра из файла..." -ForegroundColor Gray
    reg load "HKU\TempKiosk" "$Prof"
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Не удалось загрузить реестр. Возможно, файл занят. ПЕРЕЗАГРУЗИТЕ ПК!"
        Exit
    }
    New-PSDrive -Name $HiveDrive -PSProvider Registry -Root "HKEY_USERS\TempKiosk" | Out-Null
    $ManualLoad = $true
} else {
    Write-Warning "Файл профиля NTUSER.DAT не найден по пути $Prof"
    Exit
}
$HivePath = "$($HiveDrive):"

try {

# ==============================================================================
# ЧАСТЬ 2: ОБЪЯВЛЕНИЕ ПЕРЕМЕННЫХ ПУТЕЙ
# ==============================================================================
$PolEx = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
$PolSys = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Policies\System"
$PolAD = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop"
$PolDlg = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Policies\Comdlg32"
$WinLogon = "$HivePath\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"

# ==============================================================================
# ЧАСТЬ 3: СНЯТИЕ БЛОКИРОВОК ЗАПУСКА (HKCU)
# ==============================================================================
Write-Host "Снятие блокировок приложений..." -ForegroundColor Cyan
$UserLayers = "$HivePath\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"

$BlockedApps = @(
    "$env:SystemRoot\System32\cmd.exe", 
    "$env:SystemRoot\System32\taskmgr.exe", 
    "$env:SystemRoot\regedit.exe",
    "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe", 
    "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell_ise.exe",
    "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
)

foreach ($App in $BlockedApps) {
    Remove-ItemProperty -Path $UserLayers -Name $App -Force -ErrorAction SilentlyContinue
}

# Включаем глобальные сообщения об ошибках обратно (по умолчанию 0)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Windows" -Name "ErrorMode" -Value 0 -Force -ErrorAction SilentlyContinue

# Удаляем черный список запуска (DisallowRun)
Remove-ItemProperty -Path $PolEx -Name "DisallowRun" -Force -ErrorAction SilentlyContinue
$DisallowKey = "$PolEx\DisallowRun"
if (Test-Path $DisallowKey) { Remove-Item -Path $DisallowKey -Recurse -Force -ErrorAction SilentlyContinue }

# Снимаем жесткую блокировку CMD
Remove-ItemProperty -Path $PolSys -Name "DisableCMD" -Force -ErrorAction SilentlyContinue

$UserClasses = "$HivePath\Software\Classes"
$ExtsToKill = @(".bat", ".cmd", ".vbs", ".ps1", ".reg", ".msi")

foreach ($Ext in $ExtsToKill) {
    # Удаляем переопределение "(default) = txtfile" из ветки ребенка
    $Key = "$UserClasses\$Ext"
    if (Test-Path $Key) {
        Remove-ItemProperty -Path $Key -Name "(default)" -Force -ErrorAction SilentlyContinue
    }
    
    # Очищаем кэш выбора пользователя именно в ПРОФИЛЕ РЕБЕНКА (а не в HKCU)
    $UserExtKey = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Ext"
    if (Test-Path $UserExtKey) {
        Remove-Item -Path $UserExtKey -Force -Recurse -ErrorAction SilentlyContinue
    }
}

# ==============================================================================
# ЧАСТЬ 4: ВОССТАНОВЛЕНИЕ ПОЛИТИК ИНТЕРФЕЙСА
# ==============================================================================
Write-Host "Восстановление Меню Пуск, Панели задач и Трея..." -ForegroundColor Cyan

$TaskbarMod = "$HivePath\Software\Policies\Microsoft\Windows\TaskbarModifications"

Remove-ItemProperty -Path $PolEx -Name "NoStartMenuMorePrograms" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoStartMenuMyMusic" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoStartMenuMyPictures" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoStartMenuMyGames" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoSMHelp" -Force -ErrorAction SilentlyContinue

$Adv = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Remove-ItemProperty -Path $Adv -Name "Start_TrackProgs" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $Adv -Name "Start_TrackDocs" -Force -ErrorAction SilentlyContinue

Remove-ItemProperty -Path $TaskbarMod -Name "NoPinningToTaskbar" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $TaskbarMod -Name "NoPinningStoreToTaskbar" -Force -ErrorAction SilentlyContinue

Remove-ItemProperty -Path $PolEx -Name "LockTaskbar" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoSetTaskbar" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoToolbarsOnTaskbar" -Force -ErrorAction SilentlyContinue

Remove-ItemProperty -Path $PolEx -Name "NoTrayItemsDisplay" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoAutoTrayNotify" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "TaskbarNoNotification" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoBalloonToasts" -Force -ErrorAction SilentlyContinue

Remove-ItemProperty -Path $PolEx -Name "NoViewContextMenu" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoFileMenu" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoPropertiesMyComputer" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoControlPanel" -Force -ErrorAction SilentlyContinue

# ==============================================================================
# ЧАСТЬ 5: СНЯТИЕ ОГРАНИЧЕНИЙ СИСТЕМЫ И ВОССТАНОВЛЕНИЕ НАСТРОЕК МЫШИ
# ==============================================================================
Write-Host "Снятие ограничений системы (USB, Уведомления, Поиск, Обои)..." -ForegroundColor Cyan

$PolUSB = "$HivePath\Software\Policies\Microsoft\Windows\RemovableStorageDevices"
if (Test-Path $PolUSB) { Remove-Item -Path $PolUSB -Recurse -Force -ErrorAction SilentlyContinue }

$PolPush = "$HivePath\Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications"
Remove-ItemProperty -Path $PolPush -Name "NoToastApplicationNotification" -Force -ErrorAction SilentlyContinue

Remove-ItemProperty -Path $PolEx -Name "NoEntireNetwork" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoNetCrawling" -Force -ErrorAction SilentlyContinue

$PolSysConfig = "$HivePath\Software\Policies\Microsoft\Windows\System"
Remove-ItemProperty -Path $PolSysConfig -Name "AllowClipboardHistory" -Force -ErrorAction SilentlyContinue

Remove-ItemProperty -Path $PolEx -Name "NoSecurityTab" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoHardwareTab" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoFolderOptions" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoClose" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoDrives" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoViewOnDrive" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "SettingsPageVisibility" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoRun" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoWinKeys" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "NoDriveTypeAutoRun" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolEx -Name "DisableNotificationCenter" -Force -ErrorAction SilentlyContinue

Remove-ItemProperty -Path $PolAD -Name "NoChangingWallPaper" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolSys -Name "DisableChangePassword" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolSys -Name "DisableLockWorkstation" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolSys -Name "DisableTaskMgr" -Force -ErrorAction SilentlyContinue

Remove-ItemProperty -Path $PolDlg -Name "NoPlacesBar" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolDlg -Name "NoBackButton" -Force -ErrorAction SilentlyContinue

# Восстановление кнопки Ease of Access на экране входа
$EaseOfAccess = "HKLM:\SOFTWARE\Microsoft\Windows Embedded\EmbeddedLogon"
Remove-ItemProperty -Path $EaseOfAccess -Name "BrandingNeutral" -Force -ErrorAction SilentlyContinue

# Восстановление Уведомлений
$QuietHours = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings"
Remove-ItemProperty -Path $QuietHours -Name "NOC_GLOBAL_SETTING_TOASTS_LEVEL" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $QuietHours -Name "NOC_GLOBAL_SETTING_ALLOW_CRITICAL_ALERTS" -Force -ErrorAction SilentlyContinue

# ==============================================================================
# ЧАСТЬ 6: ВОССТАНОВЛЕНИЕ НАСТРОЕК ИНТЕРНЕТА (EDGE И BRAVE)
# ==============================================================================
Write-Host "Удаление ограничений браузера Edge..." -ForegroundColor Cyan

Remove-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "HKCU:\SOFTWARE\Policies\Microsoft\Edge" -Recurse -Force -ErrorAction SilentlyContinue
if ($HivePath) { 
    Remove-Item -Path "$HivePath\SOFTWARE\Policies\Microsoft\Edge" -Recurse -Force -ErrorAction SilentlyContinue 
}

Write-Host "Удаление ограничений браузера Brave..." -ForegroundColor Cyan

Remove-Item -Path "HKLM:\SOFTWARE\Policies\BraveSoftware" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "HKCU:\SOFTWARE\Policies\BraveSoftware" -Recurse -Force -ErrorAction SilentlyContinue
if ($HivePath) { 
    Remove-Item -Path "$HivePath\SOFTWARE\Policies\BraveSoftware" -Recurse -Force -ErrorAction SilentlyContinue 
}

# ==============================================================================
# ЧАСТЬ 7: УДАЛЕНИЕ ПЛАНИРОВЩИКА ЗАДАЧ (DNS, ОЧИСТКА)
# ==============================================================================
Write-Host "Удаление созданных задач планировщика..." -ForegroundColor Cyan

Unregister-ScheduledTask -TaskName "Kiosk_SetDNS_$TargetUser" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "Kiosk_ResetDNS" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "Kiosk_AutoCleanup_$TargetUser" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "Kiosk_DisableAutoLogon" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "Kiosk_EnableAutoLogon" -Confirm:$false -ErrorAction SilentlyContinue

# Удаление пункта из контекстного меню Eastrica Tools
if (!(Get-PSDrive -Name HKCR -ErrorAction SilentlyContinue)) { 
    New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -ErrorAction SilentlyContinue | Out-Null 
}
$MenuKey_Kiosk = "HKCR:\Directory\Background\shell\EastricaTools\shell\09_EnableKiosk"
if (Test-Path $MenuKey_Kiosk) { 
    Remove-Item -LiteralPath $MenuKey_Kiosk -Recurse -Force -ErrorAction SilentlyContinue 
}

# Очистка DNS (возврат к автоматическому получению / DHCP)
Write-Host "Сброс DNS настроек адаптеров..." -ForegroundColor Gray
Get-NetAdapter | Where-Object Status -eq Up | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddresses }

# ==============================================================================
# ЧАСТЬ 8: СНЯТИЕ ОГРАНИЧЕНИЙ ПО ВРЕМЕНИ И ТВИКОВ ИНТЕРФЕЙСА
# ==============================================================================
Write-Host "Снятие ограничений по времени (Родительский контроль)..." -ForegroundColor Cyan
net user $TargetUser /times:all | Out-Null

Write-Host "Снятие игровых твиков реестра..." -ForegroundColor Cyan
$DesktopColors = "$HivePath\Control Panel\Colors"
Remove-ItemProperty -Path $DesktopColors -Name "Background" -Force -ErrorAction SilentlyContinue

powercfg /x -standby-timeout-ac 30
powercfg /x -hibernate-timeout-ac 0 # Гибернацию обычно оставляем выключенной, но сон возвращаем.

# ==============================================================================
# ЧАСТЬ 9: СНЯТИЕ АБСОЛЮТНОЙ ЗАЩИТЫ ФАЙЛОВОЙ СИСТЕМЫ (NTFS ICACLS)
# ==============================================================================
Write-Host "Разблокировка запуска файлов из папок пользователя..." -ForegroundColor Cyan
$ChildFolders = @(
    "$env:SystemDrive\Users\$TargetUser\Downloads",
    "$env:SystemDrive\Users\$TargetUser\Desktop",
    "$env:SystemDrive\Users\$TargetUser\Documents"
)

foreach ($Folder in $ChildFolders) {
    if (Test-Path $Folder) {
        # Удаляем правило запрета (/remove:d) для пользователя
        Start-Process "icacls" -ArgumentList "`"$Folder`" /remove:d `"$TargetUser`"" -NoNewWindow -Wait
        Write-Host "Блокировка запуска снята для: $Folder" -ForegroundColor Green
    }
}

# ==============================================================================
# ЧАСТЬ 10: СНЯТИЕ "ЯДЕРНОЙ" БЛОКИРОВКИ (LOGIN)
# ==============================================================================
$PolSysLocal = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-ItemProperty -Path $PolSysLocal -Name "HideFastUserSwitching" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $PolSysLocal -Name "shutdownwithoutlogon" -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $PolSysLocal -Name "DontDisplayNetworkSelectionUI" -Force -ErrorAction SilentlyContinue

# Восстановление залипания клавиш для СИСТЕМЫ на экране входа
$StickySys = "Registry::HKEY_USERS\.DEFAULT\Control Panel\Accessibility\StickyKeys"
if (Test-Path $StickySys) {
    Set-ItemProperty -Path $StickySys -Name "Flags" -Value "510" -Force -ErrorAction SilentlyContinue
}

Write-Host "Восстановление среды восстановления (WinRE)..." -ForegroundColor Cyan
bcdedit /deletevalue "{default}" bootstatuspolicy 2>&1 | Out-Null

# Возврат запросов UAC для обычных пользователей (запрашивать учетные данные)
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorUser" -Value 3 -PropertyType DWord -Force -ErrorAction SilentlyContinue

Write-Host "Отключение автоматического входа в систему..." -ForegroundColor Cyan
$WinLogonLocal = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $WinLogonLocal -Name "AutoAdminLogon" -Value "0" -PropertyType String -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $WinLogonLocal -Name "DefaultUserName" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $WinLogonLocal -Name "DefaultPassword" -ErrorAction SilentlyContinue

# ==============================================================================
# ЧАСТЬ 11: РАЗБЛОКИРОВКА УСТАНОВЩИКА MSI И ПАРОЛЕЙ
# ==============================================================================
$Installer = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer"
Remove-ItemProperty -Path $Installer -Name "DisableMSI" -Force -ErrorAction SilentlyContinue

$PolSys = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Policies\System"
Remove-ItemProperty -Path $PolSys -Name "DisableChangePassword" -Force -ErrorAction SilentlyContinue

# ==============================================================================
# ЧАСТЬ 12: ВОССТАНОВЛЕНИЕ ОБОЛОЧКИ (ЗАМЕНА SHELL ОБРАТНО НА EXPLORER)
# ==============================================================================
Write-Host "Восстановление стандартной оболочки (explorer.exe)..." -ForegroundColor Cyan
# Удаление кастомного Shell вернет стандартный explorer.exe
Remove-ItemProperty -Path $WinLogon -Name "Shell" -Force -ErrorAction SilentlyContinue
Write-Host "Shell возвращен к значениям по умолчанию." -ForegroundColor Green

# ==============================================================================
# СНЯТИЕ ДОПОЛНИТЕЛЬНЫХ УЛУЧШЕНИЙ КИОСКА
# ==============================================================================
# --- УДАЛЕНИЕ ЗАДАЧИ АВТОВЫКЛЮЧЕНИЯ ---
Write-Host "Снятие комендантского часа..." -ForegroundColor Cyan
Unregister-ScheduledTask -TaskName "Kiosk_Curfew_$TargetUser" -Confirm:$false -ErrorAction SilentlyContinue

# --- СНЯТИЕ БЛОКИРОВКИ СЕТЕВЫХ НАСТРОЕК ---
Write-Host "Разблокировка сетевых настроек..." -ForegroundColor Cyan
$PolNet = "$HivePath\Software\Policies\Microsoft\Windows\Network Connections"
if (Test-Path $PolNet) { Remove-Item -Path $PolNet -Recurse -Force -ErrorAction SilentlyContinue }

# --- ВОССТАНОВЛЕНИЕ ЭКРАНА БЛОКИРОВКИ ---
$PolPers = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
Remove-ItemProperty -Path $PolPers -Name "NoLockScreen" -Force -ErrorAction SilentlyContinue

} finally {

# ==============================================================================
# ФИНАЛ: ВЫГРУЗКА РЕЕСТРА
# ==============================================================================
if (Get-PSDrive -Name $HiveDrive -ErrorAction SilentlyContinue) {
    Set-Location "C:\"
    Remove-PSDrive -Name $HiveDrive -Force
}
$HivePath = $null

if ($ManualLoad) {
    Write-Host "Выгрузка реестра..." -ForegroundColor Gray
    
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    
    Start-Sleep -Seconds 2
    
    $UnloadLoop = 0
    do {
        reg unload "HKU\TempKiosk" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Реестр успешно выгружен." -ForegroundColor Green
            $UnloadLoop = 10
        } else {
            Write-Warning "Файл занят, повторная попытка через 2 сек..."
            [System.GC]::Collect()
            Start-Sleep -Seconds 2
            $UnloadLoop++
        }
    } while ($UnloadLoop -lt 5)
    
    if ($UnloadLoop -eq 5) {
        Write-Warning "КРИТИЧЕСКАЯ ОШИБКА: Не удалось выгрузить реестр!"
        Write-Warning "ПЕРЕЗАГРУЗИТЕ КОМПЬЮТЕР НЕМЕДЛЕННО."
        Pause
    }
} else {
    $OriginalEncoding = [Console]::OutputEncoding
    gpupdate /force
    [Console]::OutputEncoding = $OriginalEncoding
    Write-Host "Политики обновлены." -ForegroundColor Gray
}

}

# ==============================================================================
# ВОССТАНОВЛЕНИЕ ПРАВ АДМИНИСТРАТОРА (ВОЗВРАТ ГРУППЫ)
# ==============================================================================
Write-Host "Восстановление прав Администратора для пользователя $TargetUser..." -ForegroundColor Cyan

try {
    $AdminGroup = (Get-LocalGroup | Where-Object { $_.SID -like "S-1-5-32-544" }).Name
    Add-LocalGroupMember -Group $AdminGroup -Member $TargetUser -ErrorAction SilentlyContinue
    Write-Host "Пользователь $TargetUser снова добавлен в группу 'Администраторы'." -ForegroundColor Green
} catch {
    Write-Warning "Не удалось автоматически вернуть права Администратора."
    Write-Warning "Ошибка: $_"
}

Write-Host " "
Write-Host "-------------------------------------------------------------" -ForegroundColor Green
Write-Host "ОТКАТ НАСТРОЕК УСПЕШНО ЗАВЕРШЕН!"
Write-Host "Система приведена в исходное состояние."
Write-Host "-------------------------------------------------------------"
Pause
Write-Host "АВТОМАТИЧЕСКАЯ ПЕРЕЗАГРУЗКА ПК ЧЕРЕЗ 5 СЕКУНД..." -ForegroundColor Red
Start-Sleep -Seconds 5
Restart-Computer -Force