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

    ${FMT_H1}USAGE${FMT_CLR}
    $(usage_text)
    
    ${FMT_H1}REQUIRED ARGUMENTS${FMT_CLR}

        ${FMT_ARG}POS${FMT_CLR}       <description of POS>
                    ${FMT_DIM}- <bullet point>${FMT_CLR}
        ${FMT_ARG}--foo FOO${FMT_CLR} <description of FOO>

    ${FMT_H1}OPTIONAL ARGUMENTS${FMT_CLR}

        ${FMT_ARG}BAR${FMT_CLR}           <description of BAR> [<default>]
        ${FMT_ARG}-b|--baz BAZ${FMT_CLR}  <description of BAZ> [<default>]
        ${FMT_ARG}   --examples${FMT_CLR} print script examples & exit [$FALSE]
        ${FMT_ARG}   --usage${FMT_CLR}    print script usage & exit [$FALSE]
        ${FMT_ARG}-v|--version${FMT_CLR}  print script version ($VERSION) & exit [$FALSE]

        ${FMT_H2}DEFAULT ARGUMENTS${FMT_CLR}
        ${FMT_ARG}   --color auto|always|never${FMT_CLR}    set color & formatting behaviour [auto]
                ${FMT_DIM}- auto: show if printing to terminal (i.e. not redirected to pipe or file)${FMT_CLR}
                ${FMT_DIM}- always: always enable color & formatting${FMT_CLR}
                ${FMT_DIM}- always: always disable color & formatting${FMT_CLR}
        ${FMT_ARG}   --debug${FMT_CLR}    enable debugging output: \"${MSG_DEBUG}\"
        ${FMT_ARG}-h|--help${FMT_CLR}     print help-text and exit
        ${FMT_ARG}   --logfile LOGFILE${FMT_CLR} specify logfile path [${LOGFILE}]
        ${FMT_ARG}   --trace${FMT_CLR}    enable extra debugging output: \"${MSG_TRACE}\"
        ${FMT_ARG}   --verbose${FMT_CLR}  enable output verbose mode
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
    #   default args: --color/debug/help/logfile/trace/verbose
    pre_parse_args "$@"
    # NB below *MUST* be retained to pick-up modified args from pre_parse_args
    set -- "${_pre_args[@]}"

    # iterate through input argumets
    while [[ $# -gt 0 ]]; do
        # echo "1c: $1"
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
    # delay until argument parsing completes - allows --color=always to apply
    [[ $HELP == "$TRUE" ]] && help_text && exit 0

    # VALIDATE ARGS
    # -------------------------------------

    [[ ${#POSITIONALS} -gt 0 ]] && msg_error "no postional arguments expected, got: ${POSITIONALS[*]}"

    msg_trace "parse_args(): post-validation"
    msg_trace_vars ALL_ARGS POSITIONALS LOGGING LOGFILE COLOR DEBUG TRACE VERBOSE

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
    # docstring here
    # $1 - path
    # $2 - function to run on path
    local target_path="$1"
    local function="$2"
    local fn_out=""

    if [[ $# -eq 0 || $# -gt 2 ]]; then
        msg_error "expected 2 arguments, got $#: $*"
        return 1
    fi

    # run command
    cmd="${function} ${target_path}"
    runcmd "$cmd"
    fn_out="$runcmd_output"

    # remember to return
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

bar "$POS" "$FOO"
