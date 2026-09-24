#!/usr/bin/env bash
# Copyright (c) 2026 Guy Gibson
# This file is part of bash-utils, licensed under the MIT License.
# See the LICENSE file in the project root for full license text.

# formatted messagining library

# TODO check utils.sh has beeen sourced already
# if ! $( declare -F | grep -q 'declare -f strip_ansi' 2>/dev/null );
#      echo -e "ERROR: formatting.sh: must first source ${BASH_LIB}/lib/utils.sh"
#      exit 1
# fi
# TODO promote MSG_EN_XTRACE/VERBOSE to utils.sh?
# TODO msg_debug_vars <function> ??
# TODO msg_divider_text??: ---- your text here ----
# TODO suppress xtrace globally in here - else it triggers when re-sourced for --color
# TODO bashrc: why sourcing twice leads to if_pipe not defined error

# BEHVAIORAL OPTONS
# =============================================================================
# don't override existing settings - i.e. we may source this file multipe times
# precede mesages with timestamp: [YYYY-mm-dd HH:MM:SS]
[[ ! -v MSG_EN_TIME ]] && export MSG_EN_TIME=$FALSE
[[ ! -v MSG_EN_LEVEL ]] && export MSG_EN_LEVEL=$FALSE
# cache messages, intended to e.g. hide passwords with MSG_EN_CACHE=$FALSE msg_info "your password is: XYZ"
[[ ! -v MSG_EN_CACHE ]] && export MSG_EN_CACHE=$TRUE
# f true, when passed multiple lines, prefix every line with $MSG_* string
[[ ! -v MSG_EN_MULTI ]] && export MSG_EN_MULTI=$TRUE
# add 4 space prefix to all output lines: "    "
[[ ! -v MSG_EN_INDENT ]] && export MSG_EN_INDENT=$FALSE
# enable set -o xtrace/set -x into msg_*() functions
[[ ! -v MSG_EN_XTRACE ]] && export MSG_EN_XTRACE=$FALSE
# enable set -o verbose/set -v into msg_*() functions
[[ ! -v MSG_EN_VERBOSE ]] && export MSG_EN_VERBOSE=$FALSE
# print messages of level <= $MSG_LEVEL
[[ ! -v MSG_LEVEL ]] && export MSG_LEVEL=6
# --color=auto/always/never
# overriden by $NO_COLOR, $DISABLE_<FORMAT/COLO[U]R>
# don't export - may change behaviour of other utilities
[[ ! -v COLOR ]] && COLOR="auto"

# INTERNAL GLOBALS
# =============================================================================
# track length of $MSG_* variables for padding etc
_MSG_LEN=0
# interal
declare -a _MSG_CACHE_GLOBAL=()

# LOAD VAR FROM .ENV
# =============================================================================

# source ./formatting.env - define $(FG|BG|FMT)_* variables
# FG_*  = foreground colour
# BG_*  = background colour
# FMT_* = styles, e.g bold, italics, reversed...
# MSG_* = message formats for e.g INFO, ERROR...
env_path="${BASH_LIB}/etc/formatting.env"
source "$env_path"

# HANDLE COLOR=auto/always/never, NO_COLOR, DISABLE_FORMAT
# =============================================================================

# group by COLOR/STYLE/OTHER for --color/DISABLE_<COLOR/FORMAT> handling
declare -A ANSI_CODES=()
ANSI_CODES[COLOR]="$(grep -E '^(FG|BG)_' "$env_path" | sed 's/=.*//')"
# does NOT include $MSG_*, else remove e.g. "EMERGENCY:" not just FMT_BOLD,FG_RED, FMT_REVERSE
ANSI_CODES[STYLE]="$(grep -E '^(FMT)_' "$env_path" | sed 's/=.*//')"
ANSI_CODES[OTHER]="CLR"

function _disable_ansi_codes() {
    # set specified ANSI_CODES to ""
    local style
    for style in $@; do
        for code in ${ANSI_CODES[$style]}; do
            local -n var_ref="$code"
            declare -g "${!var_ref}"=""
        done
    done
}

