# ==============================================================================
# EASTRICA: ИГРОВОЙ КИОСК
# ==============================================================================

# ПРОВЕРКА ПРАВ АДМИНИСТРАТОРА
Write-Host "Проверка прав..." -ForegroundColor Gray
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "ОШИБКА: ЗАПУСТИТЕ СКРИПТ ОТ ИМЕНИ АДМИНИСТРАТОРА!"
    Start-Sleep -Seconds 5
    Exit
}

# ==============================================================================
# ДОБАВЛЕНИЕ ИСКЛЮЧЕНИЙ DEFENDER
# ==============================================================================
Write-Host "Добавление исключений в Windows Defender..." -ForegroundColor Cyan
try {
    # Исключаем сам Watchdog.exe
    Add-MpPreference -ExclusionPath "$env:PUBLIC\Watchdog.exe" -Force -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "Watchdog.exe" -Force -ErrorAction SilentlyContinue
    
    # Исключаем скрипты в папке Public (на всякий случай)
    Add-MpPreference -ExclusionPath "$env:PUBLIC\Watchdog.ps1" -Force -ErrorAction SilentlyContinue
    
    # Исключаем процесс Playnite, чтобы антивирус не тормозил его запуск
    Add-MpPreference -ExclusionProcess "Playnite.DesktopApp.exe" -Force -ErrorAction SilentlyContinue
    
    Write-Host "Исключения Defender успешно добавлены." -ForegroundColor Green
} catch {
    Write-Warning "Не удалось добавить исключения Defender (возможно, он выключен или нет прав)."
}

# ВЫБОР ЦЕЛЕВОГО ПОЛЬЗОВАТЕЛЯ
$CurrentUserName = $env:USERNAME
Write-Host " "
Write-Host "--- НАСТРОЙКА КИОСКА ---" -ForegroundColor Yellow
Write-Host "Введите точное имя пользователя-ребенка."
Write-Host "(Нажмите Enter, если хотите настроить текущего пользователя: $CurrentUserName)"
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
# СНЯТИЕ "ЩИТА" И ЗАПРОСА ПАРОЛЯ ДЛЯ ИГР У ОБЫЧНОГО ПОЛЬЗОВАТЕЛЯ
# ==============================================================================

Write-Host "--- СНЯТИЕ ЗАПРОСА ПРАВ АДМИНИСТРАТОРА ---" -ForegroundColor Cyan
Write-Host "Сейчас откроется окно выбора файлов."
Write-Host "Выбирайте нужные .exe файлы (можно выделять по одному или сразу несколько)."
Write-Host "Когда закончите с выбором, нажмите 'ОТМЕНА' или закройте окно, чтобы скрипт пошел дальше."
Write-Host " "

# Подключаем библиотеку для работы с графическими окнами
Add-Type -AssemblyName System.Windows.Forms

$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"

# Создаем ветку, если её вдруг нет
if (!(Test-Path $RegPath)) {
    New-Item -Path $RegPath -Force | Out-Null
}

# Настраиваем диалоговое окно
$OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$OpenFileDialog.Title = "Выберите .exe файл игры (или нажмите ОТМЕНА для продолжения)"
$OpenFileDialog.Filter = "Исполняемые файлы (*.exe)|*.exe"
$OpenFileDialog.Multiselect = $true # Разрешил выделять сразу несколько файлов для удобства
$OpenFileDialog.InitialDirectory = "C:\"

# Бесконечный цикл, пока не нажмут "Отмена"
while ($true) {
    # Создаем скрытую форму поверх всех окон, чтобы диалог не спрятался за консолью
    $TopForm = New-Object System.Windows.Forms.Form -Property @{TopMost=$true}
    
    # Показываем окно выбора
    $DialogResult = $OpenFileDialog.ShowDialog($TopForm)
    $TopForm.Dispose()

    # Если пользователь выбрал файл(ы) и нажал "Открыть"
    if ($DialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        foreach ($File in $OpenFileDialog.FileNames) {
            try {
                # Добавляем флаг ~ RunAsInvoker (Снимаем щит)
                Set-ItemProperty -Path $RegPath -Name $File -Value "~ RunAsInvoker" -Force
                Write-Host "[УСПЕХ] Щит снят: $File" -ForegroundColor Green
            } catch {
                Write-Warning "[ОШИБКА] Не удалось изменить реестр для: $File"
            }
        }
        
        # Запоминаем последнюю папку, чтобы следующее окно открылось в ней же, а не на диске C:\
        $OpenFileDialog.InitialDirectory = [System.IO.Path]::GetDirectoryName($OpenFileDialog.FileNames[0])
        Write-Host "Снова открываю окно... (Нажмите 'Отмена', если закончили)" -ForegroundColor Gray
    } 
    # Если пользователь нажал "Отмена" или закрыл окно крестиком
    else {
        Write-Host "Выбор файлов завершен. Переходим к следующему шагу." -ForegroundColor Yellow
        break
    }
}

# ==============================================================================
# БЛОК КОНФИГУРАЦИИ
# ==============================================================================
Write-Host "Загрузка конфигурации..." -ForegroundColor Cyan

# Используем переменные окружения
$UserHome = "$env:SystemDrive\Users\$TargetUser"
$PublicDir = $env:PUBLIC

$WatchdogPath = "$PublicDir\Watchdog.ps1"
# Путь к Playnite в профиле ребенка
$AppPathCode = "$UserHome\AppData\Local\Playnite\Playnite.DesktopApp.exe" 
$AppArgs = "--fullscreen"

# Список конфигураций игр (Откуда -> Куда)
# Замените C: на $env:SystemDrive
$RawRestores = @{
    "$env:SystemDrive\KioskGameCfgs\Sandstorm_GameUserSettings.ini" = "$UserHome\AppData\Local\Insurgency\Saved\Config\WindowsClient\GameUserSettings.ini";
    "$env:SystemDrive\KioskGameCfgs\Cyberpunk_UserSettings.json" = "$UserHome\AppData\Local\CD Projekt Red\Cyberpunk 2077\UserSettings.json";
    "$env:SystemDrive\KioskGameCfgs\GroundBranch_GameUserSettings.ini" = "$UserHome\AppData\Local\GroundBranch\Saved\Config\WindowsNoEditor\GameUserSettings.ini";
    "$env:SystemDrive\KioskGameCfgs\GYMGAME_GameUserSettings.ini" = "$UserHome\AppData\Local\GYMGAME\Saved\Config\Windows\GameUserSettings.ini";
    "$env:SystemDrive\KioskGameCfgs\CSS_config.cfg" = "D:\Steam\steamapps\common\Counter-Strike Source\cstrike\cfg\config.cfg";
    "$env:SystemDrive\KioskGameCfgs\CS1.6_config.cfg" = "D:\Steam\steamapps\common\Half-Life\cstrike\config.cfg";
    "$env:SystemDrive\KioskGameCfgs\CZ_config.cfg" = "D:\Steam\steamapps\common\Half-Life\czero\config.cfg";
    "$env:SystemDrive\KioskGameCfgs\CZR_config.cfg" = "D:\Steam\steamapps\common\Half-Life\czeror\config.cfg";
    "$env:SystemDrive\KioskGameCfgs\HL_config.cfg" = "D:\Steam\steamapps\common\Half-Life\valve\config.cfg";
    "$env:SystemDrive\KioskGameCfgs\HL2MP_config.cfg" = "D:\Steam\steamapps\common\Half-Life 2 Deathmatch\hl2mp\cfg\config.cfg";
    "$env:SystemDrive\KioskGameCfgs\INS2_config.cfg" = "D:\Steam\steamapps\common\insurgency2\insurgency\cfg\config.cfg";
    "$env:SystemDrive\KioskGameCfgs\BMS_config.cfg" = "E:\Black Mesa\bms\cfg\config.cfg";
    "$env:SystemDrive\KioskGameCfgs\BOIII_config.ini" = "E:\Call of Duty - Black Ops 3 (2015) Portable by Canek77\boiii_players\config.ini";
    "$env:SystemDrive\KioskGameCfgs\HL1_config.cfg" = "E:\Half Life\valve\config.cfg";
    "$env:SystemDrive\KioskGameCfgs\HL2_config.cfg" = "E:\Half-Life 2. Complete Edition\hl2\cfg\config.cfg";
    "$env:SystemDrive\KioskGameCfgs\HL2EP2_config.cfg" = "E:\Half-Life 2. Complete Edition\ep2\cfg\config.cfg";
    "$env:SystemDrive\KioskGameCfgs\PenDriverPro_GameUserSettings.ini" = "E:\Pacific Drive (2024)\Pacific Drive\PenDriverPro\Config\WindowsNoEditor\GameUserSettings.ini";
    "$env:SystemDrive\KioskGameCfgs\RE4_configs.user.ini" = "E:\Resident Evil 4 Remake\steam_settings\configs.user.ini";
}

Write-Host "Проверка наличия файлов конфигурации..." -ForegroundColor Yellow
$Restores = @{}
# Проверяем существование исходных файлов
foreach ($SourceKey in $RawRestores.Keys) {
    if (Test-Path $SourceKey) {
        $Restores[$SourceKey] = $RawRestores[$SourceKey]
    } else {
        Write-Warning "Файл не найден (пропущен): $SourceKey"
    }
}

# ==============================================================================
# КОМПИЛЯЦИЯ C# WATCHDOG (EXE - НЕВИДИМЫЙ РЕЖИМ)
# ==============================================================================
Write-Host "--- Компиляция высокопроизводительного Watchdog (C#) ---" -ForegroundColor Cyan

