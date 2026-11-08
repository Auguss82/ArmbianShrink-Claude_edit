#!/bin/bash

version="v0.1.6"

# Set to "yes" to print a "[step]" line describing what the script is doing at each
# stage. Independent of -v (which only affects the compressor). Can also be set from
# the environment, e.g.  LISTSTEPS=no ./armbianshrink.sh ...
LISTSTEPS="${LISTSTEPS:yes}"

CURRENT_DIR="$(pwd)"
SCRIPTNAME="${0##*/}"
MYNAME="${SCRIPTNAME%.*}"
LOGFILE="${CURRENT_DIR}/${SCRIPTNAME%.*}.log"
REQUIRED_TOOLS="parted partprobe losetup tune2fs md5sum e2fsck resize2fs mount umount truncate mktemp"
ZIPTOOLS=(gzip xz)
declare -A ZIP_PARALLEL_TOOL=( [gzip]="pigz" [xz]="xz" ) # parallel zip tool to use in parallel mode
declare -A ZIP_PARALLEL_OPTIONS=( [gzip]="-f9" [xz]="-T0" ) # options for zip tools in parallel mode
declare -A ZIPEXTENSIONS=( [gzip]="gz" [xz]="xz" ) # extensions of zipped files

loopback=""
mountdir=""

function info() {
	echo "$SCRIPTNAME: $1 ..."
}

# Prints: script: [step HH:MM:SS | +elapsed] message
function step() {
	if [[ "$LISTSTEPS" == "yes" ]]; then
		printf '%s: [step %(%H:%M:%S)T | +%d:%02d:%02d] %s\n' "$SCRIPTNAME" -1 \
			$((SECONDS/3600)) $((SECONDS%3600/60)) $((SECONDS%60)) "$*"
	fi
}

# Prints how far a running copy process has read its source file (works even while
# cp is skipping long runs of zeros, when the destination does not grow).
function copy_progress() {
	local pid="$1" src total fd pos="" dest_size
	src="$(readlink -f "$2")"
	total="$(stat -c %s "$2")"
	for fd in /proc/"$pid"/fd/*; do
		if [[ "$(readlink "$fd")" == "$src" ]]; then
			pos="$(awk '/^pos:/ {print $2}' /proc/"$pid"/fdinfo/"${fd##*/}" 2>/dev/null)"
			break
		fi
	done
	dest_size="$(du -h "$3" 2>/dev/null | cut -f1)"
	if [[ -n "$pos" && "$total" -gt 0 ]]; then
		step "Copy: read $((pos/1048576)) of $((total/1048576)) MiB ($((pos*100/total))%), $dest_size allocated in the copy"
	else
		step "Copy in progress: $dest_size allocated in the copy"
	fi
}

function error() {
	echo -n "$SCRIPTNAME: ERROR occurred in line $1: "
	shift
	echo "$@"
}

function cleanup() {
	# Unmount and remove the temporary mount directory, if any
	if [[ -n "$mountdir" && -d "$mountdir" ]]; then
		umount "$mountdir" &>/dev/null
		rmdir "$mountdir" &>/dev/null
		mountdir=""
	fi
	# Detach the loop device, if one was set up
	if [[ -n "$loopback" ]] && losetup "$loopback" &>/dev/null; then
		step "Detaching loop device $loopback"
		losetup -d "$loopback"
	fi
	if [ "$debug" = true ]; then
		local old_owner
		old_owner=$(stat -c %u:%g "$src")
		chown "$old_owner" "$LOGFILE"
	fi
}

function mount_fs() {
	mountdir=$(mktemp -d) || { error $LINENO "Could not create temporary directory."; exit 20; }
	step "Mounting $loopback on temporary directory $mountdir"
	if ! mount "$loopback" "$mountdir"; then
		error $LINENO "Could not mount $loopback."
		exit 21
	fi
}

function umount_fs() {
	step "Unmounting $mountdir and removing the temporary directory"
	umount "$mountdir"
	rmdir "$mountdir"
	mountdir=""
}

function logVariables() {
	if [ "$debug" = true ]; then
		echo "Line $1" >> "$LOGFILE"
		shift
		local v var
		for var in "$@"; do
			eval "v=\$$var"
			echo "$var: $v" >> "$LOGFILE"
		done
	fi
}

