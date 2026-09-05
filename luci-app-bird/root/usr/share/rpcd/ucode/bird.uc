'use strict';

// BIRD antifilter rpcd backend.
// Provides ubus methods "luci.bird.*" for status, service control, list
// synchronization, and management of custom / blacklist list files.
//
// NOTE: runs under OpenWrt ucode. Arrays are iterated with
// `for (let x in arr)` which yields VALUES, and the globals `push()`,
// `length()`, `split()`, `join()`, `match()` are used instead of ES methods.

const fs = require('fs');
const uci = require('uci');

// ---- helpers ----
function capture(cmd) {
	let p = fs.popen(cmd, 'r');
	let out = p.read('all');
	p.close();
	return out || '';
}

function run(cmd) {
	return system(cmd);
}

function isRunning() {
	return run('/usr/sbin/birdc show protocols >/dev/null 2>&1') === 0;
}

function readLogTail(path, lines) {
	if (!fs.stat(path))
		return '';
	let all = fs.readfile(path) || '';
	lines = lines || 400;
	let arr = split(all, '\n');
	if (length(arr) > lines) {
		let out = [];
		for (let i = length(arr) - lines; i < length(arr); i++)
			push(out, arr[i]);
		return join('\n', out);
	}
	return all;
}

function lastLine(path) {
	if (!fs.stat(path))
		return null;
	let arr = split(fs.readfile(path) || '', '\n');
	for (let i = length(arr) - 1; i >= 0; i--) {
		if (length(arr[i]) > 0)
			return arr[i];
	}
	return null;
}

function listNames(dir) {
	if (!fs.stat(dir))
		return [];
	return fs.lsdir(dir) || [];
}

function fileInfo(dir, name) {
	let st = fs.stat(dir + '/' + name);
	if (!st)
		return { size: 0 };
	return { size: st.size, mtime: st.mtime };
}

function validName(name) {
	name = '' + (name || '');
	if (length(name) === 0)
		return null;
	if (index(name, '/') >= 0 || index(name, '..') >= 0 || index(name, '\\') >= 0)
		return null;
	return name;
}

// ---- status ----
function status(request) {
	let running = isRunning();
	let protocols = '';
	let uptime = '';
	let memory = '';
	let routes = '';
	let enabled = false;

	let cur = uci.cursor();
	let en = cur.get('bird', 'global', 'enabled');
	if (en == '1')
		enabled = true;

	if (running) {
		uptime = capture('/usr/sbin/birdc show status');
		protocols = capture('/usr/sbin/birdc show protocols');
		memory = capture('/usr/sbin/birdc show memory');
		routes = capture('/usr/sbin/birdc show route count');
	}

	return {
		enabled: enabled,
		running: running,
		uptime: uptime,
		protocols: protocols,
		memory: memory,
		routes: routes,
		lastSync: lastLine('/var/log/bird-sync.log')
	};
}

// ---- service control ----
function service(request) {
	let argv = request.args || {};
	let action = '' + (argv.action || '');
	let allowed = [ 'start', 'stop', 'restart', 'reload' ];
	let ok = false;
	for (let a in allowed) {
		if (a == action) ok = true;
	}
	if (!ok)
		return { code: 1, stdout: '', error: 'invalid action' };
	let res = run('/etc/init.d/bird2-antifilter ' + action + ' >/dev/null 2>&1');
	sleep(500);
	return { code: res, stdout: '', error: res === 0 ? '' : 'command failed' };
}

// ---- sync ----
function sync(request) {
	let res = run('/usr/sbin/bird-sync.sh >/dev/null 2>&1');
	return { code: res, stdout: '', error: res === 0 ? '' : 'sync failed' };
}

function syncstatus(request) {
	return {
		lastSync: lastLine('/var/log/bird-sync.log'),
		log: readLogTail('/var/log/bird-sync.log', 300)
	};
}

function configfile(request) {
	let out = '';
	if (fs.stat('/etc/bird/bird.conf'))
		out = fs.readfile('/etc/bird/bird.conf') || '';
	return { content: out };
}

