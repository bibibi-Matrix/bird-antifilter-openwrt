'use strict';
'require form';
'require uci';

return L.view.extend({
	render: function() {
		var m, s, o;

		m = new L.form.Map('bird', _('Настройки BIRD Antifilter'), _(
			'Основные настройки демона BIRD. Демон работает в двух ролях: ' +
			'BGP-сервер (раздаёт маршруты из списков внешним пирам) и ' +
			'BGP-клиент (принимает маршруты от апстрим-пира и устанавливает ' +
			'маршруты из списков в таблицу маршрутизации ядра). Трафик из ' +
			'списков уходит через указанный интерфейс (обычно WireGuard/AmneziaWG), ' +
			'остальной трафик остаётся на WAN.'));

		s = m.section(form.NamedSection, 'global', 'bird', _('Общие настройки'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('Включить сервис'));
		o.rmempty = false;

		o = s.option(form.Value, 'router_id', _('Router ID (идентификатор)'));
		o.datatype = 'or(ipaddr, "auto")';
		o.rmempty = false;
		o.default = 'auto';
		o.description = _('IP-адрес для идентификации BIRD. Значение "auto" — определить автоматически.');

		o = s.option(form.Value, 'local_as', _('Местный номер AS'));
		o.datatype = 'range(1, 4294967295)';
		o.rmempty = false;

		o = s.option(form.Value, 'via_interface', _('Интерфейс для маршрутов (via)'));
		o.rmempty = false;
		o.default = 'awg0';
		o.description = _('Интерфейс, через который будет уходить трафик из списков. ' +
			'Обычно это интерфейс WireGuard/AmneziaWG (например awg0, wg0).');

		o = s.option(form.Value, 'port', _('Порт BGP (по умолчанию 179)'));
		o.datatype = 'port';
		o.rmempty = true;
		o.default = '179';

		o = s.option(form.Value, 'hold_time', _('Время удержания BGP (сек)'));
		o.datatype = 'range(3, 7200)';
		o.rmempty = true;
		o.default = '240';

		return m.render();
	}
});