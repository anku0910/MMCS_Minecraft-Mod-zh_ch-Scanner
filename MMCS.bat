@echo off
rem zh_cn finder launcher - ASCII only for codepage safety
rem Double-click to pick a folder, or drag a folder onto this file.
if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0MMCS.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0MMCS.ps1" "%~1"
)
