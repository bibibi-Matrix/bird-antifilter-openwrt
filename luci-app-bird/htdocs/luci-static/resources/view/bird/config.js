'use strict';
'require form';
'require uci';

return L.view.extend({
	render: function() {
		var m, s, o;

		m = new L.form.Map('bird', _('BIRD Antifilter'), _(
			'Global BIRD daemon settings and BGP peers. ' +
			'The daemon acts both as a BGP server (advertising the listed routes) ' +
			'and as a BGP client (installing the listed routes into the kernel ' +
			'routing table, sending the listed traffic through the wireguard/amnezia ' +
			'interface). The default route stays on WAN.'));

		/* ---- Global settings ---- */
		s = m.section(form.NamedSection, 'global', 'bird', _('Global settings'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.rmempty = false;

		o = s.option(form.Value, 'router_id', _('Router ID'));
		o.datatype = 'or(ipaddr, "auto")';
		o.rmempty = false;

		o = s.option(form.Value, 'local_as', _('Local AS number'));
		o.datatype = 'range(1, 4294967295)';
		o.rmempty = false;

		o = s.option(form.Value, 'via_interface', _('Wireguard via interface'));
		o.rmempty = false;
		o.default = 'amneziawg0';

		o = s.option(form.Flag, 'sync_cron', _('Enable periodic list sync'));
		o.rmempty = false;

		o = s.option(form.Value, 'cron_expr', _('Sync schedule (cron)'));
		o.rmempty = true;
		o.default = '0 3 * * *';

		/* ---- BGP peers ---- */
		s = m.section(form.TypedSection, 'bgp_peer', _('BGP peers'));
		s.anonymous = true;
		s.addremove = true;
		s.sortable = true;

		s.tab('general', _('General'));
		s.tab('settings', _('Settings'));

		o = s.option(form.Flag, 'enabled', _('Enable peer'));
		o.tab = 'general';
		o.rmempty = false;

		o = s.option(form.ListValue, 'role', _('Role'));
		o.tab = 'general';
		o.rmempty = false;
		o.value('server', _('Server (advertise lists to peer)'));
		o.value('client', _('Client (receive from peer, install in kernel)'));

		o = s.option(form.Value, 'neighbor', _('Neighbor address'));
		o.tab = 'general';
		o.rmempty = false;
		o.datatype = 'ipaddr';

		o = s.option(form.Value, 'remote_as', _('Remote (peer) AS'));
		o.tab = 'general';
		o.rmempty = false;
		o.datatype = 'range(1, 4294967295)';

		o = s.option(form.Value, 'local_ip', _('Local address'));
		o.tab = 'settings';
		o.rmempty = true;
		o.datatype = 'ipaddr';

		o = s.option(form.Flag, 'passive', _('Passive (wait for peer to connect)'));
		o.tab = 'settings';
		o.rmempty = true;

		o = s.option(form.Flag, 'next_hop_self', _('Set next-hop-self on advertised routes'));
		o.tab = 'settings';
		o.rmempty = true;

		/* ---- Blacklist ---- */
		o = s.option(form.Flag, 'blacklist', _('Enable blacklist'));
		o.rmempty = false;
		o.default = '1';

		o = s.option(form.Flag, 'blacklist_split', _('Split wide prefixes covered by blacklist'));
		o.rmempty = false;
		o.default = '1';

		return m.render();
	}
});
