#!/usr/bin/env bash
# Copyright (c) 2026 Guy Gibson
# This file is part of bash-utils, licensed under the MIT License.
# See the LICENSE file in the project root for full license text.

# TODO explain xtrace trap
# TODO advice on formatting for accessibility

[[ ! -v BASH_LIB ]] && BASH_LIB="$(dirname ${0})/.."

LOREM="Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor"

linux_log_levels="""${FMT_BOLD}Level	Name       Description${FMT_CLR}
0	    EMERG	   System is unusable.
1	    ALERT	   Immediate action is required.
2	    CRIT	   Critical conditions that may cause system failure.
3	    ERR	       Error conditions that require attention.
4	    WARNING	   Warning conditions that may lead to problems.
5	    NOTICE	   Normal but significant events.
6	    INFO	   General information about system events.
7	    DEBUG	   Detailed information for debugging purposes."""

#
function sep() {
    # repeated block to separate code previews & output
    echo
    echo -e "${FMT_DIM}$(msg_divider - 35)${FMT_CLR}"
    echo
}

function hint() {
    # display the code used in the demo
    local i
    for i in "$@"; do
        echo -e "${FMT_DIM}${i}${FMT_CLR}"
    done
}

function run_demo() {
    (
        # # # re-enable cache before demo
        # MSG_EN_CACHE=$TRUE
        source "${BASH_LIB}/lib/utils.sh"
        "$1"
    )
}

function loop_demos() {
    # in a loop, list available demos & prompt & run user's selected demo
    source "${BASH_LIB}/lib/utils.sh"
    # interactively prompt user with available demo_table
    local fn_str fn_table fn_max=0 fn_num=0 response
    declare -a fn_list=()

    function _print_table() {
        echo "Please select a demo to run:"
        echo
        # always rebuild as fn_list will be updated on each loop
        local i j
        fn_table=""
        for i in "${!fn_list[@]}"; do
            # start from 1, not 0
            j=$((i + 1))
            # TODO filter out ^_* functions?
            fn_table+=$'\n'"$j) ${fn_list[$i]}"
        done
        # output
        echo -e "$fn_table" | column -c "$(tput cols)"
    }

    function _prompt_user() {
        echo
        local valid="(1-${fn_max}, quit)"
        read -r -p "Enter a demo number or quit ${valid}: " response
        # quit, Quit, no, No etc -> exit, done
        if [[ $response =~ ^[qQnN] ]]; then
            echo "quitting"
            exit 0
        # unrecognised string
        elif [[ ! $response =~ [0-9]+ ]]; then
            msg_error "invalid response, expected ${valid}, got: $response"
            return 1
        # valid response
        elif [[ $response -le $fn_max && $response -ne 0 ]]; then
            fn_num=$((response - 1))
            return 0
        # invalid integer
        else
            msg_error "invalid response, expected ${valid}, got: $response"
            return 1
        fi
    }

    function _run_demo() {
        local fn="${fn_list[$fn_num]}"
        echo
        echo "Now running: $response - ${fn}()"
        echo "=================================================="
        echo
        # re-enable cache before demo
        MSG_EN_CACHE=$TRUE
        # run demo in sub-shell to preserve clean shell
        (
            source "${BASH_LIB}/lib/utils.sh"
            "demo_$fn"
        )
        # re-enable cache before demo
        MSG_EN_CACHE=$FALSE
        MSG_BANNER="${BG_RED}" msg_banner "end of: $fn"

        echo
        echo "=================================================="
        echo "End of: ${fn}"
        echo
        # apply dim & strikethrough to completed demos
        fn_list[$fn_num]="${FMT_DIM}${FMT_STRIKE}${fn_list[$fn_num]}${FMT_CLR}"
    }

    # gather a list of all available functions,
    # ignoring ^_* and demo_basics_all which always runs first
    fn_str="$(
        grep "^function.*demo" "$0" |
            sed 's/function //;s/(.*//;/^$/d;s/demo_//' |
            sort -h |
            grep -v "^_" |
            grep -v "demo_basics_all"
    )"
    readarray -t fn_list <<<"$fn_str"
    fn_max=${#fn_list[@]}

    # don't pollute the cache before running a demo
    MSG_EN_CACHE="$FALSE"

    # enter prompt loop
    while true; do
        _print_table
        while true; do
            if _prompt_user; then
                break
            fi
        done
        _run_demo
    done
}