function checkFilesystem() {
	info "Checking filesystem"
	step "Running e2fsck -pf on $loopback (forced check; the filesystem must be clean before it can be resized)"
	e2fsck -pf "$loopback"
	(( $? < 4 )) && return

	info "Filesystem error detected!"

	info "Trying to recover corrupted filesystem"
	e2fsck -y "$loopback"
	(( $? < 4 )) && return

	if [[ $repair == true ]]; then
		info "Trying to recover corrupted filesystem - Phase 2"
		e2fsck -fy -b 32768 "$loopback"
		(( $? < 4 )) && return
	fi
	error $LINENO "Filesystem recoveries failed. Giving up..."
	exit 9
}

function set_autoexpand() {
	#Make armbian expand filesystem on next boot
	step "Enabling Armbian's armbian-resize-filesystem.service so the filesystem expands on first boot"
	partprobe "$loopback"
	mount_fs
	mkdir -p "${mountdir}/etc/systemd/system/basic.target.wants"
	ln -sf /lib/systemd/system/armbian-resize-filesystem.service "${mountdir}/etc/systemd/system/basic.target.wants/armbian-resize-filesystem.service"
	umount_fs
}

function set_autoexpand_logical() {
	# Armbian's own expand service only handles primary partitions. For a logical
	# root partition both the extended container and the logical partition have
	# to grow, so install a small one-shot first-boot service that does it.
	step "Installing first-boot service armbianshrink-expand.service (grows extended + logical partition, then the filesystem)"
	partprobe "$loopback"
	mount_fs
	mkdir -p "${mountdir}/usr/local/sbin" "${mountdir}/etc/systemd/system/basic.target.wants"

	cat > "${mountdir}/usr/local/sbin/armbianshrink-expand.sh" << 'EOS'
#!/bin/bash
# Installed by ArmbianShrink: grow extended + logical root partition, then the filesystem
rootsrc=$(findmnt -n -o SOURCE /)
disk="/dev/$(lsblk -no PKNAME "$rootsrc")"
partnum=$(cat "/sys/class/block/${rootsrc##*/}/partition")
extnum=$(parted -s "$disk" unit B print | awk '$5=="extended"{print $1}')
if [[ -n "$extnum" ]]; then
	echo ", +" | sfdisk --no-reread -N "$extnum" "$disk"
	partx -u "$disk"
fi
echo ", +" | sfdisk --no-reread -N "$partnum" "$disk"
partx -u "$disk"
resize2fs "$rootsrc"
# run only once
systemctl disable armbianshrink-expand.service
rm -f /etc/systemd/system/armbianshrink-expand.service /usr/local/sbin/armbianshrink-expand.sh
EOS
	chmod 755 "${mountdir}/usr/local/sbin/armbianshrink-expand.sh"

	cat > "${mountdir}/etc/systemd/system/armbianshrink-expand.service" << 'EOS'
[Unit]
Description=Expand logical root partition and filesystem (ArmbianShrink)
DefaultDependencies=no
After=local-fs.target
Before=basic.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/armbianshrink-expand.sh
RemainAfterExit=yes

[Install]
WantedBy=basic.target
EOS
	ln -sf /etc/systemd/system/armbianshrink-expand.service "${mountdir}/etc/systemd/system/basic.target.wants/armbianshrink-expand.service"
	umount_fs
}

function sysprep() {
	step "Mounting the filesystem to delete logs, apt archives, DHCP leases, tmp files and SSH host keys"
	mount_fs
	# ${mountdir:?} aborts the script if mountdir is ever empty, so these
	# globs can never expand against the host's own /var, /tmp or /etc.
	rm -rvf -- \
		"${mountdir:?}"/var/cache/apt/archives/* \
		"${mountdir:?}"/var/lib/dhcpcd5/* \
		"${mountdir:?}"/var/log/* \
		"${mountdir:?}"/var/tmp/* \
		"${mountdir:?}"/tmp/* \
		"${mountdir:?}"/etc/ssh/*_host_*
	umount_fs
}

help() {
	local help
	read -r -d '' help << EOM
Usage: $0 [-adhrspvzZ] imagefile.img [newimagefile.img]

  -s         Don't expand filesystem when image is booted the first time
  -v         Be verbose
  -r         Use advanced filesystem repair option if the normal one fails
  -z         Compress image after shrinking with gzip
  -Z         Compress image after shrinking with xz
  -a         Compress image in parallel using multiple cores
  -p         Remove logs, apt archives, dhcp leases and ssh hostkeys
  -d         Write debug messages in a debug log file
EOM
	echo "$help"
	exit 1
}

should_skip_autoexpand=false
debug=false
repair=false
parallel=false
verbose=false
prep=false
ziptool=""

while getopts ":adhprsvzZ" opt; do
  case "${opt}" in
    a) parallel=true;;
    d) debug=true;;
    h) help;;
    p) prep=true;;
    r) repair=true;;
    s) should_skip_autoexpand=true ;;
    v) verbose=true;;
    z) ziptool="gzip";;
    Z) ziptool="xz";;
    *) help;;
  esac
done
shift $((OPTIND-1))

if [ "$debug" = true ]; then
	info "Creating log file $LOGFILE"
	rm "$LOGFILE" &>/dev/null
	exec 1> >(stdbuf -i0 -o0 -e0 tee -a "$LOGFILE" >&1)
	exec 2> >(stdbuf -i0 -o0 -e0 tee -a "$LOGFILE" >&2)
fi

echo "${0##*/} $version"

