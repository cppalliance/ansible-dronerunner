#!/bin/bash
# Drain and stop the drone runner. On SIGTERM the runner immediately stops
# accepting new stages, then exits once running stages finish and report to
# the server; -t (seconds) is a ceiling, not a delay - an idle runner stops
# in seconds. Restart later with startdronerunner.sh (or docker start runner).

docker stop -t {{ dronerunner_stop_timeout }} runner