# ==============================================
# DEMO FUNCTIONS
# ==============================================

# TODO expand/improve
function demo_basics_all() {
    # print "<level>: <name>" for all defined MSG_FORMATS, sorted by levels
    msg_banner "demo all basic msg_*() functions"
    msg_info "The following functions are provided to output text:"
    echo
    local i format level func fn_call
    declare -a fn_calls
    declare -A format_text=(
        ["MSG_EMERG"]="most significant error - host is unusable"
        ["MSG_ALERT"]="very significant error"
        ["MSG_CRITICAL"]="significant error"
        ["MSG_ERROR"]="non-recoverable event - bad permissions, missing args"
        ["MSG_WARN"]="recoverable event - target already exists, unexpected & ignored input"
        ["MSG_ACTION"]="user should take specified action"
        ["MSG_FAILURE"]="script or stage failed, report issues with \`msg_cache_dump error\`"
        ["MSG_SUCCESS"]="script or stage passed"
        ["MSG_INFO"]="general information - now attempting to X, script completed Y"
        ["MSG_PRINT"]="${FMT_BOLD}${FMT_UNDER}no formatting applied${FMT_CLR}, intended to replace echo/printf with adding caching"
        [MSG_WRITE]="similar to MSG_PRINT, but inclues prefix: \"${MSG_WRITE}\""
        [MSG_BANNER]="--see below--"
        [MSG_DIVIDER]="--see below--"
        ["MSG_DEBUG"]="info for debug, if [[ \$DEBUG == \$TRUE ]]"
        ["MSG_DRYRUN"]="expanded command in runcmd, if [[ \$DEBUG == \$TRUE ]]"
        ["MSG_TRACE"]="more info for debug, raw cmd/api outputs etc, if [[ \$TRACE == \$TRUE ]]"
    )

    hint "\`\`\`"
    # dump calls
    for i in $(seq 0 "$(_msg_levels_max)"); do
        for format in "${!MSG_FORMATS[@]}"; do
            # skip banner & divider - leave to the end
            [[ $format =~ ^MSG_(BANNER|DIVIDER) ]] && continue
            level="${MSG_FORMATS[$format]}"
            if [[ $i == "$level" ]]; then
                func="${format,,}"
                fn_call="${func} '${level}: ${format} - ${format_text[$format]}'"
                hint "\$ $fn_call"
                # add fn to be called later
                fn_calls+=("$fn_call")
            fi
        done
    done
    hint "\$ msg_banner '5: MSG_BANNER - banners act as headings'"
    hint "\$ msg_print '6: MSG_DIVIDER - dividers add a line across the terminal'"
    hint "\$ msg_divider"
    hint "\`\`\`"

    # actually call commands
    for i in "${fn_calls[@]}"; do
        # ++MSG_LEVEL to force all to be output
        MSG_LEVEL=8 eval "$i"
    done
    msg_banner '5: MSG_BANNER - banners act as headings'
    msg_print '6: MSG_DIVIDER - dividers add a line across the terminal'
    msg_divider
    sep
}

