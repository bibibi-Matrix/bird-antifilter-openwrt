'use strict';

// BIRD antifilter rpcd backend.
// Registers the "luci.bird" ubus object with methods to inspect and
// control the BIRD daemon and the list synchronization.

const fs = require('fs');
const uci = require('uci');

// Run a command capturing stdout; returns { code, stdout }.
function capture(cmd) {
	const p = fs.popen(cmd, 'r');
	const out = p.read('all');
	const code = p.close();
	return { code: code, stdout: out || '' };
}

// Run a command without capturing output; returns exit code.
function run(cmd) {
	return system(cmd);
}

function isRunning() {
	return run('/usr/sbin/birdc show uptime >/dev/null 2>&1') === 0;
}

function status(request) {
	const svc = isRunning();
	let protocols = '';
	let uptime = '';

	if (svc) {
		protocols = capture('/usr/sbin/birdc show protocols').stdout;
		uptime = capture('/usr/sbin/birdc show uptime').stdout;
	}

	let enabled = false;
	const cur = uci.cursor();
	const en = cur.get('bird', 'global', 'enabled');
	if (en == '1')
		enabled = true;

	let lastSync = null;
	if (fs.stat('/var/log/bird-sync.log')) {
		let lines = fs.readfile('/var/log/bird-sync.log').split('\n');
		lines = lines.filter((l) => l.length > 0);
		if (lines.length > 0)
			lastSync = lines[lines.length - 1];
	}

	return {
		enabled: enabled,
		running: svc,
		uptime: uptime,
		protocols: protocols,
		lastSync: lastSync
	};
}

function sync(request) {
	return capture('/usr/sbin/bird-sync.sh');
}

function configure(request) {
	return capture('/usr/sbin/birdc configure');
}

function syncstatus(request) {
	let last = null;
	if (fs.stat('/var/log/bird-sync.log')) {
		let lines = fs.readfile('/var/log/bird-sync.log').split('\n');
		lines = lines.filter((l) => l.length > 0);
		if (lines.length > 0)
			last = lines[lines.length - 1];
	}
	return { lastSync: last };
}

return {
	'luci.bird': {
		status: { call: status },
		sync: { call: sync },
		configure: { call: configure },
		syncstatus: { call: syncstatus }
	}
};
