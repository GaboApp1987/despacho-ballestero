@echo off
REM Genera el .exe final (build\windows\x64\runner\Release\despacho_app.exe)
REM apuntando al backend real en Railway, para compartir con quien vaya a probar.
flutter build windows --release --dart-define=API_BASE_URL=https://web-production-925bf0.up.railway.app/api
