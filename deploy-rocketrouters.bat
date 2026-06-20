@echo off
echo.
echo ========================================
echo  Rocket Routers — Cloudflare Deploy
echo ========================================
echo.

set SRC=D:\Rocket-Routers-Website
set TMP=D:\Rocket-Deploy-Temp

echo [1/3] Copying site to temp folder (excluding large/private files)...
if exist "%TMP%" rmdir /S /Q "%TMP%"
mkdir "%TMP%"

robocopy "%SRC%" "%TMP%" /E ^
  /XD "firmware-build" ^
  /XD "pdfs" ^
  /XD "rocket-encryptor" ^
  /XD ".wrangler" ^
  /XD "MY INFO" ^
  /XF "IWF-Partnership-Contact.md" ^
  /XF "ROUTER_RESUME_NOTES.md" ^
  /XF "feedback-to-anthropic.txt" ^
  /XF "RocketRouters-CredentialGenerator.html" ^
  /XF "RocketRouters-WiFiGenerator.html" ^
  /XF "RocketRouters-CustomerCard.html" ^
  /XF "*.pem" ^
  /XF "*.bin" ^
  /XF ".cfpagesignore"

echo.
echo [1b/3] Checking images\why was copied...
if exist "%TMP%\images\why" (
  echo   FOUND: images\why folder
  dir "%TMP%\images\why" /B
) else (
  echo   MISSING: images\why folder was NOT copied!
)
echo.
echo [2/3] Deploying to Cloudflare Pages...
wrangler pages deploy "%TMP%" --project-name=rocketrouters

echo.
echo [3/3] Cleaning up temp folder...
rmdir /S /Q "%TMP%"

echo.
echo ========================================
echo  Done!
echo ========================================
echo.
pause
