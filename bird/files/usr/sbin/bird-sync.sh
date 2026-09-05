#!/bin/sh
# BIRD2 antifilter list sync for OpenWrt.
# Port of the original bird2.sh (docker-based) adapted to BusyBox/ash.

set -u

LOG_TAG="bird-sync"

LIST_DIR="/etc/bird/list"
LIST_CUSTOM_DIR="/etc/bird/list_custom"
RSC_DIR="/etc/bird/list_rsc"
BLACKLIST_DIR="/etc/bird/blacklist"
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
	BLACKLIST_DIR=$(get_global blacklist_dir)
	[ -n "$BLACKLIST_DIR" ] || BLACKLIST_DIR="/etc/bird/blacklist"
	VIA_IFACE=$(get_global via_interface)
	[ -n "$VIA_IFACE" ] || VIA_IFACE="awg0"
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

	# custom.lst на antifilter.network лежит по другому пути (/downloads, а не /download)
	if src_enabled "nf_custom"; then
		if download_file "https://antifilter.network/downloads/custom.lst" "$TMP_DIR/nf_custom.lst"; then
			log "Downloaded (antifilter.network): nf_custom.lst"
			updated=true
		else
			warn "Failed: nf_custom.lst"
		fi
	fi

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

# Returns 0 if the given list base name (e.g. nf_govno) is enabled in UCI.
list_enabled() {
	local base="$1"
	case "$base" in
		ip)            src_enabled ip; return $? ;;
		ipresolve)     src_enabled ipresolve; return $? ;;
		ipsum)         src_enabled ipsum; return $? ;;
		subnet)        src_enabled subnet; return $? ;;
		allyouneed)    src_enabled allyouneed; return $? ;;
		community)     src_enabled community; return $? ;;
		nf_ip)         src_enabled nf_ip; return $? ;;
		nf_ipsmart)    src_enabled nf_ipsmart; return $? ;;
		nf_ipsum)      src_enabled nf_ipsum; return $? ;;
		nf_subnet)     src_enabled nf_subnet; return $? ;;
		nf_uablacklist) src_enabled nf_uablacklist; return $? ;;
		nf_govno)      src_enabled nf_govno; return $? ;;
		nf_custom)     src_enabled nf_custom; return $? ;;
		nf_ip6)        src_enabled nf_ip6; return $? ;;
	esac
	return 1
}

