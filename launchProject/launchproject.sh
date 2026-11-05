#!/bin/bash
# Fullscreen konsole on the laptop screen: lazygit on the left, claude on the right.
# Usage: launchproject.sh [dir]

dir=$(realpath "${1:-.}")
here=$(dirname "$(realpath "$0")")
tmp=$(mktemp -d)
trap "rm -rf $tmp" EXIT

# konsole won't let us push commands into a session over dbus (disabled by default),
# so make a throwaway profile that runs pane.sh, which figures out which side it's on
profile=$(sed -n 's/^DefaultProfile=//p' ~/.config/konsolerc)
if [ -n "$profile" ]; then
    grep -vE '^(Command|Name|Directory)=' ~/.local/share/konsole/"$profile" > $tmp/lp.profile
fi
grep -q '^\[General\]' $tmp/lp.profile 2>/dev/null || echo "[General]" >> $tmp/lp.profile
sed -i "/^\[General\]/a Name=launchproject\nCommand=$here/pane.sh $dir\nDirectory=$dir" $tmp/lp.profile

konsole --separate --profile $tmp/lp.profile >/dev/null 2>&1 &
pid=$!
disown

# give konsole a sec to show up on dbus
until gdbus introspect --session --dest org.kde.konsole-$pid --object-path /konsole/MainWindow_1 &>/dev/null; do
    sleep 0.1
done

gdbus call --session --dest org.kde.konsole-$pid --object-path /konsole/MainWindow_1 \
    --method org.kde.KMainWindow.activateAction split-view-left-right >/dev/null

# can't move windows ourselves on wayland, so ask kwin to do it
cat > $tmp/move.js <<EOF2
var screen = workspace.screens.filter(s => s.name.startsWith("eDP"))[0];
workspace.windowList().forEach(w => {
    if (w.pid != $pid || !w.normalWindow) return;
    w.desktops = [workspace.currentDesktop];
    if (screen) workspace.sendClientToScreen(w, screen);
    w.fullScreen = true;
    workspace.activeWindow = w;
});
EOF2

id=$(gdbus call --session --dest org.kde.KWin --object-path /Scripting \
    --method org.kde.kwin.Scripting.loadScript $tmp/move.js lp-$pid | grep -o '[0-9]\+')
gdbus call --session --dest org.kde.KWin --object-path /Scripting/Script$id --method org.kde.kwin.Script.run >/dev/null
sleep 0.3
gdbus call --session --dest org.kde.KWin --object-path /Scripting --method org.kde.kwin.Scripting.unloadScript lp-$pid >/dev/null
