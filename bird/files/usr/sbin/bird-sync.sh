#!/bin/sh
# BIRD2 antifilter list sync for OpenWrt.
# Port of the original bird2.sh (docker-based) adapted to BusyBox/ash.

set -u

LOG_TAG="bird-sync"

LIST_DIR="/etc/bird/list"
LIST_CUSTOM_DIR="/etc/bird/list_custom"
RSC_DIR="/etc/bird/list_rsc"
TMP_DIR="/tmp/bird_sync"
VIA_IFACE=""

log()  { echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1"; }
warn() { echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] $1" >&2; }

get_global() {
	uci -q get "bird.global.$1" 2>/dev/null
}

get_source() {
	uci -q get "bird.antifilter.$1" 2>/dev/null
}

src_enabled() {
	[ "$(get_source "$1")" = "1" ]
}

load_global() {
	LIST_DIR=$(get_global list_dir);  [ -n "$LIST_DIR" ]  || LIST_DIR="/etc/bird/list"
	RSC_DIR=$(get_global rsc_dir);    [ -n "$RSC_DIR" ]   || RSC_DIR="/etc/bird/list_rsc"
	VIA_IFACE=$(get_global via_interface)
	[ -n "$VIA_IFACE" ] || VIA_IFACE="amneziawg0"
}

check_internet() {
	wget -q -T 5 -O /dev/null "http://antifilter.download/" 2>/dev/null
	return $?
}

download_file() {
	local url="$1" out="$2" i
	for i in 1 2 3; do
		if wget -q -T 60 -O "$out" "$url" 2>/dev/null; then
			return 0
		fi
		[ "$i" -lt 3 ] && sleep 3
	done
	return 1
}

files_differ() {
	[ -f "$2" ] || return 0
	cmp -s "$1" "$2"
	# cmp returns 0 when equal -> differ only if status is non-zero
	[ $? -ne 0 ]
}

# Step 1: list_custom -> list
sync_custom_lists() {
	log "--- Syncing list_custom -> list ---"
	for f in "$LIST_CUSTOM_DIR"/*.lst; do
		[ -f "$f" ] || continue
		name=$(basename "$f" .lst)
		cp "$f" "$LIST_DIR/$name.lst"
		log "Copied: $name"
	done
}

# Step 2: download antifilter -> tmp
download_antifilter_lists() {
	log "--- Downloading antifilter lists ---"
	if ! check_internet; then
		warn "No internet - skip download"
		return 1
	fi

	local updated=false file url
	for file in ip ipresolve ipsum subnet allyouneed community; do
		src_enabled "$file" || { log "Skipped (disabled): $file"; continue; }
		url="https://antifilter.download/list/${file}.lst"
		[ "$file" = "community" ] && url="https://community.antifilter.download/list/${file}.lst"
		if download_file "$url" "$TMP_DIR/$file.lst"; then
			log "Downloaded (antifilter.download): $file.lst"
			updated=true
		else
			warn "Failed: $file.lst"
		fi
	done

	for file in ip ipsmart ipsum subnet uablacklist govno ip6; do
		src_enabled "nf_$file" || { log "Skipped (disabled): nf_$file"; continue; }
		if download_file "https://antifilter.network/download/${file}.lst" "$TMP_DIR/nf_${file}.lst"; then
			log "Downloaded (antifilter.network): nf_${file}.lst"
			updated=true
		else
			warn "Failed: nf_${file}.lst"
		fi
	done

	$updated || true
}

# Step 3: compare tmp vs list, update on change
compare_and_update() {
	log "--- Comparing lists ---"
	local updated=0 unchanged=0 f name target
	for f in "$TMP_DIR"/*.lst; do
		[ -f "$f" ] || continue
		name=$(basename "$f")
		target="$LIST_DIR/$name"
		if files_differ "$f" "$target"; then
			cp "$f" "$target"
			log "Updated: $name"
			updated=$((updated+1))
		else
			log "Unchanged: $name"
			unchanged=$((unchanged+1))
		fi
	done
	log "Result: $updated updated, $unchanged unchanged"
}

# Step 4: list -> list_rsc (.rsc) per file.
# For the BGP client role routes are sent via the wireguard interface;
# the via_interface is substituted into each route line.
process_lists() {
	log "--- Processing lists -> list_rsc ---"
	rm -f "$RSC_DIR"/*.rsc 2>/dev/null

	local f name
	for f in "$LIST_DIR"/*.lst; do
		[ -f "$f" ] || continue
		name=$(basename "$f" .lst)
		# strip comments/blank lines, append /32 to bare IPs, emit via-route
		sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$f" \
			| awk -v iface="$VIA_IFACE" '!/\// { $0=$0"/32" } { print "route " $0 " via \"" iface "\";" }' \
			| sort -u > "$RSC_DIR/$name.rsc"
		count=$(wc -l < "$RSC_DIR/$name.rsc")
		log "Generated: $name.rsc ($count routes)"
	done
}

main() {
	log "=== BIRD2 List Sync Started ==="

	mkdir -p "$LIST_DIR" "$RSC_DIR" "$LIST_CUSTOM_DIR" "$TMP_DIR" 2>/dev/null

	load_global
	sync_custom_lists
	download_antifilter_lists
	compare_and_update
	process_lists

	rm -f "$TMP_DIR"/*.lst 2>/dev/null

	if /usr/sbin/birdc configure >/dev/null 2>&1; then
		log "BIRD reloaded"
	else
		log "BIRD not running - config will be applied on start"
	fi

	log "=== BIRD2 List Sync Completed ==="
}

main "$@"
