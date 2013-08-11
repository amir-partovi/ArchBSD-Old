usage() {
	echo "usage: $progname $cmd_usage"
	echo "options:"
	for i in "${cmd_options[@]}"; do
		echo "$i"
	done | awk '{
		split($1,arg,":");
		sub("[^ ]+ +[^ ]+ +","",$0);
		printf("  -%s % -5s  %s\n", arg[1], arg[2], $0);
	}'
}

cmd_buildline() {
	for i in "${cmd_options[@]}"; do
		echo "$i"
	done | awk '
	BEGIN { line=":" }
	{
		if (length($1) == 1) {
			line=line $1
		} else {
			line=line substr($1, 1, 1) ":"
		}
	}
	END { print(line); }'
}

cmd_setup() {
	for i in "${cmd_options[@]}"; do
		echo "$i"
	done | awk '{
		printf("declare -f cmdopt_" $2 " > /dev/null || cmdopt_" $2 "() {\n:\n}\n");
		split($1,arg,":");
		printf("cmdopt_" arg[1] "() {\nopt_" $2 "=1\ncmdopt_" $2 "\n}\n");
		print("opt_" $2 "=0");
	}'
}

cmd_parse() {
	eval "`cmd_setup`"
	getopt_opts=`cmd_buildline`
	OPTIND=1
	while getopts "$getopt_opts" opt; do
		case $opt in
			\:) usage ; exit 1 ;;
			\?) usage ; exit 1 ;;
			*)
				eval "cmdopt_$opt"
			;;
		esac
	done
}

imply() {
	eval "ison=\$opt_$1"
	shift
	local changed=0
	if (( $ison )); then
		for i in "$@"; do
			eval "ison=\$opt_$i"
			if (( ! $ison )); then
				eval "opt_$i=1"
				changed=1
			fi
		done
	fi
	if (( $changed )); then
		true
	else
		false
	fi
}

get_full_version() {
	if [[ -z $1 ]]; then
		if [[ $epoch ]] && (( ! $epoch )); then
			printf "%s\n" "$pkgver-$pkgrel"
		else
			printf "%s\n" "$epoch:$pkgver-$pkgrel"
		fi
	else
		for i in pkgver pkgrel epoch; do
			local indirect="${i}_override"
			eval $(declare -f package_$1 | gsed -n "s/\(^[[:space:]]*$i=\)/${i}_override=/p")
			[[ -z ${!indirect} ]] && eval ${indirect}=\"${!i}\"
		done
		if (( ! $epoch_override )); then
			printf "%s\n" "$pkgver_override-$pkgrel_override"
		else
			printf "%s\n" "$epoch_override:$pkgver_override-$pkgrel_override"
		fi
	fi
}

getsource() {
	cd "${fullpath}"
	source PKGBUILD
	pkgbase=${pkgbase:-${pkgname[0]}}
	epoch=${epoch:-0}
	fullver=$(get_full_version)
	echo "${pkgbase}-${fullver}${SRCEXT}"
}
