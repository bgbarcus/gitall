#!/bin/bash

function print_usage
{
	appname=`basename ${0}`
	echo "Usage: ${appname} [Switches] [path] [git args [AND git args ...]]"
	echo ""
	echo "Switches:"
	echo "    --help, -h      : show this help message and exit"
	echo ""
	echo "    -v              : show each command being executed"
	echo "    -q              : only show the output of git commands"
	echo "                      (with blank lines between repos)"
	echo "    -l              : only lists commands to be executed."
	echo "                      (with -q, produces script formatted output)"
	echo ""
	echo "    -a              : apply command to all repos (Default)"
	echo "    -m              : apply command to repos on master "
	echo "    -M              : apply command to repos not on master"
	echo "                      (equivalent to: -b -n )"
	echo "    -n              : apply command to repos on a hash (no branch)"
	echo "    -N              : apply command to repos not on a hash"
	echo "                      (equivalent to: -m -b )"
	echo "    -b              : apply command to repos on a branch"
	echo "    -B              : apply command to repos not on a branch"
	echo "                      (equivalent to: -m -n )"
	echo ""
	echo "    -c              : apply command to repos which are clean"
	echo "    -C              : apply command to repos which are not clean"
	echo "                      (equivalent to: -d )"
	echo "    -d              : apply command to repos which are dirty"
	echo "    -D              : apply command to repos which are not dirty"
	echo "                      (equivalent to: -c )"
	echo ""
	echo "    -p              : don't dereference current directory"
	echo ""
	echo "    -s [strings] -- : specify strings to match against subdirectories."
	echo "                      (see below)"
	echo ""
	echo "Arguments:"
	echo "    path     : a directory containing git repos (Default: . )"
	echo "    git args : arguments to pass to git"
	echo "    AND      : individual sets of git args can be separated by the"
	echo "               keyword AND"
	echo ""
	echo "Switches must be specified before Arguments.  Single letter switches"
	echo "may be combine (ex: -lqM is equivalent to -l -q -M)  If the first"
	echo "Argument happens to be a directory with respect to the current"
	echo "working directory, only subdirectories of that repo will be"
	echo "considered.  NOTE: If your first git argument happens to be a"
	echo "directory of the current directory, you will need to specify a"
	echo "first argument of '.' to prevent weirdness."
	echo ""
	echo "You can specify strings with -s to match against the the beginning"
	echo "of the names of each subdirectory.  Strings are space delimited,"
	echo "with the list of strings terminated by a --.  Subdirectories are"
	echo "processed on the first matching string, so with '-s s sh --' the"
	echo "'sh' would never be applied."
	echo ""
	echo "Pairing -l with -q will generate a list of commands which includes"
	echo "changing directories and can be copied and pasted to generate the"
	echo "results of the command."
	echo ""
	echo ""
	echo "Useful Examples:"
	echo ""
	echo "${appname} -M checkout master"
	echo "   Checkout master on all repos that are not on master."
	echo ""
	echo "${appname} -s f sh -- checkout -b qq-9999"
	echo "   Checkout or create the branch qq-9999 on all repos that start"
	echo "   with 'f' or 'sh'."
	echo ""
	echo "${appname} pull origin master AND fetch"
	echo "   execute 'git pull origin master' and 'git fetch' in each repo"
	echo ""
	echo ""
	echo "Git Alias:"
	echo ""
	echo "You can add an alias for ${appname} in your .gitconfig to allow"
	echo "calling ${appname} with 'git all'."
	echo ""
	echo "[alias]"
	echo "    all = !sh -c \"$(which ${0}) \$@\" -"
	echo ""
	echo "Note: Using the alias, git will eat a few arguments (--help, -c)."
	echo "   Use -h for help and -D for clean."
	echo ""
}

BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
LIME_YELLOW=$(tput setaf 190)
POWDER_BLUE=$(tput setaf 153)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)
BRIGHT=$(tput bold)
NORMAL=$(tput sgr0)
BLINK=$(tput blink)
REVERSE=$(tput smso)
UNDERLINE=$(tput smul)

