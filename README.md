# bash-lib

`bash-lib` provides an all-in-one Bash Library which can be used to...

- create scripts for production, personal or occsional use
- add to your ~/.bashrc to provide useful formatting & utility functions
  - e.g. can be used to easily format your prompt/$PS1

## Features

- formatted messaging library
  - --color=auto/always/never support
  - message caching - e.g. check for any >=error messages & replay on exit
  - supports function calls with string arguments and input via pipes
  - global flags allow one-shot or persistent changes to behaviour
    - e.g. enable timestamps, indent each line, output direct to logfile
  - internal behaviour skipped from `xtrace/verbose` output, with optional override
  - define logging level to control which messages are output
- templates for lightweight & production Bash scripts
  - logging setup, parsing common arguments etc handled by `lib/utils.sh`
  - --help/usage/examples support
- interactive script to demonstrate most functionality & act as example usage code
- common utilities
  - argument parsing
    - `-ab --color=never`
  - logging which can be toggled
    - e.g. avoid password prompts, API keys in logfiles
  - runcmd() with dryrun, debug & trace support
  - if\_\* functions to easily check if...
    - debug/trace/verbose/dryrun are enabled
    - specified file descriptor exists
  - robustly query terminal size, falling back to standard 80x24 when no pseudo-terminal is present

## Status

> [!CAUTION]
> This is work-in-progress library, approaching a 1.0 release.
> Use at your own risk

## AI Disclosure

None of the code in this project has been written by AI/LLMs.

I have referred to stackoverflow etc on occasions and ran a few error messages through an chatbot -

## Screenshots

Demo of msg\_\*() functions to pretty-print messages

![demo of msg_*() functions](./media/demo_basics_all.png)

Demo of manually-formatted help-text using formatting.sh

![demo of manually-formatted help-text using formatting.sh](./media/demo_help.png)

## Usage

1. grab project files
   - `git clone https://github.com/guyg-codes/bash-lib.git`
1. set BASH_LIB & call demo script
   - `BASH_LIB="${PWD/bash-lib} ./bash-lib/scripts/formatting.demo.sh`
