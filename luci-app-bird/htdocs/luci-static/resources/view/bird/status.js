'use strict';
'require view';
'require rpc';
'require ui';

var callBird = rpc.declare({
	object: 'luci.bird',
	method: 'status',
	expect: { enabled: false, running: false, uptime: '', protocols: '', lastSync: '' }
});

var callConfigure = rpc.declare({
	object: 'luci.bird',
	method: 'configure',
	expect: { code: 0, stdout: '' }
});

var callSync = rpc.declare({
	object: 'luci.bird',
	method: 'sync',
	expect: { code: 0, stdout: '', stderr: '' }
});

return view.extend({
	render: function() {
		return callBird().then(function(data) {
			var container = E([]);

			var statusChildren = [
				E('h3', { 'class': 'cbi-section-title' }, _('Service status')),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, _('Service enabled')),
					E('div', { 'class': 'cbi-value-field' },
						E('span', { 'class': data.enabled ? 'fa fa-check' : 'fa fa-times' }, data.enabled ? _('Enabled') : _('Disabled')))
				]),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, _('Daemon running')),
					E('div', { 'class': 'cbi-value-field' },
						E('span', { 'class': data.running ? 'fa fa-check' : 'fa fa-times' }, data.running ? _('Running') : _('Stopped')))
				])
			];

			if (data.uptime)
				statusChildren.push(
					E('div', { 'class': 'cbi-value' }, [
						E('label', { 'class': 'cbi-value-title' }, _('Uptime')),
						E('div', { 'class': 'cbi-value-field' }, E('textarea', { 'readonly': 'readonly', 'rows': 1 }, data.uptime))
					]));

			if (data.lastSync)
				statusChildren.push(
					E('div', { 'class': 'cbi-value' }, [
						E('label', { 'class': 'cbi-value-title' }, _('Last sync')),
						E('div', { 'class': 'cbi-value-field' }, E('textarea', { 'readonly': 'readonly', 'rows': 1 }, data.lastSync))
					]));

			container.appendChild(E('div', { 'class': 'cbi-section' }, statusChildren));

			if (data.protocols)
				container.appendChild(
					E('div', { 'class': 'cbi-section' }, [
						E('h3', { 'class': 'cbi-section-title' }, _('BIRD protocols')),
						E('pre', { 'class': 'cbi-section-node' }, data.protocols)
					]));

			container.appendChild(
				E('div', { 'class': 'cbi-section' }, [
					E('h3', { 'class': 'cbi-section-title' }, _('Actions')),
					E('div', { 'class': 'cbi-page-actions' }, [
						E('input', {
							'type': 'button',
							'class': 'cbi-button cbi-button-apply',
							'value': _('Reload Bird configuration'),
							'click': function() {
								callConfigure().then(function() {
									ui.addNotification(null, E('p', _('Bird configuration reloaded')));
								});
							}
						}),
						E('input', {
							'type': 'button',
							'class': 'cbi-button cbi-button-reset',
							'value': _('Run list sync'),
							'click': function() {
								callSync().then(function() {
									ui.addNotification(null, E('p', _('List sync finished')));
								});
							}
						})
					])
				]));

			return container;
		});
	}
});