function _disable_all_ansi_codes() {
    # disable *all* ANSI formatting if...
    local color_never=$FALSE color_auto=$FALSE
    # if $COLOR is set to a bad value, warn user & force COLOR=never as safest option
    [[ -v COLOR && ! $COLOR =~ auto|always|never ]] && echo -e "${MSG_ERROR}COLOR != auto/always/never, got: $COLOR" | strip_ansi 1>&2 && COLOR="never"
    # --color=never, $NO_COLOR are set
    #   NO_COLOR disabling formatting follows establish unix/shell norms
    [[ $COLOR == "never" || -v NO_COLOUR || -v NO_COLOR ]] && color_never=$TRUE
    # --color=auto && NOT ( fd0 == terminal || fd1 == terminal )
    #   fd0 - background process etc
    #   fd1 - pipe or redirect STDOUT to file etc
    [[ $COLOR == "auto" && (! -t 0 || ! -t 1) ]] && color_auto=$TRUE
    if [[ $color_never == "$TRUE" || $color_auto == "$TRUE" || -v DISABLE_FORMAT ]]; then
        _disable_ansi_codes "COLOR STYLE"
    fi
}

function _disable_color_ansi_codes() {
    # disable only colors if $DISABLE_COLO[U]R
    if [[ -v DISABLE_COLOUR || -v DISABLE_COLOR ]]; then
        _disable_ansi_codes "COLOR"
    fi
}

# apply formatting restrictions via --color, NO_COLOR, DISABLE_<FORMAT/COLOR>
_disable_all_ansi_codes
_disable_color_ansi_codes

# export finalised values
# style = COLOR, STYLE, OTHER
for style in ${!ANSI_CODES[@]}; do
    # code = FG_BLUE, BG_BLUE, FMT_BOLD, MSG_INFO...
    for code in ${ANSI_CODES[$style]}; do
        declare -n var_ref="$code"
        export "${!var_ref}"="${var_ref}"
    done
done
unset style code

# MESSAGE FORMATS
# =============================================================================

# LINUX SYSLOG LEVELS
# Level	Name        Description
# 0	    EMERG	   System is unusable.
# 1	    ALERT	   Immediate action is required.
# 2	    CRIT	   Critical conditions that may cause system failure.
# 3	    ERR	       Error conditions that require attention.
# 4	    WARNING	   Warning conditions that may lead to problems.
# 5	    NOTICE	   Normal but significant events.
# 6	    INFO	   General information about system events.
# 7	    DEBUG	   Detailed information for debugging purposes.
declare -xA MSG_FORMATS=(
    ["MSG_EMERG"]=0
    ["MSG_ALERT"]=1
    ["MSG_CRITICAL"]=2
    ["MSG_ERROR"]=3
    ["MSG_WARN"]=4
    ["MSG_ACTION"]=5
    ["MSG_FAILURE"]=5
    ["MSG_SUCCESS"]=5
    ["MSG_BANNER"]=5
    ["MSG_INFO"]=6
    ["MSG_PRINT"]=6
    ["MSG_WRITE"]=6
    ["MSG_DIVIDER"]=6
    ["MSG_DEBUG"]=7
    ["MSG_DRYRUN"]=7
    ["MSG_TRACE"]=8
)

function _msg_levels() {
    # echo sorted list of all levels in MSG_FORMATS
    # 0 1 2 ...

    local i
    declare -a levels=()
    for i in "${MSG_FORMATS[@]}"; do
        [[ ! ${levels[*]} =~ $i ]] && levels+=("$i")
    done
    echo "${levels[@]}" | tr ' ' \\n | sort -h | tr \\n ' ' | sed 's/ $//'
}

function _msg_levels_max() {
    # report highest MSG_LEVEL
    _msg_levels | sed 's/.* //'
}