function git_print_header
{
	local repo="${1}"
	local branch="${2}"

	if [[ "${OPT_QUIET}" -eq 0 ]] ; then
		printf "${YELLOW}${REVERSE}%20s${NORMAL} : " "$repo"

		case "$branch" in
			master)
				printf "${GREEN}$branch${NORMAL}"
				;;

			"NoBranch")
                if [ -d .git ] ; then
                    local hash = $(cat .git)
                else
				    local hash = $(cat .git/HEAD)
                fi
				printf "${CYAN}$hash${NORMAL}"
				;;

			*)
				printf "${GREEN}$branch${NORMAL}"
				;;

		esac
  
		if [[ "${STATE_DIRTY}" -eq 1 ]]; then
			printf " ${RED}${REVERSE}***${NORMAL}"
		fi
		printf "\n"
	else
		if [[ "${OPT_LIST_ONLY}" -eq 1 ]] && [[ "${OPT_QUIET}" -eq 1 ]] ; then
			local workingdir=`pwd -P | sed "s/${USER}[^\/]*/\$\{USER}/"`
			echo
			echo cd ${workingdir}
		fi
	fi
}

function git_execute_with_args
{
	local ArgString=$@

	if [[ "${OPT_QUIET}" -eq 0 ]] ; then

		if [[ "${OPT_VERBOSE}" -eq 1 ]] && [[ "${OPT_LIST_ONLY}" -ne 1 ]] ; then
			printf "               [CMD] : git %s\n" "$ArgString"
		fi

		echo "------------------------------------------------------------"
	fi

	## Execute the git command
	if [[ "${OPT_LIST_ONLY}" -eq 0 ]]; then
		eval "git ${ArgString}"
	else
		printf "git %s\n" "${ArgString}"
	fi

	if [[ "${OPT_QUIET}" -eq 0 ]] ; then
		echo "------------------------------------------------------------"
	else
		## a blank line between makes better output
		if [[ "${OPT_LIST_ONLY}" -ne 1 ]] ; then
			echo ""
		fi
	fi
	#below seems not to work for some commands (checkout, etc..)
	#script -a /dev/null -c "git ${@} 2>&1" -q /dev/null | sed 's/^/                       /'
}

function git_all_do
{
    local DIR=${1}
	cd ${DIR}
	shift

    if [ $? -eq 0 ]; then
		local STATE_MASTER=0
		local STATE_HASH=0
		local STATE_BRANCH=0
		local STATE_DIRTY=0

        local branch=$(git branch | grep \* | sed "s/\*//" | sed "s/ //")
		local repo=$(basename ${DIR})

		############################################################
		# return if not a match
		case "$branch" in
			master)			STATE_MASTER=1	;;
			"(no branch)")	STATE_HASH=1; branch='NoBranch'	;;
			*)				STATE_BRANCH=1	;;
		esac

		if [[ "${OPT_ALL}" -ne 1 ]]; then
			if [[ "${OPT_MASTER_ONLY}" -eq 0 ]] && [[ "${STATE_MASTER}" -eq 1 ]]; then
				return
			fi
			if [[ "${OPT_HASH_ONLY}" -eq 0 ]] && [[ "${STATE_HASH}" -eq 1 ]]; then
				return
			fi
			if [[ "${OPT_BRANCH_ONLY}" -eq 0 ]] && [[ "${STATE_BRANCH}" -eq 1 ]]; then
				return
			fi
		fi

		if [[ -n $(git status -s ${SUBMODULE_SYNTAX}  2> /dev/null) ]]; then
			STATE_DIRTY=1
		fi

		if [[ "${OPT_CLEAN_OR_DIRTY}" -ne 1 ]]; then
			if [[ "${OPT_DIRTY_ONLY}" -eq 0 ]] && [[ "${STATE_DIRTY}" -eq 1 ]]; then
				return
			fi
			if [[ "${OPT_CLEAN_ONLY}" -eq 0 ]] && [[ "${STATE_DIRTY}" -eq 0 ]]; then
				return
			fi
		fi

		git_print_header "$repo" "$branch"

		############################################################
		# Build Argument String
		local ArgString=''

		for myarg in "$@" ; do

			if [[ "${myarg}" != "AND" ]]; then
				myarg=${myarg//\"/\\\"}
				if [[ "${myarg}" =~ " " ]]; then
					ArgString="${ArgString} \"${myarg}\""
				else
					ArgString="${ArgString} ${myarg}"
				fi
			else
				git_execute_with_args ${ArgString}
				ArgString='';
			fi

		done

		git_execute_with_args ${ArgString}
		ArgString='';

    else
		printf "${WHITE}${REVERSE}[!]${NORMAL}"
        echo " Error: Could not cd into: ${DIR}"
    fi
}

if [ "$#" -eq 0 ]; then
	print_usage
	exit
fi

# Defaults
LOCATION=`pwd -P`