#Args
src="$1"
img="$1"

#Usage checks
if [[ -z "$img" ]]; then
  help
fi

if [[ ! -f "$img" ]]; then
  error $LINENO "$img is not a file..."
  exit 2
fi
if (( EUID != 0 )); then
  error $LINENO "You need to be running as root."
  exit 3
fi

# set locale to POSIX(English) temporarily
# these locale settings only affect the script and its sub processes

export LANGUAGE=POSIX
export LC_ALL=POSIX
export LANG=POSIX


# check selected compression tool is supported and installed
if [[ -n $ziptool ]]; then
	supported=false
	for t in "${ZIPTOOLS[@]}"; do
		if [[ "$t" == "$ziptool" ]]; then
			supported=true
			break
		fi
	done
	if [[ $supported != true ]]; then
		error $LINENO "$ziptool is an unsupported ziptool."
		exit 17
	fi
	if [[ $parallel == true && $ziptool == "gzip" ]]; then
		REQUIRED_TOOLS="$REQUIRED_TOOLS pigz"
	else
		REQUIRED_TOOLS="$REQUIRED_TOOLS $ziptool"
	fi
fi

#Check that what we need is installed
step "Checking required tools are installed: $REQUIRED_TOOLS"
for command in $REQUIRED_TOOLS; do
  command -v "$command" >/dev/null 2>&1
  if (( $? != 0 )); then
    error $LINENO "$command is not installed."
    exit 4
  fi
done

#Copy to new file if requested
if [ -n "$2" ]; then
  f="$2"
  if [[ -n $ziptool && "${f##*.}" == "${ZIPEXTENSIONS[$ziptool]}" ]]; then	# remove zip extension if zip requested because zip tool will complain about extension
    f="${f%.*}"
  fi
  info "Copying $1 to $f..."
  if [[ "$LISTSTEPS" == "yes" ]]; then
    step "Making a full copy of the image (only the copy is modified; the original is left untouched)"
    step "Source: apparent size $(stat -c %s "$1") bytes, $(du -h "$1" | cut -f1) actually allocated on disk"
    cp --reflink=auto --sparse=always "$1" "$f" &
    cp_pid=$!
    while kill -0 "$cp_pid" 2>/dev/null; do
      sleep 5
      kill -0 "$cp_pid" 2>/dev/null && copy_progress "$cp_pid" "$1" "$f"
    done
    wait "$cp_pid"
    cp_rc=$?
    step "Copy finished (exit code $cp_rc); data may still be flushing to the destination drive"
    (( cp_rc == 0 )) || false
  else
    cp --reflink=auto --sparse=always "$1" "$f"
  fi
  if (( $? != 0 )); then
    error $LINENO "Could not copy file..."
    exit 5
  fi
  old_owner=$(stat -c %u:%g "$1")
  chown "$old_owner" "$f"
  img="$f"
fi

# cleanup at script exit
trap cleanup EXIT

#Gather info
info "Gathering data"
step "Reading the partition table of $img with parted"
beforesize="$(ls -lh "$img" | cut -d ' ' -f 5)"
parted_output="$(parted -ms "$img" unit B print)"
rc=$?
if (( $rc )); then
	error $LINENO "parted failed with rc $rc"
	info "Possibly invalid image. Run 'parted $img unit B print' manually to investigate"
	exit 6
fi
# Line 2 of the machine-readable output describes the disk; field 6 is the table type (msdos, gpt, ...)
table_type="$(echo "$parted_output" | sed -n 2p | cut -d ':' -f 6)"
last_part_line="$(echo "$parted_output" | tail -n 1)"
partnum="$(echo "$last_part_line" | cut -d ':' -f 1)"
partstart="$(echo "$last_part_line" | cut -d ':' -f 2 | tr -d 'B')"
partname="$(echo "$last_part_line" | cut -d ':' -f 6)"
# Flags (boot, lba, esp, ...) are lost when the partition is recreated, so remember them
partflags="$(echo "$last_part_line" | cut -d ':' -f 7 | tr -d ';')"

