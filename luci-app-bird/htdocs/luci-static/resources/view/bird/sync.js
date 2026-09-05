'use strict';
'require form';
'require rpc';
'require ui';

var callSync = rpc.declare({
	object: 'luci.bird',
	method: 'sync',
	expect: { code: 0, stdout: '', stderr: '' }
});

var callSyncStatus = rpc.declare({
	object: 'luci.bird',
	method: 'syncstatus',
	expect: { lastSync: '' }
});

return L.view.extend({
	render: function() {
		var m = new L.form.Map('bird', _('List synchronization'), _(
			'Configure when the IP lists are re-downloaded and converted. ' +
			'You can also trigger a synchronization manually.'));

		var s = m.section(form.NamedSection, 'global', 'bird', _('Schedule'));
		s.anonymous = true;

		var o = s.option(form.Flag, 'sync_cron', _('Enable periodic sync'));
		o.rmempty = false;

		o = s.option(form.Value, 'cron_expr', _('Cron expression'));
		o.default = '0 3 * * *';
		o.rmempty = true;

		var output = E('pre', { 'class': 'cbi-section-node' });

		return m.render().then(function(node) {
			var box = E('div', { 'class': 'cbi-section' }, [
				E('h3', { 'class': 'cbi-section-title' }, _('Actions')),
				E('div', { 'class': 'cbi-page-actions' },
					E('input', {
						'type': 'button',
						'class': 'cbi-button cbi-button-apply',
						'value': _('Run synchronization now'),
						'click': function() {
							callSync().then(function(res) {
								var msg = res.code === 0 ? _('Synchronization finished') : _('Synchronization failed');
								ui.addNotification(null, E('p', msg));
								output.textContent = res.stdout || res.stderr || '';
							});
						}
					}))
			]);
			box.appendChild(output);

			node.appendChild(box);
			return node;
		});
	}
});