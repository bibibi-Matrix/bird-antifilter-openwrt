'use strict';
'require form';
'require uci';
'require rpc';
'require ui';

var callNetinfo = rpc.declare({
	object: 'luci.bird',
	method: 'netinfo',
	expect: { '': {} }
});

return L.view.extend({
	render: function() {
		var m, s, o;

		m = new L.form.Map('bird', _('BGP-пиры'), _(
			'Настройка BGP-пиров. Сервер — раздаёт маршруты из списков внешнему ' +
			'пиру (пассивный режим). Клиент — принимает маршруты от апстрим-пира ' +
			'и устанавливает местные маршруты из списков в ядро (трафик уходит ' +
			'через интерфейс via), default route остаётся на WAN.'));

		s = m.section(form.TypedSection, 'bgp_peer', _('BGP-пиры'));
		s.anonymous = true;
		s.addremove = true;
		s.sortable = true;

		s.tab('general', _('Основные'));
		s.tab('bgp', _('BGP'));

		o = s.option(form.Flag, 'enabled', _('Включить пир'));
		o.tab = 'general';
		o.rmempty = false;

		o = s.option(form.ListValue, 'role', _('Роль'));
		o.tab = 'general';
		o.rmempty = false;
		o.value('server', _('Сервер — раздавать списки пиру'));
		o.value('client', _('Клиент — принимать от пира'));

		o = s.option(form.Value, 'neighbor', _('Адрес соседа (neighbor)'));
		o.tab = 'general';
		o.rmempty = false;
		o.datatype = 'ipaddr';
		o.description = _('IP-адрес BGP-соседа (пира). Автозаполнение невозможно — укажите вручную.');

		o = s.option(form.Value, 'remote_as', _('Remote AS (номер AS пира)'));
		o.tab = 'general';
		o.rmempty = false;
		o.datatype = 'range(1, 4294967295)';
		o.description = _('Номер автономной системы соседа. Определяется вручную.');

		o = s.option(form.Value, 'local_ip', _('Локальный адрес (local / source address)'));
		o.tab = 'general';
		o.rmempty = true;
		o.datatype = 'ipaddr';
		o.description = _('Местный IP для BGP-сессии (source address). ' +
			'Используйте кнопку «Определить IP» для показа доступных адресов роутера.');

		// Кнопка автозаполнения — показывает все IP роутера, подставляет via_ip или lan_ip.
		o = s.option(form.DummyValue, '_autofill', _('Определить IP роутера (local)'));
		o.tab = 'general';
		o.renderWidget = function(section_id) {
			var map = this.map;
			return E('input', {
				'type': 'button',
				'class': 'cbi-button cbi-button-apply',
				'value': _('Определить IP для local'),
				'click': function() {
					callNetinfo().then(function(info) {
						var ip = (info && (info.via_ip || info.lan_ip)) || '';
						var lines = (info && info.interfaces || []).map(function(it) {
							return it.iface + ': ' + it.ip;
						}).join('\n');
						ui.addNotification(null, E('pre', { 'style': 'white-space:pre-wrap' }, lines ||
							_('IP-адреса не найдены')));
						if (ip && map)
							map.setValue(section_id, 'local_ip', ip);
					});
				}
			});
		};

		o = s.option(form.Flag, 'passive', _('Пассивный режим (ждать подключения пира)'));
		o.tab = 'bgp';
		o.rmempty = true;
		o.description = _('Сервер: ожидает входящего соединения от соседа. Клиент: подключается сам.');

		o = s.option(form.Flag, 'next_hop_self', _('Next hop self'));
		o.tab = 'bgp';
		o.rmempty = true;
		o.description = _('Устанавливать себя как next hop для анонсируемых маршрутов (сервер).');

		o = s.option(form.Value, 'port', _('Порт BGP'));
		o.tab = 'bgp';
		o.rmempty = true;
		o.datatype = 'port';
		o.description = _('Порт BGP (по умолчанию 179). Оставить пустым — по умолчанию.');

		o = s.option(form.Value, 'hold_time', _('Время удержания (сек)'));
		o.tab = 'bgp';
		o.rmempty = true;
		o.datatype = 'range(3, 7200)';
		o.description = _('Время жизни BGP-сессии (по умолчанию 240 с). Пусто — глобальное значение.');

		o = s.option(form.Value, 'password', _('Пароль MD5'));
		o.tab = 'bgp';
		o.rmempty = true;
		o.password = true;
		o.description = _('Пароль аутентификации BGP (необязательно).');

		o = s.option(form.Flag, 'export_kernel', _('Экспорт маршрутов в ядро (для клиента)'));
		o.tab = 'bgp';
		o.rmempty = true;
		o.description = _('Если включено, маршруты из статических антифильтр-списков отправляются пиру-клиенту.');

		return m.render();
	}
});