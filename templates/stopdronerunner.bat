
@ECHO ON

REM Drain and stop the drone runner. On the stop signal the runner immediately
REM stops accepting new stages, then exits once running stages finish and
REM report to the server; -t (seconds) is a ceiling, not a delay - an idle
REM runner stops in seconds. NOTE: draining on Windows requires a runner image
REM with a raised WaitToKillServiceTimeout registry value (see README-CPP.md in
REM the drone-runner-docker fork); otherwise Windows kills the container about
REM 5 seconds after the signal regardless of -t.
REM Restart later with startdronerunner.bat (or docker start runner).

docker stop -t {{ dronerunner_stop_timeout }} runner
