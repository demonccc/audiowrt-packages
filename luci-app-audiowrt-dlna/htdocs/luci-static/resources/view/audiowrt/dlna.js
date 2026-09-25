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
	return E('tr', { 'class': 'tr' }, [
		E('th', { 'class': 'th' }, label),
		E('td', { 'class': 'td', 'id': id }, value || '-')
	]);
}

function renderCodecs(codecs) {
	if (!codecs.length)
		return E('p', {}, _('No codecs are currently registered in /etc/config/audiowrt-runtime-codecs.'));

	var rows = [
		E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, _('Codec')),
			E('th', { 'class': 'th' }, _('DLNA default')),
			E('th', { 'class': 'th' }, _('Effective player')),
			E('th', { 'class': 'th' }, _('Fallbacks')),
			E('th', { 'class': 'th' }, _('MIME types'))
		])
	];

	codecs.forEach(function(c) {
		var fallbacks = (c.players || []).filter(function(p) {
			return p.available && p.id !== c.effective_player;
		}).map(function(p) { return p.name || p.id; });

		rows.push(E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td' }, E('strong', {}, String(c.id || '').toUpperCase())),
			E('td', { 'class': 'td' }, c.default_player || _('Automatic')),
			E('td', { 'class': 'td' }, c.effective_player || _('Unavailable')),
			E('td', { 'class': 'td' }, fallbacks.length ? fallbacks.join(', ') : '-'),
			E('td', { 'class': 'td' }, c.mime || '-')
		]));
	});

	return E('table', { 'class': 'table cbi-section-table' }, rows);
}

return view.extend({
	handleSave: function() {
		var args = [];
		this.rendererSection.children.forEach(function(option) {
			if (!option.isValid('main')) throw new Error(_('Correct invalid settings before saving.'));
			var value = option.formvalue('main');
			value = value == null ? '' : String(value);
			if (value !== String(uci.get('audiowrt-dlna', 'main', option.option) || ''))
				args.push(option.option, value);
		});
		return fs.exec('/usr/libexec/audiowrt-save-renderer', args).then(function(result) {
			if (result.code) throw new Error(result.stderr || _('Could not save DLNA Renderer settings.'));
			window.location.reload();
		});
	},
	handleSaveApply: function() { return this.handleSave(); },
	handleReset: function() { window.location.reload(); },

	load: function() {
		return Promise.all([
			uci.load('audiowrt-dlna'),
			uci.load('audiowrt-runtime-codecs'),
			uci.load('audiowrt-runtime-players'),
			L.resolveDefault(fs.exec('/usr/libexec/audiowrt-renderer', [ 'status' ]), { stdout: '{}' }),
			L.resolveDefault(fs.exec('/usr/libexec/audiowrt-renderer', [ 'players' ]), { stdout: '[]' })
		]);
	},

	render: function(data) {
		var status = parseJSON(data[3].stdout, {});
		var codecs = parseJSON(data[4].stdout, []);
		var codecSections = uci.sections('audiowrt-runtime-codecs', 'codec') || [];
		var playerSections = uci.sections('audiowrt-runtime-players', 'player') || [];
		var playerById = {};
		var rendererMap, s, o;

		playerSections.forEach(function(p) {
			playerById[p['.name']] = p;
		});

		rendererMap = new form.Map('audiowrt-dlna', _('DLNA Renderer'),
			_('DLNA reads codec capabilities from /etc/config/audiowrt-runtime-codecs and installed players from /etc/config/audiowrt-runtime-players. Player preferences configured here belong only to the DLNA module.'));

		s = rendererMap.section(form.TypedSection, 'renderer', _('DLNA Renderer'));
		this.rendererSection = s;
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.default = o.enabled;

		o = s.option(form.Value, 'friendly_name', _('Friendly name'));
		o.placeholder = _('Use the device hostname');
		o.rmempty = true;

		o = s.option(form.Value, 'port', _('UPnP HTTP control port'));
		o.datatype = 'port';
		o.default = '49152';

		o = s.option(form.Value, 'alsa_device', _('ALSA device'));
		o.default = 'default';
		o.description = _('Usually leave this as default. AudioWRT output selection controls the underlying ALSA route.');

		o = s.option(form.Value, 'volume', _('Initial volume'));
		o.datatype = 'range(0,100)';
		o.default = '100';

		codecSections.forEach(function(codec) {
			var codecId = codec['.name'];
			var optionName = 'default_player_' + codecId;
			var current = uci.get('audiowrt-dlna', 'main', optionName);
			var compatible = playerSections.filter(function(p) {
				return asList(p.codec).indexOf(codecId) >= 0;
			});

			o = s.option(form.ListValue, optionName,
				_('%s default player').format(String(codecId).toUpperCase()));
			o.rmempty = true;
			o.value('', _('Automatic fallback'));
			compatible.forEach(function(p) {
				o.value(p['.name'], (p.name || p['.name']) + ' (' + p['.name'] + ')');
			});
			if (current && !playerById[current])
				o.value(current, current + ' (' + _('not installed') + ')');
			o.description = _('The selected player is preferred for this codec. If it is unavailable or fails, DLNA tries another compatible installed player.');
		});

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

		return rendererMap.render().then(function(node) {
			return E('div', { 'class': 'cbi-map' }, [
				E('h2', {}, _('DLNA Renderer status')),
				E('div', { 'class': 'cbi-section' }, [
					E('div', { 'class': 'cbi-section-descr' }, _('Discovery: SSDP/DLNA and mDNS/DNS-SD are provided by the DLNA Renderer service.')),
					E('table', { 'class': 'table cbi-section-table' }, [
						E('tr', { 'class': 'tr table-titles' }, [
							E('th', { 'class': 'th' }, _('Property')),
							E('th', { 'class': 'th' }, _('Value'))
						]),
						statusRow(_('Playback'), 'dlna-state', status.state),
						statusRow(_('Last controller'), 'dlna-controller', status.controller),
						statusRow(_('Codec'), 'dlna-codec', status.codec ? String(status.codec).toUpperCase() : '-'),
						statusRow(_('Player'), 'dlna-player', status.player),
						statusRow(_('Position'), 'dlna-position', status.position),
						statusRow(_('Volume'), 'dlna-volume', status.volume != null ? String(status.volume) + '%' : '-'),
						statusRow(_('URI'), 'dlna-uri', status.uri)
					])
				]),
				E('div', { 'class': 'cbi-section cbi-tblsection' }, [
					E('h3', {}, _('Codec players')),
					renderCodecs(codecs)
				]),
				node
			]);
		});
	}
});