// ---- network autodetect (for peer auto-fill) ----
// Collects usable IPv4 addresses of the router: preferred is the interface
// that is used for list routes (via_interface), then the LAN interface
// (br-lan / lan), then everything else. Used by the peers view to prefill
// the "local" / "source address" field.
function netinfo(request) {
	let cur = uci.cursor();
	let via = cur.get('bird', 'global', 'via_interface') || 'awg0';
	let asn = cur.get('bird', 'global', 'local_as') || '64500';
	let lan_ip = '';
	let via_ip = '';
	let all = [];
	// Вывод по строке на интерфейс: "eth0 10.0.0.1" (awk удаляет маску и лишнее).
	let out = capture('ip -4 -o addr 2>/dev/null | awk \'{ c=index($4,"/"); if(c>0) ip=substr($4,0,c-1); else ip=$4; print $2, ip }\'');
	for (let line in split(out, '\n')) {
		let sp = split(line, ' ');
		if (length(sp) < 2)
			continue;
		let dev = sp[0];
		let ip = sp[1];
		if (length(dev) == 0 || ip == '127.0.0.1' || length(ip) == 0)
			continue;
		push(all, { iface: dev, ip: ip });
		if (dev == via)
			via_ip = ip;
		if (dev == 'br-lan' || dev == 'lan')
			lan_ip = ip;
	}
	// Fallback: UCI network.lan.ipaddr (может содержать /маску).
	if (length(lan_ip) == 0) {
		let li = cur.get('network', 'lan', 'ipaddr');
		if (li) {
			if (type(li) == 'array' && length(li) > 0)
				li = li[0];
			let p = index('' + li, '/');
			lan_ip = p >= 0 ? substr('' + li, 0, p) : ('' + li);
		}
	}
	return {
		interfaces: all,
		via_iface: via,
		via_ip: via_ip,
		lan_ip: '' + lan_ip,
		local_as: '' + asn
	};
}

// ---- custom & blacklist list files ----
function lists(request) {
	let custom = [];
	let customDir = '/etc/bird/list_custom';
	for (let n in listNames(customDir)) {
		let info = fileInfo(customDir, n);
		push(custom, { name: n, size: info.size, mtime: info.mtime });
	}

	let black = [];
	let argv = request.args || {};
	let blackDir = '' + (argv.blacklist_dir || '/etc/bird/blacklist');
	for (let n in listNames(blackDir)) {
		let info = fileInfo(blackDir, n);
		push(black, { name: n, size: info.size, mtime: info.mtime });
	}

	let rscCount = length(listNames('/etc/bird/list_rsc'));

	return { custom: custom, blacklist: black, rscCount: rscCount };
}

function readList(request) {
	let argv = request.args || {};
	let kind = argv.kind === 'blacklist' ? 'blacklist' : 'custom';
	let dir = kind === 'blacklist' ? '/etc/bird/blacklist' : '/etc/bird/list_custom';
	let name = validName(argv.name);
	if (!name)
		return { code: 1, content: '', error: 'invalid name' };
	if (!fs.stat(dir + '/' + name))
		return { code: 1, content: '', error: 'no such file' };
	return { code: 0, content: fs.readfile(dir + '/' + name) || '' };
}

function writeList(request) {
	let argv = request.args || {};
	let kind = argv.kind === 'blacklist' ? 'blacklist' : 'custom';
	let dir = kind === 'blacklist' ? '/etc/bird/blacklist' : '/etc/bird/list_custom';
	let name = validName(argv.name);
	if (!name)
		return { code: 1, error: 'invalid name' };
	let content = (argv.content == null) ? '' : ('' + argv.content);
	let rc = fs.writefile(dir + '/' + name, content) == null ? 1 : 0;
	return { code: rc };
}

function deleteList(request) {
	let argv = request.args || {};
	let kind = argv.kind === 'blacklist' ? 'blacklist' : 'custom';
	let dir = kind === 'blacklist' ? '/etc/bird/blacklist' : '/etc/bird/list_custom';
	let name = validName(argv.name);
	if (!name)
		return { code: 1, error: 'invalid name' };
	return { code: run('rm -f "' + dir + '/' + name + '"') };
}

