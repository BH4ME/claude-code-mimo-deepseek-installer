@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0set-provider-key.ps1" %*
