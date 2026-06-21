@echo off
echo Setting environment variables...
set LIBGL_ALWAYS_SOFTWARE=1
set SDL_VIDEO_DRIVER=x11
set SDL_VIDEODRIVER=x11
set WSLENV=LIBGL_ALWAYS_SOFTWARE/u:SDL_VIDEO_DRIVER/u:SDL_VIDEODRIVER/u

echo Launching KOReader in WSL...
C:\Windows\System32\wsl.exe --exec dbus-launch --exit-with-session bash -c "cd /home/jimmy/squashfs-root && ./AppRun"

echo.
echo Process exited. Press any key to close.
pause > nul
