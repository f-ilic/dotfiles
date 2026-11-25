#!/usr/bin/env bash
# Set up the kmonad keyboard remap as systemd services on this Linux machine, for the keyboards plugged in here.
#
#   kmonad/install.sh            install or refresh a service for every config whose keyboard is connected
#   kmonad/install.sh --list     show which configs match a connected keyboard; changes nothing
#   kmonad/install.sh --remove   stop and remove the services again
#
# Each config names its keyboard in a header line:   ;; device: /dev/input/by-id/usb-...*-event-kbd
# (a glob is fine, so a serial number in the path does not tie a config to one unit). The first match is written into a
# copy of the config under /etc/kmonad/, and `kmonad --dry-run` has to accept that copy before anything is touched.
# One template unit (systemd/kmonad@.service) runs them all, with the real path of the kmonad binary filled in.
# Run it as yourself: it uses sudo only for the steps that need it. Re-run it after editing a config.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${KMONAD_CONFIG_DIR:-$HERE/config}"
ETC_DIR="${KMONAD_ETC:-/etc}/kmonad"
UNIT_DIR="${KMONAD_UNIT_DIR:-/etc/systemd/system}"
TEMPLATE="$HERE/systemd/kmonad@.service"

die() { echo "kmonad/install.sh: $*" >&2; exit 1; }
say() { printf '  %s\n' "$*"; }

[[ "$(uname -s)" == Linux ]] || die "this is for Linux (on macOS the same layer is .hammerspoon/Spoons/KeyRemap)"

if [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    command -v sudo >/dev/null || die "sudo is needed for the system changes"
    SUDO="sudo"
fi

find_kmonad() {
    local c
    for c in "${KMONAD_BIN:-}" "$(command -v kmonad 2>/dev/null || true)" "$HOME/bin/kmonad" "$HOME/.local/bin/kmonad" /usr/local/bin/kmonad; do
        if [[ -n "$c" && -x "$c" ]]; then printf '%s\n' "$c"; return 0; fi
    done
    return 1
}

device_pattern() {  # the "device:" header of a config, else the literal device-file of its defcfg
    local p
    p="$(sed -n 's/^;; device:[[:space:]]*//p' "$1" | head -n 1)"
    if [[ -z "$p" ]]; then p="$(sed -n 's/.*(device-file "\([^"]*\)").*/\1/p' "$1" | head -n 1)"; fi
    printf '%s\n' "$p"
}

resolve_device() {  # first existing match of a glob
    local m
    # the glob is meant to expand here
    # shellcheck disable=SC2086
    for m in $1; do
        if [[ -e "$m" ]]; then printf '%s\n' "$m"; return 0; fi
    done
    return 1
}

each_config() {  # prints "name<TAB>path" for every config
    local cfg
    for cfg in "$CONFIG_DIR"/*.kbd; do
        if [[ -e "$cfg" ]]; then printf '%s\t%s\n' "$(basename "$cfg" .kbd)" "$cfg"; fi
    done
}

cmd_list() {
    local name cfg pat dev state inst
    while IFS=$'\t' read -r name cfg; do
        pat="$(device_pattern "$cfg")"
        if dev="$(resolve_device "$pat")"; then state="connected: $dev"; else state="not connected"; fi
        if [[ -f "$ETC_DIR/$name.kbd" ]]; then inst="installed"; else inst="-"; fi
        printf '  %-26s %-10s %s\n' "$name" "$inst" "$state"
    done < <(each_config)
}

cmd_install() {
    local KMONAD todo name cfg pat dev
    KMONAD="$(find_kmonad)" || die "kmonad is not installed (./start.sh installs it on a Linux desktop)"
    [[ -f "$TEMPLATE" ]] || die "missing $TEMPLATE"
    tmp="$(mktemp -d)"  # global on purpose: the EXIT trap runs after this function has returned
    trap 'rm -rf "$tmp"' EXIT

    # 1. check everything first: at this point nothing on the system has been touched
    todo=""
    while IFS=$'\t' read -r name cfg; do
        pat="$(device_pattern "$cfg")"
        if ! dev="$(resolve_device "$pat")"; then say "skip $name: its keyboard is not connected ($pat)"; continue; fi
        sed "s|(device-file \"[^\"]*\")|(device-file \"$dev\")|" "$cfg" > "$tmp/$name.kbd"
        grep -q "(device-file \"$dev\")" "$tmp/$name.kbd" || die "$name.kbd has no (device-file ...) line to fill in"
        if ! "$KMONAD" --dry-run "$tmp/$name.kbd" >/dev/null 2>"$tmp/err"; then
            cat "$tmp/err" >&2
            die "kmonad rejects $name.kbd; nothing was changed"
        fi
        todo="$todo $name"
    done < <(each_config)
    if [[ -z "$todo" ]]; then echo "No configured keyboard is connected here; nothing to install."; return 0; fi

    # 2. then change the system
    sed "s|@KMONAD@|$KMONAD|" "$TEMPLATE" > "$tmp/kmonad@.service"
    $SUDO install -d -m 755 "$ETC_DIR"
    $SUDO install -m 644 "$tmp/kmonad@.service" "$UNIT_DIR/kmonad@.service"
    for name in $todo; do
        if [[ -f "$UNIT_DIR/keyboard_$name.service" ]]; then  # the old hand-copied unit would grab the same keyboard twice
            $SUDO systemctl disable --now "keyboard_$name.service" || true
            $SUDO rm -f "$UNIT_DIR/keyboard_$name.service"
            say "removed the old keyboard_$name.service"
        fi
        $SUDO install -m 644 "$tmp/$name.kbd" "$ETC_DIR/$name.kbd"
    done
    $SUDO systemctl daemon-reload
    for name in $todo; do
        $SUDO systemctl enable "kmonad@$name.service"
        $SUDO systemctl restart "kmonad@$name.service"  # restart, so an edited config takes effect
        sleep "${KMONAD_WAIT:-1}"
        if $SUDO systemctl is-active --quiet "kmonad@$name.service"; then
            say "kmonad@$name is running"
        else
            say "WARNING: kmonad@$name is not running yet; see: journalctl -u kmonad@$name -n 20"
        fi
    done
}

cmd_remove() {
    local kbd name found=0
    for kbd in "$ETC_DIR"/*.kbd; do
        [[ -e "$kbd" ]] || continue
        name="$(basename "$kbd" .kbd)"
        $SUDO systemctl disable --now "kmonad@$name.service" || true
        $SUDO rm -f "$kbd"
        say "removed kmonad@$name"
        found=1
    done
    if [[ -f "$UNIT_DIR/kmonad@.service" ]]; then $SUDO rm -f "$UNIT_DIR/kmonad@.service"; found=1; fi
    $SUDO systemctl daemon-reload
    $SUDO rmdir "$ETC_DIR" 2>/dev/null || true
    if [[ $found -eq 0 ]]; then echo "Nothing was installed."; fi
}

case "${1:-}" in
    "")       cmd_install ;;
    --list)   cmd_list ;;
    --remove) cmd_remove ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
    *)        die "unknown option: $1 (try --list, --remove)" ;;
esac