# Подготовка путей для копирования в C# (экранирование слешей)
$CodeRestores = ""
foreach ($Key in $Restores.Keys) {
    $S = $Key.Replace("\", "\\")
    $D = $Restores[$Key].Replace("\", "\\")
    $CodeRestores += "            { `"$S`", `"$D`" },`r`n"
}

$WatchdogSrc = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Media;
using System.Runtime; 
using Microsoft.Win32;

public class Watchdog {
    // --- ИМПОРТ ФУНКЦИЙ WINDOWS API ---
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr hWnd); 
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd); // ДЛЯ АВТОВОЗВРАТА ФОКУСА
    [DllImport("winmm.dll")] internal static extern uint timeBeginPeriod(uint uPeriod);
    
    // API для работы с разрешением экрана
    [DllImport("user32.dll")] static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
    [DllImport("user32.dll")] static extern int ChangeDisplaySettings(ref DEVMODE devMode, int flags);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    private const int SW_MAXIMIZE = 3; 

    static string AppPath = @"$AppPathCode";
    static string AppArgs = @"$AppArgs"; 
    
    static Dictionary<string, string> Restores = new Dictionary<string, string>() {
$CodeRestores
    };

    // --- ЛОГИКА КОНТРОЛЯ РАЗРЕШЕНИЯ ЭКРАНА ---
    static DEVMODE nativeMode;
    static bool hasNativeMode = false;

    static void InitResolution() {
        nativeMode = new DEVMODE();
        nativeMode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (EnumDisplaySettings(null, -2, ref nativeMode)) {
            hasNativeMode = true;
        }
    }

    static void RestoreResolution() {
        if (!hasNativeMode) return;
        DEVMODE currentMode = new DEVMODE();
        currentMode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (EnumDisplaySettings(null, -1, ref currentMode)) {
            if (currentMode.dmPelsWidth != nativeMode.dmPelsWidth || 
                currentMode.dmPelsHeight != nativeMode.dmPelsHeight ||
                currentMode.dmDisplayFrequency != nativeMode.dmDisplayFrequency) {
                ChangeDisplaySettings(ref nativeMode, 0);
            }
        }
    }

    // --- ИНТЕРФЕЙСЫ ДЛЯ УПРАВЛЕНИЯ ЗВУКОМ ---
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class MMDeviceEnumerator { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator {
        void EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr ppDevices);
        void GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice {
        void Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
    }

    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioEndpointVolume {
        int RegisterControlChangeNotify(IntPtr pNotify);
        int UnregisterControlChangeNotify(IntPtr pNotify);
        int GetChannelCount(out int pnChannelCount);
        int SetMasterVolumeLevel(float fLevelDB, Guid pguidEventContext);
        int SetMasterVolumeLevelScalar(float fLevel, Guid pguidEventContext);
        int GetMasterVolumeLevel(out float pfLevelDB);
        int GetMasterVolumeLevelScalar(out float pfLevel);
        int SetChannelVolumeLevel(uint nChannel, float fLevelDB, Guid pguidEventContext);
        int SetChannelVolumeLevelScalar(uint nChannel, float fLevel, Guid pguidEventContext);
        int GetChannelVolumeLevel(uint nChannel, out float pfLevelDB);
        int GetChannelVolumeLevelScalar(uint nChannel, out float pfLevel);
        int SetMute(bool bMute, Guid pguidEventContext);
        int GetMute(out bool pbMute);
        int GetVolumeStepInfo(out uint pnStep, out uint pnStepCount);
        int VolumeStepUp(Guid pguidEventContext);
        int VolumeStepDown(Guid pguidEventContext);
    }

    static void ControlVolume(string action) {
        try {
            var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumerator());
            IMMDevice dev;
            enumerator.GetDefaultAudioEndpoint(0, 1, out dev);
            
            Guid iid = new Guid("5CDF2C82-841E-4546-9722-0CF74078229A");
            object epvObj;
            dev.Activate(ref iid, 1, IntPtr.Zero, out epvObj);
            
            var epv = (IAudioEndpointVolume)epvObj;

            if (action == "UP") {
                epv.SetMute(false, Guid.Empty); 
                epv.VolumeStepUp(Guid.Empty);
                new SoundPlayer(@"C:\Windows\Media\Speech On.wav").Play();
            }
            else if (action == "DOWN") {
                epv.SetMute(false, Guid.Empty);
                epv.VolumeStepDown(Guid.Empty);
                new SoundPlayer(@"C:\Windows\Media\Speech Off.wav").Play();
            }
            else if (action == "MUTE") {
                bool isMuted; 
                epv.GetMute(out isMuted);
                epv.SetMute(!isMuted, Guid.Empty);
                new SoundPlayer(@"C:\Windows\Media\Speech Sleep.wav").Play();
            }
        } catch {}
    }

    // --- ФУНКЦИЯ 4: АВТОБЭКАП БАЗЫ ДАННЫХ PLAYNITE (С ПРОВЕРКОЙ ПОДПАПКИ LIBRARY) ---
    static void BackupPlayniteDB() {
        try {
            string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            // Проверяем современный путь Playnite 9/10/11
            string dbFile = Path.Combine(appData, @"Playnite\library\games.db");
            // Если нет, проверяем старый/портативный путь
            if (!File.Exists(dbFile)) {
                dbFile = Path.Combine(appData, @"Playnite\games.db");
            }

            if (File.Exists(dbFile)) {
                string bakFile = dbFile + ".bak";
                if (!File.Exists(bakFile) || (DateTime.Now - File.GetLastWriteTime(bakFile)).TotalHours > 24) {
                    File.Copy(dbFile, bakFile, true);
                }
            }
        } catch {}
    }

    static void StartSteamSilently() {
        try {
            string registryKey = @"SOFTWARE\WOW6432Node\Valve\Steam";
            RegistryKey key = Registry.LocalMachine.OpenSubKey(registryKey) ?? Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Valve\Steam");
            if (key != null) {
                string steamPath = key.GetValue("InstallPath") as string;
                if (!string.IsNullOrEmpty(steamPath)) {
                    string exePath = Path.Combine(steamPath, "Steam.exe");
                    if (File.Exists(exePath)) {
                        Process.Start(exePath, "-silent -minimized");
                    }
                }
            }
        } catch {}
    }

    [STAThread]
    public static void Main() {
        try { timeBeginPeriod(1); } catch {}
        try { Process.GetCurrentProcess().PriorityClass = ProcessPriorityClass.High; } catch {}
        GCSettings.LatencyMode = GCLatencyMode.LowLatency;

        InitResolution(); // Запоминаем родное разрешение при старте ПК

        StartSteamSilently();
        BackupPlayniteDB(); // Запуск автобэкапа базы данных раз в сутки

        int CrashCount = 0;
        
        while (true) {
            Thread.Sleep(500); // Снижаем агрессивность цикла

            bool ctrl = (GetAsyncKeyState(0x11) & 0x8000) != 0; 
            bool alt = (GetAsyncKeyState(0x12) & 0x8000) != 0;  

            if (ctrl && alt) {
                if ((GetAsyncKeyState(0x53) & 0x8000) != 0) { Process.Start("shutdown", "/s /t 0"); return; } // S
                if ((GetAsyncKeyState(0x52) & 0x8000) != 0) { Process.Start("shutdown", "/r /t 0"); return; } // R
                if ((GetAsyncKeyState(0x51) & 0x8000) != 0) { Process.Start("explorer.exe"); return; }        // Q
                
                // --- ФУНКЦИЯ 2: [CTRL+ALT+L] ВХОД ДЛЯ РОДИТЕЛЯ ---
                if ((GetAsyncKeyState(0x4C) & 0x8000) != 0) { 
                    try {
                        // Запускаем системную задачу на снятие автовхода
                        Process.Start("schtasks", "/run /tn \"Kiosk_DisableAutoLogon\"");
                    } catch {}
                    Thread.Sleep(300);
                    Process.Start("shutdown", "/l"); 
                    return; 
                }

                // K - УБИТЬ ЗАВИСШУЮ ИГРУ (На переднем плане)
                if ((GetAsyncKeyState(0x4B) & 0x8000) != 0) { 
                    try {
                        IntPtr fgWnd = GetForegroundWindow();
                        uint fgPid;
                        GetWindowThreadProcessId(fgWnd, out fgPid);
                        Process fgProc = Process.GetProcessById((int)fgPid);
                        
                        // Защита от убийства самого Playnite
                        if (!fgProc.ProcessName.ToLower().Contains("playnite") && 
                            !fgProc.ProcessName.ToLower().Contains("explorer")) {
                            fgProc.Kill();
                            new SoundPlayer(@"C:\Windows\Media\Windows Critical Stop.wav").Play();
                        }
                    } catch {}
                    Thread.Sleep(1000); 
                }

                // P - Принудительный сброс Playnite
                if ((GetAsyncKeyState(0x50) & 0x8000) != 0) {
                    try { 
                        foreach (var p in Process.GetProcessesByName("Playnite.DesktopApp")) { p.Kill(); }
                        foreach (var p in Process.GetProcessesByName("Playnite.FullscreenApp")) { p.Kill(); }
                    } catch {}
                    SystemSounds.Hand.Play(); 
                    Thread.Sleep(1000); 
                }
                
                if ((GetAsyncKeyState(0x26) & 0x8000) != 0) { ControlVolume("UP"); Thread.Sleep(200); }
                if ((GetAsyncKeyState(0x28) & 0x8000) != 0) { ControlVolume("DOWN"); Thread.Sleep(200); }
                if ((GetAsyncKeyState(0x4D) & 0x8000) != 0) { ControlVolume("MUTE"); Thread.Sleep(300); }
            }

            // Ищем любой запущенный Playnite (Обычный или Fullscreen)
            Process[] pDesktop = Process.GetProcessesByName("Playnite.DesktopApp");
            Process[] pFullscreen = Process.GetProcessesByName("Playnite.FullscreenApp");
            
            // --- ПРОВЕРКА И ВОССТАНОВЛЕНИЕ РАЗРЕШЕНИЯ ---
            try {
                IntPtr foregroundWnd = GetForegroundWindow();
                uint foregroundPid;
                GetWindowThreadProcessId(foregroundWnd, out foregroundPid);

                bool isLauncherActive = false;
                foreach (var p in pDesktop) { if (p.Id == foregroundPid) isLauncherActive = true; }
                foreach (var p in pFullscreen) { if (p.Id == foregroundPid) isLauncherActive = true; }

                // Если Playnite закрыт (краш/перезагрузка), тоже восстанавливаем разрешение
                if (pDesktop.Length == 0 && pFullscreen.Length == 0) {
                    isLauncherActive = true; 
                }

                // Восстанавливаем только если игра не активна, а мы смотрим на лаунчер
                if (isLauncherActive) {
                    RestoreResolution();
                    
                    // --- ФУНКЦИЯ 3: АВТОВОЗВРАТ ФОКУСА PLAYNITE (АНТИ-ЧЕРНЫЙ ЭКРАН) ---
                    IntPtr pWnd = pFullscreen.Length > 0 ? pFullscreen[0].MainWindowHandle : (pDesktop.Length > 0 ? pDesktop[0].MainWindowHandle : IntPtr.Zero);
                    if (pWnd != IntPtr.Zero) {
                        if (!IsZoomed(pWnd)) { ShowWindow(pWnd, SW_MAXIMIZE); }
                        SetForegroundWindow(pWnd);
                    }
                }
            } catch {}
            // ----------------------------------------------

            if (pDesktop.Length == 0 && pFullscreen.Length == 0) {
                if (CrashCount < 15) { 
                    RestoreConfigs(); 
                    if (File.Exists(AppPath)) {
                        try {
                            ProcessStartInfo psi = new ProcessStartInfo(AppPath, AppArgs);
                            Process.Start(psi);
                            CrashCount++;
                        } catch {}
                        // Ждем 5 секунд, чтобы Playnite успел полностью запуститься
                        Thread.Sleep(5000); 
                    }
                } else {
                    Process.Start("shutdown", "/r /t 0");
                    CrashCount = 0;
                    return;
                }
            } else {
                CrashCount = 0;
                
                // Проверяем и разворачиваем окно лаунчера (Fullscreen или Desktop)
                try {
                    IntPtr playniteWnd = pFullscreen.Length > 0 ? pFullscreen[0].MainWindowHandle : (pDesktop.Length > 0 ? pDesktop[0].MainWindowHandle : IntPtr.Zero);
                    if (playniteWnd != IntPtr.Zero) {
                        IntPtr foregroundWnd = GetForegroundWindow();
                        uint foregroundPid;
                        GetWindowThreadProcessId(foregroundWnd, out foregroundPid);
                        
                        bool isPlayniteActive = (pFullscreen.Length > 0 && foregroundPid == pFullscreen[0].Id) ||
                                                (pDesktop.Length > 0 && foregroundPid == pDesktop[0].Id);

                        if (isPlayniteActive) {
                            if (!IsZoomed(playniteWnd)) { ShowWindow(playniteWnd, SW_MAXIMIZE); }
                            SetForegroundWindow(playniteWnd);
                        }
                    }
                } catch {}
            }
        }
    }

    static void RestoreConfigs() {
        foreach(var item in Restores) {
            try {
                if (File.Exists(item.Key)) {
                    string dir = Path.GetDirectoryName(item.Value);
                    if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                    File.Copy(item.Key, item.Value, true);
                }
            } catch {}
        }
    }
}
"@

