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

function statusRow(label, id, value) {
	return E('div', { 'class': 'tr' }, [
		E('div', { 'class': 'td left', 'style': 'width:35%' }, [ E('strong', {}, label) ]),
		E('div', { 'class': 'td left', 'id': id }, value || '-')
	]);
}

function renderPlayers(players) {
	if (!players.length)
		return E('p', {}, _('No AudioWRT codec player packages are installed.'));

	return E('div', { 'class': 'table' }, [
		E('div', { 'class': 'tr table-titles' }, [
			E('div', { 'class': 'th left' }, _('Codec')),
			E('div', { 'class': 'th left' }, _('Status')),
			E('div', { 'class': 'th left' }, _('Effective player')),
			E('div', { 'class': 'th left' }, _('MIME types'))
		])
	].concat(players.map(function(p) {
		var official = p.auto_command ? E('div', {
			'class': 'cbi-value-description',
			'style': p.mode === 'custom' ? 'opacity:.45' : ''
		}, (p.mode === 'custom' ? _('Automatic (overridden): ') : _('Automatic: ')) + p.auto_command) : '';
		return E('div', { 'class': 'tr' }, [
			E('div', { 'class': 'td left' }, [ E('strong', {}, String(p.id || '').toUpperCase()), official ]),
			E('div', { 'class': 'td left' }, p.available ? (p.mode === 'custom' ? _('Custom override') : _('Autodetected')) : _('Unavailable')),
			E('div', { 'class': 'td left' }, p.command || '-'),
			E('div', { 'class': 'td left' }, p.mime || '-')
		]);
	})));
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('audiowrt-dlna'),
			L.resolveDefault(fs.exec('/usr/libexec/audiowrt-renderer', [ 'status' ]), { stdout: '{}' }),
			L.resolveDefault(fs.exec('/usr/libexec/audiowrt-renderer', [ 'players' ]), { stdout: '[]' })
		]);
	},

	render: function(data) {
		var status = parseJSON(data[1].stdout, {});
		var players = parseJSON(data[2].stdout, []);
		var m, s, o;

		m = new form.Map('audiowrt-dlna', _('AudioWRT Renderer & Discovery'),
			_('A single native service exposes AudioWRT through SSDP/DLNA and minimal mDNS/DNS-SD. It advertises only codecs whose AudioWRT player packages are installed. Custom mappings override autodetected players without deleting the automatic fallback.'));

		s = m.section(form.TypedSection, 'renderer', _('Renderer'));
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

		s = m.section(form.GridSection, 'player', _('Custom player overrides'));
		s.anonymous = true;
		s.addremove = true;
		s.sortable = true;
		s.description = _('A custom player supersedes the autodetected AudioWRT player for the same codec. The play command receives the URI in $AUDIOWRT_URI. Optional pause/resume/stop commands allow external players such as MPD to be controlled cleanly.');

		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.default = o.enabled;

		o = s.option(form.Value, 'codec', _('Codec ID'));
		o.rmempty = false;
		[ 'flac', 'mp3', 'aac', 'wav' ].forEach(function(v) { o.value(v, v.toUpperCase()); });

		o = s.option(form.Value, 'command', _('Play command'));
		o.rmempty = false;
		o.placeholder = 'mpc clear && mpc add "$AUDIOWRT_URI" && mpc play';

		o = s.option(form.Flag, 'managed', _('Managed process'));
		o.default = o.disabled;
		o.description = _('Enable only when the play command stays in the foreground for the whole playback session.');

		o = s.option(form.Value, 'pause_command', _('Pause command'));
		o.optional = true;
		o = s.option(form.Value, 'resume_command', _('Resume command'));
		o.optional = true;
		o = s.option(form.Value, 'stop_command', _('Stop command'));
		o.optional = true;
		o = s.option(form.Value, 'mime', _('MIME types'));
		o.optional = true;
		o.placeholder = 'audio/flac audio/x-flac';
		o = s.option(form.Value, 'extensions', _('Extensions'));
		o.optional = true;
		o.placeholder = 'flac';

		poll.add(function() {
			return L.resolveDefault(fs.exec('/usr/libexec/audiowrt-renderer', [ 'status' ]), { stdout: '{}' }).then(function(res) {
				var st = parseJSON(res.stdout, {}), fields = {
					'dlna-state': st.state || '-',
					'dlna-controller': st.controller || '-',
					'dlna-codec': st.codec ? String(st.codec).toUpperCase() : '-',
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

		return Promise.resolve(m.render()).then(function(formNode) {
			return E('div', { 'class': 'cbi-map' }, [
				E('h2', {}, _('Renderer status')),
				E('div', { 'class': 'cbi-section' }, [
					E('p', {}, _('Discovery: SSDP/DLNA and mDNS/DNS-SD are provided by this renderer service.')),
					E('div', { 'class': 'table' }, [
						statusRow(_('Playback'), 'dlna-state', status.state),
						statusRow(_('Last controller'), 'dlna-controller', status.controller),
						statusRow(_('Codec'), 'dlna-codec', status.codec ? String(status.codec).toUpperCase() : '-'),
						statusRow(_('Position'), 'dlna-position', status.position),
						statusRow(_('Volume'), 'dlna-volume', status.volume != null ? String(status.volume) + '%' : '-'),
						statusRow(_('URI'), 'dlna-uri', status.uri)
					])
				]),
				E('h3', {}, _('Codec players')),
				E('div', { 'class': 'cbi-section' }, [ renderPlayers(players) ]),
				formNode
			]);
		});
	}
});
