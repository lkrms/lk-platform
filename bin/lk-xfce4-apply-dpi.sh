#!/bin/bash

lk_bin_depth=1 . lk-bash-load.sh || exit
lk_include linux

shopt -s nullglob

LK_USAGE="\
Usage: ${0##*/} [DPI]"

lk_getopt
eval "set -- $LK_GETOPT"

DPI=${1:-$(lk_x_dpi)}
[[ $DPI =~ ^[0-9]+$ ]] || lk_usage

_M=$(bc <<<"scale = 10; $DPI / 96")
_Mx10=$(bc <<<"scale = 10; v = $DPI * 10 / 96; scale = 0; v / 1")

_16=$(bc <<<"v = 16 * $_M / 1; v - v % 2")
_24=$(bc <<<"v = 24 * $_M / 1; v - v % 2")
_32=$(bc <<<"v = 32 * $_M / 1; v - v % 2")
_48=$(bc <<<"v = 48 * $_M / 1; v - v % 2")
_128=$(bc <<<"v = 128 * $_M / 1; v - v % 2")
_GAP=$(bc <<<"v = 4 * $_M / 1 - 2; if (v < 2) v = 2; v - v % 2")

lk_console_message "Configuring Xfce4"
lk_console_detail "Display resolution:" "$DPI DPI"
lk_console_detail "Multiplier:" "$(sed -E 's/0+$//' <<<"$_M")"

if [ "$_Mx10" -le 10 ]; then
    # scaling <= 1
    THUNAR_ICON_SIZE_16=THUNAR_ICON_SIZE_16
    THUNAR_ICON_SIZE_24=THUNAR_ICON_SIZE_24
    THUNAR_ICON_SIZE_32=THUNAR_ICON_SIZE_32
    THUNAR_ICON_SIZE_48=THUNAR_ICON_SIZE_48
    THUNAR_ICON_SIZE_64=THUNAR_ICON_SIZE_64
    THUNAR_ZOOM_LEVEL_25_PERCENT=THUNAR_ZOOM_LEVEL_25_PERCENT
    THUNAR_ZOOM_LEVEL_38_PERCENT=THUNAR_ZOOM_LEVEL_38_PERCENT
    THUNAR_ZOOM_LEVEL_50_PERCENT=THUNAR_ZOOM_LEVEL_50_PERCENT
    THUNAR_ZOOM_LEVEL_75_PERCENT=THUNAR_ZOOM_LEVEL_75_PERCENT
    THUNAR_ZOOM_LEVEL_100_PERCENT=THUNAR_ZOOM_LEVEL_100_PERCENT
elif [ "$_Mx10" -le 15 ]; then
    # 1 < scaling <= 1.5
    THUNAR_ICON_SIZE_16=THUNAR_ICON_SIZE_24
    THUNAR_ICON_SIZE_24=THUNAR_ICON_SIZE_32
    THUNAR_ICON_SIZE_32=THUNAR_ICON_SIZE_48
    THUNAR_ICON_SIZE_48=THUNAR_ICON_SIZE_64
    THUNAR_ICON_SIZE_64=THUNAR_ICON_SIZE_96
    THUNAR_ZOOM_LEVEL_25_PERCENT=THUNAR_ZOOM_LEVEL_38_PERCENT
    THUNAR_ZOOM_LEVEL_38_PERCENT=THUNAR_ZOOM_LEVEL_50_PERCENT
    THUNAR_ZOOM_LEVEL_50_PERCENT=THUNAR_ZOOM_LEVEL_75_PERCENT
    THUNAR_ZOOM_LEVEL_75_PERCENT=THUNAR_ZOOM_LEVEL_100_PERCENT
    THUNAR_ZOOM_LEVEL_100_PERCENT=THUNAR_ZOOM_LEVEL_150_PERCENT
else
    # scaling > 1.5
    THUNAR_ICON_SIZE_16=THUNAR_ICON_SIZE_32
    THUNAR_ICON_SIZE_24=THUNAR_ICON_SIZE_48
    THUNAR_ICON_SIZE_32=THUNAR_ICON_SIZE_64
    THUNAR_ICON_SIZE_48=THUNAR_ICON_SIZE_96
    THUNAR_ICON_SIZE_64=THUNAR_ICON_SIZE_128
    THUNAR_ZOOM_LEVEL_25_PERCENT=THUNAR_ZOOM_LEVEL_50_PERCENT
    THUNAR_ZOOM_LEVEL_38_PERCENT=THUNAR_ZOOM_LEVEL_75_PERCENT
    THUNAR_ZOOM_LEVEL_50_PERCENT=THUNAR_ZOOM_LEVEL_100_PERCENT
    THUNAR_ZOOM_LEVEL_75_PERCENT=THUNAR_ZOOM_LEVEL_150_PERCENT
    THUNAR_ZOOM_LEVEL_100_PERCENT=THUNAR_ZOOM_LEVEL_200_PERCENT
