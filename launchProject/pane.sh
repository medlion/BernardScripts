#!/bin/bash
# started by launchproject.sh in each konsole split
cd "$1"
if [[ $KONSOLE_DBUS_SESSION == */Sessions/1 ]]; then
    lazygit
else
    # claude redraws constantly while working, so alert on silence (it finished) instead of activity
    for m in "setMonitorActivity false" "setMonitorSilence true"; do
        gdbus call --session --dest "$KONSOLE_DBUS_SERVICE" --object-path "$KONSOLE_DBUS_SESSION" \
            --method org.kde.konsole.Session.${m% *} "${m#* }" &>/dev/null
    done
    claude
fi
exec $SHELL
