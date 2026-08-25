
@ECHO ON

REM Drain and stop the drone runner.
REM
REM Windows cannot do signal-based draining: on "docker stop" the container OS
REM gives the entrypoint a hardcoded ~5 seconds regardless of -t, and the
REM WaitToKillServiceTimeout registry value only affects services, not console
REM apps like the runner (https://github.com/moby/moby/issues/25982; confirmed
REM by testing on Windows Server 2025, 2026-08).
REM
REM Instead, wait until no drone build containers (label io.drone) are running,
REM then stop the runner. CAVEAT: the runner still accepts new jobs while this
REM waits, so on a busy server pause the drone queue first ("drone queue pause",
REM admin CLI) and resume it after maintenance. Ctrl+C aborts the wait.
REM Restart later with startdronerunner.bat (or docker start runner).

powershell -NoProfile -Command "if (docker ps -q --filter 'label=io.drone') { Write-Host 'waiting for drone build containers to finish...' }; while (docker ps -q --filter 'label=io.drone') { Start-Sleep -Seconds 1 }"

docker stop runner
