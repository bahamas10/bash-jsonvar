NUM_TESTS=0
NUM_PASS=0

is-equal() {
	_format-message -- "$@"
	shift
	(($# == 2)) && [[ $1 == "$2" ]]
	_format-output $?
}

cmd-valid() {
	_format-message valid "$@"
	shift
	"$@" &>/dev/null
	_format-output $?
}

cmd-invalid() {
	_format-message invalid "$@"
	shift
	! "$@" &>/dev/null
	_format-output $?
}

_format-message() {
	local state=$1
	local msg=$2
	shift 2

	if [[ $msg == '--' && $state == 'valid' ]]; then
		echo -n "command success: $*... "
	elif [[ $msg == '--' ]]; then
		echo -n "command failure: $*... "
	else
		echo -n "$msg... "
	fi
}

_format-output() {
	local code=$1

	local red=$'\e[31m'
	local green=$'\e[32m'
	local rst=$'\e[0m'

	((NUM_TESTS++))
	if ((code == 0)); then
		echo "${green}ok${rst}"
		((NUM_PASS++))
	else
		echo "${red}fail${rst}"
	fi
}

utils-finish() {
	echo "passed $NUM_PASS / $NUM_TESTS tests"
	if ((NUM_PASS < NUM_TESTS)); then
		exit 1
	fi
}

trap utils-finish EXIT
