'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var callStatus = rpc.declare({
	object: 'luci.bird',
	method: 'status',
	expect: { '': {} }
});

var callService = rpc.declare({
	object: 'luci.bird',
	method: 'service',
	params: { action: '' },
	expect: { '': {} }
});

var callSync = rpc.declare({
	object: 'luci.bird',
	method: 'sync',
	expect: { '': {} }
});

function cell(label, field) {
	return E('div', { 'class': 'cbi-value' }, [
		E('label', { 'class': 'cbi-value-title' }, label),
		E('div', { 'class': 'cbi-value-field' }, field)
	]);
}

function boolSpan(ok, yes, no) {
	return E('span', { 'class': ok ? 'fa fa-check' : 'fa fa-times' },
		ok ? yes : no);
}

function render(data) {
	var box = E([]);

	var g = E('div', { 'class': 'cbi-section' }, [
		E('h3', { 'class': 'cbi-section-title' }, _('Состояние сервиса'))
	]);
	g.appendChild(cell(_('Сервис включён'), boolSpan(data.enabled, _('Включено'), _('Выключено'))));
	g.appendChild(cell(_('Демон BIRD'), boolSpan(data.running, _('Работает'), _('Остановлен'))));
	if (data.uptime)
		g.appendChild(cell(_('Время работы'), E('pre', { 'class': 'cbi-section-node' }, data.uptime.trim())));
	if (data.lastSync)
		g.appendChild(cell(_('Последняя синхронизация'), E('pre', { 'class': 'cbi-section-node' }, data.lastSync)));
	box.appendChild(g);

	if (data.protocols)
		box.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', { 'class': 'cbi-section-title' }, _('Протоколы BIRD')),
			E('pre', { 'class': 'cbi-section-node' }, data.protocols)
		]));

	if (data.memory)
		box.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', { 'class': 'cbi-section-title' }, _('Память')),
			E('pre', { 'class': 'cbi-section-node' }, data.memory)
		]));

	if (data.routes)
		box.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', { 'class': 'cbi-section-title' }, _('Маршруты (статистика)')),
			E('pre', { 'class': 'cbi-section-node' }, data.routes)
		]));

	var actions = E('div', { 'class': 'cbi-section' }, [
		E('h3', { 'class': 'cbi-section-title' }, _('Действия')),
		E('div', { 'class': 'cbi-page-actions' }, [
			E('input', {
				'type': 'button', 'class': 'cbi-button cbi-button-apply', 'value': _('Запустить'),
				'click': function() { act('start', _('Служба запущена'), _('Ошибка запуска')); }
			}),
			E('input', {
				'type': 'button', 'class': 'cbi-button cbi-button-reset', 'value': _('Остановить'),
				'click': function() { act('stop', _('Служба остановлена'), _('Ошибка остановки')); }
			}),
			E('input', {
				'type': 'button', 'class': 'cbi-button cbi-button-apply', 'value': _('Перезапустить'),
				'click': function() { act('restart', _('Служба перезапущена'), _('Ошибка перезапуска')); }
			}),
			E('input', {
				'type': 'button', 'class': 'cbi-button cbi-button-reload', 'value': _('Перезагрузить конфигурацию'),
				'click': function() { act('reload', _('Конфигурация перезагружена'), _('Ошибка перезагрузки')); }
			}),
			E('input', {
				'type': 'button', 'class': 'cbi-button cbi-button-apply', 'value': _('Запустить синхронизацию списков'),
				'click': function() {
					callSync().then(function(res) {
						ui.addNotification(null, E('p', res.code === 0 ? _('Синхронизация завершена') : _('Ошибка синхронизации')));
					}).then(loadStatus);
				}
			})
		])
	]);
	box.appendChild(actions);

	return box;
}

function act(action, okMsg, errMsg) {
	callService({ action: action }).then(function(res) {
		var msg = res.code === 0 ? E('p', okMsg) : E('p', errMsg + ': ' + (res.stdout || res.error || res.code));
		ui.addNotification(null, msg);
	}).then(loadStatus);
}

function loadStatus() {
	return callStatus().then(function(data) {
		if (_container && _container.parentNode)
			_container.parentNode.replaceChild(render(data), _container);
		_container = render(data);
		return _container;
	});
}

var _container = null;

return view.extend({
	render: function() {
		this._po = poll.add(loadStatus, 15);

		return callStatus().then(function(data) {
			_container = render(data);
			return _container;
		});
	},
	destroy: function() {
		if (this._po)
			poll.remove(this._po);
	}
});