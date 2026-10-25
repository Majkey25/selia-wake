#!/bin/bash
# Invoked only as /bin/bash --noprofile --norc -p <private-copy> <four argv>.
# -p ignores inherited shell functions and startup hooks. No caller-selected
# executable, environment-supplied command, command string, or network operation.

linux_wake_validate_arguments() {
    if [[ $# != 4 ]] ||
        [[ $1 != enable && $1 != query ]] ||
        [[ ! $2 =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,14}$ ]] ||
        [[ ! $3 =~ ^[0-9a-f][02468ace](:[0-9a-f]{2}){5}$ ]] ||
        [[ $3 == 00:00:00:00:00:00 ]] ||
        [[ ! $4 =~ ^[1-9][0-9]{0,9}$ ]] ||
        (( $4 > 2147483647 )); then
        builtin printf '%s\n' 'Invalid Linux wake arguments.' >&2
        return 64
    fi
}

linux_wake_identity_changed() {
    builtin printf '%s\n' \
        'The selected physical adapter changed or disappeared. Inspect again.' >&2
    return 65
}

# The root is an internal function parameter for reading a sysfs snapshot;
# the executable entry point below always supplies the fixed /sys mount.
linux_wake_check_identity() {
    local sysfs=$1 name=$2 expected_mac=$3 expected_index=$4
    local root="$sysfs/class/net/$name" resolved type index link flags mac
    if [[ ! -d $root/device || -d $root/wireless || -e $root/phy80211 ]]; then
        linux_wake_identity_changed
        return 65
    fi
    resolved=$(builtin cd -P -- "$root" && builtin pwd -P) || {
        linux_wake_identity_changed
        return 65
    }
    if [[ $resolved == "$sysfs/devices/virtual" ||
          $resolved == "$sysfs/devices/virtual/"* ]]; then
        linux_wake_identity_changed
        return 65
    fi
    if ! {
        IFS= builtin read -r type < "$root/type" &&
        IFS= builtin read -r link < "$root/iflink" &&
        IFS= builtin read -r flags < "$root/flags" &&
        IFS= builtin read -r mac < "$root/address" &&
        IFS= builtin read -r index < "$root/ifindex"
    }; then
        linux_wake_identity_changed
        return 65
    fi
    if [[ $type != 1 || $index != "$expected_index" ||
          $link != "$expected_index" || $mac != "$expected_mac" ||
          ! $flags =~ ^0x[0-9a-fA-F]{1,8}$ ]] || (( (flags & 1) == 0 )); then
        linux_wake_identity_changed
        return 65
    fi
}

linux_wake_main() {
    set -eu
    unset BASH_ENV ENV CDPATH
    export LC_ALL=C LANG=C PATH=/usr/sbin:/sbin:/usr/bin:/bin
    linux_wake_validate_arguments "$@" || return "$?"
    local ethtool=''
    local candidate
    for candidate in /usr/sbin/ethtool /sbin/ethtool /usr/bin/ethtool /bin/ethtool; do
        if [[ -f $candidate && -x $candidate ]]; then
            ethtool=$candidate
            break
        fi
    done
    if [[ -z $ethtool ]]; then
        builtin printf '%s\n' 'ethtool is missing at a supported system path.' >&2
        return 69
    fi
    # Runs with ordinary privileges, immediately before replacing this process
    # with fixed ethtool. The app also checks the identity after it exits.
    linux_wake_check_identity /sys "$2" "$3" "$4" || return "$?"
    if [[ $1 == enable ]]; then
        exec "$ethtool" -s "$2" wol g
    else
        exec "$ethtool" "$2"
    fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    linux_wake_main "$@"
fi
