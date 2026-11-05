@echo off
setlocal
rem Use the Windows short path to avoid SDK/CMake failures with accented paths.
for %%I in ("%~dp0..") do set "HEMOLINK_ROOT=%%~fsI"
pushd "%HEMOLINK_ROOT%"
if errorlevel 1 exit /b 1
call flutter %*
set "HEMOLINK_EXIT_CODE=%ERRORLEVEL%"
popd
exit /b %HEMOLINK_EXIT_CODE%