function _demo_format2level_level2formats() {
    source "${BASH_LIB}/lib/utils.sh"
    msg_banner "_msg_format2level & _msg_level2formats"
    msg_info "INPUT: OUTPUT, RETURN"
    msg_info "${FMT_BOLD}${FMT_ITALIC}_msg_format2level"
    msg_info "expect \$?==0"
    echo "info    : $(_msg_format2level info), $?"
    echo "INFO    : $(_msg_format2level INFO), $?"
    echo "MSG_INFO: $(_msg_format2level MSG_INFO), $?"
    echo "3       : $(_msg_format2level 3), $?"
    echo "6       : $(_msg_format2level 6), $?"
    msg_info "expect \$?==1"
    echo "foo     : $(_msg_format2level foo), $?"
    echo "12      : $(_msg_format2level 12), $?"
    echo
    msg_info "_msg_level2formats"
    msg_info "expect \$?==0"
    echo "info    : $(_msg_level2formats info), $?"
    echo "INFO    : $(_msg_level2formats INFO), $?"
    echo "MSG_INFO: $(_msg_level2formats MSG_INFO), $?"
    echo "3       : $(_msg_level2formats 3), $?"
    echo "6       : $(_msg_level2formats 6), $?"
    msg_info "expect \$?==1"
    echo "foo     : $(_msg_level2formats foo), $?"
    echo "12      : $(_msg_level2formats 12), $?"
}

function demo_cache_dump() {
    source "${BASH_LIB}/lib/utils.sh"
    MSG_EN_CACHE=$FALSE msg_banner "dumping cache"
    MSG_EN_CACHE=$FALSE msg_print "msg_cache_dump() & msg_cache_reset() can be used to repeat cached messages & manage the cache..." | center_text
    sep

    MSG_EN_CACHE=$FALSE msg_info "populate the cache (skip cache for this message)"
    echo
    hint '```'
    hint "\$ msg_alert 'alert text'"
    hint "\$ msg_error 'error text'"
    hint "\$ msg_warn 'warning text'"
    hint "\$ msg_info 'info text'"
    hint '```'
    msg_alert "alert text"
    msg_error "error text"
    msg_warn "warning text"
    msg_info "info text"
    sep

    MSG_EN_CACHE=$FALSE msg_info "now dump the cache, previous messages will be repeated"
    MSG_EN_CACHE=$FALSE msg_info "note the missing 'INFO: this is printed but NOT cached!!'"
    echo
    hint "\$ msg_cache_dump"
    msg_cache_dump
    sep

    MSG_EN_CACHE=$FALSE msg_info 'use MSG_EN_CACHE="$FALSE" to (temporarily) disable caching'
    MSG_EN_CACHE=$FALSE msg_info "note, output is same as last dump, despite new INFO message"
    hint '```'
    hint "\$ MSG_EN_CACHE=\$FALSE msg_info 'this is printed but NOT cached!!'"
    hint '$ msg_cache_dump'
    hint '```'
    MSG_EN_CACHE=$FALSE msg_info "this is printed but NOT cached!!"
    msg_cache_dump
    sep

    MSG_EN_CACHE=$FALSE msg_info "by default, all messages except DEBUG/TRACE are printed"
    MSG_EN_CACHE=$FALSE msg_info "we can change specify the desired levels: only for level == 3 - i.e. error"
    echo
    hint "\$ msg_cache_dump 3 3"
    msg_cache_dump 3 3
    MSG_EN_CACHE=$FALSE msg_info "again, using strings 'error', 'MSG_ERROR' instead of level '3'"
    echo
    hint "\$ msg_cache_dump error MSG_ERROR"
    msg_cache_dump error MSG_ERROR
    sep

    msg_info "the cache can be reset - only the new warning message will be dumped below..."
    echo
    hint '```'
    hint "\$ msg_cache_reset"
    hint "\$ msg_cache_dump"
    hint "\$ msg_warn 'warning text'"
    hint "\$ echo"
    hint "\$ msg_cache_dump"
    hint '```'
    msg_cache_reset
    msg_cache_dump
    msg_warn "warning text"
    echo
    msg_cache_dump
    sep
}

