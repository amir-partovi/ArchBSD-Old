submsg() {
	local mesg=$1; shift
	printf "\033[1;35m  ->\033[0;0m ${mesg}\n" "$@"
}

preconf() {
	progname=${0##*/}

	msg() {
		local mesg=$1; shift
		printf "\033[1;34m==>\033[0;0m ${mesg}\n" "$@"
	}

	want_unmount=0
	die() {
		msg "$@"
		if (( $want_unmount )); then
			do_unmount
		fi
		exit 1
	}
}

newmsg() {
	msg() {
		local mesg=$1; shift
		printf "\033[1;34m==>\033[0;0m [$repo/$package] ${mesg}\n" "$@"
	}
}

readconf() {
	source /etc/makepkg.conf
	if (( ! ${#PACKAGER} )); then
		die "Empty PACKAGER variable not allowed in /etc/makepkg.conf"
	fi
	# don't allow the commented out thing either: :P
	if [[ $PACKAGER == "John Doe <john@doe.com>" ]]; then
		die "Please update the PACKAGER variable in /etc/makepkg.conf"
	fi

	cachedir=/var/cache/pacman/pkg
	abstree=/var/absd-build/abs
	buildtop=/var/absd-build/build
	subvol=INVALID
	zfs_compression=gzip
	configfile="/etc/archbsd-build.conf"
	[ -f "$configfile" ] || die "please create a config in $configfile"
	source "$configfile"
	package_output=${package_output:-${buildtop}/output}
	builder_bashrc=${builder_bashrc:-${buildtop}/bashrc}
	setup_script=${setup_script:-${buildtop}/setup_root}
	prepare_script=${prepare_script:-${buildtop}/prepare_root}
	subvol_dir=${subvol_dir:-${buildtop}/subvol}

	if [[ $subvol == "INVALID" ]]; then
		zfs_enabled=0
	else
		zfs_enabled=1
	fi
}

postconf() {
	do_unmount() {
		msg "unmounting binds"
		umount "${builddir}"/{dev,proc,var/cache/pacman/pkg} 2>/dev/null
	}
	do_unmount
	want_unmount=0
}

load_config() {
	preconf
	readconf
	postconf
}

check_source() {
	#msg "Creating source package..."
	cd "$fullpath"
	#makepkg -Sf || die "failed creating src package"

	[ -f "$srcpkg" ] || die "Not a valid source package: %s" "$srcpkg"
}

clean_previous() {
	do_unmount 2>/dev/null
	msg "Cleaning previous work..."
	find "$builddir" -print0 | xargs -0 chflags noschg
	rm -rf "$builddir"
}

create_chroot() {
	msg "Installing chroot environment..."
	mkdir -p "$builddir" || die "Failed to create build dir: %s" "$builddir"
	mkdir -p "$builddir/var/lib/pacman"

	pacman_rootopt=(--config /etc/pacman.conf.clean --root "$builddir" --cachedir "$cachedir")

	if (( ! $opt_nosync )); then
		if ! pacman $opt_confirm "${pacman_rootopt[@]}" -Sy; then
			die "Failed to sync databases"
		fi
	fi

	if (( ! $opt_existing )); then
		if ! pacman $opt_confirm "${pacman_rootopt[@]}" -Su freebsd-world bash freebsd-init base base-devel "${opt_install[@]}"; then
			die "Failed to install build chroot"
		fi
	elif (( $opt_update )); then
		if ! pacman $opt_confirm "${pacman_rootopt[@]}" -Su --needed "${opt_install[@]}"; then
			die "Failed to update build chroot"
		fi
	fi

	install -m644 /etc/pacman.conf.clean "${builddir}/etc/pacman.conf"
}

mount_into_chroot() {
	want_unmount=1
	mount_nullfs {,"${builddir}"}/var/cache/pacman/pkg || die "Failed to bind package cache"
	mount -t devfs devfs "${builddir}/dev" || die "Failed to mount devfs"
	mount -t procfs procfs "${builddir}/proc" || die "Failed to mount procfs"
}

configure_chroot() {
	echo 'PACKAGER="'"$PACKAGER"\" >> "$builddir/etc/makepkg.conf" \
		|| die "Failed to add PACKAGER information"

	install -dm755 "${builddir}/var/cache/pacman/pkg" || die "Failed to setup package cache mountpoint"
	mount_into_chroot

	msg "Running setup script %s" "$setup_script"
	install -m644 "$setup_script" "${builddir}/root/setup.sh"
	chroot "${builddir}" /usr/bin/bash /root/setup.sh

	msg "Initializing the keyring"
	chroot "${builddir}" pacman-key --init
	chroot "${builddir}" pacman-key --populate archbsd

	msg "Setting up networking"
	install -m644 /etc/resolv.conf "${builddir}/etc/resolv.conf"

	msg "Creating user 'builder'"
	chroot "${builddir}" pw userdel builder || true
	chroot "${builddir}" pw useradd -n builder -u 1001 -c builder -s /usr/bin/bash -m \
		|| die "Failed to create user 'builder'"

	msg "Installing shell profile..."
	install -o 1001 -m644 "$builder_bashrc" "${builddir}/home/builder/.bashrc"
}

create_builder_home() {
	msg "Installing package building directory"
	install -o 1001 -dm755 "${builddir}/home/builder/package"
	install -o 1001 -m644 "$fullpath/$srcpkg" "${builddir}/home/builder/package"

	msg "Unpacking package sources"
	chroot "${builddir}" /usr/bin/su -l builder -c "cd ~/package && bsdtar --strip-components=1 -xvf ${srcpkg}" || die "Failed to unpack sources"
	source "$fullpath/PKGBUILD"
	for i in "${source[@]}"; do
		case "$i" in
			*::*) i=${i%::*} ;;
			*)    i=${i##*/} ;;
		esac
		if [ -e "$fullpath/$i" ]; then
			msg "Copying file %s" "$i"
			install -o 1001 -m644 "$fullpath/$i" "${builddir}/home/builder/package/$i"
		else
			msg "You don't have this file? %s" "$i"
		fi
	done
}

syncdeps() {
	msg "Syncing dependencies"
	local synccmd=(--asroot --nobuild --syncdeps --noconfirm --noextract)
	chroot "${builddir}" /usr/bin/bash -c "cd /home/builder/package && makepkg ${synccmd[*]}" || die "Failed to sync package dependencies"
	[[ $opt_keepbuild == 1 ]] || chroot "${builddir}" /usr/bin/bash -c "cd /home/builder/package && rm -rf pkg src"        || die "Failed to clean package build directory"
	chroot "${builddir}" /usr/bin/bash -c "chown -R builder:builder /home/builder/package"    || die "Failed to reown package directory"
}

run_prepare() {
	if (( $opt_kill_ld )); then
		msg "Killing previous ld-hints"
		rm -f "${builddir}/var/run/ld"{,-elf,elf32,32}".so.hints"
	fi

	msg "Running prepare script %s" "$prepare_script"
	install -m644 "$prepare_script" "${builddir}/root/prepare.sh"
	chroot "${builddir}" /usr/bin/bash /root/prepare.sh
}

start_build() {
	msg "Starting build"
	chroot "${builddir}" /usr/bin/su -l builder -c "cd ~/package && makepkg ${makepkgargs[*]}" || die "Failed to build package"
}

move_packages() {
	msg "Copying package archives"
	mkdir -p "$fulloutput"
	mv "${builddir}/home/builder/package/"*.pkg.tar.xz "$fulloutput" ||
		die "Failed to fetch packages..."
}
