#!/usr/bin/env bash
# [[exp del tag start]]
# # Created
# Author: Sioworker
# Date: October 13, 2026
# License: MIT
#
# # Contributors
# - Sioworker

# Experimental features for jsonvar, loaded by jsonvar.bash if this file is
# next to it. Turn them on with -x / --experimental.

# Run `./experiments.bash merge` to merge both (`jsonvar.exp.bash`), lines
# between the exp del start and finish tags are left out
# [[exp del tag finish]]

_jv-exp-usage() {
	local usage
	IFS=$' \n\t' read -r -d '' usage <<-EOF
	Experimental (experiments.bash)
	    -x    enable experimental features (--experimental), either
	          one feature or a list like [foo, bar]

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
	echo
	echo "$usage"
}

# pull out -x foo or -x [foo, bar], sets _jv_exp and _jv_args
_jv-exp-args() {
	local -a _jv_features
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
						internal|sparse|types|bytes)
							_jv_exp[$_jv_feature]=1
							;;
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
}

# types: print the value as a JSON type if it is one
_jv-exp-types() {
	local s=$1
	local BASH_REMATCH
	local re='^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$'

	if [[ $s == true || $s == false || $s == null || $s =~ $re ]]; then
		printf '%s' "$s"
		return 0
	fi
	return 1
}

# bytes: escape bytes above 0x7f as if they were latin-1
_jv-exp-bytes() {
	local s=$1
	local LC_ALL=C

	local out='' run='' esc c i
	for ((i = 0; i <= ${#s}; i++)); do
		c=${s:i:1}

		# ascii goes through the normal encoder
		if [[ -n $c && $c != [$'\x80'-$'\xff'] ]]; then
			run+=$c
			continue
		fi

		if [[ -n $run ]]; then
			esc=$(_jv-json-encode-string "$run")
			esc=${esc#\"}
			out+=${esc%\"}
			run=''
		fi

		if [[ -n $c ]]; then
			printf -v esc '\\u%04x' "'$c"
			out+=$esc
		fi
	done

	printf '"%s"' "$out"
}

# sparse: print arrays with gaps as an object keyed by index
_jv-exp-sparse() {
	local -a _jv_indices=("${!_jv_ref[@]}")
	local _jv_len=${#_jv_indices[@]}

	# arrays without gaps stay lists
	if ((_jv_len == 0 || _jv_indices[_jv_len - 1] == _jv_len - 1)); then
		return 1
	fi

	echo -n '{'
	local _jv_index _jv_i=0
	for _jv_index in "${_jv_indices[@]}"; do
		((_jv_i++))

		echo -n "\"$_jv_index\": "
		if [[ $_jv_attrs == *i* ]]; then
			_jv-json-encode-number "${_jv_ref[_jv_index]}"
		else
			_jv-json-encode-value "${_jv_ref[_jv_index]}"
		fi

		if ((_jv_i < _jv_len)); then
			echo -n ', '
		fi
	done
	echo -n '}'
}

# internal: sets _jv_attrs and _jv_copy_def, the local copy to eval
_jv-exp-internal-copy() {
	local _jv_def=${_jv_snapshot[$1]}
	IFS=' ' read -r _ _jv_attrs _ <<< "$_jv_def"

	# copy without -i so the value isn't evaluated
	local _jv_flag='--'
	case "$_jv_attrs" in
		*n*) _jv_def='';; # never copy namerefs
		*A*) _jv_flag='-A';;
		*a*) _jv_flag='-a';;
	esac
	_jv_copy_def="local $_jv_flag _jv_copy${_jv_def#"declare $_jv_attrs $1"}"
}

# internal: fills _jv_variables for -a and -e
_jv-exp-internal-list() {
	local _jv_key _jv_attrs
	for _jv_key in "${!_jv_snapshot[@]}"; do
		IFS=' ' read -r _ _jv_attrs _ <<< "${_jv_snapshot[$_jv_key]}"
		if $_jv_all || [[ $_jv_attrs == *x* ]]; then
			_jv_variables+=("$_jv_key")
		fi
	done

	((${#_jv_variables[@]})) || return 0
	readarray -t _jv_variables < <(
		printf '%s\n' "${_jv_variables[@]}" | LC_ALL=C sort
	)
}

_jv-exp-internal-defined() {
	[[ -n ${_jv_snapshot[$1]+set} ]]
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
		_jv-exp-snapshot "$@" 3< <(
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

_jv-exp-snapshot() {
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

# [[exp del tag start]]
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	dir=${BASH_SOURCE[0]%"${BASH_SOURCE[0]##*/}"}
	src=${dir}jsonvar.bash
	out=${dir}jsonvar.exp.bash

	if [[ $1 != merge ]]; then
		echo "Usage: ${0##*/} merge" >&2
		echo >&2
		echo "Make ${out##*/}, ${src##*/} with ${BASH_SOURCE[0]##*/} put in" >&2
		exit 2
	fi

	if [[ ! -f $src ]]; then
		echo "[error] $src not found" >&2
		exit 1
	fi

	# this file without the shebang
	body=''
	{
		IFS= read -r line
		while IFS= read -r line || [[ -n $line ]]; do
			body+=$line$'\n'
		done
	} < "${BASH_SOURCE[0]}"

	# put it in place of every line that sources experiments.bash
	merged=''
	re='(^|[[:space:];&|])(\.|source)[[:space:]].*experiments\.bash'
	while IFS= read -r line || [[ -n $line ]]; do
		if [[ $line != *([[:space:]])'#'* && $line =~ $re ]]; then
			merged+=$body
		else
			merged+=$line$'\n'
		fi
	done < "$src"

	# drop everything from a start tag to a finish tag, tag lines too,
	# split up so these lines aren't tags
	tag='exp del tag'
	start="[[$tag start]]"
	finish="[[$tag finish]]"
	result=''
	deleting='false'
	n=0
	while IFS= read -r line; do
		((n++))
		if [[ $line == *"$start"* ]]; then
			if $deleting; then
				echo "[error] line $n: $start inside another one" >&2
				exit 1
			fi
			deleting='true'
		elif [[ $line == *"$finish"* ]]; then
			if ! $deleting; then
				echo "[error] line $n: $finish without $start" >&2
				exit 1
			fi
			deleting='false'
		elif ! $deleting; then
			result+=$line$'\n'
		fi
	done <<< "${merged%$'\n'}"

	if $deleting; then
		echo "[error] $start without $finish" >&2
		exit 1
	fi

	printf '%s' "$result" > "$out" || exit

	[[ -x $src ]] && chmod +x "$out"
	echo "wrote $out"
fi
# [[exp del tag finish]]
