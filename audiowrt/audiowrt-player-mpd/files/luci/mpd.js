'use strict';

'require view';
'require form';
'require fs';
'require ui';
'require uci';

function parseKv(text) {
	var out = {};
	(text || '').split(/\n/).forEach(function(line) {
		var p = line.indexOf('=');
		if (p > 0)
			out[line.substring(0, p)] = line.substring(p + 1);
	});
	return out;
}

function parseCaps(text) {
	return (text || '').trim().split(/\n/).filter(Boolean).map(function(line) {
		var f = line.split('|');
		return { codec: f[0] || '', mimes: f[1] || '', extensions: f[2] || '' };
	});
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('audiowrt_mpd'),
			L.resolveDefault(fs.exec('/usr/bin/audiowrt-player-mpd', [ 'status' ]), { code: 1, stdout: '' }),
			L.resolveDefault(fs.exec('/usr/bin/audiowrt-mpd-refresh-codecs', [ 'list' ]), { code: 0, stdout: '' })
		]);
	},

	render: function(data) {
		var self = this;
		var status = parseKv(data[1].stdout);
		var caps = parseCaps(data[2].stdout);
		var m = new form.Map('audiowrt_mpd', _('MPD'),
			_('AudioWRT uses the existing MPD instance without replacing its configuration or changing its ALSA output.'));
		var s = m.section(form.NamedSection, 'main', 'mpd', _('Connection'));
		var o;

		o = s.option(form.Value, 'host', _('Host'));
		o.datatype = 'host';
		o.default = '127.0.0.1';
		o.rmempty = false;

		o = s.option(form.Value, 'port', _('Port'));
		o.datatype = 'port';
		o.default = '6600';
		o.rmempty = false;

		o = s.option(form.DummyValue, '_reachable', _('Status'));
		o.cfgvalue = function() { return status.reachable === '1' ? _('Connected') : _('Not reachable'); };

		o = s.option(form.DummyValue, '_version', _('MPD version'));
		o.cfgvalue = function() { return status.version || '-'; };

		o = s.option(form.DummyValue, '_state', _('Playback state'));
		o.cfgvalue = function() { return status.state || '-'; };

		o = s.option(form.DummyValue, '_listener', _('AudioWRT listener'));
		o.cfgvalue = function(section_id) {
			var managed = uci.get('audiowrt_mpd', section_id, 'managed_listener') === '1';
			var pending = uci.get('audiowrt_mpd', section_id, 'listener_pending_restart') === '1';
			if (pending)
				return _('Added to mpd.conf · MPD restart may be required');
			return managed ? _('Managed local listener') : _('Existing MPD listener');
		};

		var c = m.section(form.TypedSection, '_mpd_caps', _('Detected codecs'));
		c.anonymous = true;
		c.addremove = false;
		c.render = function() {
			var rows = [ E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('Codec')),
				E('th', { 'class': 'th' }, _('MIME types')),
				E('th', { 'class': 'th' }, _('Extensions'))
			]) ];
			if (caps.length) {
				caps.forEach(function(cap) {
					rows.push(E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td' }, cap.codec),
						E('td', { 'class': 'td' }, cap.mimes),
						E('td', { 'class': 'td' }, cap.extensions)
					]));
				});
			} else {
				rows.push(E('tr', { 'class': 'tr placeholder' }, [
					E('td', { 'class': 'td', 'colspan': '3' }, E('em', {}, _('No codecs detected yet.')))
				]));
			}
			return E('div', { 'class': 'cbi-section' }, [
				E('table', { 'class': 'table cbi-section-table' }, rows),
				E('p', {}, E('button', {
					'class': 'btn cbi-button-action',
					'click': function() {
						ui.showModal(_('MPD'), [ E('p', { 'class': 'spinning' }, _('Refreshing codecs...')) ]);
						fs.exec('/usr/bin/audiowrt-mpd-refresh-codecs', [ 'refresh' ]).then(function(res) {
							ui.hideModal();
							if (res.code)
								throw new Error(res.stderr || _('Codec refresh failed.'));
							window.location.reload();
						}).catch(function(err) {
							ui.hideModal();
							ui.addNotification(null, E('p', {}, err.message || String(err)), 'error');
						});
					}
				}, _('Refresh codecs')))
			]);
		};

		return m.render();
	}
});
