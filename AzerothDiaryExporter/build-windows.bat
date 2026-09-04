@echo off
setlocal
cd /d "%~dp0"
where go >nul 2>nul
if errorlevel 1 (
  echo Go wurde nicht gefunden. Installiere Go von https://go.dev/ und starte die Datei erneut.
  pause
  exit /b 1
)
set GOOS=windows
set GOARCH=amd64
set CGO_ENABLED=0
go test ./...
if errorlevel 1 goto :fail
go build -trimpath -ldflags="-H=windowsgui -s -w" -o AzerothDiaryExporter.exe .
if errorlevel 1 goto :fail
go run ./tools/iconpatch AzerothDiaryExporter.exe icon.ico
if errorlevel 1 goto :fail
echo.
echo Fertig: AzerothDiaryExporter.exe inklusive App-Icon
pause
exit /b 0
:fail
echo.
echo Build fehlgeschlagen.
pause
exit /b 1
