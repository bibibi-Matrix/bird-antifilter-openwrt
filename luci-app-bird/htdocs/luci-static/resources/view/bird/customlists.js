'use strict';
'require view';
'require rpc';
'require ui';

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

var callSync = rpc.declare({
	object: 'luci.bird',
	method: 'sync',
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
		var container = E('div', { 'id': 'bird_customlists_container' });
		var listData = [];

		function fmtSize(n) {
			if (n >= 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + ' MiB';
			if (n >= 1024) return (n / 1024).toFixed(1) + ' KiB';
			return n + ' B';
		}

		function buildTable() {
			var box = E('div', { 'class': 'cbi-section' }, [
				E('h3', { 'class': 'cbi-section-title' }, _('Свои списки (.lst)')),
				E('p', { 'class': 'cbi-section-descr' }, _(
					'Файлы в /etc/bird/list_custom/. Каждая строка — IP-адрес или подсеть CIDR, ' +
					'строки, начинающиеся с #, игнорируются. Изменения применяются после ' +
					'синхронизации.'))
			]);

			if (listData.length === 0) {
				box.appendChild(E('p', { 'class': 'cbi-section-node' }, _('Списков пока нет.')));
				return box;
			}

			var table = E('table', { 'class': 'cbi-section-table' });
			var tbody = E('tbody', [ E('tr', {}, [
				E('th', {}, _('Имя')),
				E('th', {}, _('Размер')),
				E('th', {}, _('Действия'))
			]) ]);
			table.appendChild(tbody);

			listData.forEach(function(item) {
				var tr = E('tr', {});
				tr.appendChild(E('td', {}, E('code', {}, item.name)));
				tr.appendChild(E('td', {}, fmtSize(item.size)));
				var td = E('td', {}, [
					E('input', { 'type': 'button', 'class': 'cbi-button cbi-button-apply', 'value': _('Править'),
						'click': function() { editList(item); } }),
					E('input', { 'type': 'button', 'class': 'cbi-button cbi-button-reset', 'value': _('Удалить'),
						'click': function() { delList(item); } })
				]);
				tr.appendChild(td);
				tbody.appendChild(tr);
			});

			box.appendChild(table);
			return box;
		}

		function editList(item) {
			callReadList({ kind: 'custom', name: item.name }).then(function(res) {
				var ta = E('textarea', { 'class': 'cbi-input-textarea', 'rows': 20, 'style': 'width:100%; font-family:monospace' });
				ta.value = res.content;
				var f = E('div', { 'class': 'cbi-section' });
				f.appendChild(E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, item.name),
					E('div', { 'class': 'cbi-value-field' }, ta)
				]));
				f.appendChild(modalButtons(_('Save'), function() {
					callWriteList({ kind: 'custom', name: item.name, content: ta.value }).then(function(r) {
						ui.addNotification(null, E('p', r.code === 0 ? _('Список сохранён') : _('Ошибка сохранения: ') + (r.error || '')));
						ui.hideModal();
						refresh();
					});
				}));
				ui.showModal(_('Редактирование списка') + ': ' + item.name, f);
			});
		}

		function delList(item) {
			var f = E('div', { 'class': 'cbi-section' });
			f.appendChild(E('p', {}, _('Удалить список') + ' ' + item.name + '?'));
			f.appendChild(modalButtons(_('Delete'), function() {
				callDeleteList({ kind: 'custom', name: item.name }).then(function(r) {
					ui.addNotification(null, E('p', r.code === 0 ? _('Список удалён') : _('Ошибка удаления') + (r.error ? ': ' + r.error : '')));
					ui.hideModal();
					refresh();
				});
			}));
			ui.showModal(_('Удалить список'), f);
		}

		function addList() {
			var nameIn = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'placeholder': 'mylist.lst' });
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
				if (!name) {
					ui.addNotification(null, E('p', _('Укажите имя файла')));
					return;
				}
				if (name.indexOf('.lst') < 0) name += '.lst';
				callWriteList({ kind: 'custom', name: name, content: ta.value }).then(function(r) {
					ui.addNotification(null, E('p', r.code === 0 ? _('Список создан') : _('Ошибка: ') + (r.error || '')));
					ui.hideModal();
					refresh();
				});
			}));
			ui.showModal(_('Новый список'), f);
		}

		var addBtn = E('button', { 'class': 'cbi-button cbi-button-add', 'click': addList }, _('Создать новый список'));
		var syncBtn = E('button', { 'class': 'cbi-button cbi-button-apply', 'click': function() {
			callSync().then(function(res) {
				ui.addNotification(null, E('p', res.code === 0 ? _('Синхронизация завершена') : _('Ошибка синхронизации')));
			});
		}}, _('Синхронизировать'));

		function refresh() {
			return callLists().then(function(d) {
				listData = (d && d.custom) || [];
				container.innerHTML = '';
				container.appendChild(buildTable());
				container.appendChild(E('div', { 'class': 'cbi-page-actions' }, [ addBtn, syncBtn ]));
				return container;
			});
		}

		return refresh();
	}
});