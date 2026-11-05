#!/bin/bash
# started by launchproject.sh in each konsole split
cd "$1"
if [[ $KONSOLE_DBUS_SESSION == */Sessions/1 ]]; then
    lazygit
else
    claude
fi
exec $SHELL
