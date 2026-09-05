'use strict';
'require form';
'require rpc';
'require ui';

var callSync = rpc.declare({
	object: 'luci.bird',
	method: 'sync',
	expect: { '': {} }
});

return L.view.extend({
	render: function() {
		var m = new L.form.Map('bird', _('Синхронизация списков'), _(
			'Настройка расписания автоматической загрузки и конвертации IP-списков. ' +
			'Синхронизацию также можно запустить вручную.'));

		var s = m.section(form.NamedSection, 'global', 'bird', _('Расписание'));
		s.anonymous = true;

		var o = s.option(form.Flag, 'sync_cron', _('Включить периодическую синхронизацию'));
		o.rmempty = false;

		o = s.option(form.Value, 'cron_expr', _('Расписание (cron)'));
		o.default = '0 3 * * *';
		o.rmempty = true;
		o.description = _('Стандартное cron-выражение: минуты часы день месяц день-недели. ' +
			'Например «0 3 * * *» — каждый день в 03:00.');

		var output = E('pre', { 'class': 'cbi-section-node' });

		return m.render().then(function(node) {
			var box = E('div', { 'class': 'cbi-section' }, [
				E('h3', { 'class': 'cbi-section-title' }, _('Ручная синхронизация')),
				E('p', { 'class': 'cbi-section-descr' }, _('Загружает списки, обновляет маршруты и перезагружает BIRD.')),
				E('div', { 'class': 'cbi-page-actions' },
					E('input', {
						'type': 'button',
						'class': 'cbi-button cbi-button-apply',
						'value': _('Запустить синхронизацию сейчас'),
						'click': function() {
							output.textContent = _('Синхронизация выполняется…');
							callSync().then(function(res) {
								var msg = res.code === 0 ? _('Синхронизация завершена') : _('Ошибка синхронизации');
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