#!/bin/bash
# shellcheck disable=SC2034

lk_bin_depth=1 . lk-bash-load.sh || exit

LK_USAGE="Usage: ${0##*/} [DPI]"

lk_check_args

DPI="${1:-$(xdpyinfo |
    grep -Eo '^[[:blank:]]+resolution:[[:blank:]]*[0-9]+x[0-9]+' |
    grep -Eo '[0-9]+' | head -n1)}" || lk_die
[[ "$DPI" =~ [0-9]+ ]] || lk_usage

lk_console_item "Applying Xfce4 settings based on screen DPI:" "$DPI"

_MULTIPLIER="$(bc <<<"scale = 10; $DPI / 96")"
_MULTIPLIERx10="$(bc <<<"scale = 10; v = $DPI * 10 / 96; scale = 0; v / 1")"

_16="$(bc <<<"v = 16 * $_MULTIPLIER / 1; v - v % 2")"
_24="$(bc <<<"v = 24 * $_MULTIPLIER / 1; v - v % 2")"
_32="$(bc <<<"v = 32 * $_MULTIPLIER / 1; v - v % 2")"
_48="$(bc <<<"v = 48 * $_MULTIPLIER / 1; v - v % 2")"
_128="$(bc <<<"v = 128 * $_MULTIPLIER / 1; v - v % 2")"
_GAP="$(bc <<<"v = 4 * $_MULTIPLIER / 1 - 2; if (v < 2) v = 2; v - v % 2")"

if [ "$_MULTIPLIERx10" -le 10 ]; then

    # scaling <= 1
    THUNAR_ICON_SIZE_16="THUNAR_ICON_SIZE_16"
    THUNAR_ICON_SIZE_24="THUNAR_ICON_SIZE_24"
    THUNAR_ICON_SIZE_32="THUNAR_ICON_SIZE_32"
    THUNAR_ICON_SIZE_48="THUNAR_ICON_SIZE_48"
    THUNAR_ICON_SIZE_64="THUNAR_ICON_SIZE_64"
    THUNAR_ZOOM_LEVEL_25_PERCENT="THUNAR_ZOOM_LEVEL_25_PERCENT"
    THUNAR_ZOOM_LEVEL_38_PERCENT="THUNAR_ZOOM_LEVEL_38_PERCENT"
    THUNAR_ZOOM_LEVEL_50_PERCENT="THUNAR_ZOOM_LEVEL_50_PERCENT"
    THUNAR_ZOOM_LEVEL_75_PERCENT="THUNAR_ZOOM_LEVEL_75_PERCENT"
    THUNAR_ZOOM_LEVEL_100_PERCENT="THUNAR_ZOOM_LEVEL_100_PERCENT"

elif [ "$_MULTIPLIERx10" -le 15 ]; then

    # 1 < scaling <= 1.5
    THUNAR_ICON_SIZE_16="THUNAR_ICON_SIZE_24"
    THUNAR_ICON_SIZE_24="THUNAR_ICON_SIZE_32"
    THUNAR_ICON_SIZE_32="THUNAR_ICON_SIZE_48"
    THUNAR_ICON_SIZE_48="THUNAR_ICON_SIZE_64"
    THUNAR_ICON_SIZE_64="THUNAR_ICON_SIZE_96"
    THUNAR_ZOOM_LEVEL_25_PERCENT="THUNAR_ZOOM_LEVEL_38_PERCENT"
    THUNAR_ZOOM_LEVEL_38_PERCENT="THUNAR_ZOOM_LEVEL_50_PERCENT"
    THUNAR_ZOOM_LEVEL_50_PERCENT="THUNAR_ZOOM_LEVEL_75_PERCENT"
    THUNAR_ZOOM_LEVEL_75_PERCENT="THUNAR_ZOOM_LEVEL_100_PERCENT"
    THUNAR_ZOOM_LEVEL_100_PERCENT="THUNAR_ZOOM_LEVEL_150_PERCENT"

else

    # scaling > 1.5
    THUNAR_ICON_SIZE_16="THUNAR_ICON_SIZE_32"
    THUNAR_ICON_SIZE_24="THUNAR_ICON_SIZE_48"
    THUNAR_ICON_SIZE_32="THUNAR_ICON_SIZE_64"
    THUNAR_ICON_SIZE_48="THUNAR_ICON_SIZE_96"
    THUNAR_ICON_SIZE_64="THUNAR_ICON_SIZE_128"
    THUNAR_ZOOM_LEVEL_25_PERCENT="THUNAR_ZOOM_LEVEL_50_PERCENT"
    THUNAR_ZOOM_LEVEL_38_PERCENT="THUNAR_ZOOM_LEVEL_75_PERCENT"
    THUNAR_ZOOM_LEVEL_50_PERCENT="THUNAR_ZOOM_LEVEL_100_PERCENT"
    THUNAR_ZOOM_LEVEL_75_PERCENT="THUNAR_ZOOM_LEVEL_150_PERCENT"
    THUNAR_ZOOM_LEVEL_100_PERCENT="THUNAR_ZOOM_LEVEL_200_PERCENT"