# Компилируем EXE файл
$ExeOutput = "$env:PUBLIC\Watchdog.exe"
# Удаляем старую версию
if (Test-Path $ExeOutput) { Remove-Item $ExeOutput -Force }
if (Test-Path "$env:PUBLIC\Watchdog.ps1") { Remove-Item "$env:PUBLIC\Watchdog.ps1" -Force }

try {
    # ВАЖНО: OutputType WindowsApplication делает программу без консольного окна
    Add-Type -TypeDefinition $WatchdogSrc -OutputAssembly $ExeOutput -OutputType WindowsApplication -ReferencedAssemblies "System.Windows.Forms" -ErrorAction Stop
    Write-Host "Watchdog.exe успешно скомпилирован (Невидимый режим)." -ForegroundColor Green
    # Скрываем файл
    (Get-Item $ExeOutput).Attributes = "Hidden, System"
} catch {
    Write-Error "Ошибка компиляции Watchdog! $_"
    Pause
    Exit
}

# ==============================================================================
# ЧАСТЬ 1: ПОДКЛЮЧЕНИЕ РЕЕСТРА ПОЛЬЗОВАТЕЛЯ
# ==============================================================================
Write-Host "Подключение реестра пользователя..." -ForegroundColor Cyan

$HiveDrive = "HKU_Kiosk"
$ManualLoad = $false

# Проверка: Залогинен ли пользователь?
$IsLoggedOn = $false
try {
    $LoggedUsers = Get-CimInstance Win32_LogonSession | Get-CimAssociatedInstance -Association Win32_LoggedOnUser | Select-Object -ExpandProperty Name
    if ($LoggedUsers -contains $TargetUser) { $IsLoggedOn = $true }
} catch {}

if ($IsLoggedOn) {
    if ($TargetUser -ne $CurrentUserName) {
        Write-Warning "ОШИБКА: Пользователь $TargetUser сейчас залогинен в системе!"
        Write-Warning "Сначала выйдите из учетной записи ребенка (Sign out), затем запустите скрипт."
        Pause
        Exit
    } else {
         # Настраиваем себя же
         New-PSDrive -Name $HiveDrive -PSProvider Registry -Root "HKEY_USERS\$SID" -ErrorAction SilentlyContinue | Out-Null
         Write-Host "Используется активный реестр текущего пользователя." -ForegroundColor Gray
    }
} else {
    # Пользователь оффлайн - загружаем файл
    $Prof = "$env:SystemDrive\Users\$TargetUser\NTUSER.DAT"
    if (Test-Path $Prof) {
        Write-Host "Загрузка куста реестра из файла..." -ForegroundColor Gray
        reg load "HKU\TempKiosk" "$Prof"
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Не удалось загрузить реестр. Возможно, файл занят."
            Exit
        }
        New-PSDrive -Name $HiveDrive -PSProvider Registry -Root "HKEY_USERS\TempKiosk" | Out-Null
        $ManualLoad = $true
    } else {
        Write-Warning "Файл профиля NTUSER.DAT не найден по пути $Prof"
        Exit
    }
}
$HivePath = "$($HiveDrive):"