# On MS-DOS tables, ask parted whether the partition is primary or logical, and
# find the extended partition (its end has to be shrunk too for logical partitions)
parttype="primary"
extnum=""
if [[ "$table_type" == "msdos" ]]; then
    parttype="$(parted -s "$img" unit B print | awk -v n="$partnum" '$1==n {print $5}')"
    [[ "$parttype" == "logical" ]] || parttype="primary"
    extnum="$(parted -s "$img" unit B print | awk '$5=="extended" {print $1}')"
fi

# On GPT the argument to mkpart is the partition *name*, not a type
if [[ "$table_type" == "gpt" ]]; then
    mkpart_arg="${partname:-primary}"
else
    mkpart_arg="$parttype"
fi

step "Partition table is $table_type; last partition is #$partnum ($parttype), starting at byte $partstart, flags: ${partflags:-none}"
[[ -n "$extnum" ]] && step "Extended partition is #$extnum (it will be shrunk too)"
step "Attaching a loop device at offset $partstart so the last partition can be handled as a filesystem"
loopback="$(losetup -f --show -o "$partstart" "$img")"
if [[ -z "$loopback" ]]; then
    error $LINENO "losetup failed to set up a loop device"
    exit 8
fi
tune2fs_output="$(tune2fs -l "$loopback")"
rc=$?
if (( $rc )); then
    echo "$tune2fs_output"
    error $LINENO "tune2fs failed. Unable to shrink this type of image"
    exit 7
fi

step "Reading filesystem size with tune2fs"
currentsize="$(echo "$tune2fs_output" | grep '^Block count:' | tr -d ' ' | cut -d ':' -f 2)"
blocksize="$(echo "$tune2fs_output" | grep '^Block size:' | tr -d ' ' | cut -d ':' -f 2)"

step "Filesystem has $currentsize blocks of $blocksize bytes"
logVariables $LINENO beforesize parted_output table_type partnum partstart partname partflags parttype extnum tune2fs_output currentsize blocksize

#Check if we should make armbian expand rootfs on next boot
if [ "$should_skip_autoexpand" = true ]; then
  step "Autoexpand disabled by -s: the filesystem will NOT grow on first boot"
  echo "Skipping autoexpanding process..."
elif [ "$parttype" == "logical" ]; then
  info "Logical root partition: installing first-boot expand service"
  set_autoexpand_logical
else
  set_autoexpand
fi

if [[ $prep == true ]]; then
  info "Syspreping: Removing logs, apt archives, dhcp leases and ssh hostkeys"
  sysprep
fi


#Make sure filesystem is ok
checkFilesystem

step "Asking resize2fs for the minimum possible filesystem size"
if ! minsize=$(resize2fs -P "$loopback"); then
	rc=$?
	error $LINENO "resize2fs failed with rc $rc"
	exit 10
fi
minsize=$(cut -d ':' -f 2 <<< "$minsize" | tr -d ' ')
logVariables $LINENO currentsize minsize
if [[ $currentsize -eq $minsize ]]; then
  error $LINENO "Image already shrunk to smallest size"
  exit 11
fi

#Add some free space to the end of the filesystem
extra_space=$(($currentsize - $minsize))
logVariables $LINENO extra_space
for space in 5000 1000 100; do
  if [[ $extra_space -gt $space ]]; then
    minsize=$(($minsize + $space))
    break
  fi
done
logVariables $LINENO minsize

#Shrink filesystem
info "Shrinking filesystem"
step "Shrinking filesystem from $currentsize to $minsize blocks (includes a small safety buffer); this moves data and can take a long time"
resize2fs -p "$loopback" $minsize
rc=$?
if (( $rc )); then
  error $LINENO "resize2fs failed with rc $rc"
  # the EXIT trap detaches the loop device
  exit 12
fi
sleep 1

#Shrink partition
partnewsize=$(($minsize * $blocksize))
newpartend=$(($partstart + $partnewsize))
logVariables $LINENO partnewsize newpartend
step "Deleting partition #$partnum from the partition table (the data stays; only the table entry is removed)"
parted -s -a minimal "$img" rm "$partnum"
rc=$?
if (( $rc )); then
	error $LINENO "parted failed with rc $rc"
	exit 13
fi

