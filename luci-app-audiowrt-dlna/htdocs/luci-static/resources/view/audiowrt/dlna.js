'use strict';
'require view';
'require form';
'require uci';
'require fs';
'require poll';

function parseJSON(text, fallback) {
	try { return JSON.parse(text || ''); }
	catch (e) { return fallback; }
}

function asList(value) {
	if (Array.isArray(value))
		return value;
	if (value == null || value === '')
		return [];
	return [ value ];
}

function statusRow(label, id, value) {
	return E('div', { 'class': 'tr' }, [
		E('div', { 'class': 'td left', 'style': 'width:35%' }, [ E('strong', {}, label) ]),
		E('div', { 'class': 'td left', 'id': id }, value || '-')
	]);
}

function renderCodecs(codecs) {
	if (!codecs.length)
		return E('p', {}, _('No codecs are currently registered in /etc/config/audiowrt.'));

	return E('div', { 'class': 'table' }, [
		E('div', { 'class': 'tr table-titles' }, [
			E('div', { 'class': 'th left' }, _('Codec')),
			E('div', { 'class': 'th left' }, _('Default player')),
			E('div', { 'class': 'th left' }, _('Effective player')),
			E('div', { 'class': 'th left' }, _('Fallbacks')),
			E('div', { 'class': 'th left' }, _('MIME types'))
		])
	].concat(codecs.map(function(c) {
		var fallbacks = (c.players || []).filter(function(p) {
			return p.available && p.id !== c.effective_player;
		}).map(function(p) { return p.name || p.id; });

		return E('div', { 'class': 'tr' }, [
			E('div', { 'class': 'td left' }, [ E('strong', {}, String(c.id || '').toUpperCase()) ]),
			E('div', { 'class': 'td left' }, c.default_player || '-'),
			E('div', { 'class': 'td left' }, c.effective_player || _('Unavailable')),
			E('div', { 'class': 'td left' }, fallbacks.length ? fallbacks.join(', ') : '-'),
			E('div', { 'class': 'td left' }, c.mime || '-')
		]);
	})));
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('audiowrt-dlna'),
			uci.load('audiowrt'),
			L.resolveDefault(fs.exec('/usr/libexec/audiowrt-renderer', [ 'status' ]), { stdout: '{}' }),
			L.resolveDefault(fs.exec('/usr/libexec/audiowrt-renderer', [ 'players' ]), { stdout: '[]' })
		]);
	},

	render: function(data) {
		var status = parseJSON(data[2].stdout, {});
		var codecs = parseJSON(data[3].stdout, []);
		var codecSections = uci.sections('audiowrt', 'codec') || [];
		var playerSections = uci.sections('audiowrt', 'player') || [];
		var codecIds = codecSections.map(function(c) { return c['.name']; });
		var playerById = {};
		var rendererMap, registryMap, s, o;

		playerSections.forEach(function(p) {
			playerById[p['.name']] = p;
		});

		rendererMap = new form.Map('audiowrt-dlna', _('AudioWRT Renderer & Discovery'),
			_('A single native service exposes AudioWRT through SSDP/DLNA and minimal mDNS/DNS-SD. Codec and player capabilities are registered in /etc/config/audiowrt and can be reloaded without interrupting the renderer.'));

		s = rendererMap.section(form.TypedSection, 'renderer', _('Renderer'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.default = o.enabled;

		o = s.option(form.Value, 'friendly_name', _('Friendly name'));
		o.default = 'AudioWRT';
		o.rmempty = false;

		o = s.option(form.Value, 'port', _('UPnP HTTP control port'));
		o.datatype = 'port';
		o.default = '49152';

		o = s.option(form.Value, 'alsa_device', _('ALSA device'));
		o.default = 'default';
		o.description = _('Usually leave this as default. AudioWRT output selection controls the underlying ALSA route.');

		o = s.option(form.Value, 'volume', _('Initial volume'));
		o.datatype = 'range(0,100)';
		o.default = '100';

		registryMap = new form.Map('audiowrt', _('Codec and player registry'),
			_('Player packages register codecs and executables here. A player receives the media URL as its only argument and must remain in the foreground while playing. Other compatible players automatically act as fallbacks.'));

		s = registryMap.section(form.GridSection, 'codec', _('Codec defaults'));
		s.anonymous = false;
		s.addremove = false;
		s.sortable = false;

		o = s.option(form.ListValue, 'default_player', _('Default player'));
		o.rmempty = true;
		playerSections.forEach(function(p) {
			o.value(p['.name'], (p.name || p['.name']) + ' (' + p['.name'] + ')');
		});
		o.validate = function(section_id, value) {
		var player, supported;
		if (!value)
			return true;
		player = playerById[value];
		if (!player)
			return _('The selected player is not registered.');
		supported = asList(player.codec);
		return supported.indexOf(section_id) >= 0 ? true :
			_('The selected player does not declare support for this codec.');
	};

		s = registryMap.section(form.GridSection, 'player', _('Registered players'));
		s.anonymous = false;
		s.addremove = true;
		s.sortable = true;
		s.description = _('Package players and custom players use the same contract. Custom wrappers for VLC, MPD or another engine can be added by registering their executable and supported codecs.');

		o = s.option(form.Value, 'name', _('Name'));
		o.rmempty = false;

		o = s.option(form.Value, 'executable', _('Executable'));
		o.rmempty = false;
		o.placeholder = '/usr/libexec/audiowrt-player-vlc';

		o = s.option(form.DynamicList, 'codec', _('Codecs'));
		o.rmempty = false;
		codecIds.forEach(function(id) { o.value(id, id.toUpperCase()); });

		poll.add(function() {
			return L.resolveDefault(fs.exec('/usr/libexec/audiowrt-renderer', [ 'status' ]), { stdout: '{}' }).then(function(res) {
				var st = parseJSON(res.stdout, {}), fields = {
					'dlna-state': st.state || '-',
					'dlna-controller': st.controller || '-',
					'dlna-codec': st.codec ? String(st.codec).toUpperCase() : '-',
					'dlna-player': st.player || '-',
					'dlna-position': st.position || '-',
					'dlna-volume': st.volume != null ? String(st.volume) + '%' : '-',
					'dlna-uri': st.uri || '-'
				};
				Object.keys(fields).forEach(function(id) {
					var node = document.getElementById(id);
					if (node) node.textContent = fields[id];
				});
			});
		}, 2);

		return Promise.all([ rendererMap.render(), registryMap.render() ]).then(function(nodes) {
			return E('div', { 'class': 'cbi-map' }, [
				E('h2', {}, _('Renderer status')),
				E('div', { 'class': 'cbi-section' }, [
					E('p', {}, _('Discovery: SSDP/DLNA and mDNS/DNS-SD are provided by this renderer service.')),
					E('div', { 'class': 'table' }, [
						statusRow(_('Playback'), 'dlna-state', status.state),
						statusRow(_('Last controller'), 'dlna-controller', status.controller),
						statusRow(_('Codec'), 'dlna-codec', status.codec ? String(status.codec).toUpperCase() : '-'),
						statusRow(_('Player'), 'dlna-player', status.player),
						statusRow(_('Position'), 'dlna-position', status.position),
						statusRow(_('Volume'), 'dlna-volume', status.volume != null ? String(status.volume) + '%' : '-'),
						statusRow(_('URI'), 'dlna-uri', status.uri)
					])
				]),
				E('h3', {}, _('Codec players')),
				E('div', { 'class': 'cbi-section' }, [ renderCodecs(codecs) ]),
				nodes[0],
				nodes[1]
			]);
		});
	}
});
