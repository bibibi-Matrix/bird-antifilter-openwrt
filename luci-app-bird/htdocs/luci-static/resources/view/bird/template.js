'use strict';
'require rpc';
'require ui';
'require view';

var callTemplate = rpc.declare({
	object: 'luci.bird',
	method: 'template',
	expect: { '': {} }
});

var callSaveTemplate = rpc.declare({
	object: 'luci.bird',
	method: 'saveTemplate',
	params: { content: '' },
	expect: { '': {} }
});

return view.extend({
	render: function() {
		var container = E('div', { 'id': 'bird_template_container' });

		return callTemplate().then(function(res) {
			var textarea = E('textarea', {
				'class': 'cbi-input-textarea',
				'style': 'width:100%; min-height:360px; font-family:monospace; font-size:12px; box-sizing:border-box',
				'spellcheck': 'false'
			});
			textarea.value = (res && res.content) || '';

			var status = E('span', {});

			function save() {
				callSaveTemplate({ content: textarea.value }).then(function(r) {
					var ok = (r.code === 0);
					ui.addNotification(null, E('p',
						ok ? _('Шаблон сохранён, BIRD перечитал конфигурацию') :
						_('Шаблон сохранён, но перезагрузка BIRD не удалась: ') + ((r.error) || r.code)));
				});
			}

			container.appendChild(E('div', { 'class': 'cbi-section' }, [
				E('h3', { 'class': 'cbi-section-title' }, _('Шаблон конфигурации BIRD')),
				E('p', { 'class': 'cbi-section-descr' }, _(
					'Здесь редактируется файл /etc/bird/extra.conf. Его содержимое ' +
					'подключается в конец автоматически сгенерированного /etc/bird/bird.conf, ' +
					'поэтому можно добавлять собственные протоколы, фильтры и таблицы BIRD, ' +
					'которые не перезаписываются при настройке через LuCI.')),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, _('extra.conf')),
					E('div', { 'class': 'cbi-value-field' }, [
						textarea,
						status
					])
				]),
				E('div', { 'class': 'cbi-page-actions' }, [
					E('input', {
						'type': 'button',
						'class': 'cbi-button cbi-button-apply',
						'value': _('Сохранить и применить'),
						'click': save
					})
				])
			]));

			return container;
		});
	}
});