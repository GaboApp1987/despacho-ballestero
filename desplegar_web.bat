@echo off
REM Compila la app web apuntando a Railway, la copia al backend, y sube el
REM cambio para que Railway la redespliegue automaticamente.
echo Compilando...
flutter build web --pwa-strategy=none --dart-define=API_BASE_URL=https://web-production-925bf0.up.railway.app/api
if errorlevel 1 goto :error

echo Copiando al backend...
rmdir /s /q "..\DespachoBallesteroProject\webapp" 2>nul
xcopy /e /i /y "build\web" "..\DespachoBallesteroProject\webapp" >nul

echo Subiendo a Railway...
cd ..\DespachoBallesteroProject
git add webapp
git commit -m "Actualiza build de la app web"
git push origin master
cd ..\despacho_app

echo Listo. Railway va a redesplegar solo en unos minutos.
goto :end

:error
echo Fallo la compilacion, revisa el error arriba.

:end
