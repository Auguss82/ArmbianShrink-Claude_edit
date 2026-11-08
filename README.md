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

## Example ##
```bash

```

## Contributing ##
I only use this for scripts that I find and want to improve for my use. I just publish them here if someone else would like to use them too.
