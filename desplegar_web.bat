@echo off
REM Compila la app web apuntando a Railway, la copia al backend (SOLO
REM webapp\app -- ahi vive la app, webapp\ tambien tiene el landing page y
REM pagos\tarjeta.html, que NO se deben borrar), y sube el cambio para que
REM Railway la redespliegue automaticamente.
REM
REM OJO: el dominio tiene que ser equilibracr.com, NUNCA *.up.railway.app --
REM Railway tiene ALLOWED_HOSTS=equilibracr.com, asi que un build apuntando
REM al dominio de railway.app deja el login (y toda la API) roto con "Bad
REM Request (400)" sin que el build avise nada. Paso real en produccion el
REM 2026-09-11.
echo Compilando...
flutter build web --release --dart-define=API_BASE_URL=https://equilibracr.com/api --base-href=/app/
if errorlevel 1 goto :error

echo Copiando al backend...
rmdir /s /q "..\DespachoBallesteroProject\webapp\app" 2>nul
xcopy /e /i /y "build\web" "..\DespachoBallesteroProject\webapp\app" >nul

echo Subiendo a Railway...
cd ..\DespachoBallesteroProject
git add webapp\app
git commit -m "Actualiza build de la app web"
git push origin master
cd ..\despacho_app

echo Listo. Railway va a redesplegar solo en unos minutos.
goto :end

:error
echo Fallo la compilacion, revisa el error arriba.

:end