try {

# ==============================================================================
# ЧАСТЬ 2: ОБЪЯВЛЕНИЕ ПЕРЕМЕННЫХ ПУТЕЙ (ВАЖНО ДЛЯ ИЗБЕЖАНИЯ ОШИБОК)
# ==============================================================================
$PolEx = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
$PolSys = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Policies\System"
$PolAD = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop"
$PolDlg = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Policies\Comdlg32"
$WinLogon = "$HivePath\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"

# Создаем пути, если их нет
foreach ($path in @($PolEx, $PolSys, $PolAD, $PolDlg, $WinLogon)) {
    if(!(Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
}

# ==============================================================================
# ЧАСТЬ 3: БЛОКИРОВКИ ЗАПУСКА (HKCU - ПРОФИЛЬ РЕБЕНКА)
# ==============================================================================
Write-Host "Настройка блокировок приложений..." -ForegroundColor Cyan
$UserLayers = "$HivePath\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
if (!(Test-Path $UserLayers)) { New-Item -Path $UserLayers -Force | Out-Null }

$BlockedApps = @(
    "$env:SystemRoot\System32\cmd.exe", 
    "$env:SystemRoot\System32\taskmgr.exe", 
    "$env:SystemRoot\regedit.exe",
    "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe", 
    "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell_ise.exe",
    "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
)

foreach ($App in $BlockedApps) {
    # Ставим флаг RUNASADMIN - это блокирует запуск без прав админа
    New-ItemProperty -Path $UserLayers -Name $App -Value "~ RUNASADMIN" -PropertyType String -Force | Out-Null
}
# Отключаем глобальные сообщения об ошибках
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Windows" -Name "ErrorMode" -Value 2 -Force

# --- ЧЕРНЫЙ СПИСОК ЗАПУСКА (DisallowRun) ---
# Включаем политику ограничивания запуска
New-ItemProperty -Path $PolEx -Name "DisallowRun" -Value 1 -PropertyType DWord -Force | Out-Null

# Создаем список запрещенных программ
$DisallowKey = "$PolEx\DisallowRun"
if (!(Test-Path $DisallowKey)) { New-Item -Path $DisallowKey -Force | Out-Null }

# Полный список EXE, которые запрещено запускать (даже если найти файл)
$BannedExes = @(
    "cmd.exe", 
    "powershell.exe", 
    "regedit.exe", 
    "taskmgr.exe", 
    "mmc.exe", 
    "Control.exe",          # Панель управления
    "SystemSettings.exe",   # Современные "Параметры" (Шестеренка)
    "msconfig.exe",         # Конфигурация системы
    "wscript.exe",          # VBS скрипты
    "cscript.exe",          # VBS скрипты (консоль)
    "mshta.exe",            # HTML приложения
    "hh.exe",               # Справка Windows
    "HelpPane.exe",         # Еще одна справка
    "ftp.exe",              # FTP клиент
    "bash.exe"             # Linux подсистема (если включена)
)

$counter = 1
foreach ($exe in $BannedExes) {
    New-ItemProperty -Path $DisallowKey -Name "$counter" -Value $exe -PropertyType String -Force | Out-Null
    $counter++
}

# --- ЖЕСТКАЯ БЛОКИРОВКА CMD ---
# Значение 2 = Запретить запуск cmd.exe и выполнение bat-файлов (скриптов)
New-ItemProperty -Path $PolSys -Name "DisableCMD" -Value 2 -PropertyType DWord -Force | Out-Null
Write-Host "CMD и BAT-файлы заблокированы жесткой политикой." -ForegroundColor Yellow

# --- БЕЗОПАСНАЯ ПОДМЕНА АССОЦИАЦИЙ (HKCU) ---
# Мы говорим проводнику ребенка: "Считай .bat и .ps1 обычными текстовыми файлами".
# Это не затрагивает настройки Администратора.

$UserClasses = "$HivePath\Software\Classes"
if (!(Test-Path $UserClasses)) { New-Item -Path $UserClasses -Force | Out-Null }

# Список опасных расширений
$ExtsToKill = @(".bat", ".cmd", ".vbs", ".ps1", ".reg", ".msi")

foreach ($Ext in $ExtsToKill) {
    $Key = "$UserClasses\$Ext"
    if (!(Test-Path $Key)) { New-Item -Path $Key -Force | Out-Null }
    
    # Перенаправляем на txtfile (Блокнот)
    # (Default) = "txtfile"
    New-ItemProperty -Path $Key -Name "(default)" -Value "txtfile" -PropertyType String -Force | Out-Null
    
    # Для надежности ломаем UserChoice (чтобы Windows 10/11 не пыталась исправить)
    # Удаляем UserChoice, если он был, чтобы система взяла наши настройки
    $UserChoice = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Ext\UserChoice"
    if (Test-Path $UserChoice) { Remove-Item -Path $UserChoice -Force -ErrorAction SilentlyContinue }
}

# ==============================================================================
# ЧАСТЬ 4: ПОЛИТИКИ ИНТЕРФЕЙСА (ПУСК, ПАНЕЛЬ ЗАДАЧ, ТРЕЙ)
# ==============================================================================
Write-Host "Блокировка Меню Пуск и Панели задач..." -ForegroundColor Cyan

# Убеждаемся, что пути существуют
$PolEx = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
$TaskbarMod = "$HivePath\Software\Policies\Microsoft\Windows\TaskbarModifications"

if (!(Test-Path $PolEx)) { New-Item -Path $PolEx -Force | Out-Null }
if (!(Test-Path $TaskbarMod)) { New-Item -Path $TaskbarMod -Force | Out-Null }

# --- ОЧИСТКА МЕНЮ ПУСК ---

# Скрывает список "Все программы" (Оставляет меню Пуск пустым/чистым)
New-ItemProperty -Path $PolEx -Name "NoStartMenuMorePrograms" -Value 1 -PropertyType DWord -Force | Out-Null

# Скрывает папки пользователя из меню Пуск (Документы, Музыка и т.д.)
New-ItemProperty -Path $PolEx -Name "NoStartMenuMyMusic" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $PolEx -Name "NoStartMenuMyPictures" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $PolEx -Name "NoStartMenuMyGames" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $PolEx -Name "NoSMHelp" -Value 1 -PropertyType DWord -Force | Out-Null

# Скрывает "Недавно добавленные" и "Часто используемые"
$Adv = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
if (!(Test-Path $Adv)) { New-Item -Path $Adv -Force | Out-Null }
New-ItemProperty -Path $Adv -Name "Start_TrackProgs" -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $Adv -Name "Start_TrackDocs" -Value 0 -PropertyType DWord -Force | Out-Null

# --- БЛОКИРОВКА ПАНЕЛИ ЗАДАЧ (ЗАКРЕПЛЕНИЕ) ---

# Запрет закрепления программ в панели задач (Pin to Taskbar)
New-ItemProperty -Path $TaskbarMod -Name "NoPinningToTaskbar" -Value 1 -PropertyType DWord -Force | Out-Null

# Запрет закрепления Магазина
New-ItemProperty -Path $TaskbarMod -Name "NoPinningStoreToTaskbar" -Value 1 -PropertyType DWord -Force | Out-Null

# Блокировка настроек Панели задач (ПКМ по панели не сработает или не даст настроить)
New-ItemProperty -Path $PolEx -Name "LockTaskbar" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $PolEx -Name "NoSetTaskbar" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $PolEx -Name "NoToolbarsOnTaskbar" -Value 1 -PropertyType DWord -Force | Out-Null

# --- БЛОКИРОВКА ТРЕЯ (ОБЛАСТЬ УВЕДОМЛЕНИЙ) ---

# Запрет настройки иконок в трее (Balloon Tips и уведомления тоже отключаем)
New-ItemProperty -Path $PolEx -Name "NoTrayItemsDisplay" -Value 0 -PropertyType DWord -Force | Out-Null # 0 = Показывать трей (нужно для часов), 1 = Скрыть совсем
New-ItemProperty -Path $PolEx -Name "NoAutoTrayNotify" -Value 1 -PropertyType DWord -Force | Out-Null # Запрет всплывающих уведомлений
New-ItemProperty -Path $PolEx -Name "TaskbarNoNotification" -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $PolEx -Name "NoBalloonToasts" -Value 1 -PropertyType DWord -Force | Out-Null

# --- ФИЗИЧЕСКОЕ УДАЛЕНИЕ УЖЕ ЗАКРЕПЛЕННЫХ ИКОНОК ---
# Политики запрещают НОВЫЕ закрепления, но старые (Edge, Store, Explorer) могут остаться.
# Мы удаляем их файлы ярлыков из профиля ребенка.

Write-Host "Очистка ярлыков панели задач..." -ForegroundColor Gray
$UserPinnedPath = "$env:SystemDrive\Users\$TargetUser\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"

if (Test-Path $UserPinnedPath) {
    # Удаляем все ярлыки внутри
    Remove-Item -Path "$UserPinnedPath\*" -Force -ErrorAction SilentlyContinue
    
    # Сбрасываем кэш панели задач в реестре (чтобы иконки исчезли визуально)
    $Taskband = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
    if (Test-Path $Taskband) {
        Remove-Item -Path $Taskband -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- ОБЩИЕ ЗАПРЕТЫ EXPLORER (КОНТЕКСТНОЕ МЕНЮ И Т.Д.) ---
# NoViewContextMenu = 1 (Запрещает ПКМ на рабочем столе и в проводнике)
New-ItemProperty -Path $PolEx -Name "NoViewContextMenu" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $PolEx -Name "NoFileMenu" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $PolEx -Name "NoPropertiesMyComputer" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $PolEx -Name "NoControlPanel" -Value 1 -PropertyType DWord -Force | Out-Null

Write-Host "Интерфейс заблокирован: Пуск пустой, закрепление запрещено." -ForegroundColor Green

# --- ЧЕРНЫЙ ФОН РАБОЧЕГО СТОЛА ---
$DesktopColors = "$HivePath\Control Panel\Colors"
if (!(Test-Path $DesktopColors)) { New-Item -Path $DesktopColors -Force | Out-Null }
# RGB 0 0 0 = Черный
Set-ItemProperty -Path $DesktopColors -Name "Background" -Value "0 0 0" -Force

$DesktopBG = "$HivePath\Control Panel\Desktop"
Set-ItemProperty -Path $DesktopBG -Name "Wallpaper" -Value "" -Force

# ==============================================================================
# ЧАСТЬ 5: ПОЛИТИКИ (БЕЗОПАСНЫЙ СИНТАКСИС)
# ==============================================================================
Write-Host "Применение ограничений..." -ForegroundColor Cyan

foreach ($path in @($PolEx, $PolSys, $PolAD, $PolDlg, $WinLogon)) {
    if(!(Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
}

# --- ОТКЛЮЧЕНИЕ XBOX GAME BAR ---
# Путь к политике GameDVR
$PolGame = "$HivePath\Software\Policies\Microsoft\Windows\GameDVR"

if (!(Test-Path $PolGame)) { New-Item -Path $PolGame -Force | Out-Null }

# AllowGameDVR = 0 (Запрещает запись игр и вызов панели)
New-ItemProperty -Path $PolGame -Name "AllowGameDVR" -Value 0 -PropertyType DWord -Force | Out-Null

# --- ОГРАНИЧЕНИЕ USB УСТРОЙСТВ (БЕЗОПАСНЫЙ МЕТОД HKCU) ---
# Это отключает флешки только для целевого пользователя. Клавиатура/Мышь продолжат работать.

# Путь в реестре ПОЛЬЗОВАТЕЛЯ (а не системы)
$PolUSB = "$HivePath\Software\Policies\Microsoft\Windows\RemovableStorageDevices"
# GUID класса Storage (Флешки, внешние диски)
$USBClass = "$PolUSB\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}"

if (!(Test-Path $PolUSB)) { New-Item -Path $PolUSB -Force | Out-Null }
if (!(Test-Path $USBClass)) { New-Item -Path $USBClass -Force | Out-Null }

# Deny_Read = 1 (Запрет чтения)
New-ItemProperty -Path $USBClass -Name "Deny_Read" -Value 1 -PropertyType DWord -Force | Out-Null
# Deny_Write = 1 (Запрет записи)
New-ItemProperty -Path $USBClass -Name "Deny_Write" -Value 1 -PropertyType DWord -Force | Out-Null

# --- ОТКЛЮЧЕНИЕ УВЕДОМЛЕНИЙ ---
$PolPush = "$HivePath\Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications"

if (!(Test-Path $PolPush)) { New-Item -Path $PolPush -Force | Out-Null }

# NoToastApplicationNotification = 1 (Отключает всплывающие баннеры приложений)
New-ItemProperty -Path $PolPush -Name "NoToastApplicationNotification" -Value 1 -PropertyType DWord -Force | Out-Null

# --- ОТКЛЮЧЕНИЕ ПОИСКА И КОРТАНЫ ---
$PolSearch = "$HivePath\Software\Policies\Microsoft\Windows\Windows Search"
if (!(Test-Path $PolSearch)) { New-Item -Path $PolSearch -Force | Out-Null }

# Отключаем Кортану
New-ItemProperty -Path $PolSearch -Name "AllowCortana" -Value 0 -PropertyType DWord -Force | Out-Null
# Отключаем поиск в интернете через меню Пуск
New-ItemProperty -Path $PolSearch -Name "DisableWebSearch" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $PolSearch -Name "ConnectedSearchUseWeb" -Value 0 -PropertyType DWord -Force | Out-Null

# --- ПОДАВЛЕНИЕ ДИАЛОГОВ ОБ ОШИБКАХ ---
$PolErr = "$HivePath\Software\Microsoft\Windows\Windows Error Reporting"
if (!(Test-Path $PolErr)) { New-Item -Path $PolErr -Force | Out-Null }

# DontShowUI = 1 (Не показывать окно "Программа не отвечает")
New-ItemProperty -Path $PolErr -Name "DontShowUI" -Value 1 -PropertyType DWord -Force | Out-Null
# Disabled = 1 (Полностью выключить отчеты)
New-ItemProperty -Path $PolErr -Name "Disabled" -Value 1 -PropertyType DWord -Force | Out-Null

# --- СКРЫТИЕ СЕТЕВОГО ОКРУЖЕНИЯ ---
# NoEntireNetwork = 1 (Убирает "Вся сеть" из сетевого окружения)
New-ItemProperty -Path $PolEx -Name "NoEntireNetwork" -Value 1 -PropertyType DWord -Force | Out-Null

# NoNetCrawling = 1 (Запрещает автоматический поиск сетевых папок и принтеров)
New-ItemProperty -Path $PolEx -Name "NoNetCrawling" -Value 1 -PropertyType DWord -Force | Out-Null

# --- ОТКЛЮЧЕНИЕ БУФЕРА ОБМЕНА И WIN+V ---
$PolSysConfig = "$HivePath\Software\Policies\Microsoft\Windows\System"
if (!(Test-Path $PolSysConfig)) { New-Item -Path $PolSysConfig -Force | Out-Null }

# Отключает историю буфера обмена (Win+V)
New-ItemProperty -Path $PolSysConfig -Name "AllowClipboardHistory" -Value 0 -PropertyType DWord -Force | Out-Null

# Скрывает вкладку "Безопасность" в свойствах файлов
New-ItemProperty -Path $PolEx -Name "NoSecurityTab" -Value 1 -PropertyType DWord -Force | Out-Null

# Скрывает вкладку "Оборудование" (чтобы не видели драйверы)
New-ItemProperty -Path $PolEx -Name "NoHardwareTab" -Value 1 -PropertyType DWord -Force | Out-Null

# Запрещает менять свойства папок (вид, скрытые файлы)
New-ItemProperty -Path $PolEx -Name "NoFolderOptions" -Value 1 -PropertyType DWord -Force | Out-Null

# Запрет кнопки "Завершение работы" в диалоге Ctrl+Alt+Del (оставляет только выход из системы)
New-ItemProperty -Path $PolEx -Name "NoClose" -Value 1 -PropertyType DWord -Force | Out-Null

# Explorer Policies
New-ItemProperty -Path $PolEx -Name "NoDrives" -Value 67108863 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $PolEx -Name "NoViewOnDrive" -Value 67108863 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $PolEx -Name "SettingsPageVisibility" -Value "hide:all" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $PolEx -Name "NoRun" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $PolEx -Name "NoWinKeys" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $PolEx -Name "NoDriveTypeAutoRun" -Value 255 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $PolEx -Name "DisableNotificationCenter" -Value 1 -PropertyType DWord -Force | Out-Null

# Обои
New-ItemProperty -Path $PolAD -Name "NoChangingWallPaper" -Value 1 -PropertyType DWord -Force | Out-Null

# Система
New-ItemProperty -Path $PolSys -Name "DisableChangePassword" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $PolSys -Name "DisableLockWorkstation" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $PolSys -Name "DisableTaskMgr" -Value 1 -PropertyType DWord -Force | Out-Null

# Диалоги
New-ItemProperty -Path $PolDlg -Name "NoPlacesBar" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $PolDlg -Name "NoBackButton" -Value 1 -PropertyType DWord -Force | Out-Null

# Залипание клавиш (Откл)
$Sticky = "$HivePath\Control Panel\Accessibility\StickyKeys"
if(!(Test-Path $Sticky)){New-Item $Sticky -Force | Out-Null}
Set-ItemProperty -Path $Sticky -Name "Flags" -Value "506" -Force

# --- ОТКЛЮЧЕНИЕ "СПЕЦИАЛЬНЫХ ВОЗМОЖНОСТЕЙ" НА ЭКРАНЕ ВХОДА ---
# Защищает от запуска экранной клавиатуры/лупы до входа в систему
$EaseOfAccess = "HKLM:\SOFTWARE\Microsoft\Windows Embedded\EmbeddedLogon"
if (!(Test-Path $EaseOfAccess)) { New-Item -Path $EaseOfAccess -Force | Out-Null }

# BrandingNeutral = 8 (Скрывает кнопку Ease of Access)
# Примечание: Это работает на Pro/Enterprise версиях и некоторых Home.
New-ItemProperty -Path $EaseOfAccess -Name "BrandingNeutral" -Value 8 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

Write-Host "Включение тихого режима (Без уведомлений)..." -ForegroundColor Cyan
$QuietHours = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings"
if (!(Test-Path $QuietHours)) { New-Item -Path $QuietHours -Force | Out-Null }
# NOC_GLOBAL_SETTING_TOASTS_LEVEL = 0 (Никаких всплывающих окон)
New-ItemProperty -Path $QuietHours -Name "NOC_GLOBAL_SETTING_TOASTS_LEVEL" -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $QuietHours -Name "NOC_GLOBAL_SETTING_ALLOW_CRITICAL_ALERTS" -Value 0 -PropertyType DWord -Force | Out-Null

# ==============================================================================
# ЧАСТЬ 6: НАСТРОЙКА EDGE И BRAVE: ОТКРЫТЫЙ ИНТЕРНЕТ + БЛОКИРОВКА НАСТРОЕК
# ==============================================================================
Write-Host "Настройка Edge: Блокировка настроек и F12..." -ForegroundColor Cyan

# ЗАВЕРШЕНИЕ ПРОЦЕССОВ EDGE
Stop-Process -Name "msedge" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "MicrosoftEdgeUpdate" -Force -ErrorAction SilentlyContinue

# ОЧИСТКА ВСЕХ СТАРЫХ ПОЛИТИК (HKLM и HKCU)
# Удаляем старые белые и черные списки, чтобы открыть интернет.
Remove-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "HKCU:\SOFTWARE\Policies\Microsoft\Edge" -Recurse -Force -ErrorAction SilentlyContinue

if ($HivePath) { 
    Remove-Item -Path "$HivePath\SOFTWARE\Policies\Microsoft\Edge" -Recurse -Force -ErrorAction SilentlyContinue 
}

# ПОДГОТОВКА РЕЕСТРА ПОЛЬЗОВАТЕЛЯ
$EdgePolicy = "$HivePath\SOFTWARE\Policies\Microsoft\Edge"
New-Item -Path $EdgePolicy -Force | Out-Null
New-Item -Path "$EdgePolicy\URLBlocklist" -Force | Out-Null

# ==============================================================================
# ИСПРАВЛЕНИЕ АВТОЗАГРУЗКИ STEAM (ТОЛЬКО СКРЫТЫЙ РЕЖИМ)
# ==============================================================================
Write-Host "Настройка скрытого запуска Steam в автозагрузке..." -ForegroundColor Cyan

$RunKey = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Run"
if (!(Test-Path $RunKey)) { New-Item -Path $RunKey -Force | Out-Null }

# Ищем, куда установлен Steam на этом компьютере
$SteamInstallPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
if (!$SteamInstallPath) {
    $SteamInstallPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
}

if ($SteamInstallPath -and (Test-Path "$SteamInstallPath\steam.exe")) {
    # Принудительно прописываем Steam с флагом -silent (без окон)
    Set-ItemProperty -Path $RunKey -Name "Steam" -Value "`"$SteamInstallPath\steam.exe`" -silent" -Force | Out-Null
    Write-Host "Steam принудительно переведен в скрытый режим (-silent)." -ForegroundColor Green
} else {
    # Если Steam почему-то не найден в системе, удаляем его из автозагрузки от греха подальше
    Remove-ItemProperty -Path $RunKey -Name "Steam" -Force -ErrorAction SilentlyContinue
    Write-Host "Steam убран из автозагрузки." -ForegroundColor Yellow
}

# Отключаем всплывающие окна Steam (Реклама при запуске) в реестре пользователя
$SteamUserReg = "$HivePath\Software\Valve\Steam"
if (!(Test-Path $SteamUserReg)) { New-Item -Path $SteamUserReg -Force | Out-Null }
New-ItemProperty -Path $SteamUserReg -Name "PenalizeBikers" -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null

# =========================================================
# БЛОКИРОВКА ФУНКЦИОНАЛА (КНОПКИ И МЕНЮ)
# =========================================================

# Запрет Инструментов Разработчика (F12, Ctrl+Shift+I)
# Ребенок не сможет открыть консоль и изменить код страницы.
New-ItemProperty -Path $EdgePolicy -Name "DeveloperToolsAvailability" -Value 2 -PropertyType DWord -Force | Out-Null

# Запрет доступа к расширениям (чтобы не ставил VPN и обходы)
New-ItemProperty -Path $EdgePolicy -Name "BrowserAddonsEnabled" -Value 0 -PropertyType DWord -Force | Out-Null

# Запрет режима Инкогнито (InPrivate) и Гостевого режима
# История браузера будет писаться всегда.
New-ItemProperty -Path $EdgePolicy -Name "InPrivateModeAvailability" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $EdgePolicy -Name "BrowserGuestModeEnabled" -Value 0 -PropertyType DWord -Force | Out-Null

# Запрет изменения и удаления Истории
New-ItemProperty -Path $EdgePolicy -Name "AllowDeletingBrowserHistory" -Value 0 -PropertyType DWord -Force | Out-Null

# Отключение "Первого запуска" (Приветственного экрана)
New-ItemProperty -Path $EdgePolicy -Name "HideFirstRunExperience" -Value 1 -PropertyType DWord -Force | Out-Null

# Очистка интерфейса (Убираем боковую панель и лишние кнопки)
New-ItemProperty -Path $EdgePolicy -Name "HubsSidebarEnabled" -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $EdgePolicy -Name "ShowCollectionsButton" -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $EdgePolicy -Name "ShowVerticalTabsButton" -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $EdgePolicy -Name "PersonalizationReportingEnabled" -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $EdgePolicy -Name "ShowHomeButton" -Value 1 -PropertyType DWord -Force | Out-Null

# Разрешить загрузку файлов (Нужно для обновления игр)
New-ItemProperty -Path $EdgePolicy -Name "DownloadRestrictions" -Value 0 -PropertyType DWord -Force | Out-Null

# Отключение игры "Динозаврик" (Surf) при отсутствии интернета
New-ItemProperty -Path $EdgePolicy -Name "AllowSurfGame" -Value 0 -PropertyType DWord -Force | Out-Null

# =========================================================
# БЛОКИРОВКА ВНУТРЕННИХ СТРАНИЦ (SETTINGS, FLAGS)
# =========================================================
# Мы не блокируем интернет (*), мы блокируем только служебные адреса настроек.
# Если ребенок нажмет "Настройки", браузер попытается перейти на edge://settings и выдаст ошибку.

$InternalBlockList = @(
    "edge://settings*",      # Главные настройки
    "edge://flags*",         # Экспериментальные функции
    "edge://extensions*",    # Расширения
    "edge://management*",    # Управление
    "edge://favorites*",     # Избранное
    "edge://history*",       # История (чтобы не удалил)
    "edge://downloads*",     # Загрузки (можно оставить, если нужно)
    "about:flags",
    "chrome://settings*",
    "chrome://extensions*"
)

$j = 1
foreach ($page in $InternalBlockList) {
    New-ItemProperty -Path "$EdgePolicy\URLBlocklist" -Name "$j" -Value $page -PropertyType String -Force | Out-Null
    $j++
}

# Отключаем SmartScreen (чтобы не мешал играм и разрешенным сайтам)
New-ItemProperty -Path $EdgePolicy -Name "SmartScreenEnabled" -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $EdgePolicy -Name "TyposquattingCheckerEnabled" -Value 0 -PropertyType DWord -Force | Out-Null

Write-Host "Edge настроен: Интернет открыт, Настройки и F12 заблокированы." -ForegroundColor Green

# ==============================================================================
# НАСТРОЙКА BRAVE BROWSER: ОТКРЫТЫЙ ИНТЕРНЕТ + БЛОКИРОВКА НАСТРОЕК
# ==============================================================================
Write-Host "Настройка Brave: Блокировка настроек, F12 и мусора..." -ForegroundColor Cyan

# ЗАВЕРШЕНИЕ ПРОЦЕССОВ BRAVE
Stop-Process -Name "brave" -Force -ErrorAction SilentlyContinue

# ОЧИСТКА ВСЕХ СТАРЫХ ПОЛИТИК
Remove-Item -Path "HKLM:\SOFTWARE\Policies\BraveSoftware" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "HKCU:\SOFTWARE\Policies\BraveSoftware" -Recurse -Force -ErrorAction SilentlyContinue
if ($HivePath) { 
    Remove-Item -Path "$HivePath\SOFTWARE\Policies\BraveSoftware" -Recurse -Force -ErrorAction SilentlyContinue 
}

# ПОДГОТОВКА РЕЕСТРА ПОЛЬЗОВАТЕЛЯ
$BravePolicy = "$HivePath\SOFTWARE\Policies\BraveSoftware\Brave"
New-Item -Path $BravePolicy -Force | Out-Null
New-Item -Path "$BravePolicy\URLBlocklist" -Force | Out-Null
New-Item -Path "$BravePolicy\ExtensionInstallBlocklist" -Force | Out-Null

# =========================================================
# БЛОКИРОВКА ФУНКЦИОНАЛА BRAVE
# =========================================================

# Запрет Инструментов Разработчика (F12, Ctrl+Shift+I)
New-ItemProperty -Path $BravePolicy -Name "DeveloperToolsAvailability" -Value 2 -PropertyType DWord -Force | Out-Null

# Запрет установки ВСЕХ расширений (VPN и прочее)
New-ItemProperty -Path "$BravePolicy\ExtensionInstallBlocklist" -Name "1" -Value "*" -PropertyType String -Force | Out-Null

# Запрет режима Инкогнито и Гостевого режима
New-ItemProperty -Path $BravePolicy -Name "IncognitoModeAvailability" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $BravePolicy -Name "BrowserGuestModeEnabled" -Value 0 -PropertyType DWord -Force | Out-Null

# Запрет изменения и удаления Истории
New-ItemProperty -Path $BravePolicy -Name "AllowDeletingBrowserHistory" -Value 0 -PropertyType DWord -Force | Out-Null

# Отключение "Первого запуска" и запросов по умолчанию
New-ItemProperty -Path $BravePolicy -Name "DefaultBrowserSettingEnabled" -Value 0 -PropertyType DWord -Force | Out-Null

# ЖЕСТКОЕ ОТКЛЮЧЕНИЕ "МУСОРА" BRAVE (Крипта, ВПН, ИИ)
New-ItemProperty -Path $BravePolicy -Name "BraveRewardsDisabled" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $BravePolicy -Name "BraveWalletDisabled" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $BravePolicy -Name "BraveVPNDisabled" -Value 1 -PropertyType DWord -Force | Out-Null

# Разрешить загрузку файлов
New-ItemProperty -Path $BravePolicy -Name "DownloadRestrictions" -Value 0 -PropertyType DWord -Force | Out-Null

# Отключение игры "Динозаврик" без интернета
New-ItemProperty -Path $BravePolicy -Name "AllowDinosaurEasterEgg" -Value 0 -PropertyType DWord -Force | Out-Null

# Отключение SafeBrowsing (чтобы не блокировал игровые файлы)
New-ItemProperty -Path $BravePolicy -Name "SafeBrowsingProtectionLevel" -Value 0 -PropertyType DWord -Force | Out-Null

# =========================================================
# БЛОКИРОВКА ВНУТРЕННИХ СТРАНИЦ BRAVE (SETTINGS, FLAGS)
# =========================================================

$BraveBlockList = @(
    "brave://settings*",      # Настройки Brave
    "brave://flags*",         # Эксперименты
    "brave://extensions*",    # Расширения
    "brave://wallet*",        # Кошелек
    "brave://rewards*",       # Награды
    "brave://history*",       # История
    "brave://downloads*",     # Загрузки (опционально)
    "chrome://settings*",     # Хромиум настройки
    "chrome://flags*",        # Хромиум флаги
    "chrome://extensions*",
    "about:flags"
)

$k = 1
foreach ($page in $BraveBlockList) {
    New-ItemProperty -Path "$BravePolicy\URLBlocklist" -Name "$k" -Value $page -PropertyType String -Force | Out-Null
    $k++
}

Write-Host "Brave настроен: Интернет открыт, настройки, расширения и крипта заблокированы." -ForegroundColor Green

# --- НАСТРОЙКА БЕЗОПАСНОГО DNS (ЧЕРЕЗ ПЛАНИРОВЩИК ЗАДАНИЙ) ---
Write-Host "Настройка задач смены DNS при входе пользователя..." -ForegroundColor Cyan

$TaskNameSet = "Kiosk_SetDNS_$TargetUser"
$TaskNameReset = "Kiosk_ResetDNS"
$DNS_Servers = "94.140.14.15,94.140.15.16" # AdGuard Family

# Задача: Включить фильтрацию при входе РЕБЕНКА
$ActionSet = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"(Get-NetAdapter | Where-Object Status -eq Up).InterfaceIndex | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex `$_ -ServerAddresses $DNS_Servers }`""
$TriggerSet = New-ScheduledTaskTrigger -AtLogOn -User $TargetUser
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $TaskNameSet -Action $ActionSet -Trigger $TriggerSet -Principal $Principal -Force | Out-Null

# Задача: Сбросить DNS при входе ЛЮБОГО ДРУГОГО пользователя (или Админа)
# (Для надежности ставим триггер на разблокировку рабочей станции любым пользователем)
$ActionReset = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command `"(Get-NetAdapter | Where-Object Status -eq Up).InterfaceIndex | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex `$_ -ResetServerAddresses }`""
$TriggerReset = New-ScheduledTaskTrigger -AtLogOn
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $TaskNameReset -Action $ActionReset -Trigger $TriggerReset -Principal $Principal -Force | Out-Null

Write-Host "Созданы задачи планировщика: $TaskNameSet и $TaskNameReset" -ForegroundColor Green
Write-Host "DNS будет меняться автоматически только для пользователя $TargetUser." -ForegroundColor Gray

# --- ОГРАНИЧЕНИЕ ВРЕМЕНИ РАБОТЫ (РОДИТЕЛЬСКИЙ КОНТРОЛЬ) ---
# Разрешено играть с 08:00 до 24:00 каждый день.

Write-Host "Установка разрешенных часов работы (08:00 - 24:00)..." -ForegroundColor Cyan
# Формат: День,Время-Время
net user $TargetUser /times:M-Su,08:00-24:00 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "Время работы ограничено: Пн-Вс, 08:00-24:00." -ForegroundColor Green
} else {
    Write-Warning "Не удалось установить время работы (возможно, имя пользователя содержит пробелы?)"
}

# --- ЗАЩИТА ЭКРАНА ВХОДА (LOGIN SCREEN) ---
Write-Host "Усиление защиты экрана входа..." -ForegroundColor Cyan

# Убираем кнопку выключения с экрана блокировки
# (Чтобы нельзя было сделать Shift+Перезагрузка для взлома)
$PolWin = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
if (!(Test-Path $PolWin)) { New-Item -Path $PolWin -Force | Out-Null }
New-ItemProperty -Path $PolWin -Name "shutdownwithoutlogon" -Value 0 -PropertyType DWord -Force | Out-Null

# Отключаем "Залипание клавиш" для СИСТЕМЫ (чтобы не работало Shift x5 на экране пароля)
# Это нужно делать в ветке .DEFAULT, так как пользователь еще не вошел
$StickySys = "Registry::HKEY_USERS\.DEFAULT\Control Panel\Accessibility\StickyKeys"
if (Test-Path $StickySys) {
    Set-ItemProperty -Path $StickySys -Name "Flags" -Value "506" -Force -ErrorAction SilentlyContinue
}

# ==============================================================================
# ЧАСТЬ 7: АБСОЛЮТНАЯ ЗАЩИТА ФАЙЛОВОЙ СИСТЕМЫ
# ==============================================================================
Write-Host "Установка защиты файловой системы (NTFS)..." -ForegroundColor Cyan

# ЗАПРЕТ ЗАПУСКА ПРОГРАММ ИЗ ЗАГРУЗОК И РАБОЧЕГО СТОЛА
# Это главная защита от вирусов. Ребенок может скачать файл, но не сможет нажать на него дважды.
$ChildFolders = @(
    "$env:SystemDrive\Users\$TargetUser\Downloads",
    "$env:SystemDrive\Users\$TargetUser\Desktop",
    "$env:SystemDrive\Users\$TargetUser\Documents"
)

foreach ($Folder in $ChildFolders) {
    if (Test-Path $Folder) {
        # ICACLS: (OI)(CI) = Наследовать объектами и контейнерами
        # /deny ...:X = ЗАПРЕТИТЬ Выполнение (Execute)
        Start-Process "icacls" -ArgumentList "`"$Folder`" /deny `"$TargetUser`":(OI)(CI)(X)" -NoNewWindow -Wait
        Write-Host "Блокировка запуска (EXE) установлена для: $Folder" -ForegroundColor Green
    }
}

# АВТООЧИСТКА МУСОРА ПРИ ВХОДЕ (DEEP FREEZE LITE)
# Создаем задачу, которая молча удаляет мусор при входе ребенка
$UserDL = "$env:SystemDrive\Users\$TargetUser\Downloads"
$UserTemp = "$env:SystemDrive\Users\$TargetUser\AppData\Local\Temp"
$UserCrash = "$env:SystemDrive\Users\$TargetUser\AppData\Local\CrashDumps"

$CleanupScript = @"
Get-ChildItem -Path '$UserDL\*' -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue;
Get-ChildItem -Path '$UserTemp\*' -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue;
if (Test-Path '$UserCrash') { Get-ChildItem -Path '$UserCrash\*' -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
"@
# Кодируем команду в Base64, чтобы планировщик не подавился спецсимволами
$Bytes = [System.Text.Encoding]::Unicode.GetBytes($CleanupScript)
$Encoded = [Convert]::ToBase64String($Bytes)
$CleanCmd = "-EncodedCommand $Encoded"

$TaskNameClean = "Kiosk_AutoCleanup_$TargetUser"
$ActionClean = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -NonInteractive $CleanCmd"
$TriggerClean = New-ScheduledTaskTrigger -AtLogOn -User $TargetUser
# Используем Principal (SYSTEM)
Register-ScheduledTask -TaskName $TaskNameClean -Action $ActionClean -Trigger $TriggerClean -Principal $Principal -Force | Out-Null
Write-Host "Автоочистка папки 'Загрузки' включена." -ForegroundColor Green

# ==============================================================================
# ЧАСТЬ 8: "ЯДЕРНАЯ" БЛОКИРОВКА (LOGIN)
# ==============================================================================
Write-Host "Установка блокировок системных вызовов..." -ForegroundColor Cyan

# СКРЫТИЕ СМЕНЫ ПОЛЬЗОВАТЕЛЯ (Fast User Switching)
# Убирает кнопку "Сменить пользователя" из меню Пуск и Ctrl+Alt+Del.
# На экране входа останется только последняя учетка (ребенка).
$PolSysLocal = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
if (!(Test-Path $PolSysLocal)) { New-Item -Path $PolSysLocal -Force | Out-Null }
New-ItemProperty -Path $PolSysLocal -Name "HideFastUserSwitching" -Value 1 -PropertyType DWord -Force | Out-Null
Write-Host "Смена пользователя заблокирована." -ForegroundColor Green

# --- БЛОКИРОВКА SAFE MODE ---
Write-Host "Отключение автоматического восстановления при сбоях..." -ForegroundColor Cyan
bcdedit /set "{default}" bootstatuspolicy ignoreallfailures | Out-Null

# --- СКРЫТИЕ СЕТИ НА ЭКРАНЕ БЛОКИРОВКИ ---
Write-Host "Скрытие сетевых настроек до входа в систему..." -ForegroundColor Cyan
$PolSysLocal = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
if (!(Test-Path $PolSysLocal)) { New-Item -Path $PolSysLocal -Force | Out-Null }
New-ItemProperty -Path $PolSysLocal -Name "DontDisplayNetworkSelectionUI" -Value 1 -PropertyType DWord -Force | Out-Null

# ==============================================================================
# ЧАСТЬ 9: ТОТАЛЬНАЯ ЗАЧИСТКА
# ==============================================================================
Write-Host "Применение максимальных мер защиты..." -ForegroundColor Red

# БЛОКИРОВКА УСТАНОВЩИКА MSI
# Полный запрет на установку программ (кроме обновлений Windows)
$Installer = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer"
if (!(Test-Path $Installer)) { New-Item -Path $Installer -Force | Out-Null }
# DisableMSI = 2 (Всегда запрещено)
New-ItemProperty -Path $Installer -Name "DisableMSI" -Value 2 -PropertyType DWord -Force | Out-Null

# Автоматически отклонять запросы UAC для обычных пользователей (без показа окна ввода пароля)
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorUser" -Value 0 -PropertyType DWord -Force | Out-Null

# УДАЛЕНИЕ КНОПКИ "СМЕНИТЬ ПАРОЛЬ" из CTRL+ALT+DEL
$PolSys = "$HivePath\Software\Microsoft\Windows\CurrentVersion\Policies\System"
New-ItemProperty -Path $PolSys -Name "DisableChangePassword" -Value 1 -PropertyType DWord -Force | Out-Null

# --- АВТОМАТИЧЕСКИЙ ВХОД (AUTO-LOGON) ---
Write-Host "Настройка автоматического входа для $TargetUser без пароля..." -ForegroundColor Cyan
$WinLogonLocal = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
New-ItemProperty -Path $WinLogonLocal -Name "AutoAdminLogon" -Value "1" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $WinLogonLocal -Name "DefaultUserName" -Value $TargetUser -PropertyType String -Force | Out-Null

# Задача 1: для безопасного выхода Родителя (снимает автовход по Ctrl+Alt+L)
$ActionDisableAuto = New-ScheduledTaskAction -Execute "reg.exe" -Argument "add `"HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon`" /v AutoAdminLogon /t REG_SZ /d 0 /f"
Register-ScheduledTask -TaskName "Kiosk_DisableAutoLogon" -Action $ActionDisableAuto -Principal $Principal -Force | Out-Null

# Задача 2: для возврата автовхода (вызывается из контекстного меню)
$ActionEnableAuto = New-ScheduledTaskAction -Execute "reg.exe" -Argument "add `"HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon`" /v AutoAdminLogon /t REG_SZ /d 1 /f"
Register-ScheduledTask -TaskName "Kiosk_EnableAutoLogon" -Action $ActionEnableAuto -Principal $Principal -Force | Out-Null

# --- ДОБАВЛЕНИЕ ПУНКТА В КОНТЕКСТНОЕ МЕНЮ EASTRICA TOOLS (ПКМ) ---
if (!(Get-PSDrive -Name HKCR -ErrorAction SilentlyContinue)) { 
    New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -ErrorAction SilentlyContinue | Out-Null 
}

$EastricaShell = "HKCR:\Directory\Background\shell\EastricaTools\shell"
$MenuKey_Kiosk = "$EastricaShell\09_EnableKiosk"

if (!(Test-Path "$MenuKey_Kiosk\command")) { 
    New-Item -Path "$MenuKey_Kiosk\command" -Force | Out-Null 
}

Set-ItemProperty -Path $MenuKey_Kiosk -Name "MUIVerb" -Value "Вернуть игровой Киоск" -Force
Set-ItemProperty -Path $MenuKey_Kiosk -Name "Icon" -Value "joy.cpl,0" -Force # Иконка геймпада

$KioskCmd = 'cmd.exe /q /c "schtasks /run /tn \"Kiosk_EnableAutoLogon\" >nul 2>&1 & timeout /t 1 >nul & shutdown /l"'
Set-Item -Path "$MenuKey_Kiosk\command" -Value $KioskCmd -Force

Write-Host "Пункт 'Вернуть игровой Киоск' добавлен в меню Eastrica Tools (ПКМ)." -ForegroundColor Green

# ==============================================================================
# ЧАСТЬ 10: ПОДМЕНА ОБОЛОЧКИ (ЗАМЕНА SHELL)
# ==============================================================================
Write-Host "Настройка оболочки..." -ForegroundColor Cyan

# ТЕПЕРЬ МЫ УКАЗЫВАЕМ ПУТЬ ПРЯМО К EXE (БЕЗ POWERSHELL)
$ShellCmd = "$env:PUBLIC\Watchdog.exe"

New-ItemProperty -Path $WinLogon -Name "Shell" -Value $ShellCmd -PropertyType String -Force | Out-Null
Write-Host "Shell заменен на Watchdog.exe." -ForegroundColor Green

# ==============================================================================
# ЧАСТЬ 11: ДОПОЛНИТЕЛЬНЫЕ УЛУЧШЕНИЯ ДЛЯ КИОСКА
# ==============================================================================

# --- АВТОВЫКЛЮЧЕНИЕ ПК (КОМЕНДАНТСКИЙ ЧАС В 23:55) ---
Write-Host "Настройка автовыключения в 23:55..." -ForegroundColor Cyan
$ShutdownCmd = "shutdown.exe"
# /s - выключение, /t 300 - таймер 5 минут, /c - сообщение поверх всех окон (включая игры)
$ShutdownArgs = "/s /t 300 /c `"Время вышло! Сохраните игру, компьютер выключится через 5 минут.`""
$TaskNameShutdown = "Kiosk_Curfew_$TargetUser"

$ActionSD = New-ScheduledTaskAction -Execute $ShutdownCmd -Argument $ShutdownArgs
$TriggerSD = New-ScheduledTaskTrigger -Daily -At "23:55"
# Запускаем от СИСТЕМЫ, чтобы ребенок не мог отменить процесс через консоль
Register-ScheduledTask -TaskName $TaskNameShutdown -Action $ActionSD -Trigger $TriggerSD -User "SYSTEM" -Force | Out-Null

# --- БЛОКИРОВКА СЕТЕВЫХ НАСТРОЕК (ЗАЩИТА DNS) ---
Write-Host "Блокировка доступа к настройкам сети..." -ForegroundColor Cyan
$PolNet = "$HivePath\Software\Policies\Microsoft\Windows\Network Connections"
if (!(Test-Path $PolNet)) { New-Item -Path $PolNet -Force | Out-Null }
# Запрет открытия свойств адаптера (IPv4/DNS)
New-ItemProperty -Path $PolNet -Name "NC_LanProperties" -Value 0 -PropertyType DWord -Force | Out-Null
# Запрет включения/выключения адаптеров (нельзя "передернуть" сеть)
New-ItemProperty -Path $PolNet -Name "NC_LanConnect" -Value 0 -PropertyType DWord -Force | Out-Null

# --- ОТКЛЮЧЕНИЕ ЭКРАНА БЛОКИРОВКИ (NoLockScreen) ---
Write-Host "Отключение экрана блокировки (сразу вход в систему)..." -ForegroundColor Cyan
$PolPers = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
if (!(Test-Path $PolPers)) { New-Item -Path $PolPers -Force | Out-Null }
New-ItemProperty -Path $PolPers -Name "NoLockScreen" -Value 1 -PropertyType DWord -Force | Out-Null

Write-Host "Отключение спящего режима..." -ForegroundColor Gray
powercfg /x -standby-timeout-ac 0
powercfg /x -hibernate-timeout-ac 0

} finally {

# ==============================================================================
# ЧАСТЬ 12: ФИНАЛ: ВЫГРУЗКА
# ==============================================================================
# Сначала удаляем диск PowerShell, чтобы отпустить хендлы
if (Get-PSDrive -Name $HiveDrive -ErrorAction SilentlyContinue) {
    Set-Location "C:\"
    Remove-PSDrive -Name $HiveDrive -Force
}
$HivePath = $null

if ($ManualLoad) {
    Write-Host "Выгрузка реестра..." -ForegroundColor Gray
    
    # ПРИНУДИТЕЛЬНАЯ ЧИСТКА ПАМЯТИ
    # Это критически важно, чтобы отпустить файл NTUSER.DAT
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
        Write-Warning "ПЕРЕЗАГРУЗИТЕ КОМПЬЮТЕР НЕМЕДЛЕННО, чтобы не повредить профиль!"
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
# ВКЛЮЧЕНИЕ УДАЛЕННОГО ДОСТУПА (RDP) ДЛЯ АДМИНИСТРАТОРА
# ==============================================================================
Write-Host "Включение RDP (Удаленного рабочего стола)..." -ForegroundColor Cyan
# Разрешаем подключения RDP
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 -Force
# Включаем Network Level Authentication для безопасности
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1 -Force
# Открываем порт в Брандмауэре Windows
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
Write-Host "Черный ход для родителя открыт (RDP)." -ForegroundColor Green

# ==============================================================================
# АВТОМАТИЧЕСКОЕ ПОНИЖЕНИЕ ПРАВ (ВМЕСТО NETPLWIZ)
# ==============================================================================
Write-Host "Снятие прав Администратора с пользователя $TargetUser..." -ForegroundColor Cyan

try {
    # Получаем локализованные имена групп по их SID (S-1-5-32-544 = Админы, S-1-5-32-545 = Пользователи)
    # Это нужно, чтобы скрипт работал и на Русской, и на Английской Windows
    $AdminGroup = (Get-LocalGroup | Where-Object { $_.SID -like "S-1-5-32-544" }).Name
    $UserGroup  = (Get-LocalGroup | Where-Object { $_.SID -like "S-1-5-32-545" }).Name

    # Добавляем в группу "Пользователи" (Обычные права)
    Add-LocalGroupMember -Group $UserGroup -Member $TargetUser -ErrorAction SilentlyContinue
    
    # Удаляем из группы "Администраторы"
    Remove-LocalGroupMember -Group $AdminGroup -Member $TargetUser -ErrorAction SilentlyContinue
    
    Write-Host "Права успешно изменены: $TargetUser теперь обычный пользователь." -ForegroundColor Green
} catch {
    Write-Warning "Не удалось автоматически сменить группу пользователя."
    Write-Warning "Ошибка: $_"
    Write-Host "Пожалуйста, сделайте это вручную через netplwiz."
    netplwiz
    Pause
}

Write-Host " "
Write-Host "-------------------------------------------------------------" -ForegroundColor Green
Write-Host "НАСТРОЙКА ЗАВЕРШЕНА УСПЕШНО!"
Write-Host " "
Write-Host "В настройках Playnite обязательно выставите следующие параметры:"
Write-Host "(Настройки -> Общие -> Сворачивать Playnite в системный трей при запуске игры.)"
Write-Host "(Настройки -> Общие -> Восстанавливать окно после закрытия игры.)"
Write-Host "-------------------------------------------------------------"
Write-Host "Горячие клавиши:"
Write-Host "  [CTRL+ALT+UP]    -  Прибавить громкость"
Write-Host "  [CTRL+ALT+DOWN]  -  Убавить громкость"
Write-Host "  [CTRL+ALT+M]     -  Заглушить звук"
Write-Host " "
Write-Host "  [CTRL+ALT+K]     -  Закрыть зависшую игру"
Write-Host "  [CTRL+ALT+P]     -  Принудительный перезапуск Playnite"
Write-Host "  (Нажмите, если игра закрылась, а Playnite не появился.)"
Write-Host " "
Write-Host "  [CTRL+ALT+Q]     -  Экстренный выход из Киоска"
Write-Host "  [CTRL+ALT+L]     -  Смена пользователя (Вход для Родителя)"
Write-Host "  [CTRL+ALT+R]     -  Перезагрузить компьютер"
Write-Host "  [CTRL+ALT+S]     -  Выключить компьютер"
Write-Host "-------------------------------------------------------------"
Pause
Write-Host "АВТОМАТИЧЕСКАЯ ПЕРЕЗАГРУЗКА ПК ЧЕРЕЗ 5 СЕКУНД..." -ForegroundColor Red
Start-Sleep -Seconds 5
Restart-Computer -Force