fi

GTK_ICON_SIZES="\
gtk-button=${_16},${_16}:gtk-dialog=${_48},${_48}:\
gtk-dnd=${_32},${_32}:gtk-large-toolbar=${_24},${_24}:\
gtk-menu=${_16},${_16}:gtk-small-toolbar=${_16},${_16}"

xfconf-query -c xsettings -n -t int \
    -p /Xft/DPI -s "$DPI"
xfconf-query -c xsettings -n -t int \
    -p /Gtk/CursorThemeSize -s "${_24}"
xfconf-query -c xsettings -n -t string \
    -p /Gtk/IconSizes -s "$GTK_ICON_SIZES"
xfconf-query -c xfce4-desktop -n -t uint \
    -p /desktop-icons/icon-size -s "${_48}"
xfconf-query -c xfce4-desktop -n -t double \
    -p /desktop-icons/tooltip-size -s "${_128}"
xfconf-query -c thunar -n -t string \
    -p /shortcuts-icon-size -s "$THUNAR_ICON_SIZE_24"
xfconf-query -c thunar -n -t string \
    -p /tree-icon-size -s "$THUNAR_ICON_SIZE_16"
xfconf-query -c thunar -n -t string \
    -p /last-icon-view-zoom-level -s "$THUNAR_ZOOM_LEVEL_100_PERCENT"
xfconf-query -c thunar -n -t string \
    -p /last-details-view-zoom-level -s "$THUNAR_ZOOM_LEVEL_38_PERCENT"
xfconf-query -c thunar -n -t string \
    -p /last-compact-view-zoom-level -s "$THUNAR_ZOOM_LEVEL_25_PERCENT"

for PANEL in $(
    xfconf-query -c xfce4-panel -p /panels -lv 2>/dev/null |
        grep -Eo "^/panels/[^/]+/" | sort -u
); do
    xfconf-query -c xfce4-panel -p "${PANEL}size" -n -t int -s "${_24}"
    ICON_SIZE=$(xfconf-query -c xfce4-panel \
        -p "${PANEL}icon-size" 2>/dev/null) || ICON_SIZE=
    [ "$ICON_SIZE" = 0 ] ||
        xfconf-query -c xfce4-panel \
            -p "${PANEL}icon-size" -n -t int -s "${_16}"
done

if PANEL_PLUGINS=$(
    xfconf-query -c xfce4-panel -p /plugins -lv 2>/dev/null |
        grep -E "^/plugins/[^/]+$S+"
); then
    ((PANEL_ICON_SIZE = _24 - _GAP - 4))
    while read -r PLUGIN_ID PLUGIN_NAME; do
        case "$PLUGIN_NAME" in
        systray)
            ICON_SIZE=$(xfconf-query -c xfce4-panel \
                -p "${PLUGIN_ID}/icon-size" 2>/dev/null) || ICON_SIZE=
            [ "$ICON_SIZE" = 0 ] ||
                xfconf-query -c xfce4-panel \
                    -p "${PLUGIN_ID}/icon-size" -n -t int -s "$PANEL_ICON_SIZE"
            ;;
        esac
    done < <(echo "$PANEL_PLUGINS")
fi

WHISKER_SETTINGS=(
    "menu-width=$(bc <<<"450 * $_M / 1")"
    "menu-height=$(bc <<<"500 * $_M / 1")"
    "item-icon-size=$(bc <<<"v = 3 * $_M / 1; if (v > 6) v = 6; v")"
    "category-icon-size=$(bc \
        <<<"v = 3 * $_M / 1 - 2; if (v < 0) v = 0; if (v > 6) v = 6; v")"
)

REGEX="^($S*$|menu-(width|height)=)"
for FILE in ~/.config/xfce4/panel/whiskermenu*.rc; do
    NEW_SETTINGS=$(
        lk_echo_array WHISKER_SETTINGS
        sed -E '/^(menu-(width|height)|(item|category)-icon-size)=/d' "$FILE"
    )
    if ! diff \
        <(sed -E "/$REGEX/d" "$FILE" | sort) \
        <(sed -E "/$REGEX/d" <<<"$NEW_SETTINGS" | sort) >/dev/null; then
        cp -aLf "$FILE" "$FILE.bak"
        echo "$NEW_SETTINGS" >"$FILE"
        ! pgrep -xu "$USER" xfce4-panel >/dev/null || xfce4-panel -r || true
    fi
done

for PLANK_DOCK in $(dconf list /net/launchpad/plank/docks/); do
    dconf write "/net/launchpad/plank/docks/${PLANK_DOCK}icon-size" "${_48}"
done