function demo_cache_check() {
    source "${BASH_LIB}/lib/utils.sh"
    MSG_EN_CACHE=$FALSE msg_banner "msg_cache_check"
    MSG_EN_CACHE=$FALSE msg_info "populate the cache"
    echo "msg_alert 'alert text'"
    echo "msg_error 'error text'"
    echo "msg_warn 'warning text'"
    echo "msg_info 'info text'"
    sep
    msg_alert "alert text"
    msg_error "error text"
    msg_warn "warning text"
    msg_info "info text"

    sep
    MSG_EN_CACHE=$FALSE msg_info "confirm cache is populated"
    echo "DEBUG=$TRUE msg_debug_vars MSG_LEVEL _MSG_CACHE_GLOBAL"
    echo "msg_cache_dump"
    sep
    DEBUG=$TRUE MSG_EN_CACHE=$FALSE msg_debug_vars MSG_LEVEL _MSG_CACHE_GLOBAL
    msg_cache_dump
    sep

    msg_info "default msg_cache_check 0-\$MSG_LEVEL ($MSG_LEVEL)"
    msg_info "cache is poulated with levels 1-6 (ALERT-INFO) - will return 0"
    msg_info "can manually specify level with integer 0-8 or string e.g. error"
    sep
    msg_cache_check
    echo "0-\$MSG_LEVEL (6): 'msg_cache_check': $?"
    msg_cache_check 3
    echo "0-3             : 'msg_cache_check 3': $?"
    msg_cache_check error
    echo "0-3             : 'msg_cache_check error': $?"
    sep
    msg_info "now we can check for <1 and >7 - will return 1"
    sep
    msg_cache_check emerg emerg
    echo "0-0             : 'msg_cache_check emergency alert': $?"
    msg_cache_check 8 7
    echo "7-8             : 'msg_cache_check 8 7': $?"
    sep
}

function demo_banner_divider() {
    msg_print "we can use msg_banner() to print very clear 'headings' and msg_divider() to add a line across the terminal"
    sep

    msg_info "typically banners have a short single-line message"
    hint "\$ msg_banner 'example banner text'"
    msg_banner 'example banner text'
    sep

    msg_info "as we set a background/reverse and add surrounding ===, this also works well for COLOR=none or after strip_ansi() in logfiles"
    echo
    hint "\$ (COLOR='never'; source formatting.sh; msg_banner 'example banner text')"
    (
        COLOR="never"
        source "${BASH_LIB}/lib/formatting.sh"
        msg_banner 'example banner text'
    )
    sep

    msg_info "very long lines are split into multiple lines"
    echo
    hint "\$ msg_banner 'this was a very very long line which is wider than the width of the screen in order to test unreasonably long lines'"
    msg_banner 'this was a very very long line which is wider than the width of the screen in order to test unreasonably long lines'
    sep

    msg_info "dividers are easy to customise"
    hint '```'
    hint "msg_divider"
    hint "msg_divider '-'"
    hint "msg_divider '^' 5"
    hint '```'
    msg_divider
    msg_divider '-'
    msg_divider '^' 5
}

function demo_debug_vars() {
    msg_banner "demonstrate debugging variables"
    msg_info "enable DEBUG/TRACE, equivalent to --debug/trace"
    hint '$ DEBUG="$TRUE"'
    hint '$ TRACE="$TRUE"'
    DEBUG=$TRUE
    TRACE=$TRUE
    echo

    msg_info "set some variables to inspect"
    hint '```'
    hint '$ a="$TRUE"'
    hint '$ b="$FALSE"'
    hint '$ long="this is a very very long variable value which is wider than the width of the screen in order to demonstrate unreasonably long values"'
    hint '$ declare -a c=("guy" "was" "here")'
    hint '$ declare -A d=([guy]="engineer" [dude]="scientist")'
    hint '```'
    a=$TRUE
    b=$FALSE
    long="this is a very very long variable value which is wider than the width of the screen in order to demonstrate unreasonably long values"
    declare -a c=("guy" "was" "here")
    declare -A d=([guy]="engineer" [dude]="scientist")
    sep

    msg_info "inspect a single variable ~== \`declare -p output\`"
    hint "\$ msg_debug_vars 'a'"
    msg_debug_vars a
    sep

    msg_info "inspect multiple variables or a very long variable, either adds START >>/<< END"
    echo
    msg_info "2 variables"
    hint '$ msg_debug_vars a b'
    msg_debug_vars a b
    echo
    msg_info "variable length > terminal width"
    hint '$ msg_debug_vars long'
    msg_debug_vars long
    sep

    msg_info "arrays are pretty-printed, one key-value pair per line"
    hint '$ msg_debug_vars c d'
    msg_debug_vars c d
    sep

    msg_info "variables which have not been set indicated with ${FMT_DIM}>>IS_NOT_SET<<"
    hint '$ msg_debug_vars e'
    msg_debug_vars e
    sep

    msg_info "msg_trace_vars() is also available, same functionality"
    hint '$ msg_debug_vars a'
    hint '$ msg_trace_vars a'
    msg_debug_vars a
    msg_trace_vars a
    sep

    return 0
}

