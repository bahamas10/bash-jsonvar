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
	IFS=$' \n\t' read -r -d '' usage <<-EOF
	Usage: jsonvar [-aev] [-x feature] [[name], ...]

	Serialize bash variables to JSON output

	Options
	    -a    show all variables
	    -e    show only exported variables
	    -v    show only the values of the variables
	    -h    show this message and exit
	    -x    enable experimental features (--experimental), either
	          one feature or a list like [foo, bar]

	Experimental
	    internal
	          allow variables named _jv_*
	    sparse
	          keep the indices of sparse arrays, as an object
	    types
	          print true, false, null and numbers in strings as JSON types
	    bytes
	          escape strings that aren't valid utf-8 byte by byte (\u00XX)
	          instead of null
	EOF
	echo "$usage"
}

# validate strings that bash supports (no nul support)
_jv-validate-utf8() {
	local s=$1

	# 0xxxxxxx                            1 byte,  7 bits
	# 110xxxxx 10xxxxxx                   2 bytes, 11 bits
	# 1110xxxx 10xxxxxx 10xxxxxx          3 bytes, 16 bits
	# 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx 4 bytes, 21 bits

	local LC_ALL=C
	local len=${#s}

	local i=0
	while ((i < len)); do
		local cp b1 b2 b3 b4 n

		# grab first byte
		printf -v b1 '%d' "'${s:i:1}"

		# check: b is 0xxxxxxx (1 octet)
		if (( (b1 & 2#10000000) == 0 )); then
			# 1 byte character, ASCII
			n=1

			# 0xxxxxxx
			cp=$(( b1 & 2#01111111 ))

		# check: b is 110xxxxx (2 octet)
		elif (( (b1 & 2#11100000) == 2#11000000 )); then
			# 2 byte character
			n=2

			(( i + 1 < len )) || return 1

			printf -v b2 '%d' "'${s:i+1:1}"

			(( (b2 & 2#11000000) == 2#10000000 )) || return 1

			# 110xxxxx 10xxxxxx
			cp=$((
				((b1 & 2#00011111) << 6) |
				 (b2 & 2#00111111)
			))

		# check: b is 1110xxxx (3 octet)
		elif (( (b1 & 2#11110000) == 2#11100000 )); then
			# 3 byte character
			n=3

			(( i + 2 < len )) || return 1

			printf -v b2 '%d' "'${s:i+1:1}"
			printf -v b3 '%d' "'${s:i+2:1}"

			(( (b2 & 2#11000000) == 2#10000000 )) || return 1
			(( (b3 & 2#11000000) == 2#10000000 )) || return 1

			# 1110xxxx 10xxxxxx 10xxxxxx
			cp=$((
				((b1 & 2#00001111) << 12) |
				((b2 & 2#00111111) << 6) |
				 (b3 & 2#00111111)
			))

		# check: b is 11110xxx (4 octet)
		elif (( (b1 & 2#11111000) == 2#11110000 )); then
			# 4 byte character
			n=4

			(( i + 3 < len )) || return 1

			printf -v b2 '%d' "'${s:i+1:1}"
			printf -v b3 '%d' "'${s:i+2:1}"
			printf -v b4 '%d' "'${s:i+3:1}"

			(( (b2 & 2#11000000) == 2#10000000 )) || return 1
			(( (b3 & 2#11000000) == 2#10000000 )) || return 1
			(( (b4 & 2#11000000) == 2#10000000 )) || return 1

			# 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
			cp=$((
				((b1 & 2#00000111) << 18) |
				((b2 & 2#00111111) << 12) |
				((b3 & 2#00111111) << 6) |
				 (b4 & 2#00111111)
			))
		else
			return 1
		fi
		(( i += n ))

		# at this point we have a codepoint and we've filtered out
		# invalid "looking" bytes, but we still have more work to do

		# check for overlong sequences
		case "$n" in
			1) ((cp >= 0x00000000 && cp <= 0x0000007F)) || return 1;;
			2) ((cp >= 0x00000080 && cp <= 0x000007FF)) || return 1;;
			3) ((cp >= 0x00000800 && cp <= 0x0000FFFF)) || return 1;;
			4) ((cp >= 0x00010000 && cp <= 0x0010FFFF)) || return 1;;
			*) exit 1;;
		esac

		# check for utf-16 surrogate pair domain
		# U+D800 and U+DFFF
		((cp >= 0xd800 && cp <= 0xdff)) && return 1
	done

	return 0
}

_jv-json-encode-string() {
	local s=$1

	local LC_ALL=C
	local -A table=()

	# let's ensure the string is utf-8 before doing anything
	local bytes='false'
	if ! _jv-validate-utf8 "$s"; then
		if ! $_jv_bytes; then
			printf 'null'
			return 0
		fi
		bytes='true'
	fi

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
		elif $bytes && [[ $c == [$'\x80'-$'\xff'] ]]; then
			# escape the byte as if it were latin-1
			printf -v esc '\\u%04x' "'$c"
			out+=$esc
		else
			# no lookup table match, byte falls through
			out+=$c
		fi
	done


	printf '"%s"' "$out"
}

_jv-json-encode-number() {
	local num=$1
	local re='^-?([0-9]+)$'

	# make sure it walks like a duck
	if ! [[ $num =~ $re ]]; then
		printf 'null'
		return
	fi

	# make sure it quacks like a duck
	if ! printf -v num '%d' "$num"; then
		printf 'null'
		return
	fi

	printf '%s' "$num"
}

# encode a string value, optionally as a JSON type
_jv-json-encode-value() {
	local s=$1
	local BASH_REMATCH
	local re='^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$'

	if $_jv_types && [[ $s == true || $s == false || $s == null || $s =~ $re ]]; then
		printf '%s' "$s"
	else
		_jv-json-encode-string "$s"
	fi
}

_jv-encode-variable() {
	local _jv_name=$1
	local _jv_attrs

	if $_jv_internal; then
		local _jv_def=${_jv_snapshot[$_jv_name]}
		IFS=' ' read -r _ _jv_attrs _ <<< "$_jv_def"

		# copy without -i so the value isn't evaluated
		local _jv_flag='--'
		case "$_jv_attrs" in
			*n*) _jv_def='';; # never copy namerefs
			*A*) _jv_flag='-A';;
			*a*) _jv_flag='-a';;
		esac
		eval "local $_jv_flag _jv_copy${_jv_def#"declare $_jv_attrs $_jv_name"}"
		local -n _jv_ref=_jv_copy
	else
		local -n _jv_ref=$_jv_name

		# before looking into the variable by name using a nameref we
		# are going to cowardly refuse to look into variables that
		# themselves are a nameref.
		# see https://github.com/bahamas10/bash-jsonvar/issues/6
		IFS=' ' read -r _ _jv_attrs _ < <(declare -p -- "$_jv_name")
	fi

	case "$_jv_attrs" in
		*n*) # process namerefs
			# todo maybe warn?
			echo -n 'null'
			;;
		*a*) # process indexed array
			local -a _jv_indices=("${!_jv_ref[@]}")
			local _jv_len=${#_jv_indices[@]}

			# arrays with gaps keep their indices
			local _jv_sparse='false'
			if $_jv_sparse_arrays && ((_jv_len > 0)) &&
			    ((_jv_indices[_jv_len - 1] != _jv_len - 1)); then
				_jv_sparse='true'
			fi

			if $_jv_sparse; then
				echo -n '{'
			else
				echo -n '['
			fi

			local _jv_index _jv_value _jv_i=0
			for _jv_index in "${_jv_indices[@]}"; do
				((_jv_i++))
				_jv_value=${_jv_ref[_jv_index]}

				if $_jv_sparse; then
					echo -n "\"$_jv_index\": "
				fi

				# check member type
				if [[ $_jv_attrs == *i* ]]; then
					_jv-json-encode-number "$_jv_value"
				else
					_jv-json-encode-value "$_jv_value"
				fi

				if ((_jv_i < _jv_len)); then
					echo -n ', '
				fi
			done

			if $_jv_sparse; then
				echo -n '}'
			else
				echo -n ']'
			fi
			;;
		*A*) # process associative array
			echo -n '{'
			local _jv_key _jv_value _jv_i=0
			for _jv_key in "${!_jv_ref[@]}"; do
				((_jv_i++))

				_jv_value=${_jv_ref[$_jv_key]}

				_jv-json-encode-string "$_jv_key"
				echo -n ': '

				if [[ $_jv_attrs == *i* ]]; then
					_jv-json-encode-number "$_jv_value"
				else
					_jv-json-encode-value "$_jv_value"
				fi

				if ((_jv_i < ${#_jv_ref[@]})); then
					echo -n ', '
				fi
			done
			echo -n '}'
			;;
		*i*) # process integer
			_jv-json-encode-number "$_jv_ref"
			;;
		*) # anything else, it's probably a string lol
			_jv-json-encode-value "$_jv_ref"
			;;
	esac

}

_jv-jsonvar() {
	local _jv_all='false'
	local _jv_exported='false'
	local _jv_value='false'
	local _jv_internal='false'
	local _jv_sparse_arrays='false'
	local _jv_types='false'
	local _jv_bytes='false'

	# pull out experimental features, -x foo or -x [foo, bar]
	local -a _jv_args=() _jv_features
	local _jv_list _jv_feature
	while (($#)); do
		case "$1" in
			-x|--experimental)
				if (($# < 2)); then
					echo "[error] $1 requires a feature" >&2
					return 2
				fi
				shift
				_jv_list=$1
				if [[ $_jv_list == '['* ]]; then
					while [[ $_jv_list != *']' ]]; do
						if (($# < 2)); then
							echo "[error] missing ']'" >&2
							return 2
						fi
						shift
						_jv_list+=" $1"
					done
					_jv_list=${_jv_list#[}
					_jv_list=${_jv_list%]}
				fi

				IFS=',' read -r -a _jv_features <<< "$_jv_list"
				for _jv_feature in "${_jv_features[@]}"; do
					_jv_feature=${_jv_feature//[[:space:]]/}
					case "$_jv_feature" in
						internal) _jv_internal='true';;
						sparse) _jv_sparse_arrays='true';;
						types) _jv_types='true';;
						bytes) _jv_bytes='true';;
						'') ;;
						*)
							echo "[error] unknown experimental feature '$_jv_feature'" >&2
							return 2
							;;
					esac
				done
				;;
			*) _jv_args+=("$1");;
		esac
		shift
	done
	set -- "${_jv_args[@]}"

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
	if $_jv_internal && { $_jv_all || $_jv_exported; }; then
		local _jv_attrs
		for _jv_key in "${!_jv_snapshot[@]}"; do
			IFS=' ' read -r _ _jv_attrs _ <<< "${_jv_snapshot[$_jv_key]}"
			if $_jv_all || [[ $_jv_attrs == *x* ]]; then
				_jv_variables+=("$_jv_key")
			fi
		done
		readarray -t _jv_variables < <(
			printf '%s\n' "${_jv_variables[@]}" | LC_ALL=C sort
		)
	elif $_jv_all; then
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
			if ! $_jv_internal && [[ $_jv_key == _jv_* ]]; then
				echo "[error] invalid internal variable '$_jv_key'" >&2
				_jv_error='true'
			fi

			# check to make sure the variable is defined
			if $_jv_internal; then
				if [[ -z ${_jv_snapshot[$_jv_key]+set} ]]; then
					echo "[error] variable '$_jv_key' not defined" >&2
					_jv_error='true'
				fi
			elif ! declare -p -- "$_jv_key" &>/dev/null; then
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
		if ! $_jv_internal && [[ $_jv_key == _jv_* ]]; then
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

jsonvar() {
	# no locals in here, they would shadow the caller's variables
	if (
		x='false'
		while (($#)); do
			[[ $1 == '-x' || $1 == '--experimental' ]] && x='true'
			$x && [[ $1 == *internal* ]] && exit 0
			shift
		done
		exit 1
	); then
		# snapshot every variable before anything can shadow it
		_jv-jsonvar-internal "$@" 3< <(
			# compgen -v skips variables that are declared but unset
			eval "set -- \"\$@\" $(compgen -v | tr '\n' ' ')"
			while (($#)); do
				declare -p -- "$1" 2>/dev/null
				printf '\0'
				shift
			done
		)
		return
	fi

	_jv-jsonvar "$@"
}

_jv-jsonvar-internal() {
	local -A _jv_snapshot=()
	local _jv_def _jv_name
	while IFS= read -r -d '' _jv_def <&3; do
		[[ -n $_jv_def ]] || continue
		_jv_name=${_jv_def#declare * }
		_jv_name=${_jv_name%%[=$'\n']*}
		_jv_snapshot[$_jv_name]=$_jv_def
	done

	_jv-jsonvar "$@"
}

_jv-complete() {
	COMPREPLY=(
		# add all variables
		$(compgen -v -- "${COMP_WORDS[COMP_CWORD]}")

		# add the individual flags
		$(compgen -W '-a -e -v -h -x --experimental' -- "${COMP_WORDS[COMP_CWORD]}")
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

	declare -ai test_indexed_ints=(0 1 2 0xff foo bar baz)
	declare -Ai test_assoc_ints=([foo]=0 [bar]=1 [baz]=0xff [bat]=foo)

	declare -a test_array_mixed_ints=(0 1 2 0xff foo bar baz)
	declare -i test_array_mixed_ints

	declare -A test_assoc_mixed_ints=([foo]=0 [bar]=1 [baz]=0xff [bat]=foo)
	declare -i test_assoc_mixed_ints

	test_bad_int='hello world'
	declare -i test_bad_int

	declare -n test_nameref='test_indexed'

	test_bad_octal='08'
	declare -i test_bad_octal

	test_big_int=99999999999999999999999
	declare -i test_big_int

	test_bad_utf8=$'a\xffb'

	jsonvar "$@"
fi
