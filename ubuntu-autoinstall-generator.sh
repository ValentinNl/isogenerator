#!/bin/bash
set -Eeuo pipefail

function cleanup() {
        trap - SIGINT SIGTERM ERR EXIT
        if [ -n "${tmpdir+x}" ]; then
                rm -rf "$tmpdir"
                log "Deleted temporary working directory $tmpdir"
        fi
}

trap cleanup SIGINT SIGTERM ERR EXIT
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
[[ ! -x "$(command -v date)" ]] && echo "date command not found." && exit 1
today=$(date +"%Y-%m-%d")

function log() {
        echo >&2 -e "[$(date +"%Y-%m-%d %H:%M:%S")] ${1-}"
}

function die() {
        local msg=$1
        local code=${2-1}
        log "$msg"
        exit "$code"
}

usage() {
        cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-a] [-u user-data-file] [-m meta-data-file] [-c] [-s source-iso-file] [-d destination-iso-file]

This script will create fully-automated Ubuntu 20.04 Focal Fossa installation media.

Available options:

-h, --help              Print this help and exit
-v, --verbose           Print script debug info
-u, --user-data         Path to user-data file. Required if using -a
-m, --meta-data         Path to meta-data file. Will be an empty file if not specified and using -a
-s, --source            Source ISO file. By default the latest daily ISO for Ubuntu 20.04 will be downloaded
                        and saved as ${script_dir}/ubuntu-original-$today.iso
                        That file will be used by default if it already exists.
-d, --destination       Destination ISO file. By default ${script_dir}/ubuntu-autoinstall-$today.iso will be
                        created, overwriting any existing file.
EOF
        exit
}

function parse_params() {
        # default values of variables set from params
        user_data_file=''
        meta_data_file=''
        original_iso=''
        source_iso="${script_dir}/${original_iso}"
        destination_iso="${script_dir}/ubuntu-autoinstall-$today.iso"
        sha_suffix="${today}"
        use_hwe_kernel=0
        use_release_iso=0

        while :; do
                case "${1-}" in
                -h | --help) usage ;;
                -v | --verbose) set -x ;;
                -u | --user-data)
                        user_data_file="${2-}"
                        shift
                        ;;
                -s | --source)
                        source_iso="${2-}"
                        shift
                        ;;
                -d | --destination)
                        destination_iso="${2-}"
                        shift
                        ;;
                -m | --meta-data)
                        meta_data_file="${2-}"
                        shift
                        ;;
                -?*) die "Unknown option: $1" ;;
                *) break ;;
                esac
                shift
        done

        log "Starting up..."

        # check required params and arguments

        [[ -z "${user_data_file}" ]] && die "user-data file was not specified."
        [[ ! -f "$user_data_file" ]] && die "user-data file could not be found."

        destination_iso=$(realpath "${destination_iso}")
        source_iso=$(realpath "${source_iso}")

        return 0
}

parse_params "$@"

tmpdir=$(mktemp -d)

log "Checking for required utilities..."
[[ ! -x "$(command -v xorriso)" ]] && die "xorriso is not installed. On Ubuntu, install  the 'xorriso' package."
[[ ! -x "$(command -v sed)" ]] && die "sed is not installed. On Ubuntu, install the 'sed' package."
[[ ! -f "/usr/lib/ISOLINUX/isohdpfx.bin" ]] && die "isolinux is not installed. On Ubuntu, install the 'isolinux' package."
log "All required utilities are installed."

[[ ! -f "${source_iso}" ]] && die "Please downlaod source iso" 

log "Extracting ISO image..."
#7z x $source_iso -x'![BOOT]' -o$tmpdir &>/dev/null 

xorriso -osirrox on -indev "${source_iso}" -extract / "$tmpdir" &>/dev/null
chmod -R u+w "$tmpdir"
rm -rf "$tmpdir/"'[BOOT]'
log "Extracted to $tmpdir"

log "Adding autoinstall parameter to kernel command line..."
sed -i -e 's/---/ autoinstall  ---/g' "$tmpdir/isolinux/txt.cfg"
sed -i -e 's/---/ autoinstall  ---/g' "$tmpdir/boot/grub/grub.cfg"
sed -i -e 's/---/ autoinstall  ---/g' "$tmpdir/boot/grub/loopback.cfg"
log "Added parameter to UEFI and BIOS kernel command lines."

log "Adding user-data and meta-data files..."
mkdir "$tmpdir/nocloud"
cp "$user_data_file" "$tmpdir/nocloud/user-data"
touch "$tmpdir/nocloud/meta-data"
sed -i -e 's,---, ds=nocloud;s=/cdrom/nocloud/  ---,g' "$tmpdir/isolinux/txt.cfg"
sed -i -e 's,---, ds=nocloud\\\;s=/cdrom/nocloud/  ---,g' "$tmpdir/boot/grub/grub.cfg"
sed -i -e 's,---, ds=nocloud\\\;s=/cdrom/nocloud/  ---,g' "$tmpdir/boot/grub/loopback.cfg"
log "Added data and configured kernel command line."

log "Updating $tmpdir/md5sum.txt with hashes of modified files..."
md5=$(md5sum "$tmpdir/boot/grub/grub.cfg" | cut -f1 -d ' ')
sed -i -e 's,^.*[[:space:]] ./boot/grub/grub.cfg,'"$md5"'  ./boot/grub/grub.cfg,' "$tmpdir/md5sum.txt"
md5=$(md5sum "$tmpdir/boot/grub/loopback.cfg" | cut -f1 -d ' ')
sed -i -e 's,^.*[[:space:]] ./boot/grub/loopback.cfg,'"$md5"'  ./boot/grub/loopback.cfg,' "$tmpdir/md5sum.txt"
log "Updated hashes."

log "Repackaging extracted files into an ISO image..."
cd "$tmpdir"
xorriso -as mkisofs -r -V "ubuntu-autoinstall-$today" -J -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin -boot-info-table -input-charset utf-8 -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat -o "${destination_iso}" . &>/dev/null
cd "$OLDPWD"
log "Repackaged into ${destination_iso}"

die "Completed." 0
