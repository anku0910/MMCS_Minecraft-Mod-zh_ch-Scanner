@echo off
rem zh_cn finder launcher - ASCII only for codepage safety
rem Double-click to pick a folder, or drag a folder onto this file.
if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0find_zh_cn.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0find_zh_cn.ps1" "%~1"
)