// ---- source list catalog & selection (UCI bird.antifilter.*) ----
const SOURCES = [
	{ key: 'antifilter', title: 'antifilter.download',
	  lists: [
		{ key: 'ip',         label: 'IP (полный список)',
		  desc: 'Отдельные IP-адреса, определённые резолвингом доменов из блэклиста РКН. ~50k префиксов, употреблять с осторожностью.',
		  url: 'https://antifilter.download/list/ip.lst' },
		{ key: 'ipresolve',  label: 'IP resolve',
		  desc: 'Отдельные IP-адреса от дружественной компании, получены резолвингом. ~154k префиксов, употреблять с осторожностью.',
		  url: 'https://antifilter.download/list/ipresolve.lst' },
		{ key: 'ipsum',      label: 'IP суммарный (ipsum)',
		  desc: 'Суммаризация отдельных адресов по маске /24. ~16k префиксов.',
		  url: 'https://antifilter.download/list/ipsum.lst' },
		{ key: 'subnet',     label: 'Подсети (subnet)',
		  desc: 'Подсети, не перекрывающие ipsum.lst. Нужны даже при использовании других списков.',
		  url: 'https://antifilter.download/list/subnet.lst' },
		{ key: 'allyouneed', label: 'AllYouNeed (объединённый)',
		  desc: 'Суммарный список префиксов из ipsum.lst и subnet.lst. Рекомендуется большинству.',
		  url: 'https://antifilter.download/list/allyouneed.lst' },
		{ key: 'community',  label: 'Community',
		  desc: 'Списки, поддерживаемые сообществом сервиса.',
		  url: 'https://community.antifilter.download/list/community.lst' }
	  ]},
	{ key: 'nf_net', title: 'antifilter.network',
	  lists: [
		{ key: 'nf_ip',          label: 'IP (полный список)',
		  desc: 'Отдельные IP-адреса из списка РКН без суммаризации (reestr.rublacklist.net, zapret-info) + резолвинг доменов собственными серверами. ~100k префиксов.',
		  url: 'https://antifilter.network/download/ip.lst' },
		{ key: 'nf_ipsmart',     label: 'IP smart',
		  desc: 'IP-адреса с суммаризацией по сетям от /32 до /23, строится из ip.lst. ~21k префиксов.',
		  url: 'https://antifilter.network/download/ipsmart.lst' },
		{ key: 'nf_ipsum',       label: 'IP суммарный (ipsum)',
		  desc: 'Суммаризация отдельных адресов по маске /24, строится из ipsmart.lst. ~21k префиксов.',
		  url: 'https://antifilter.network/download/ipsum.lst' },
		{ key: 'nf_subnet',      label: 'Подсети (subnet)',
		  desc: 'Подсети, не перекрывающие ipsum.lst; все префиксы меньше /24 для совместного использования.',
		  url: 'https://antifilter.network/download/subnet.lst' },
		{ key: 'nf_uablacklist', label: 'UA Blacklist',
		  desc: 'Список адресов и сетей, заблокированных на Украине (uablacklist.net).',
		  url: 'https://antifilter.network/download/uablacklist.lst' },
		{ key: 'nf_govno',       label: 'Govno (гос. сети)',
		  desc: 'Сети государственных структур — GOVernment Networks Only (AntiZapret).',
		  url: 'https://antifilter.network/download/govno.lst' },
		{ key: 'nf_custom',      label: 'Custom',
		  desc: 'Сети, собранные пользователями сервиса через antifilter.network/add.',
		  url: 'https://antifilter.network/downloads/custom.lst' },
		{ key: 'nf_ip6',         label: 'IPv6',
		  desc: 'Список IPv6-сетей (reestr.rublacklist.net, zapret-info). ~127k префиксов.',
		  url: 'https://antifilter.network/download/ip6.lst' }
	  ]}
];

function allListKeys() {
	let keys = [];
	for (let s in SOURCES) {
		for (let l in s.lists)
			push(keys, l.key);
	}
	return keys;
}

function available(request) {
	return { sources: SOURCES };
}

function selection(request) {
	let cur = uci.cursor();
	let values = {};
	let keys = allListKeys();
	for (let k in keys) {
		let v = cur.get('bird', 'antifilter', k);
		values[k] = v == '1' ? '1' : (v ? v : '');
	}
	return { values: values };
}

function saveSources(request) {
	try {
		let argv = request.args || {};
		let enc = '' + (argv.encoded || '');
		let parsed = json(enc);
		if (!parsed || type(parsed.values) != 'object')
			return { code: 1, error: 'bad input' };

		let cur = uci.cursor();
		let keys = allListKeys();
		for (let k in keys) {
			let raw = parsed.values[k];
			let val = raw == null ? '0' : ('' + raw == '0' ? '0' : '1');
			cur.set('bird', 'antifilter', k, val);
		}
		cur.save('bird');
		cur.commit('bird');
		return { code: 0, error: '' };
	} catch (e) {
		return { code: 1, error: 'exception: ' + e };
	}
}

return {
	'luci.bird': {
		status:      { call: status },
		service:     { args: { action: 'action' }, call: service },
		sync:        { call: sync },
		syncstatus:  { call: syncstatus },
		configfile:  { call: configfile },
		netinfo:     { call: netinfo },
		lists:       { args: { blacklist_dir: 'blacklist_dir' }, call: lists },
		readList:    { args: { name: 'name', kind: 'kind' }, call: readList },
		writeList:   { args: { name: 'name', kind: 'kind', content: 'content' }, call: writeList },
		deleteList:  { args: { name: 'name', kind: 'kind' }, call: deleteList },
		available:   { call: available },
		selection:   { call: selection },
		saveSources: { args: { encoded: 'encoded' }, call: saveSources }
	}
};
