'use strict';
'require view';
'require rpc';
'require ui';

var callAvailable = rpc.declare({
	object: 'luci.bird',
	method: 'available',
	expect: { '': {} }
});

var callSelection = rpc.declare({
	object: 'luci.bird',
	method: 'selection',
	expect: { '': {} }
});

var callSaveSources = rpc.declare({
	object: 'luci.bird',
	method: 'saveSources',
	params: { encoded: '' },
	expect: { '': {} }
});

var callSync = rpc.declare({
	object: 'luci.bird',
	method: 'sync',
	expect: { '': {} }
});

return view.extend({
	render: function() {
		var container = E('div', { 'id': 'bird_lists_container' });
		var sel = {};

		return callAvailable().then(function(av) {
			return callSelection().then(function(seld) {
				var sources = (av && av.sources) || [];
				var values = (seld && seld.values) || {};
				var k;
				for (k in values)
					sel[k] = values[k];

				if (sources.length === 0) {
					container.appendChild(E('div', { 'class': 'cbi-section' }, [
						E('h3', { 'class': 'cbi-section-title' }, _('Источники списков')),
						E('p', { 'class': 'cbi-section-node' }, _('Нет доступных источников.'))
					]));
					return container;
				}

				var select = E('select', { 'class': 'cbi-input-select' });
				sources.forEach(function(s, i) {
					select.appendChild(E('option', { 'value': String(i) }, s.title));
				});

				var listArea = E('div', { 'id': 'bird_list_area' });

				function renderArea() {
					listArea.innerHTML = '';
					var src = sources[Number(select.value)];
					if (!src) return;
					(src.lists || []).forEach(function(list) {
						var cb = E('input', { 'type': 'checkbox', 'class': 'cbi-input-checkbox', 'id': 'bird_bl_' + list.key });
						cb.checked = (sel[list.key] === '1');
						cb.addEventListener('change', function() {
							sel[list.key] = cb.checked ? '1' : '0';
						});
						var row = E('div', { 'class': 'cbi-value' }, [
							E('label', { 'class': 'cbi-value-title', 'for': 'bird_bl_' + list.key }, list.label),
							E('div', { 'class': 'cbi-value-field' }, [
								cb,
								E('span', { 'class': 'cbi-value-description', 'style': 'margin-left:6px; font-size:12px' }, list.desc || list.url)
							])
						]);
						listArea.appendChild(row);
					});
				}

				select.addEventListener('change', renderArea);

				var saveBtn = E('input', {
					'type': 'button', 'class': 'cbi-button cbi-button-apply', 'value': _('Сохранить'),
					'click': function() {
						callSaveSources({ encoded: JSON.stringify({ values: sel }) }).then(function(res) {
							ui.addNotification(null, E('p',
								res.code === 0 ? _('Настройки сохранены') :
								_('Ошибка сохранения: ') + ((res && res.error) || res.code)));
						});
					}
				});

				var syncBtn = E('input', {
					'type': 'button', 'class': 'cbi-button cbi-button-reload', 'value': _('Синхронизировать'),
					'click': function() {
						callSync().then(function(res) {
							ui.addNotification(null, E('p',
								res.code === 0 ? _('Синхронизация завершена') :
								_('Ошибка синхронизации: ') + ((res && (res.stderr || res.stdout)) || res.code)));
						});
					}
				});

				container.appendChild(E('div', { 'class': 'cbi-section' }, [
					E('h3', { 'class': 'cbi-section-title' }, _('Источники списков')),
					E('p', { 'class': 'cbi-section-descr' }, _(
						'Выберите источник и отметьте галочкой нужные списки. Отмеченные списки ' +
						'загружаются и преобразуются в маршруты BIRD при синхронизации.')),
					E('div', { 'class': 'cbi-value' }, [
						E('label', { 'class': 'cbi-value-title' }, _('Источник')),
						E('div', { 'class': 'cbi-value-field' }, select)
					]),
					listArea,
					E('div', { 'class': 'cbi-page-actions' }, [ saveBtn, syncBtn ])
				]));

				renderArea();
				return container;
			});
		});
	}
});