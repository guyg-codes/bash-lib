#!/usr/bin/env bash
# Copyright (c) 2026 Guy Gibson
# This file is part of bash-utils, licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
# TODO finish LICENSE

# TODO specify default $LOGFILE within log_init - allows to pass timestamp as an arg etc
# TODO logfile is wrtten only on exit, explore stdbuf to enable e.g. `tail -f log`
# TODO if_pipe - check fd1 too?

# GLOBALS
# =============================================================================
# [[ ! -v ... ]] prevents overriding externally set variables
#
# avoid shell ambiguity around 0/1 being truthy, i.e.:
#   declare: myVar="$FALSE"
#   test   : [[ $myVar == "$TRUE" ]] && ...
export TRUE="True"
export FALSE="False"
# 1st level debugging - actions taken, variable values etc
[[ ! -v DEBUG ]] && DEBUG=$FALSE
# 2nd level debugging - raw command return values etc
[[ ! -v TRACE ]] && TRACE=$FALSE
# enable additional output for user/logs
# NB: ./formatting.sh does not provide msg_verbose, instead:
#   if_verbose && msg_info "..."
[[ ! -v VERBOSE ]] && VERBOSE=$FALSE
# used by runcmd to skip command execution
[[ ! -v DRYRUN ]] && DRYRUN=$FALSE
# enable logging of both SDOUT/ERR to $LOGILE
[[ ! -v LOGGING ]] && LOGGING=$FALSE
# tracks whether --help detected during pre_parse_args()
HELP=$FALSE
# default logfile path
[[ ! -v LOGFILE ]] && LOGFILE="/tmp/${0}.log"

# CORE - can be used by libraries, as these are loaded first
# NB: must not use any library functions, vars
# =============================================================================

# if_*
# ------------------------------------------------
# avoid lots of '[[ $DEBUG == "$TRACE" ]] && ...'
# examples:
#
# if_debug && <cmd>
#
# if if_vebose; then
#   <cmd1>
# else
#   <cmd2>
# fi

function _if_generic() {
    # return 0 if $1 is defined and set to any non $FALSE value, inc. ""
    # else return 1
    local -n var="$1"
    [[ -z ${var+x} || $var == "$FALSE" ]] && return 1 || return 0
}

# create if_debug() etc
for i in DEBUG TRACE VERBOSE DRYRUN; do
    eval "function if_${i,,}() {
        _if_generic \"${i}\"
        return \"\$?\"
    }"
done
unset i

function if_pipe() {
    # return 0 if any non-interactive/non-terminal stdin, else 1
    # i.e. pipe, redirection, here-strings
    [[ ! -t 0 ]] && return 0 || return 1
}