function _msg_formats() {
    # echo sorted list of all formats in MSG_FORMATS
    local i
    declare -a formats=()
    for i in "${!MSG_FORMATS[@]}"; do
        [[ ! ${formats[*]} =~ $i ]] && formats+=("$i")
    done
    echo "${formats[@]}" | tr ' ' \\n | sort -h | tr \\n ' '
}

function _msg_format2level() {
    # swap e.g. [MSG_]WRITE -> 6
    # INPUT -> OUTPUT; RETURN: 0/1
    # write, WRITE, MSG_WRITE -> 6; ret: 0
    # foo -> foo; ret: 0
    # 8 -> 8; ret 0
    # 12 -> 12; ret 1

    # keep msg_* internals out of xtrace/verbose logs, unless enabled
    [[ -o xtrace && $MSG_EN_XTRACE == "$FALSE" ]] && set +x && trap 'set -x' RETURN
    [[ -o verbose && $MSG_EN_VERBOSE == "$FALSE" ]] && set +v && trap 'set -v' RETURN

    local in="$1" _in="$1" level format
    # if input is a valid integer, return immediately
    if [[ $in =~ ^[0-9]+$ ]]; then
        echo "$_in"
        [[ ! $(_msg_levels) =~ $in ]] && return 1 || return 0
    fi
    # otherwise, format -> level
    # if required, format input: uppercase & prefix MSG_
    [[ ! $_in =~ [A-Z]+ ]] && _in="${_in^^}"
    [[ ! $_in =~ ^MSG_ ]] && _in="MSG_${_in}"
    for format in "${!MSG_FORMATS[@]}"; do
        level="${MSG_FORMATS[$format]}"
        # e.g. WRITE =~ WRITE$
        [[ $format =~ $_in$ ]] && echo "$level" && return 0
    done
    echo "$in"
    return 1
}

function _msg_level2formats() {
    # swap e.g. 7 -> "MSG_DEBUG MSG_DRYRUN"
    # INPUT -> OUTPUT; RETURN: 0/1
    # 3 -> MSG_ERROR; ret: 0
    # 6 -> MSG_INFO MSG_PRINT MSG_WRITE; ret: 0
    # 8 -> 8; ret 0
    # 12 -> 12; ret 1
    # write, WRITE, MSG_WRITE -> write, WRITE, MSG_WRITE; ret: 0
    # foo -> foo; ret: 1

    # keep msg_* internals out of xtrace/verbose logs, unless enabled
    [[ -o xtrace && $MSG_EN_XTRACE == "$FALSE" ]] && set +x && trap 'set -x' RETURN
    [[ -o verbose && $MSG_EN_VERBOSE == "$FALSE" ]] && set +v && trap 'set -v' RETURN

    local in="$1" _in="$1" level format="" formats=""
    # if $1 is a valid format, return immediately
    if [[ $in =~ [a-zA-Z]+ ]]; then
        # uppercase
        [[ ! $_in =~ [A-Z]+ ]] && _in="${_in^^}"
        # prefix MSG_
        [[ ! $_in =~ ^MSG_ ]] && _in="MSG_${_in}"
        # matching formats are returned as-is
        [[ ${!MSG_FORMATS[*]} =~ (^| )${_in}( |$) ]] && echo "$in" && return 0
    fi
    # otherwise, level -> formats
    for format in "${!MSG_FORMATS[@]}"; do
        level="${MSG_FORMATS[$format]}"
        [[ $_in == "$level" ]] && formats+=" $format"
    done
    if [[ -z $formats ]]; then
        # for no matches, return input as-is
        echo "$in"
        return 1
    else
        echo "${formats/ /}"
        return 0
    fi
}