step "Recreating partition at byte $partstart, ending at byte $newpartend"
# -a minimal keeps the start offset exactly where it was (the filesystem lives there)
parted -s -a minimal "$img" unit B mkpart "$mkpart_arg" "$partstart" "$newpartend"
rc=$?
if (( $rc )); then
	error $LINENO "parted failed with rc $rc"
	exit 14
fi

# A logical partition lives inside the extended partition, which must shrink as
# well, otherwise the image cannot be truncated and the table points past its end.
if [[ "$parttype" == "logical" && -n "$extnum" ]]; then
	# Use the real end of the new logical partition (parted may have aligned it), and
	# answer parted's "shrinking can cause data loss" prompt, which -s would answer "No".
	logend="$(parted -ms "$img" unit B print | tail -n 1 | cut -d ':' -f 3 | tr -d 'B')"
	logVariables $LINENO logend extnum
	step "Shrinking extended partition #$extnum to end at byte $logend"
	echo Yes | parted -a minimal ---pretend-input-tty "$img" unit B resizepart "$extnum" "$logend" >/dev/null
	rc=${PIPESTATUS[1]}
	if (( $rc )); then
		error $LINENO "parted failed to shrink extended partition $extnum with rc $rc"
		exit 22
	fi
fi

# Restore partition flags (boot, lba, esp, ...)
if [[ -n "$partflags" ]]; then
	newpartnum="$(parted -ms "$img" unit B print | tail -n 1 | cut -d ':' -f 1)"
	step "Restoring partition flags on #$newpartnum: $partflags"
	IFS=',' read -ra flaglist <<< "$partflags"
	for flag in "${flaglist[@]}"; do
		flag="${flag// /}"
		[[ -z "$flag" ]] && continue
		if ! parted -s "$img" set "$newpartnum" "$flag" on; then
			echo "WARNING: could not restore flag '$flag' on partition $newpartnum"
		fi
	done
fi

#Truncate the file
info "Shrinking image"
endresult=$(parted -ms "$img" unit B print free)
rc=$?
if (( $rc )); then
	error $LINENO "parted failed with rc $rc"
	exit 15
fi

lastline=$(tail -1 <<< "$endresult")
if [[ "$lastline" == *":free;" ]]; then
	# start of the trailing free space = end of the last partition
	endresult=$(cut -d ':' -f 2 <<< "$lastline" | tr -d 'B')
else
	# no trailing free space: use the end of the last partition (inclusive, so +1)
	endresult=$(( $(cut -d ':' -f 3 <<< "$lastline" | tr -d 'B') + 1 ))
fi
logVariables $LINENO endresult
step "Truncating the image file to $endresult bytes (removing the now-unused space at the end)"
truncate -s "$endresult" "$img"
rc=$?
if (( $rc )); then
	error $LINENO "truncate failed with rc $rc"
	exit 16
fi

if [[ "$table_type" == "gpt" ]]; then
	echo "WARNING: GPT image: the backup partition table at the end of the disk was removed by truncation."
	echo "         Most tools will recover it automatically; to repair it manually run: sgdisk -e $img"
fi

# handle compression
if [[ -n $ziptool ]]; then
	options=""
	envVarname="${MYNAME^^}_${ziptool^^}" # e.g. ARMBIANSHRINK_GZIP or ARMBIANSHRINK_XZ (derived from the script name) override all options for gzip or xz
	[[ $parallel == true ]] && options="${ZIP_PARALLEL_OPTIONS[$ziptool]}"
	[[ -v $envVarname ]] && options="${!envVarname}" # if environment variable defined use these options
	[[ $verbose == true ]] && options="$options -v" # add verbose flag if requested

	step "Compressing the image with $ziptool (options: ${options:-default})"
	if [[ $parallel == true ]]; then
		parallel_tool="${ZIP_PARALLEL_TOOL[$ziptool]}"
		info "Using $parallel_tool on the shrunk image"
		if ! $parallel_tool ${options} "$img"; then
			rc=$?
			error $LINENO "$parallel_tool failed with rc $rc"
			exit 18
		fi

	else # sequential
		info "Using $ziptool on the shrunk image"
		if ! $ziptool ${options} "$img"; then
			rc=$?
			error $LINENO "$ziptool failed with rc $rc"
			exit 19
		fi
	fi
	img=$img.${ZIPEXTENSIONS[$ziptool]}
fi

aftersize=$(ls -lh "$img" | cut -d ' ' -f 5)
logVariables $LINENO aftersize

step "Done"
info "Shrunk $img from $beforesize to $aftersize"