function if_fd() {
    # return 0 if file descriptior is defined - useful for logging enable/disable
    # $1 - file description, usually 1/2/3/4
    local test="true >&$1"
    # if fd not defined
    if { eval "$test"; } 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

function strip_ansi() {
    # remove ANSI escape codes for formatting
    # e.g. \e[0m \e[38;2;255;0;128m
    local ansi_regex='s/\x1b\[[0-9;]+m//g'
    if if_pipe; then
        cat - | sed -E "$ansi_regex"
    else
        sed -E "$ansi_regex" <<<"$@"
    fi
}

function get_term_height() {
    # get terminal width, if not in a (recognised) terminal, defaul to unix-standard 80 wide
    local term_height=80
    if term_height="$(tput lines 2>/dev/null)"; then
        echo "$term_height"
    else
        echo 24
    fi
}

function get_term_width() {
    # get terminal width, if not in a (recognised) terminal, defaul to unix-standard 80 wide
    local term_width=80
    if term_width="$(tput cols 2>/dev/null)"; then
        echo "$term_width"
    else
        echo 80
    fi
}

function center_text() {
    # center single input line of text within terminal width
    # forcing padding of 1/5 width
    # NB: this will not properly handle strings containing ANSI formatting codes
    #  $1  - message to print
    # [$2] - override max width of each line [4/5*terminal width]
    # [$3] - override the apparent terminal width
    local msg="" folded=""
    declare -a lines=()
    local max_width=0 term_width=0
    local len_line len_pad_r len_pad_l
    if if_pipe; then
        msg="$(cat -)"
    else
        msg="$1"
    fi

    if [[ $# -lt 2 ]]; then
        max_width="$(get_term_width)"
        # enforce some padding
        max_width="$((max_width * 4 / 5))"
    else
        max_width="$2"
    fi

    if [[ ! $# -eq 3 ]]; then
        term_width="$(get_term_width)"
    else
        term_width="$3"
    fi

    [[ $term_width -lt $max_width ]] && echo "ERROR: center_text(): term_width (${term_width}) < max_width (${max_width})" 1>&2 && return 1

    # fold long lines to fit within terminal width
    folded="$(fold -w "$max_width" <<<"$msg")"
    readarray -t lines <<<"$folded"

    for line in "${lines[@]}"; do
        # raw length of message, without ANSI codes & removing for newline
        # <before><msg><after>
        # before = tw - <msg>/2
        # after = tw - <msg>/2
        len_line="$(strip_ansi <<<"${line}" | wc -c)"
        len_pad_l=$(((term_width - len_line) / 2))
        len_pad_r=$((term_width - len_line - len_pad_l))
        # long lines can send this negative
        [[ $len_pad_r -lt 0 ]] && len_pad_r=0
        # N empty spaces
        pad_l="$(printf "%${len_pad_l}s" "")"
        pad_r="$(printf "%${len_pad_r}s" "")"
        printf "%s%s%s\n" "$pad_l" "$line" "$pad_r"
    done
}

function pre_parse_args() {
    # handle common argument parsing functions
    #   -ab -> -a -a
    #   --color=never -> --color never
    #   --color/debug/trace/verbose/logfile
    #   -- * - stop processing arguments
    #   pre-process to support e.g. --color=never format
    #
    # BASH_ARGV - arguments as supplied by user, reverse ordered
    # ALL_ARGS  - arguments after splitting
    # _pre_args - arguments after handling common --debug etc
    # common_usage -
    #
    # NB *MUST* remember to run the following below pre_parse_args:
    # set -- "${_pre_args[@]}"

    local full_arg="" key="" value="" i=0
    # 'output' via fixed arrays
    declare -ga ALL_ARGS=()
    declare -ga _pre_args=()
    declare -g common_usage_text="[--color auto|always|never] [--debug] [--help] [--logfile LOGFILE] [--trace] [--verbose]"

    # handle splitting of input arguments, defer default args for later
    while [[ $# -gt 0 ]]; do
        # echo "1a: $1"
        # -ab -> -a -b
        if [[ $1 =~ ^-[a-z]+ ]]; then
            # iterate through ab, skip the initial -
            for i in $(seq 1 $((${#1} - 1))); do
                # slice 1 as an array to extract Nth char & return to args array
                ALL_ARGS+=("-${1:$i:1}")
            done
        # --color=never -> --color never, ignore where missing value e.g. "--logfile="
        elif [[ $1 =~ --[a-zA-Z0-9_-]+=[^\s]+ ]]; then
            # remove leading --
            full_arg="${1##--}"
            # split eitehr side of =
            key="${full_arg/=*/}"
            value="${full_arg/*=/}"
            # restore leading -- & return to args array
            ALL_ARGS+=("--${key}")
            ALL_ARGS+=("$value")
        # -- denotes end of arguments - linux standard
        elif [[ $1 =~ ^--$ ]]; then
            # return remaining unprocessed args to array
            # including current "--"
            ALL_ARGS+=("${@}")
            break
        else
            # return all others to args array
            ALL_ARGS+=("$1")
        fi
        shift
    done

    # swap args for pre-processed args
    set -- "${ALL_ARGS[@]}"

    # empty array to process default arguments after abpve splitting
    _pre_args=()

    # parse default arguments
    # prefer not to set -[a-z] short args as they often collide with script-specific args
    #   -h/--help is the exception as it is widely supported
    # NB arguments handled here are not passed back to script-specific parse_args()
    while [[ $# -gt 0 ]]; do
        # DEBUG
        # echo "1b: $1"
        case "$1" in
        --logfile)
            if [[ $# -gt 1 && ! $2 =~ ^- ]]; then
                LOGFILE="$2"
                shift 2
            else
                msg_error "missing argument to --logfile"
                shift
            fi
            ;;
        --color) # auto/always/never, validated in formatting.sh
            if [[ $# -gt 1 && ! $2 =~ ^- ]]; then
                # set COLOR & source lib again for refreshed $FMT_* etc
                COLOR="$2" && source "${BASH_LIB}/lib/formatting.sh"
                shift 2
            else
                msg_error "missing argument to --color"
                shift
            fi
            ;;
        --debug)
            DEBUG="$TRUE"
            shift
            ;;
        -h | --help)
            HELP="$TRUE"
            shift
            ;;
        --trace)
            TRACE="$TRUE"
            shift
            ;;
        --verbose)
            VERBOSE="$TRUE"
            shift
            ;;
        --) # -- denotes end of arguments - linux standard
            _pre_args+=("${@}")
            break
            ;;
        *) # leave other args to script-specific parsing
            _pre_args+=("$1")
            shift
            ;;
        esac
    done

    # NB *MUST* remember to run the following below pre_parse_args:
    # set -- "${_pre_args[@]}"
}

function timestamp() {
    # naive timestamp using local TZ, seconds
    # YYYYmmdd-HHMMSS - e.g. 20260922-182318
    date '+%Y%m%d-%H%M%S'
}

function timestamp_iso() {
    # ISO-formatted time, specifying TZ, defaults to nanoseconds
    local fmt="ns"
    [[ $# -gt 0 ]] && fmt="$1"
    date --iso="${fmt}"
}

# LIBRARIES - lib contents may be used in below code
# =============================================================================

# grab msg_*(), $<MSG|FMT|FG|BG>_*
[[ ! -v BASH_LIB ]] && export BASH_LIB="$(dirname "${0}")"
source "${BASH_LIB}/lib/formatting.sh"

# RUNCMD
# =============================================================================

function _runcmd() {
    # eval provided command, $DRYRUN support, print $cmd via msg_debug
    # WARNING - it is highly *unsafe* to `eval "$user_input"` as a service account etc
    local print="$1"
    local cmd="$2"

    # output via globals, not sub-shell capture
    declare -g runcmd_out runcmd_status

    # safely quoted using bash built-in, suitable for copy-paste
    local cmd_quoted="${cmd:q}"

    if [[ $DRYRUN == "$TRUE" ]]; then
        msg_dryrun "runcmd - cmd: ${cmd_quoted}"
        runcmd_out=""
        runcmd_status=0
        return 0
    else
        msg_debug "${FMT_DRYRUN}DRYRUN${FMT_CLR}: runcmd: $cmd_quoted}"
    fi

    # we can't run eval in a sub-shell or we lose $?/PIPESTATUS
    # so we store STDOUT/ERR in a file
    outfile="$(mktemp /tmp/XXXXX)"

    msg_debug "cmd: ${cmd}"

    if [[ $print == "$TRUE" ]]; then
        # STDOUT/ERR to TTY and saved to file
        eval "$cmd" 2>&1 | tee -a "$outfile" >&2
    else
        # no output to TTY, all saved to file
        eval "$cmd" >"$outfile" >&2
    fi

    # work around for $? == exit status of tee in above pipe
    runcmd_status="${PIPESTATUS[0]}"
    runcmd_out="$(cat "$outfile")"
    rm "$outfile"

    return "$runcmd_status"
}

function runcmd() {
    # execute command provided as string
    # no output to STDOUT/ERR
    [[ -o xtrace ]] && set +x && trap 'set -x' RETURN
    [[ -o verbose ]] && set +v && trap 'set -v' RETURN

    local cmd="$1"
    _runcmd "$FALSE" "$cmd"
}

function runcmd_print() {
    # execute command provided as string
    # both STDOUT/ERR output to STDERR
    [[ -o xtrace ]] && set +x && trap 'set -x' RETURN
    [[ -o verbose ]] && set +v && trap 'set -v' RETURN
    local cmd="$1"
    _runcmd "$TRUE" "$cmd"
}

function mk_file() {
    # create a new file, with robust error checking
    # $1 - path to target file, relative or absolute
    # --force - overwrite existing logfile [$FALSE]
    # --required - error on any permissions issues [$FALSE]
    # --makedir - where neccessary, use `mkdir -p "$(dirname $LOGFILE)"` [$FALSE]
    # --append - append to existing logfile, else new file [$FALSE]
    # arguments
    local force=$FALSE required=$FALSE mkdir=$FALSE append=$FALSE
    # argument parsing
    [[ $* =~ --force ]] && force=$TRUE
    [[ $* =~ --required ]] && required=$TRUE
    [[ $* =~ --mkdir ]] && mkdir=$TRUE
    [[ $* =~ --append ]] && append=$TRUE

    # internals
    local file="" dir="" file="" msg_fn="msg_warn" issue="$FALSE"
    file="$1"
    dir="$(dirname "$file")"
    filename="$(basename "$file")"
    # select between msg_<warn/error>
    [[ $required == "$TRUE" ]] && msg_fn="msg_error"

    # dir, file exists & ensure perms OK
    if [[ ! -e "$dir" ]]; then
        if [[ $mkdir == "$TRUE" ]]; then
            mkdir -p "$dir"
            if [[ ! $? == 0 ]]; then
                "$msg_fn" "failed to create parent dir: ${dir}"
                issue="$TRUE"
            fi
        else
            "$msg_fn" "parent directory does not exist: ${dir}"
            issue="$TRUE"
        fi
    elif [[ ! -w "$dir" ]]; then
        "$msg_fn" "no permission to write to parent directory: ${dir}"
        issue="$TRUE"
    fi
    if [[ -e "$file" ]]; then
        if [[ ! -w "$file" ]]; then
            "$msg_fn" "no permission to edit file: ${file}"
            issue="$TRUE"
        # if not appending, always start from fresh file
        elif [[ $append == "$FALSE" && $force == "$TRUE" ]]; then
            rm -f "$file"
            if [[ ! $? == 0 ]]; then
                "$msg_fn" "failed to remove existing logfile: ${file}"
                issue="$TRUE"
            fi
        fi
    fi

    [[ $issue == "$TRUE" ]] && return 1 || return 0
}

# LOGGING
# =============================================================================
# the following relies on several file descriptor redirections
# fd1 - active STDOUT
# fd2 - active STDERR
# fd3 - on init/reenable, stash original STDOUT
# fd4 - on init/reenable, stash original STDERR
# fd5 - on disable, stash custom logged STDOUT
# fd5 - on disable, stash custom logged STDOUT
# overview:
# init      - stash original fd1/2 to fd3/4 & create cusotm logging on new fd1/2
#             - also creates logfile
# disable   - stash custom logged fd1/2 on fd5/6 & restore original fd1/2 from fd3/4
# reenable  - again, stash original fd1/2 on fd3/4 & restore custom logged fd1/2 from fd5/6
#
# NB: logifle is not written until exit

function log_init() {
    # create logfile, borrows args from mk_file()
    # skip where disabled
    [[ $LOGGING == "$FALSE" ]] && return 0
    # error where no path specified
    if [[ -z $LOGFILE ]]; then
        msg_error "logging(): LOGFILE is not defined"
        return 1
    fi

    mk_file "$LOGFILE" "$@" || return 1

    # ls -l "/proc/$$/fd/"
    if if_fd 3 && if_fd 4; then
        if_verbose && msg_warn "log_init(): cannot init logging twice"
        return 1
    elif ! if_fd 3 && ! if_fd 4; then
        # stash original STDOUT/ERR, fd3/4 becomes fd1/2
        exec 3<&1
        exec 4<&2
    fi

    # implement logging - captures all output to STDOUT/ERR (i.e. fd1/2)
    # removing all ANSI chars from logfile
    exec > >(tee -a >(strip_ansi >>"$LOGFILE")) 2>&1
    # ls -l "/proc/$$/fd/"

    # report logfile to end-user now & on final script exit
    log_report "enable"
    trap "log_report 'exit'" EXIT
}

function log_disable() {
    if ! if_fd 3 && ! if_fd 4; then
        if_verbose && msg_warn "log_disable(): original STDOUT/ERR are not defined, logging likely not enabled"
        return 1
    else
        if_verbose && msg_warn "disabling logging"
        # preserve custom logged STDOUT/ERR on fd5/6
        exec 5>&1
        exec 6>&2
        # restore original STDOUT/ERR, fd3/4 become fd1/2
        exec 1>&3
        exec 2>&4
        # ls -l "/proc/$$/fd/"
        return 0
    fi
}

function log_reenable() {
    #
    # ensure alt-STDOUT/ERR are defined
    if ! if_fd 5 && ! if_fd 6; then
        if_verbose && msg_warn "log_enable(): fd5/6 are not defined, call log_init first"
        return 1
    else
        if_verbose && msg_warn "re-enabling logging"
        # stash original STDOUT/ERR, fd3/4 becomes fd1/2
        exec 3<&1
        exec 4<&2
        # restore custom logged STDOUT/ERR, fd5/6 become fd1/2
        exec 1<&5
        exec 2<&6
        # ls -l "/proc/$$/fd/"
        return 0
    fi
}

function log_report() {
    # $1 - set output string, either: <enable/exit>
    local msg=""
    if [[ $1 == "enable" ]]; then
        msg="logging started for all output to: $LOGFILE"
    elif [[ $1 == "exit" ]]; then
        msg="all terminal output logged to: $LOGFILE"
    fi
    msg_info "$msg"
}
