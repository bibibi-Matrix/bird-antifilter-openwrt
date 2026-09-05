'use strict';
'require view';
'require rpc';
'require ui';
'require form';

var callLists = rpc.declare({
	object: 'luci.bird',
	method: 'lists',
	expect: { '': {} }
});

var callReadList = rpc.declare({
	object: 'luci.bird',
	method: 'readList',
	params: { name: '', kind: '' },
	expect: { '': {} }
});

var callWriteList = rpc.declare({
	object: 'luci.bird',
	method: 'writeList',
	params: { name: '', kind: '', content: '' },
	expect: { '': {} }
});

var callDeleteList = rpc.declare({
	object: 'luci.bird',
	method: 'deleteList',
	params: { name: '', kind: '' },
	expect: { '': {} }
});

function modalButtons(okText, okClick) {
	return E('div', { 'class': 'right' }, [
		E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-apply important', 'click': okClick }, _('OK')),
		' ',
		E('button', { 'type': 'button', 'class': 'btn cbi-button', 'click': function() { ui.hideModal(); } }, _('Cancel'))
	]);
}

return view.extend({
	render: function() {
		var container = E('div', { 'id': 'bird_blacklist_container' });
		var listData = [];

		var m = new L.form.Map('bird', _('Чёрный список'), _(
			'Управление чёрным списком: IP/CIDR, исключаемые из итоговых маршрутов. ' +
			'Комментарии начинаются с #.'));
		var s = m.section(form.NamedSection, 'global', 'bird', _('Настройки чёрного списка'));
		s.anonymous = true;

		var o = s.option(form.Flag, 'blacklist', _('Включить чёрный список'));
		o.rmempty = false;
		o.default = '1';

		o = s.option(form.Flag, 'blacklist_split', _('Разбивать широкие префиксы'));
		o.rmempty = false;
		o.default = '1';
		o.description = _('Если запись чёрного списка попадает внутрь более широкого префикса, ' +
			'префикс разбивается на части вместо полного исключения.');

		o = s.option(form.Value, 'blacklist_dir', _('Папка чёрного списка'));
		o.rmempty = true;
		o.default = '/etc/bird/blacklist';

		function buildTable() {
			var box = E('div', { 'class': 'cbi-section' }, [
				E('h3', { 'class': 'cbi-section-title' }, _('Файлы чёрного списка')),
				E('p', { 'class': 'cbi-section-descr' }, _(
					'Файлы формата .lst в /etc/bird/blacklist/. IP/CIDR по одной записи на ' +
					'строку, комментарии начинаются с #.'))
			]);
			if (listData.length === 0) {
				box.appendChild(E('p', { 'class': 'cbi-section-node' }, _('Файлов чёрного списка нет.')));
				return box;
			}
			var table = E('table', { 'class': 'cbi-section-table' });
			var tbody = E('tbody', [ E('tr', {}, [
				E('th', {}, _('Имя')), E('th', {}, _('Действия'))
			]) ]);
			table.appendChild(tbody);
			listData.forEach(function(item) {
				var tr = E('tr', {});
				tr.appendChild(E('td', {}, E('code', {}, item.name)));
				tr.appendChild(E('td', {}, [
					E('input', { 'type': 'button', 'class': 'cbi-button cbi-button-apply', 'value': _('Править'),
						'click': function() { editList(item); } }),
					E('input', { 'type': 'button', 'class': 'cbi-button cbi-button-reset', 'value': _('Удалить'),
						'click': function() { delList(item); } })
				]));
				tbody.appendChild(tr);
			});
			box.appendChild(table);
			return box;
		}

		function editList(item) {
			callReadList({ kind: 'blacklist', name: item.name }).then(function(res) {
				var ta = E('textarea', { 'class': 'cbi-input-textarea', 'rows': 20, 'style': 'width:100%; font-family:monospace' });
				ta.value = res.content;
				var f = E('div', { 'class': 'cbi-section' });
				f.appendChild(E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, item.name),
					E('div', { 'class': 'cbi-value-field' }, ta)
				]));
				f.appendChild(modalButtons(_('Save'), function() {
					callWriteList({ kind: 'blacklist', name: item.name, content: ta.value }).then(function(r) {
						ui.addNotification(null, E('p', r.code === 0 ? _('Список сохранён') : _('Ошибка сохранения: ') + (r.error || '')));
						ui.hideModal();
						refresh();
					});
				}));
				ui.showModal(_('Редактирование черного списка') + ': ' + item.name, f);
			});
		}

		function delList(item) {
			var f = E('div', { 'class': 'cbi-section' });
			f.appendChild(E('p', {}, _('Удалить список') + ' ' + item.name + '?'));
			f.appendChild(modalButtons(_('Delete'), function() {
				callDeleteList({ kind: 'blacklist', name: item.name }).then(function(r) {
					ui.addNotification(null, E('p', r.code === 0 ? _('Список удалён') : _('Ошибка удаления')));
					ui.hideModal();
					refresh();
				});
			}));
			ui.showModal(_('Удалить список'), f);
		}

		function addList() {
			var nameIn = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'placeholder': 'myblack.lst' });
			var ta = E('textarea', { 'class': 'cbi-input-textarea', 'rows': 15, 'style': 'width:100%; font-family:monospace', 'placeholder': '1.2.3.4\n5.6.7.0/24\n' });
			var f = E('div', { 'class': 'cbi-section' });
			f.appendChild(E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Имя файла')),
				E('div', { 'class': 'cbi-value-field' }, nameIn)
			]));
			f.appendChild(E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Содержимое')),
				E('div', { 'class': 'cbi-value-field' }, ta)
			]));
			f.appendChild(modalButtons(_('Create'), function() {
				var name = nameIn.value.trim();
				if (!name) { ui.addNotification(null, E('p', _('Укажите имя файла'))); return; }
				if (name.indexOf('.lst') < 0) name += '.lst';
				callWriteList({ kind: 'blacklist', name: name, content: ta.value }).then(function(r) {
					ui.addNotification(null, E('p', r.code === 0 ? _('Список создан') : _('Ошибка: ') + (r.error || '')));
					ui.hideModal();
					refresh();
				});
			}));
			ui.showModal(_('Новый файл чёрного списка'), f);
		}

		var addBtn = E('button', { 'class': 'cbi-button cbi-button-add', 'click': addList }, _('Создать файл чёрного списка'));

		function refresh() {
			return callLists().then(function(d) {
				listData = (d && d.blacklist) || [];
				container.innerHTML = '';
				container.appendChild(buildTable());
				container.appendChild(E('div', { 'class': 'cbi-page-actions' }, [ addBtn ]));
				return container;
			});
		}

		return L.resolveDefault(m.render()).then(function(formNode) {
			container.appendChild(formNode);
			return refresh();
		});
	}
});