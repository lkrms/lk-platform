#!/bin/bash

# lk_feature_enabled FEATURE...
#
# Return true if all features are enabled.
#
# To be enabled, FEATURE or one of its aliases must appear in the
# comma-delimited LK_FEATURES setting.
function lk_feature_enabled() {
    (($#)) && [[ -n ${LK_FEATURES:+1} ]] || return
    [[ -n ${_LK_FEATURES:+1} ]] &&
        [[ ${_LK_FEATURES_LAST-} == "$LK_FEATURES" ]] ||
        lk_feature_expand || return
    while (($#)); do
        [[ ,$_LK_FEATURES, == *,"$1",* ]] || return
        shift
    done
}

# - _lk_feature_expand FEATURE ALIAS
# - _lk_feature_expand GROUP FEATURE FEATURE...
# - _lk_feature_expand -n FEATURE IMPLIED_FEATURE
#
# The first two forms work in both directions:
# - FEATURE enables ALIAS, and ALIAS enables FEATURE
# - GROUP enables each FEATURE, and they collectively enable GROUP
#
# The third form only works in one direction:
# - FEATURE enables IMPLIED_FEATURE, but enabling IMPLIED_FEATURE does not
#   enable FEATURE.
function _lk_feature_expand() {
    local REVERSIBLE=1 FEATURE
    [[ $1 != -n ]] || { REVERSIBLE=0 && shift; }
    FEATURE=$1
    shift
    if [[ ,$FEATURES, == *,"$FEATURE",* ]]; then
        FEATURES+=$(printf ',%s' "$@")
    elif ((REVERSIBLE)); then
        while (($#)); do
            [[ ,$FEATURES, == *,"$1",* ]] || return 0
            shift
        done
        FEATURES+=",$FEATURE"
    fi
}

# lk_feature_expand
#
# Copy LK_FEATURES to _LK_FEATURES, with aliases and groups expanded.
function lk_feature_expand() {
    local FEATURES=$LK_FEATURES
    _lk_feature_expand apache+php apache2 php-fpm &&
        _lk_feature_expand mysql mariadb &&
        _lk_feature_expand -n xfce4 desktop &&
        _LK_FEATURES=$(IFS=, &&
            lk_args $FEATURES | lk_uniq | lk_implode_input ,) &&
        _LK_FEATURES_LAST=$LK_FEATURES
}
