'use strict';
'require form';
'require fs';

return L.view.extend({
	render: function() {
		var m, s, o;

		m = new L.form.Map('bird', _('Antifilter sources'), _(
			'Select which IP lists are downloaded and converted into BIRD routes. ' +
			'Custom lists are read from /etc/bird/list_custom/.'));

		s = m.section(form.NamedSection, 'antifilter', 'source', _('Sources'));
		s.anonymous = true;

		o = s.option(form.Flag, 'antifilter_download', _('Enable antifilter.download'));
		o.rmempty = false;

		o = s.option(form.Flag, 'antifilter_network', _('Enable antifilter.network'));
		o.rmempty = false;

		o = s.option(form.DummyValue, '_dl_hdr', _('antifilter.download lists'));
		o.rawhtml = false;

		['ip', 'ipresolve', 'ipsum', 'subnet', 'allyouneed', 'community'].forEach(function(f) {
			var flag = s.option(form.Flag, f, f);
			flag.rmempty = false;
		});

		o = s.option(form.DummyValue, '_nw_hdr', _('antifilter.network lists'));
		o.rawhtml = false;

		['nf_ip', 'nf_ipsmart', 'nf_ipsum', 'nf_subnet', 'nf_uablacklist', 'nf_govno', 'nf_ip6'].forEach(function(f) {
			var flag = s.option(form.Flag, f, f);
			flag.rmempty = false;
		});

		return m.render().then(function(node) {
			return fs.list('/etc/bird/list_custom').catch(function() { return []; }).then(function(names) {
				node.appendChild(
					E('div', { 'class': 'cbi-section' }, [
						E('h3', { 'class': 'cbi-section-title' }, _('Custom lists')),
						E('ul', { 'class': 'cbi-section-node' },
							names.filter(function(n) { return n.indexOf('.lst') >= 0; })
							    .map(function(n) { return E('li', {}, n); }))
					]));
				return node;
			});
		});
	}
});