# record length of message strings
function _msg_len() {
    local max_len=0 raw=""
    for format in "${!MSG_FORMATS[@]}"; do
        local -n var_ref="$format"
        # don't count 0-length ANSI escape codes
        raw="$(echo -e "$var_ref" | strip_ansi)"
        [[ ${#raw} -gt $max_len ]] && max_len="${#raw}"
    done
    echo "$max_len"
}
export _MSG_LEN="$(_msg_len)"

# CACHING
# =============================================================================

# for each level in $MSG_FORMATS[@], create arrays separate $_MSG_CACHE_<N>[]
# plus $_MSG_CACHE_GLOBAL[@] for all messages
if [[ ! -v _MSG_CACHE_GLOBAL ]]; then
    for i in "${MSG_FORMATS[@]}" GLOBAL; do
        # TODO x -> g
        declare -a "_MSG_CACHE_${i}"
    done
fi

function msg_cache_reset() {
    # for each of $_MSG_CACHE_*[@] arrays, empty them
    # TODO allow to empty specific cache(s)?

    # keep msg_* internals out of xtrace/verbose logs, unless enabled
    [[ -o xtrace && $MSG_EN_XTRACE == "$FALSE" ]] && set +x && trap 'set -x' RETURN
    [[ -o verbose && $MSG_EN_VERBOSE == "$FALSE" ]] && set +v && trap 'set -v' RETURN

    local i
    for i in "${MSG_FORMATS[@]}" GLOBAL; do
        local -n cache="_MSG_CACHE_${i}"
        cache=()
    done
}

function _msg_cache_store() {
    # store all messages in $_MSG_CACHE_* array
    local level="$1"
    local msg="$2"
    # store in level-based array
    # e.g. _MSG_CACHE_5+=("ACTION : ...")
    local -n cache="_MSG_CACHE_${level}"
    cache+=("$msg")
    # always add to global cache
    _MSG_CACHE_GLOBAL+=("${level}@$msg")
}

function msg_cache_dump() {
    # dump all messages in $_MSG_CACHE_GLOBAL array <= $max_level
    # msg_cache_dump [MAX] [MIN]
    # [$1] = check max level, lowest severity [$MSG_LEVEL]
    #   e.g. error, MSG_ERROR, 3
    # [$2] = check min level, highest severity [0]
    #   e.g. alert, ALERT, 1

    # keep msg_* internals out of xtrace/verbose logs, unless enabled
    [[ -o xtrace && $MSG_EN_XTRACE == "$FALSE" ]] && set +x && trap 'set -x' RETURN
    [[ -o verbose && $MSG_EN_VERBOSE == "$FALSE" ]] && set +v && trap 'set -v' RETURN

    local max_level="$MSG_LEVEL" min_level=0 i in_max_level in_min_level
    # max_level input may be a string, convert to equiv int
    if [[ $# -gt 0 ]]; then
        # e.g. write, WRITE, MSG_WRITE -> 6
        in_max_level="$(_msg_format2level "$1")"
        [[ ! $? == 0 ]] && msg_error "_msg_cache_dump(): invalid max_level: ${in_max_level}" 2>&1 && return 1
        max_level="$in_max_level"
    fi
    # min_level input may be a string, convert to equiv int
    if [[ $# -gt 1 ]]; then
        # e.g. write, WRITE, MSG_WRITE -> 6
        in_min_level="$(_msg_format2level "$2")"
        [[ ! $? == 0 ]] && msg_error "_msg_cache_dump(): invalid min_level: ${in_min_level}" 2>&1 && return 1
        min_level="$in_min_level"
    fi
    # validate min < max
    [[ $min_level -gt max_level ]] && msg_error "_msg_cache_dump(): min_level > max_level: ${min_level}, ${max_level}" 2>&1 && return 1
    # dump
    for i in "${_MSG_CACHE_GLOBAL[@]}"; do
        # format = "${level}@${msg}"
        # remove all chars following first @ char
        local level="${i%%@*}"
        # remove initial 'level@'
        local msg="${i#"${level}"@}"
        [[ $level -ge $min_level && $level -le $max_level ]] && printf -- "$msg"
    done
}

function msg_cache_check() {
    # return 0 if any cached message satisfies: $min_level <= $level <= $max_level
    # msg_cache_check [MAX] [MIN]
    # [$1] = check max level, lowest severity [$MSG_LEVEL]
    #   e.g. error, MSG_ERROR, 3
    # [$2] = check min level, highest severity [0]
    #   e.g. alert, ALERT, 1

    # keep msg_* internals out of xtrace/verbose logs, unless enabled
    [[ -o xtrace && $MSG_EN_XTRACE == "$FALSE" ]] && set +x && trap 'set -x' RETURN
    [[ -o verbose && $MSG_EN_VERBOSE == "$FALSE" ]] && set +v && trap 'set -v' RETURN

    local max_level="$MSG_LEVEL" min_level=0 i in_max_level in_min_level
    if [[ $# -gt 0 ]]; then
        # e.g. write, WRITE, MSG_WRITE -> 6
        in_max_level="$(_msg_format2level "$1")"
        [[ ! $? == 0 ]] && msg_error "_msg_cache_check(): invalid max_level: ${in_max_level}" 2>&1 && return 1
        max_level="$in_max_level"
    fi
    if [[ $# -gt 1 ]]; then
        # e.g. write, WRITE, MSG_WRITE -> 6
        in_min_level="$(_msg_format2level "$2")"
        [[ ! $? == 0 ]] && msg_error "_msg_cache_check(): invalid min_level: ${in_min_level}" 2>&1 && return 1
        min_level="$in_min_level"
    fi
    # validate min < max
    [[ $min_level -gt $max_level ]] && msg_error "_msg_cache_check(): min_level > max_level: ${min_level}, ${max_level}" 2>&1 && return 1
    # return on first hit - don't need a count of matches
    for i in "${_MSG_CACHE_GLOBAL[@]}"; do
        # format = "${level}@${msg}"
        # remove all chars following first @ char
        local level="${i%%@*}"
        # remove initial 'level@'
        local msg="${i#"${level}"@}"
        [[ $level -ge $min_level && $level -le $max_level ]] && return 0
    done
    return 1
}

# MESSAGING
# =============================================================================

function _msg_generic() {
    local format="$1" level i
    declare -a msgs=() sub_msgs=()
    shift
    # skip DEBUG and TRACE unless enabled
    # [[ $format == MSG_DEBUG && $DEBUG == "$FALSE" ]] && return 0
    # [[ $format == MSG_TRACE && $TRACE == "$FALSE" ]] && return 0
    level="${MSG_FORMATS[$format]}"
    # skip if level > $MSG_LEVEL, $DEBUG/TRACE override
    # e.g. MSG_INFO=5, MSG_LEVEL=4 -> skip
    # e.g. MSG_INFO=5, MSG_LEVEL=7 -> print
    if [[ $MSG_LEVEL -lt $level ]]; then
        # non-DEBUG/TRACE, go straight to skip
        if [[ ! $format =~ MSG_(DEBUG|TRACE) ]]; then
            return 0
        # DEBUG/TRACE override if $TRUE
        elif [[ $format == MSG_DEBUG && $DEBUG == "$FALSE" ]]; then
            return 0
        elif [[ $format == MSG_TRACE && $TRACE == "$FALSE" ]]; then
            return 0
        fi
    fi
    # format to allow $MSG_* prefix on each line, else only on first line
    if [[ $MSG_EN_MULTI == "$TRUE" && $(wc -l <<<"$@") -gt 1 ]]; then
        for i in "$@"; do
            readarray -t sub_msgs <<<"$i"
            msgs+=("${sub_msgs[@]}")
        done
    else
        msgs+=("$@")
    fi
    for i in "${msgs[@]}"; do
        local msg_str=""
        # timestamp
        [[ $MSG_EN_TIME == "$TRUE" ]] && msg_str+="${FMT_DIM}[$(date '+%Y-%m-%d-%H:%M:%S')]${FMT_CLR} "
        # level
        [[ $MSG_EN_LEVEL == "$TRUE" ]] && msg_str+="${FMT_DIM}[${MSG_FORMATS[$format]}]${FMT_CLR} "
        # "EMERGENCY: " with REVERSE & RED etc
        [[ $format == MSB_BANNER ]] && declare -p $format ${!format}
        msg_str+="${!format}"
        # add leading 4 spaces - for bullets etc: "    "
        [[ $MSG_EN_INDENT == "$TRUE" ]] && msg_str+="    "
        # $msg within printf styling string to support ANSI codes in messages
        msg_str+="${i}"
        # always close formatting & append newline
        msg_str+="${FMT_CLR}\\n"
        [[ $MSG_EN_CACHE == "$TRUE" ]] && _msg_cache_store "$level" "$msg_str"
        # skip STDOUT/STDERR
        if [[ $MSG_LOG_ONLY == "$TRUE" && ! -z $LOGFILE ]]; then
            # -- required to separate format string & printf options
            # else fail on msg_str="-..."
            printf -- "$msg_str" >"$LOGFILE"
        # debug/trace -> STDERR
        elif [[ $format =~ MSG_(DEBUG|DRYRUN|TRACE) ]]; then
            # else fail on msg_str="-..."
            printf -- "$msg_str" 1>&2
        # else STDOUT
        else
            printf -- "$msg_str"
        fi
    done
    return 0
}

# define e.g. msg_info() for each MSG_FORMAT
for msg_format in "${!MSG_FORMATS[@]}"; do
    eval "function ${msg_format,,}(){

        # keep msg_* internals out of xtrace/verbose logs, unless enabled
        [[ -o xtrace && \$MSG_EN_XTRACE == \"\$FALSE\" ]] && set +x && trap 'set -x' RETURN
        [[ -o verbose && \$MSG_EN_VERBOSE == \"\$FALSE\" ]] && set +v && trap 'set -v' RETURN

        if if_pipe; then
            _msg_generic \"${msg_format}\" \"\$(cat -)\"
        else
            _msg_generic \"${msg_format}\" \"\$@\"
        fi
    }"
done
unset msg_format

# BANNER
# =============================================================================

function msg_banner() {
    # print centered message surrounded by formatted box
    # $1  - message string
    #
    # ========================================================
    # =               your message here                      =
    # ========================================================
    #

    # keep msg_* internals out of xtrace/verbose logs, unless enabled
    [[ -o xtrace && $MSG_EN_XTRACE == "$FALSE" ]] && set +x && trap 'set -x' RETURN
    [[ -o verbose && $MSG_EN_VERBOSE == "$FALSE" ]] && set +v && trap 'set -v' RETURN

    local term_width=0 center_width=0
    local head_tail lines_folded i
    declare -a lines

    # set -x
    # output across fill terminal width, folding long lines
    term_width="$(get_term_width)"
    center_width="$((term_width - 3))"
    max_width="$((term_width - 6))"

    # split input message on newlines & limit to screen width
    lines_folded="$(fold -w "$max_width" <<<"$1")"
    readarray -t lines <<<"$lines_folded"

    # setup header/footer
    head_tail="${FMT_BANNER}$(MSG_EN_CACHE=$FALSE msg_divider)"

    # header
    _msg_generic "MSG_BANNER" ""
    _msg_generic "MSG_BANNER" "${head_tail}"
    # body
    for line in "${lines[@]}"; do
        # override pdding to use entire scren width
        line_center="$(center_text "$line" "$center_width" "$center_width")"
        line="$(printf "${FMT_BANNER}= %s =${FMT_CLR}" "$line_center")"
        _msg_generic "MSG_BANNER" "$line"
    done
    # tail
    _msg_generic "MSG_BANNER" "${head_tail}"
    _msg_generic "MSG_BANNER" ""
}

function msg_divider() {
    # print a divider the widht of the screen
    # [$1] - override character
    # [$2] - override width = terminal width

    # keep msg_* internals out of xtrace/verbose logs, unless enabled
    [[ -o xtrace && $MSG_EN_XTRACE == "$FALSE" ]] && set +x && trap 'set -x' RETURN
    [[ -o verbose && $MSG_EN_VERBOSE == "$FALSE" ]] && set +v && trap 'set -v' RETURN

    local max_width=0 term_width char="=" msg=""
    [[ $# -gt 0 ]] && char="$1"
    [[ $# -gt 1 ]] && max_width="$2"
    width="$(get_term_width)"
    [[ ! $max_width == 0 && $max_width -lt $width ]] && width=$max_width

    msg="$(printf -- "${char}%.0s" $(seq 1 "$width"))"
    _msg_generic "MSG_DIVIDER" "$msg"
}

# DEBUGGING
# =============================================================================

function _msg_print_vars() {
    # use declare -p to pretty-print variables
    # value if not defines: IS_NOT_SET

    # first arg is format, remainder are variable names
    # so shift here to allow $@ to iterate
    local format="$1"
    shift
    local n var regex max_len_in=0 max_len_max=0
    n="$(wc -w <<<"$@")"
    # e.g. terminal width - len("INFO   : ")
    max_len_max="$(($(get_term_width) - _MSG_LEN))"
    local declaration=""
    declare -A declarations=()

    for var in "$@"; do
        # get max_len_in of all variables
        local -n var_ref="$var"
        [[ ${#var_ref} -gt $max_len_in ]] && max_len_in="${#var_ref}"
        # fallback string if variable is not set
        if ! declaration="$(declare -p "$var" 2>/dev/null)"; then
            # NB: not set && declared Associative arrays with no elements
            declarations[$var]="declare -- $var=${FMT_DIM}>>IS_NOT_SET<<"
        # set output strings for variable
        else
            # pretty-print arrays with each element on a newline
            if grep -q "^declare -[b-zB-Z]*[aA][b-zB-Z]*" <<<"$declaration"; then
                # insert newlines precedeing first, middle & final elements
                regex="s@^declare -[b-zB-Z]*[aA][b-zB-Z]* ${var}=\(@&\n\t@;"
                regex+="s@ (\[[a-zA-Z0-9_]+\]=)@\n\t\1@g;"
                regex+="s@\)"'$'"@\n) \\${FMT_DIM}${var}@g;"
                declaration="$(sed -E "$regex" <<<"$declaration")"
            fi
            declarations[$var]="$declaration"
        fi
    done
    # 12 + variable length: "declare -- <VAR>="
    [[ $max_len_in -gt 0 ]] && max_len_in="$((max_len_in + 12))"

    # output strings
    # header/footer if multiple variables, or >1.5x terminal width
    [[ $n -gt 1 || $max_len_in -gt $max_len_max ]] && "msg_${format}" "${FMT_DIM}${format^^}_VARS: START >> ====================================================="
    for var in $@; do
        "msg_${format}" "${declarations[$var]}"
    done
    [[ $n -gt 1 || $max_len_in -gt $max_len_max ]] && "msg_${format}" "${FMT_DIM}${format^^}_VARS: << END ====================================================="
}

function msg_debug_vars() {
    # if $DEBUG, pretty-print variable values

    # keep msg_* internals out of xtrace/verbose logs, unless enabled
    [[ -o xtrace && $MSG_EN_XTRACE == "$FALSE" ]] && set +x && trap 'set -x' RETURN
    [[ -o verbose && $MSG_EN_VERBOSE == "$FALSE" ]] && set +v && trap 'set -v' RETURN

    _msg_print_vars "debug" "$@"
}
function msg_trace_vars() {
    # if $TRACE, pretty-print variable values

    # keep msg_* internals out of xtrace/verbose logs, unless enabled
    [[ -o xtrace && $MSG_EN_XTRACE == "$FALSE" ]] && set +x && trap 'set -x' RETURN
    [[ -o verbose && $MSG_EN_VERBOSE == "$FALSE" ]] && set +v && trap 'set -v' RETURN

    _msg_print_vars "trace" "$@"
}
