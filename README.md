# ArmbianShrink - claude.ai improvements #
ArmbianShrink is a bash script that automatically shrink a armbian image that will then resize to the max size of the SD card on boot. This will make putting the image back onto the SD card faster and the shrunk images will compress better.

This script is based on [PiShrink](https://github.com/Drewsif/PiShrink) by [Drewsif](https://github.com/Drewsif)

This script was forked from [ArmbianShrink](https://github.com/dedalodaelus/ArmbianShrink) by [dedalodaelus](https://github.com/dedalodaelus)

Assisted by Claude.ai:

- Added partprobe, mount, umount, truncate and mktemp to the required-tools check.
- Removed the leftover PiShrink rollback code (the rc.local.bak mount and move) from the resize2fs failure branch.
- Temporary mount directories are now always unmounted and removed, including when the script exits early.
- The -p cleanup rm is guarded with "${mountdir:?}", so it can never expand against the host's /var, /tmp or /etc.
- cleanup only detaches the loop device if one exists, and the script exits if losetup returns nothing.
- ZIPTOOLS is a proper array with an exact-match check instead of a substring match.
- GPT images pass the original partition name to mkpart, with a warning that truncation removes the backup GPT header.
- Added mkdir -p before creating the autoexpand symlink.
- Fixed the "trunate" typo, quoted $command, and corrected the environment variable comment.
- Partition flags (boot, esp, lba and so on) are read before the partition is deleted and restored afterwards.
- The partition is recreated with -a minimal so its start offset can't move.
- Logical partitions: the extended partition is shrunk along with the logical one, so the image can actually be truncated.
- The extended shrink uses the logical partition's real end and answers parted's shrink prompt with an automatic "Yes".
- Partition type (primary or logical) and the extended partition number are found by parsing parted's output instead of a loose grep.
- Autoexpand for logical partitions through a first-boot service, armbianshrink-expand.service. This is still untested on real hardware.
- The truncation point no longer breaks when parted reports no trailing free space.
- New exit codes: 20 and 21 for mount failures, and 22 for the extended-partition resize.
- Added a LISTSTEPS variable at the top (on by default, overridable from the environment) that lists what the script is doing without touching -v.
- Added a [step] message at each stage: tool check, copy, partition table, loop device, autoexpand, filesystem check, resize, partition delete and recreate, flags, truncation, compression and "Done".
- While the image copy runs, the script reports how far through the source file cp has read, instead of the destination's size. This addresses the apparent freeze at 14 GB.
- Each step line now shows the clock time and the time elapsed since the script started.
- The core options (-a -d -h -p -r -s -v -z -Z) are unchanged.
- Wrote a README for the fork, with an "About this fork" section crediting Claude, a changelog, the options table, requirements, usage examples, the LISTSTEPS explanation, notes and limitations, exit codes and credits. It also corrects the old README's wrong log filename and environment variable names.

## Usage ##
`sudo armbianshrink.sh [-s] imagefile.img [newimagefile.img]`

If the `-s` option is given the script will skip the autoexpanding part of the process.  If you specify the `newimagefile.img` parameter, the script will make a copy of `imagefile.img` and work off that. You will need enough space to make a full copy of the image to use that option.

## Prerequisites ##
If using Ubuntu, you will likely see an error about `e2fsck` being out of date and `metadata_csum`. The simplest fix for this is to use Ubuntu 16.10 and up, as it will save you a lot of hassle in the long run.

## Installation ##
```bash
wget https://raw.githubusercontent.com/Auguss82/ArmbianShrink/master/armbianshrink.sh
chmod +x armbianshrink.sh
sudo mv armbianshrink.sh /usr/local/bin
```
## Starting ##
```bash
shrinker_claudai.sh v0.1.6
shrinker_claudai.sh: [step 16:22:35 | +0:00:00] Checking required tools are installed: parted partprobe losetup tune2fs md5sum e2fsck resize2fs mount umount truncate mktemp
shrinker_claudai.sh: Copying ambian_pi_backup_mbuffer.img to shrunken1.img... ...
shrinker_claudai.sh: [step 16:22:35 | +0:00:00] Making a full copy of the image (only the copy is modified; the original is left untouched)
shrinker_claudai.sh: [step 16:22:35 | +0:00:00] Source: apparent size 268436504576 bytes, 251G actually allocated on disk
shrinker_claudai.sh: [step 16:22:40 | +0:00:05] Copy: read 441 of 256001 MiB (0%), 368M allocated in the copy
```


## Ending ##
```bash
shrinker_claudai.sh: [step 15:09:14 | +2:50:49] Copy finished (exit code 0); data may still be flushing to the destination drive
shrinker_claudai.sh: Gathering data ...
shrinker_claudai.sh: [step 15:09:14 | +2:50:49] Reading the partition table of shrunken.img with parted
shrinker_claudai.sh: [step 15:09:14 | +2:50:49] Partition table is msdos; last partition is #1 (primary), starting at byte 4194304, flags: none
shrinker_claudai.sh: [step 15:09:14 | +2:50:49] Attaching a loop device at offset 4194304 so the last partition can be handled as a filesystem
shrinker_claudai.sh: [step 15:09:14 | +2:50:49] Reading filesystem size with tune2fs
shrinker_claudai.sh: [step 15:09:14 | +2:50:49] Filesystem has 64879616 blocks of 4096 bytes
shrinker_claudai.sh: [step 15:09:14 | +2:50:49] Enabling Armbian's armbian-resize-filesystem.service so the filesystem expands on first boot
shrinker_claudai.sh: [step 15:09:14 | +2:50:49] Mounting /dev/loop0 on temporary directory /tmp/tmp.ROwTHDPsHx
shrinker_claudai.sh: [step 15:09:14 | +2:50:49] Unmounting /tmp/tmp.ROwTHDPsHx and removing the temporary directory
shrinker_claudai.sh: Syspreping: Removing logs, apt archives, dhcp leases and ssh hostkeys ...
shrinker_claudai.sh: [step 15:09:15 | +2:50:50] Mounting the filesystem to delete logs, apt archives, DHCP leases, tmp files and SSH host keys
shrinker_claudai.sh: [step 15:09:15 | +2:50:50] Mounting /dev/loop0 on temporary directory /tmp/tmp.JRH69PUEgp
removed '/tmp/tmp.JRH69PUEgp/var/cache/apt/archives/lock'
removed directory '/tmp/tmp.JRH69PUEgp/var/cache/apt/archives/partial'
removed '/tmp/tmp.JRH69PUEgp/var/cache/apt/archives/updates.list'
removed '/tmp/tmp.JRH69PUEgp/var/cache/apt/archives/updates.number'
removed '/tmp/tmp.JRH69PUEgp/var/log/README'
removed '/tmp/tmp.JRH69PUEgp/var/log/alternatives.log'
removed '/tmp/tmp.JRH69PUEgp/var/log/apt/eipp.log.xz'
removed '/tmp/tmp.JRH69PUEgp/var/log/apt/history.log'
removed '/tmp/tmp.JRH69PUEgp/var/log/apt/term.log'
removed directory '/tmp/tmp.JRH69PUEgp/var/log/apt'
removed '/tmp/tmp.JRH69PUEgp/var/log/armbian-hardware-monitor.log'
removed '/tmp/tmp.JRH69PUEgp/var/log/armbian-ramlog.log'
removed '/tmp/tmp.JRH69PUEgp/var/log/auth.log'
removed '/tmp/tmp.JRH69PUEgp/var/log/btmp'
removed '/tmp/tmp.JRH69PUEgp/var/log/cron.log'
removed '/tmp/tmp.JRH69PUEgp/var/log/dpkg.log'
removed '/tmp/tmp.JRH69PUEgp/var/log/journal/02497bb0487847bc9eba1b9a303a0c00/system.journal'
removed '/tmp/tmp.JRH69PUEgp/var/log/journal/02497bb0487847bc9eba1b9a303a0c00/system@7667582dfcb14dc3b5edb64f5f8c2c2c-0000000000000001-00065e623f652b4f.journal'
removed directory '/tmp/tmp.JRH69PUEgp/var/log/journal/02497bb0487847bc9eba1b9a303a0c00'
removed directory '/tmp/tmp.JRH69PUEgp/var/log/journal'
removed '/tmp/tmp.JRH69PUEgp/var/log/kern.log'
removed '/tmp/tmp.JRH69PUEgp/var/log/lastlog'
removed directory '/tmp/tmp.JRH69PUEgp/var/log/private'
removed directory '/tmp/tmp.JRH69PUEgp/var/log/runit/ssh'
removed directory '/tmp/tmp.JRH69PUEgp/var/log/runit'
removed '/tmp/tmp.JRH69PUEgp/var/log/syslog'
removed '/tmp/tmp.JRH69PUEgp/var/log/user.log'
removed '/tmp/tmp.JRH69PUEgp/var/log/wtmp'
removed '/tmp/tmp.JRH69PUEgp/var/log/wtmp.db'
removed '/tmp/tmp.JRH69PUEgp/etc/ssh/ssh_host_ecdsa_key'
removed '/tmp/tmp.JRH69PUEgp/etc/ssh/ssh_host_ecdsa_key.pub'
removed '/tmp/tmp.JRH69PUEgp/etc/ssh/ssh_host_ed25519_key'
removed '/tmp/tmp.JRH69PUEgp/etc/ssh/ssh_host_ed25519_key.pub'
removed '/tmp/tmp.JRH69PUEgp/etc/ssh/ssh_host_rsa_key'
removed '/tmp/tmp.JRH69PUEgp/etc/ssh/ssh_host_rsa_key.pub'
shrinker_claudai.sh: [step 15:09:15 | +2:50:50] Unmounting /tmp/tmp.JRH69PUEgp and removing the temporary directory
shrinker_claudai.sh: Checking filesystem ...
shrinker_claudai.sh: [step 15:09:15 | +2:50:50] Running e2fsck -pf on /dev/loop0 (forced check; the filesystem must be clean before it can be resized)
armbi_root: 29352/16220160 files (0.1% non-contiguous), 1384075/64879616 blocks
shrinker_claudai.sh: [step 15:09:16 | +2:50:51] Asking resize2fs for the minimum possible filesystem size
resize2fs 1.47.2 (1-Jan-2025)
shrinker_claudai.sh: Shrinking filesystem ...
shrinker_claudai.sh: [step 15:09:16 | +2:50:51] Shrinking filesystem from 64879616 to 639205 blocks (includes a small safety buffer); this moves data and can take a long time
resize2fs 1.47.2 (1-Jan-2025)
Resizing the filesystem on /dev/loop0 to 639205 (4k) blocks.
Begin pass 3 (max = 1980)
Scanning inode table          XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
The filesystem on /dev/loop0 is now 639205 (4k) blocks long.

shrinker_claudai.sh: [step 15:09:18 | +2:50:53] Deleting partition #1 from the partition table (the data stays; only the table entry is removed)
shrinker_claudai.sh: [step 15:09:18 | +2:50:53] Recreating partition at byte 4194304, ending at byte 2622377984
shrinker_claudai.sh: Shrinking image ...
shrinker_claudai.sh: [step 15:09:18 | +2:50:53] Truncating the image file to 2622378496 bytes (removing the now-unused space at the end)
shrinker_claudai.sh: [step 15:09:18 | +2:50:53] Done
shrinker_claudai.sh: Shrunk shrunken.img from 251G to 2.5G ...
shrinker_claudai.sh: [step 15:09:18 | +2:50:53] Detaching loop device /dev/loop0
```

## Contributing ##
I only use this for scripts that I find and want to improve for my use. I just publish them here if someone else would like to use them too.
