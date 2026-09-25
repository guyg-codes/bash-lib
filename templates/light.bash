#!/usr/bin/env bash

# LIBRARIES
# ==================================================
# grab common utilities & formatting functions
# globals: TRUE, FALSE, COLOR, VERBOSE, DEBUG, TRACE, DRYRUN, LOGGING
[[ ! -v BASH_LIB ]] && BASH_LIB="$(dirname "$0")/.."
source "${BASH_LIB}/lib/utils.sh"

# SCRIPT GLOBALS
# ==================================================

# enable/disable logging & set logfile name
LOGGING="$TRUE"
LOGFILE="/tmp/$(basename "${0}").$(timestamp).log"

# HELP TEXT
# ==================================================

script_name="$(basename $0)"

script_desc="<one-line description>"

function help_text() {
    # provide end-user explanaiton with direction
    # NB wrap in a function to delay definition to *aftter* parsing potential --color=always
    local help_text="
    ${FMT_BOLD}${FG_CYAN}${script_name}: ${script_desc}${FMT_CLR}
    
    ${FMT_H1}REQUIRED ARGUMENTS${FMT_CLR}

        ${FMT_ARG}POS${FMT_CLR}       <description of POS>
                    ${FMT_DIM}- <bullet point>${FMT_CLR}
        ${FMT_ARG}--foo FOO${FMT_CLR} <description of FOO>

    ${FMT_H1}OPTIONAL ARGUMENTS${FMT_CLR}

        ${FMT_ARG}BAR${FMT_CLR}           <description of BAR> [<default>]
        ${FMT_ARG}-b|--baz BAZ${FMT_CLR}  <description of BAZ> [<default>]
        ${FMT_ARG}-v|--version${FMT_CLR}  print script version ($VERSION) & exit [$FALSE]

        ${COMMON_HELP_TEXT}
    "

    # strip indentation, assuming 4 leading spaces
    # indented bash heredocs are a bad fit as they require leading tabs, not spaces
    #   cat <<- EOF...EOF heredoc
    echo -e "${help_text}" | sed "s/^    //"
}

# ARGUMENT PARSING
# ==================================================

function parse_args() {
    # collect positional arguments, i.e. those without a leading ^-/--<arg>
    declare -ga POSITIONALS=()

    # handle common argument parsing for all scripts:
    #   split args -ab -> -a -ab, --color=never -> --color never
    #   default args: --color/debug/dryrun/help/logfile/msg-level/trace/verbose
    pre_parse_args "$@"
    # NB below *MUST* be retained to pick-up modified args from pre_parse_args
    set -- "${_pre_args[@]}"

    # iterate through input argumets
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --f*) # --foo FOO
            if [[ $# -gt 1 && ! $2 =~ ^- ]]; then
                FOO="$2"
                shift 2
            else
                msg_error "missing argument to --foo"
                shift
            fi
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
    # delay until argument parsing completes - allows --color=always to apply
    [[ $HELP == "$TRUE" ]] && help_text && exit 0

    # VALIDATE ARGS
    # -------------------------------------

    [[ ! ${#POSITIONALS[@]} -eq 1 ]] && msg_error "require 1 postional argument, got (${#POSITIONALS[@]}): ${POSITIONALS[*]}"
    # extract singular expected positional
    POS="${POSITIONALS[0]}"

    msg_debug "parse_args(): post-validation"
    msg_debug_vars POSITIONALS LOGGING LOGFILE COLOR DRYRUN DEBUG TRACE VERBOSE
    msg_trace_vars ALL_ARGS

    # exit on failed validation
    if msg_cache_check error; then
        MSG_EN_CACHE="$FALSE" msg_error "one or more invalid arguments, dump previous errors & exit:"
        # indent all errors by 4 spaces "    "
        msg_cache_dump error | sed 's/^/    /'
        exit 1
    fi

}

# FUNCTIONS
# ==================================================

function foo() {
    # <your docstring here>
    # apply function to path
    # $1 - target path
    # $2 - function to run on path
    local target_path="$1"
    local function="$2"

    # basic validation
    if [[ $# -eq 0 || $# -gt 2 ]]; then
        msg_error "expected 2 arguments, got $#: $*"
        return 1
    fi

    # run command - for --debug, --dryrun support
    cmd="${function} ${target_path}"
    runcmd "$cmd"

    # display to end-user
    echo "$runcmd_output"

    # remember to set a return value 0 = success, >=1 error
    return "$runcmd_status"
}

# SETUP
# ==================================================

# parse script-specific & generic arguments
parse_args "$@"

# all following content will be looged to $LOGFILE
# user log_disable/reenable() to toggle logging for e.g. password prompts
log_init

# MAIN
# ==================================================

foo "$POS" "$FOO"