function demo_multiple_strings() {
    source "${BASH_LIB}/lib/utils.sh"
    msg_banner "passing multiple strings to msg_*()"

    msg_info "multiple strings can be passed to msg_* functions, each is printed on a newline"
    echo
    hint '$ msg_info "guy was here" "lucie too"'
    msg_info "guy was here" "lucie too"
    sep

    msg_info "newlines within the inputs are respected"
    echo
    hint '$ msg_info "horrible thing one a"$'\n'"one b" "horrible thing two a"$'\n'"two b" "horrible thing three"'
    # each newline -> separate INFO: message, 5 lines
    msg_info "horrible thing one a"$'\n'"one b" "horrible thing two a"$'\n'"two b" "horrible thing three"
    sep

    msg_info "MSG_EN_MULTI=\$FALSE can be used to disable this splitting on newlines"
    echo
    hint '$ MSG_EN_MULTI=$FALSE msg_info "horrible thing one a"$'\n'"one b" "horrible thing two a"$'\n'"two b" "horrible thing three"'
    MSG_EN_MULTI=$FALSE msg_info "horrible thing one a"$'\n'"one b" "horrible thing two a"$'\n'"two b" "horrible thing three"
    sep
}

function demo_pipe() {
    source "${BASH_LIB}/lib/utils.sh"
    msg_banner "msg_*() functions accept input from pipes!"
    msg_info "like so:"
    echo
    hint '$ echo "single line" | msg_info'
    echo "single line" | msg_info
    sep

    msg_info "two lines, preserving formatting"
    echo
    hint '$ printf "${FG_BLUE}%s${FMT_CLR}\\n" "line 1" "line 2" | msg_info'
    printf "${FG_BLUE}%s${FMT_CLR}\n" "line 1" "line 2" | msg_info
    sep

    msg_info "last example, with a real command"
    echo
    hint '$ ls -l "$HOME" | msg_write'
    ls -l "$HOME" | msg_write
    sep
}

function demo_strip_ansi() {
    msg_banner "strip_ansi() to remove ~all ANSI codes"
    msg_info "strip_ansi removes all ANSI codes relevant to formatting and works quite flexibly"
    msg_info "this should be used when manually redirecting msg_* output to a logfile"
    echo

    msg_info "setup a heavily-formatted test string & show raw ANSI codes"
    hint '```'
    hint '$ fancy="${FMT_BOLD}${FG_RED}lorem ${BG_WHITE}ipsum${BG_DEFAULT} ${FG_GREEN}${FMT_ITALIC}dolor"'
    hint '$ foo="$(msg_info "$fancy")"'
    hint '$ echo "$fancy"'
    hint '$ echo -e "$foo"'
    hint '```'
    fancy="${FMT_BOLD}${FG_RED}lorem ${BG_WHITE}ipsum${BG_DEFAULT} ${FG_GREEN}${FMT_ITALIC}dolor"
    foo="$(msg_info "$fancy")"
    echo "$fancy"
    echo "$foo"
    sep

    msg_info "pass \$foo through strip_ansi(), removing all formatting"
    echo
    hint '```'
    hint '$ strip_ansi "$foo"'
    hint '$ echo "$foo" | strip_ansi'
    hint '```'
    strip_ansi "$foo"
    echo "$foo" | strip_ansi
    sep

}