# Display options
OPT_VERBOSE=0
OPT_QUIET=0
OPT_LIST_ONLY=0

# Branch options
OPT_MASTER_ONLY=0
OPT_HASH_ONLY=0
OPT_BRANCH_ONLY=0
OPT_ALL=1

# Clean options
OPT_CLEAN_OR_DIRTY=1
OPT_CLEAN_ONLY=0
OPT_DIRTY_ONLY=0

# specific dir options
OPT_SPECIFIC_REPOS=0
OPT_SPECIFIC_DIRS=""

if [ "$#" -gt 0 ] ; then
	while [[ ${1} ]]; do 
		if [[ "${1:0:2}" == "--" ]]; then
			case "${1}" in 
				"--help")
					print_usage
					exit
					;;
			esac
		elif [[ "${1:0:1}" == "-" ]]; then
			arglist=${1:1}
			argscount=${#arglist}
			i=0
			while [[ "$i" -lt "${argscount}" ]] ; do
				argletter="${arglist:${i}:1}"
				let "i=i+1"
				case "${argletter}" in
					"h")
						print_usage
						exit
						;;

					"v")
						OPT_VERBOSE=1
						;;

					"q")
						OPT_QUIET=1
						;;

					"l")
						OPT_LIST_ONLY=1
						OPT_VERBOSE=1
						;;

					"a")
						OPT_ALL=1
						;;

					"d")
						OPT_DIRTY_ONLY=1
						OPT_CLEAN_OR_DIRTY=0
						;;

					"D")
						OPT_CLEAN_ONLY=1
						OPT_CLEAN_OR_DIRTY=0
						;;

					"c")
						OPT_CLEAN_ONLY=1
						OPT_CLEAN_OR_DIRTY=0
						;;

					"C")
						OPT_DIRTY_ONLY=1
						OPT_CLEAN_OR_DIRTY=0
						;;

					"m")
						OPT_MASTER_ONLY=1
						OPT_ALL=0
						;;

					"M")
						OPT_HASH_ONLY=1
						OPT_BRANCH_ONLY=1
						OPT_ALL=0
						;;

					"n")
						OPT_HASH_ONLY=1
						OPT_ALL=0
						;;

					"N")
						OPT_MASTER_ONLY=1
						OPT_BRANCH_ONLY=1
						OPT_ALL=0
						;;

					"b")
						OPT_BRANCH_ONLY=1
						OPT_ALL=0
						;;

					"B")
						OPT_MASTER_ONLY=1
						OPT_HASH_ONLY=1
						OPT_ALL=0
						;;

					"p")
						LOCATION=`pwd`
						;;

					"s")
						OPT_SPECIFIC_REPOS=1
						shift
						while [[ "${#}" -ne 0 ]] && [[ "${1}" != "--" ]]; do
							OPT_SPECIFIC_DIRS="${OPT_SPECIFIC_DIRS} ${1}"
							shift
						done
						;;

					*)
						printf "${WHITE}${REVERSE}[!]${NORMAL}"
						echo " unsupported short option short option: ${argletter}"
						;;
				esac
			done
		else
			case "${1}" in
				*)
					if [[ -d "${1}" ]]; then
						LOCATION=`cd ${1}; pwd -P`
						shift
					fi
					break
			esac
		fi

		shift
	done
fi

if [[ "${#}" -ne 0 ]] ; then
	cd ${LOCATION}
	for repodir in `find ${LOCATION} -maxdepth 1 -type d | grep -v "^.$"`; do 
		if [ -e ${repodir}/.git ] ; then 
			if [[ "${OPT_SPECIFIC_REPOS}" -eq 0 ]]; then
				git_all_do "${repodir}" "$@"
			else
				subdir=`basename ${repodir}`
				for pattern in $OPT_SPECIFIC_DIRS; do
					
					## NOTE: Had to remove using =~ as it didn't work on the mac
					pLen=${#pattern}
					if [[ "${subdir:0:${pLen}}" == "${pattern}" ]] ; then
						git_all_do "${repodir}" "$@"
						break
					fi
				done
			fi
		fi
	done
else
	printf "${WHITE}${REVERSE}[!]${NORMAL}"
	echo -n " No arguments to pass to git."
	if [[ "${OPT_SPECIFIC_REPOS}" -eq 1 ]] ; then
		echo "  Do you have an unterminated -s?"
		echo "    Supplied strings: ${OPT_SPECIFIC_DIRS}"
	else
		echo ""
	fi
fi