fi

GTK_ICON_SIZES="\
gtk-button=${_16},${_16}:gtk-dialog=${_48},${_48}:\
gtk-dnd=${_32},${_32}:gtk-large-toolbar=${_24},${_24}:\
gtk-menu=${_16},${_16}:gtk-small-toolbar=${_16},${_16}"

xfconf-query -c "xsettings" -p "/Xft/DPI" \
    -n -t int -s "$DPI"
xfconf-query -c "xsettings" -p "/Gtk/CursorThemeSize" \
    -n -t int -s "${_24}"
xfconf-query -c "xsettings" -p "/Gtk/IconSizes" \
    -n -t string -s "$GTK_ICON_SIZES"
xfconf-query -c "xfce4-desktop" -p "/desktop-icons/icon-size" \
    -n -t uint -s "${_48}"
xfconf-query -c "xfce4-desktop" -p "/desktop-icons/tooltip-size" \
    -n -t double -s "${_128}"
xfconf-query -c "thunar" -p "/shortcuts-icon-size" \
    -n -t string -s "$THUNAR_ICON_SIZE_24"
xfconf-query -c "thunar" -p "/tree-icon-size" \
    -n -t string -s "$THUNAR_ICON_SIZE_16"
xfconf-query -c "thunar" -p "/last-icon-view-zoom-level" \
    -n -t string -s "$THUNAR_ZOOM_LEVEL_100_PERCENT"
xfconf-query -c "thunar" -p "/last-details-view-zoom-level" \
    -n -t string -s "$THUNAR_ZOOM_LEVEL_38_PERCENT"
xfconf-query -c "thunar" -p "/last-compact-view-zoom-level" \
    -n -t string -s "$THUNAR_ZOOM_LEVEL_25_PERCENT"

for PANEL in $(xfconf-query -c "xfce4-panel" -p "/panels" -lv 2>/dev/null | grep -Eo '^/panels/[^/]+/' | sort | uniq); do
    xfconf-query -c "xfce4-panel" -p "${PANEL}size" -n -t int -s "${_24}"
    xfconf-query -c "xfce4-panel" -p "${PANEL}icon-size" -n -t int -s "${_16}"
done

if PANEL_PLUGINS="$(xfconf-query -c "xfce4-panel" -p "/plugins" -lv 2>/dev/null | grep -E '^/plugins/[^/]+\s+')"; then
    ((PANEL_ICON_SIZE = _24 - _GAP - 4))
    while IFS=' ' read -r PLUGIN_ID PLUGIN_NAME; do
        case "$PLUGIN_NAME" in
        systray)
            xfconf-query -c "xfce4-panel" -p "${PLUGIN_ID}/size-max" -n -t int -s "$PANEL_ICON_SIZE"
            ;;
        esac
    done < <(echo "$PANEL_PLUGINS")
fi

WHISKER_SETTINGS=(
    "menu-width=$(bc <<<"450 * $_MULTIPLIER / 1")"
    "menu-height=$(bc <<<"500 * $_MULTIPLIER / 1")"
    "item-icon-size=$(bc <<<"v = 3 * $_MULTIPLIER / 1; if (v > 6) v = 6; v")"
    "category-icon-size=$(bc <<<"v = 3 * $_MULTIPLIER / 1 - 2; if (v < 0) v = 0; if (v > 6) v = 6; v")"
)

for FILE in "$HOME/.config/xfce4/panel"/whiskermenu*.rc; do
    NEW_SETTINGS="$(
        printf '%s\n' "${WHISKER_SETTINGS[@]}"
        grep -Ev '^(menu-(width|height)|(item|category)-icon-size)=' "$FILE"
    )"
    diff <(sort "$FILE" | grep -Ev '^(\s*$|menu-(width|height)=)') <(echo "$NEW_SETTINGS" | sort | grep -Ev '^(\s*$|menu-(width|height)=)') >/dev/null || {
        cp -pf "$FILE" "$FILE.bak"
        printf '%s\n' "$NEW_SETTINGS" >"$FILE"
        ! pgrep -xu "$USER" xfce4-panel >/dev/null || xfce4-panel -r || true
    }
done

for PLANK_DOCK in $(dconf list "/net/launchpad/plank/docks/"); do
    dconf write "/net/launchpad/plank/docks/${PLANK_DOCK}icon-size" "${_48}"
done
