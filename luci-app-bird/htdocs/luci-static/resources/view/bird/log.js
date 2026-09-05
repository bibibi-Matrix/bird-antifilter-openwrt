'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var callSyncStatus = rpc.declare({
	object: 'luci.bird',
	method: 'syncstatus',
	expect: { '': {} }
});

var callConfigFile = rpc.declare({
	object: 'luci.bird',
	method: 'configfile',
	expect: { '': {} }
});

var callStatus = rpc.declare({
	object: 'luci.bird',
	method: 'status',
	expect: { '': {} }
});

return view.extend({
	render: function() {
		var container = E('div', { 'id': 'bird_log_container' });
		var updating = null;

		var refresh = function() {
			if (updating)
				return updating;
			updating = Promise.all([ callSyncStatus(), callConfigFile() ]).then(function(results) {
				var log = results[0].log || '';
				var conf = results[1].content || '';
				container.innerHTML = '';

				var logBox = E('div', { 'class': 'cbi-section' }, [
					E('h3', { 'class': 'cbi-section-title' }, _('Журнал синхронизации')),
					E('pre', { 'class': 'cbi-section-node' }, log || _('Журнал пуст.'))
				]);
				container.appendChild(logBox);

				var confBox = E('div', { 'class': 'cbi-section' }, [
					E('h3', { 'class': 'cbi-section-title' }, _('Текущий конфиг BIRD (/etc/bird/bird.conf)')),
					E('pre', { 'class': 'cbi-section-node' }, conf || _('Конфиг не найден.'))
				]);
				container.appendChild(confBox);
				return container;
			}).finally(function() {
				updating = null;
			});
			return updating;
		};

		this._po = poll.add(refresh, 30);

		return refresh();
	},
	destroy: function() {
		if (this._po)
			poll.remove(this._po);
	}
});