# TODO complete/prettify for users
# TODO copy from current implementation too
function _demo_parse_args() {

    function _parse_args() {
        # collect positional arguments, i.e. those without a leading ^-/--<arg>
        declare -ga POSITIONALS=()

        echo "\$* pre: $*" # DEBUG

        # pre-process to support e.g. --color=never format
        pre_parse_args "$@"
        # swap args for pre-processed args
        declare -p _pre_args
        set -- "${_pre_args[@]}"

        echo "\$* post: $*" # DEBUG

        # iterate through input argumets
        while [[ $# -gt 0 ]]; do
            echo "1c: $1"
            case "$1" in
            --no-log)
                LOGGING="$FALSE"
                shift
                ;;
            --) # -- denotes end of arguments - linux standard
                break
                shift
                ;;
            -*) # unrecosngised flags: -* & --*
                msg_error "unrecognised argument: $1"
                shift
                ;;
            *) # collect positional args
                POSITIONALS+=("$1")
                shift
                ;;
            esac
        done

        # VALIDATE ARGS
        msg_trace "parse_args(): post-validation"
        msg_trace_vars BASH_ARGV ALL_ARGS _pre_args POSITIONALS LOGFILE COLOR DEBUG TRACE VERBOSE

        [[ ${#POSITIONALS} -gt 0 ]] && msg_error "no postional arguments expected, got: ${POSITIONALS[*]}"

        # exit on failed validation
        if msg_cache_check error; then
            MSG_EN_CACHE="$FALSE" msg_error "one or more invalid arguments, dump previous errors & exit:"
            # indent all errors by 4 spaces "    "
            msg_cache_dump error | sed 's/^/    /'
            exit 1
        fi
    }

    msg_banner "parse args"
    msg_info "we can use pre_parse_args to..."
    MSG_EN_INDENT="$TRUE"
    msg_info "handle common args: --color/debug/help/logfile/trace/verbose"
    msg_info "split -ab -> -a -b"
    msg_info "--color=never -> --color never"
    MSG_EN_INDENT="$FALSE"
    hint '$ _parse_args -ab 1 2 3 --trace --debug --color=always -- lorem ipsum -cd --debug --foo=bar'
    _parse_args -ab 1 2 3 --trace --debug --color=always -- lorem ipsum -cd --debug --foo=bar
}

# TODO complete/prettify for users
function _demo_logging() {
    root="/tmp/test_logfile"
    [[ ! -d $root ]] && mkdir "$root"
    LOGFILE="${root}/newfile"
    # set -x
    msg_info "not logged - pre-enable"
    log_init
    msg_info "pid: $$"
    msg_info "logged - post-enable"
    log_disable
    msg_info "not logged - disabled 1"
    log_reenable
    msg_info "logged - re-enabled 1"
    log_disable
    msg_info "not logged - disabled 2"
    log_reenable
    msg_info "logged - re-enabled 2"
    log_init
    VERBOSE=$FALSE log_disable
    cat $LOGFILE
}

# TODO remove if finished with
function _demo_test() {
    # test if the shell is clean or not
    msg_info "msg_cache_dump"
    echo
    msg_cache_dump
}

# MAIN
# ==============================================
# call functions in sub-shells - ensures a clean environment by sourcing formatting.sh
# within each function

if [[ $# -eq 0 ]]; then
    # always provide general intro
    # while true loop prompting for user-selcted demo
    run_demo "demo_basics_all"
    loop_demos
    exit 0
else
    # assume $1 is a function name and call it
    run_demo "$1"
fi
exit 0
