@echo off
REM Corre la app apuntando al backend real en Railway (con hot reload).
REM Para desarrollo normal contra tu servidor local, usa "flutter run -d windows" sin más.
flutter run -d windows --dart-define=API_BASE_URL=https://web-production-925bf0.up.railway.app/api