# Step 3b: remove lists that are no longer selected (neither enabled in
# UCI nor present in list_custom), so they stop generating routes.
cleanup_disabled_lists() {
	local removed=0 f base custom
	for f in "$LIST_DIR"/*.lst; do
		[ -f "$f" ] || continue
		base=$(basename "$f")
		if list_enabled "${base%.lst}"; then
			continue
		fi
		custom="$LIST_CUSTOM_DIR/$base"
		[ -f "$custom" ] && continue
		rm -f "$f"
		log "Removed disabled list: $base"
		removed=$((removed+1))
	done
	if [ "$removed" -gt 0 ]; then
		log "Removed $removed disabled lists"
	fi
}

# Step 4: list -> list_rsc per file, split by address family.
# For the BGP client role routes are sent via the wireguard interface;
# the via_interface is substituted into each route line.
# BIRD static instances support only one family, so the output is split
# into <name>.v4.rsc and <name>.v6.rsc.
process_lists() {
	log "--- Processing lists -> list_rsc (v4/v6) ---"
	rm -f "$RSC_DIR"/*.v4.rsc "$RSC_DIR"/*.v6.rsc 2>/dev/null

	local f name cnt
	local v4file v6file
	for f in "$LIST_DIR"/*.lst; do
		[ -f "$f" ] || continue
		name=$(basename "$f" .lst)
		v4file="$RSC_DIR/$name.v4.rsc"
		v6file="$RSC_DIR/$name.v6.rsc"
		# strip comments/blank lines, normalize bare IPv4 -> /32 / IPv6 -> /128,
		# emit via-route lines and split by family.
		sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$f" \
			| awk -v iface="$VIA_IFACE" '
				{
					if ($0 ~ /:/) { if ($0 !~ /\//) $0=$0"/128"; }
					else          { if ($0 !~ /\//) $0=$0"/32";  }
					print "route " $0 " via \"" iface "\";";
				}' \
			| sort -u \
			| awk -v v4="$v4file" -v v6="$v6file" \
				'$2 ~ /:/ { print > v6; next } { print > v4 }'
		if [ -f "$v4file" ]; then
			cnt=$(wc -l < "$v4file")
			log "Generated: $name.v4.rsc ($cnt routes)"
		fi
		if [ -f "$v6file" ]; then
			cnt=$(wc -l < "$v6file")
			log "Generated: $name.v6.rsc ($cnt routes)"
		fi
	done
}

# Step 5: Blacklist — удаление и вычитание префиксов (IPv4 + IPv6).
# Маршрут, целиком попадающий в чёрный список, удаляется; запись чёрного
# списка внутри более широкого префикса разбивает его на sibling-префиксы
# (blacklist_split). IP/CIDR представляются как 32-hex строки, операции над
# префиксами выполняются без 128-битной арифметики.
apply_blacklist() {
	if [ "$(get_global blacklist)" = "0" ]; then
		log "Blacklist: disabled"
		return 0
	fi

	if [ ! -d "$BLACKLIST_DIR" ] && ! mkdir -p "$BLACKLIST_DIR" 2>/dev/null; then
		log "Blacklist: cannot create directory $BLACKLIST_DIR"
		return 0
	fi

	if ! ls "$BLACKLIST_DIR"/*.lst >/dev/null 2>&1; then
		log "Blacklist: no .lst files"
		return 0
	fi

	log "--- Applying blacklist ---"

	# Конкатенируем все .lst чёрного списка в один файл
	local bl_combined="$TMP_DIR/blacklist_combined.txt"
	: > "$bl_combined"
	local bl_files_count=0 bl_file
	for bl_file in "$BLACKLIST_DIR"/*.lst; do
		[ -f "$bl_file" ] || continue
		bl_files_count=$((bl_files_count + 1))
		sed '/^#/d; /^[[:space:]]*$/d' "$bl_file" >> "$bl_combined"
	done

	if [ ! -s "$bl_combined" ]; then
		log "Blacklist: empty ($bl_files_count files scanned)"
		return 0
	fi

	local bl_split="no"
	[ "$(get_global blacklist_split)" != "0" ] && bl_split="yes"

	# Общие функции: IPv4/IPv6 -> 32-hex, вложение и деление префиксов.
	cat > "$TMP_DIR/bl_lib.awk" <<'AWK'
function hd(ch,    idx) {
    idx = index("0123456789abcdefABCDEF", ch);
    if (idx == 0) return -1;
    if (idx > 16) return idx - 16 - 1;
    return idx - 1;
}
function hexd(v) { return substr("0123456789abcdef", v + 1, 1); }
function hex2(v) { return hexd(int(v / 16)) hexd(v % 16); }
function hex4(v) { return hexd(int(v / 4096)) hexd(int(v / 256) % 16) hexd(int(v / 16) % 16) hexd(v % 16); }
function hx(str,    v, i) {
    v = 0;
    for (i = 1; i <= length(str); i++) v = v * 16 + hd(substr(str, i, 1));
    return v;
}
function v4tohex(addr,    o, n, i, v, h) {
    n = split(addr, o, ".");
    if (n != 4) return "";
    h = "";
    for (i = 1; i <= 4; i++) {
        if (o[i] == "" || o[i] ~ /[^0-9]/) return "";
        v = o[i] + 0;
        if (v > 255) return "";
        h = h hex2(v);
    }
    return h;
}
function pad4(hexgrp,    v, i) {
    v = 0;
    for (i = 1; i <= length(hexgrp); i++) v = v * 16 + hd(substr(hexgrp, i, 1));
    return hex4(v);
}
function v6tohex(addr,    a, xmarks, n, i, p, hex, hg, emb, ehex, compress, c) {
    if (index(addr, ":") == 0) return "";
    a = addr;
    xmarks = gsub(/::/, ":X:", a);
    if (xmarks > 1) return "";
    n = split(a, parts_, ":");
    hex = ""; hg = 0; emb = 0; ehex = "";
    for (i = 1; i <= n; i++) {
        p = parts_[i];
        if (p == "X") continue;
        if (p == "") {
            # граничные пустые поля допустимы только у "::" на краях
            if (xmarks == 0) return "";
            if (i != 1 && i != n) return "";
            continue;
        }
        if (p ~ /\./) {
            if (emb) return "";
            ehex = v4tohex(p);
            if (ehex == "" || i != n) return "";
            emb = 1;
            continue;
        }
        if (!(p ~ /^[0-9a-fA-F]{1,4}$/)) return "";
        hg++;
    }
    hg = hg + (emb ? 2 : 0);
    if (xmarks > 0) {
        if (hg > 7) return "";
        compress = 8 - hg;
    } else {
        if (hg != 8) return "";
        compress = 0;
    }
    for (i = 1; i <= n; i++) {
        p = parts_[i];
        if (p == "X") {
            for (c = 1; c <= compress; c++) hex = hex "0000";
        } else if (p == "") {
            continue;
        } else if (p ~ /\./) {
            hex = hex ehex;
        } else {
            hex = hex pad4(p);
        }
    }
    if (length(hex) != 32) return "";
    return hex;
}
function ip2hex(addr,    h) {
    if (index(addr, ":") > 0) return v6tohex(addr);
    h = v4tohex(addr);
    if (h == "") return "";
    return "000000000000000000000000" h;
}
function fam_off(isv6) { return (isv6 ? 0 : 96); }
function masked(hex, off, L,    sc, full, rem, out, pad, i) {
    sc = off / 4 + 1;
    full = int(L / 4);
    rem = L % 4;
    out = substr(hex, 1, sc - 1);
    out = out substr(hex, sc, full);
    if (rem > 0) out = out hexd(KEEP[rem "," hd(substr(hex, sc + full, 1))]);
    pad = 32 - sc + 1 - (full + (rem > 0 ? 1 : 0));
    for (i = 1; i <= pad; i++) out = out "0";
    return out;
}
function bit_eq(a, b, off, L,    sc, full, rem, da, db) {
    sc = off / 4 + 1;
    full = int(L / 4);
    rem = L % 4;
    if (substr(a, sc, full) != substr(b, sc, full)) return 0;
    if (rem > 0) {
        da = KEEP[rem "," hd(substr(a, sc + full, 1))];
        db = KEEP[rem "," hd(substr(b, sc + full, 1))];
        if (da != db) return 0;
    }
    return 1;
}
function hex2v4(hex,    t) {
    t = substr(hex, 25, 8);
    return hx(substr(t, 1, 2)) "." hx(substr(t, 3, 2)) "." hx(substr(t, 5, 2)) "." hx(substr(t, 7, 2));
}
function hex2v6(hex,    g, i, bests, beste, run, out, pending) {
    for (i = 0; i < 8; i++) {
        g[i] = substr(hex, i * 4 + 1, 4);
        sub(/^0+/, "", g[i]);
        if (g[i] == "") g[i] = "0";
    }
    bests = -1; beste = -1;
    i = 0;
    while (i < 8) {
        if (g[i] == "0") {
            run = i;
            while (run < 8 && g[run] == "0") run++;
            if (run - i >= 2 && (run - i) > (beste - bests)) { bests = i; beste = run; }
            i = run;
        } else i++;
    }
    out = ""; pending = 0;
    for (i = 0; i < 8; i++) {
        if (bests >= 0 && i == bests) {
            out = out "::";
            i = beste - 1;
            pending = 0;
            continue;
        }
        if (pending) out = out ":";
        out = out g[i];
        pending = 1;
    }
    return out;
}
function sub_one(PH, PO, PM, BH, BO, BM,    L, off, path, ci, bo, sib) {
    res_n = 0;
    for (L = PM + 1; L <= BM; L++) {
        off = PO;
        path = masked(BH, off, L);
        ci = int((off + L - 1) / 4) + 1;
        bo = (off + L - 1) % 4;
        sib = substr(path, 1, ci - 1) hexd(FLIP[bo "," hd(substr(path, ci, 1))]) substr(path, ci + 1);
        res_n++;
        res_h[res_n] = sib;
        res_m[res_n] = L;
    }
}
function tables_init(    d) {
    for (d = 0; d < 16; d++) {
        KEEP[1 "," d] = (d >= 8 ? 8 : 0);
        KEEP[2 "," d] = int(d / 4) * 4;
        KEEP[3 "," d] = int(d / 2) * 2;
        FLIP[0 "," d] = (d >= 8 ? d - 8 : d + 8);
        FLIP[1 "," d] = (int(d / 4) % 2 ? d - 4 : d + 4);
        FLIP[2 "," d] = (int(d / 2) % 2 ? d - 2 : d + 2);
        FLIP[3 "," d] = (d % 2 ? d - 1 : d + 1);
    }
}
AWK

	# Нормализация чёрного списка: запись -> "hex|mask|is_v6",
	# невалидные и дубликаты отбрасываются с подсчётом.
	cat > "$TMP_DIR/bl_norm.awk" <<'AWK'
BEGIN {
    tables_init();
    inv = 0; dupb = 0;
    while ((getline line < src) > 0) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line);
        ok = 0;
        if (line != "" && !(line ~ /^#/)) {
            if (index(line, "/") == 0) {
                if (index(line, ":") > 0) line = line "/128"; else line = line "/32";
            }
            split(line, p, "/");
            if (p[2] ~ /^[0-9]+$/) {
                pm = p[2] + 0;
                pv6 = (index(p[1], ":") > 0);
                if (pm >= 1 && !(pv6 && pm > 128) && !(!pv6 && pm > 32)) {
                    ph = ip2hex(p[1]);
                    ok = (ph != "");
                    if (!ok) inv++;
                } else { inv++; }
            } else { inv++; }
        }
        if (ok) {
            key = ph "," pm;
            if (seen[key]) { dupb++; }
            else { seen[key] = 1; printf "%s|%d|%d\n", ph, pm, pv6; }
        }
    }
    close(src);
    printf "INVALID %d\n", inv > "/dev/stderr";
    printf "DUPBL %d\n", dupb > "/dev/stderr";
}
AWK

	awk -v src="$bl_combined" -f "$TMP_DIR/bl_lib.awk" -f "$TMP_DIR/bl_norm.awk" \
		> "$TMP_DIR/blacklist_norm.txt" 2>"$TMP_DIR/blacklist_norm_err.txt" || true

	local bl_inv=0 bl_dupb=0 bl_line=""
	while IFS= read -r bl_line; do
		case "$bl_line" in
			INVALID*) bl_inv=${bl_line#INVALID } ;;
			DUPBL*)   bl_dupb=${bl_line#DUPBL } ;;
		esac
	done < "$TMP_DIR/blacklist_norm_err.txt"
	rm -f "$TMP_DIR/blacklist_norm_err.txt"
	if [ "$bl_inv" -gt 0 ]; then warn "Blacklist: $bl_inv invalid entries skipped"; fi
	if [ "$bl_dupb" -gt 0 ]; then log "Blacklist: $bl_dupb duplicate entries collapsed"; fi

	if [ ! -s "$TMP_DIR/blacklist_norm.txt" ]; then
		log "Blacklist: no valid entries"
		rm -f "$bl_combined" "$TMP_DIR/blacklist_norm.txt"
		return 0
	fi

	# Основной фильтр: маршрут в чёрном -> удалить; чёрный внутри маршрута ->
	# разбить маршрут на sibling-префиксы (если включено). Строка .rsc имеет
	# вид "route CIDR via \"iface\";" — хвост сохраняется как есть.
	cat > "$TMP_DIR/bl_apply.awk" <<'AWK'
BEGIN {
    tables_init();
    nbl = 0;
    while ((getline line < src) > 0) {
        if (line != "" && !(line ~ /^#/)) {
            split(line, f, "|");
            bl_hex[nbl] = f[1];
            bl_mask[nbl] = f[2] + 0;
            bl_v6[nbl] = f[3] + 0;
            bl_off[nbl] = fam_off(bl_v6[nbl]);
            nbl++;
        }
    }
    close(src);
    if (nbl == 0) no_bl = 1;
    blocked_cnt = 0; split_cnt = 0;
}
{
    if (no_bl) { print; next; }
    orig = $0;
    gsub(/^route /, "");
    if (index($0, "/") == 0) { print orig; next; }
    rest = $0; tail = $0;
    sub(/ .*$/, "", rest);
    sub(/^[^ ]+ /, "", tail);
    split(rest, p, "/");
    rv6 = (index(p[1], ":") > 0);
    roff = fam_off(rv6);
    rmask = p[2] + 0;
    rhex = ip2hex(p[1]);
    if (rhex == "") { print orig; next; }

    blocked = 0;
    for (i = 0; i < nbl; i++) {
        if (bl_v6[i] != rv6) continue;
        if (bl_mask[i] <= rmask && bit_eq(bl_hex[i], rhex, bl_off[i], bl_mask[i])) { blocked = 1; break; }
    }
    if (blocked) { blocked_cnt++; next; }

    if (do_split == "yes") {
        nin = 0;
        for (i = 0; i < nbl; i++) {
            if (bl_v6[i] != rv6) continue;
            if (bl_mask[i] > rmask && bit_eq(rhex, bl_hex[i], roff, rmask)) inside[++nin] = i;
        }
        if (nin > 0) {
            pc = 1; p_h[1] = rhex; p_m[1] = rmask;
            for (j = 1; j <= nin; j++) {
                b = inside[j];
                nc = 0;
                for (k = 1; k <= pc; k++) {
                    if (p_m[k] < bl_mask[b] && bit_eq(p_h[k], bl_hex[b], roff, p_m[k])) {
                        sub_one(p_h[k], roff, p_m[k], bl_hex[b], bl_off[b], bl_mask[b]);
                        for (t = 1; t <= res_n; t++) { nc++; n_h[nc] = res_h[t]; n_m[nc] = res_m[t]; }
                    } else if (bl_mask[b] <= p_m[k] && bit_eq(bl_hex[b], p_h[k], bl_off[b], bl_mask[b])) {
                        continue;
                    } else {
                        nc++; n_h[nc] = p_h[k]; n_m[nc] = p_m[k];
                    }
                }
                for (k = 1; k <= nc; k++) { p_h[k] = n_h[k]; p_m[k] = n_m[k]; }
                pc = nc;
            }
            split_cnt++;
            for (k = 1; k <= pc; k++) {
                if (rv6) a = hex2v6(p_h[k]); else a = hex2v4(p_h[k]);
                print "route " a "/" p_m[k] " " tail;
            }
            next;
        }
    }
    print "route " rest " " tail;
}
END {
    if (cnt_f != "") {
        printf "%d\n", blocked_cnt > cnt_f;
        printf "%d\n", split_cnt > cnt_f;
        close(cnt_f);
    }
}
AWK

	local removed=0 splits=0 file fname before bcnt scnt
	for file in "$RSC_DIR"/*.rsc; do
		[ -f "$file" ] || continue
		fname=$(basename "$file")
		before=$(wc -l < "$file")
		local cntf="$TMP_DIR/blk_counts.${fname}.txt"
		: > "$cntf"

		awk -v src="$TMP_DIR/blacklist_norm.txt" -v cnt_f="$cntf" \
			-v do_split="$bl_split" \
			-f "$TMP_DIR/bl_lib.awk" -f "$TMP_DIR/bl_apply.awk" \
			"$file" > "$file.tmp" || true

		bcnt=0; scnt=0
		{ read -r bcnt; read -r scnt; } < "$cntf" || true
		removed=$((removed + bcnt))
		splits=$((splits + scnt))
		if [ -s "$file.tmp" ]; then
			mv -f "$file.tmp" "$file"
		else
			rm -f "$file.tmp"
			continue
		fi
		local after
		after=$(wc -l < "$file")
		if [ "$bcnt" -gt 0 ] || [ "$scnt" -gt 0 ] || [ "$before" -ne "$after" ]; then
			log "  $fname: removed $bcnt, split $scnt (routes: $before -> $after)"
		fi
	done

	# После разбиения некоторые префиксы могут совпасть с уже существующими
	# маршрутами других файлов — глобальная дедупликация с сортировкой.
	local total_dups=0
	if [ "$splits" -gt 0 ]; then
		local comb="$TMP_DIR/rsc_combine.txt"
		: > "$comb"
		for file in "$RSC_DIR"/*.rsc; do
			[ -f "$file" ] || continue
			awk -v tag="$(basename "$file")" '{ print tag "\t" $0 }' "$file" >> "$comb"
		done

		local outd="$TMP_DIR/rsc_out"
		rm -rf "$outd"
		mkdir -p "$outd"
		local dcounts="$TMP_DIR/rsc_dup.txt"
		: > "$dcounts"

		sort -t "$(printf '\t')" -k2,2 "$comb" | awk -F'\t' -v outd="$outd" -v dcounts="$dcounts" '
			{
				if (seen[$2]++) { dups[$1]++; next; }
				print $2 > (outd "/" $1);
			}
			END {
				for (f in dups) printf "%s\t%d\n", f, dups[f] > dcounts;
				close(dcounts);
			}
		'

		local fnam n
		while IFS="$(printf '\t')" read -r fnam n; do
			[ -n "$fnam" ] || continue
			total_dups=$((total_dups + n))
			[ "$n" -gt 0 ] && log "  $fnam: dedup -$n duplicates"
		done < "$dcounts"

		for file in "$RSC_DIR"/*.rsc; do
			[ -f "$file" ] || continue
			local fn
			fn=$(basename "$file")
			if [ -f "$outd/$fn" ] && [ -s "$outd/$fn" ]; then
				mv -f "$outd/$fn" "$file"
			else
				rm -f "$file"
			fi
		done

		rm -f "$comb"
		rm -rf "$outd"
		rm -f "$dcounts"
	else
		for file in "$RSC_DIR"/*.rsc; do
			[ -f "$file" ] && [ ! -s "$file" ] && rm -f "$file"
		done
	fi

	log "Blacklist applied: $removed removed, $splits split, $total_dups dedup"
	rm -f "$bl_combined" "$TMP_DIR/blacklist_norm.txt" \
		"$TMP_DIR/bl_lib.awk" "$TMP_DIR/bl_norm.awk" "$TMP_DIR/bl_apply.awk" \
		"$TMP_DIR/blk_counts."*.txt 2>/dev/null || true
}

LOG_FILE="/var/log/bird-sync.log"

main() {
	log "=== BIRD2 List Sync Started ==="

	mkdir -p "$LIST_DIR" "$RSC_DIR" "$LIST_CUSTOM_DIR" "$TMP_DIR" 2>/dev/null

	# Clean stale tmp lists first so an old download never re-imports a
	# now-disabled list into LIST_DIR / list_rsc.
	rm -f "$TMP_DIR"/*.lst 2>/dev/null

	load_global
	sync_custom_lists
	download_antifilter_lists
	compare_and_update
	cleanup_disabled_lists
	process_lists
	apply_blacklist

	rm -f "$TMP_DIR"/*.lst 2>/dev/null

	if [ -x /usr/sbin/birdc ] && /usr/sbin/birdc configure >/dev/null 2>&1; then
		log "BIRD reloaded"
	else
		log "BIRD not running - config will be applied on start"
	fi

	log "=== BIRD2 List Sync Completed ==="
}

# Persistent log for the LuCI status page.
main "$@" 2>&1 | tee -a "$LOG_FILE"