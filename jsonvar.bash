#!/usr/bin/env bash
#
# Serialize bash variables to JSON output
#
# # Created
# Author: Dave Eddy <ysap@daveeddy.com>
# Date: July 09, 2026
# License: MIT
#
# # Contributors
# - Dave Eddy <ysap@daveeddy.com>

_jv-usage() {
	local usage
	read -r -d '' usage <<-EOF
	Usage: jsonvar [-aev] [[name], ...]

	Serialize bash variables to JSON output

	Options
	    -a    show all variables
	    -e    show only exported variables
	    -v    show only the values of the variables
	    -h    show this message and exit
	EOF
	echo "$usage"
}

_jv-json-encode-string() {
	local s=$1

	local LC_ALL=C
	local -A table=()

	# we can start at 1 because bash variables can't have nul bytes in them
	local hex byte esc i
	for ((i = 1; i < 0x20; i++)); do
		printf -v hex '%02x' "$i"

		printf -v byte '%b' "\\x$hex"
		printf -v esc '\\u%04x' "$i"
		table[$byte]=$esc
	done

	table[$'\b']='\b'
	table[$'\t']='\t'
	table[$'\n']='\n'
	table[$'\f']='\f'
	table[$'\r']='\r'

	table['\']='\\'
	table['"']='\"'

	# serialize the string
	local out=''
	local len=${#s}
	local c
	for ((i = 0; i < len; i++)); do
		c=${s:i:1}
		esc=${table[$c]}

		if [[ -n $esc ]]; then
			# lookup table matched for this byte
			out+=$esc
		else
			# no lookup table match, byte falls through
			out+=$c
		fi
	done


	printf '"%s"' "$out"
}

_jv-encode-variable() {
	local _jv_name=$1
	local -n _jv_ref=$_jv_name

	case "${_jv_ref@a}" in
		*a*) # process indexed array
			echo -n '['
			local _jv_value _jv_i=0
			for _jv_value in "${_jv_ref[@]}"; do
				((_jv_i++))
				_jv-json-encode-string "$_jv_value"
				if ((_jv_i < ${#_jv_ref[@]})); then
					echo -n ', '
				fi
			done
			echo -n ']'
			;;
		*A*) # process associative array
			echo -n '{'
			local _jv_key _jv_value _jv_i=0
			for _jv_key in "${!_jv_ref[@]}"; do
				((_jv_i++))

				_jv_value=${_jv_ref[$_jv_key]}

				_jv-json-encode-string "$_jv_key"
				echo -n ': '
				_jv-json-encode-string "$_jv_value"

				if ((_jv_i < ${#_jv_ref[@]})); then
					echo -n ', '
				fi
			done
			echo -n '}'
			;;
		*i*) # process integer
			echo -n "$_jv_ref"
			;;
		*) # anything else, it's probably a string lol
			_jv-json-encode-string "$_jv_ref"
			;;
	esac

}

jsonvar() {
	local _jv_all='false'
	local _jv_exported='false'
	local _jv_value='false'

	# get arguments from user
	local OPTIND OPTARG _jv_opt
	while getopts 'aevh' _jv_opt; do
		case "$_jv_opt" in
			a) _jv_all='true';;
			e) _jv_exported='true';;
			v) _jv_value='true';;
			h) _jv-usage; return 0;;
			*) _jv-usage >&2; return 2;;
		esac
	done
	shift "$((OPTIND - 1))"

	local _jv_key

	# figure out what variables to look at
	local -a _jv_variables
	if $_jv_all; then
		readarray -t _jv_variables < <(compgen -v)
	elif $_jv_exported; then
		readarray -t _jv_variables < <(compgen -e)
	else
		_jv_variables=("$@")

		# ensure the user gave us *something*
		if (( ${#_jv_variables[@]} == 0 )); then
			echo 'variable name or flag required' >&2
			_jv-usage >&2
			return 2
		fi

		# check variables given
		local _jv_error='false'
		for _jv_key in "${_jv_variables[@]}"; do
			# warn the user if they gave us an internal name
			if [[ $_jv_key == _jv_* ]]; then
				echo "[error] invalid internal variable '$_jv_key'" >&2
				_jv_error='true'
			fi

			# check to make sure the variable is defined
			if ! declare -p "$_jv_key" &>/dev/null; then
				echo "[error] variable '$_jv_key' not defined" >&2
				_jv_error='true'
			fi
		done

		if $_jv_error; then
			return 1
		fi
	fi

	# loop the variables first to filter out hidden / internal var names
	local _jv_i
	local _jv_len=${#_jv_variables[@]}
	for ((_jv_i = 0; _jv_i < _jv_len; _jv_i++)); do
		_jv_key=${_jv_variables[_jv_i]}

		# filter out internal variables by name
		if [[ $_jv_key == _jv_* ]]; then
			unset '_jv_variables[_jv_i]'
			continue
		fi

		# variable name was good, do nothing
	done

	# loop the remaining variables and format them
	$_jv_value || echo '{'
	_jv_i=0
	for _jv_key in "${_jv_variables[@]}"; do
		((_jv_i++))

		if ! $_jv_value; then
			# indent
			echo -n '    '

			# print the key
			_jv-json-encode-string "$_jv_key"
			echo -n ': '
		fi

		# print the value
		_jv-encode-variable "$_jv_key"

		# optionally print the comma
		if ! $_jv_value && ((_jv_i < ${#_jv_variables[@]})); then
			echo -n ','
		fi
		echo
	done
	$_jv_value || echo '}'
}

_jv-complete() {
	COMPREPLY=(
		# add all variables
		$(compgen -v -- "${COMP_WORDS[COMP_CWORD]}")

		# add the individual flags
		$(compgen -W '-a -e -v -h' -- "${COMP_WORDS[COMP_CWORD]}")
	)
}

if ( return 0 &>/dev/null ); then
	# we are being sourced
	complete -F _jv-complete jsonvar
else
	# we are being executed directly
	declare -a test_indexed=(a b c)
	declare -a test_sparse=(a b c [67]=d)
	declare -A test_assoc=([a]=1 [b]=2 [c]=3)
	declare -i test_int=67
	declare -- test_string='hello world'

	jsonvar "$@"
fi
