'use strict';
'require view';
'require fs';
'require ui';
'require dom';

function parseStatus(text) {
	var out = {};
	(text || '').trim().split(/\n/).forEach(function(line) {
		var p = line.indexOf('=');
		if (p > 0) out[line.substring(0, p)] = line.substring(p + 1);
	});
	return out;
}

function parseScan(text) {
	var networks = [], radio = null, band = '', json = [];
	function flush() {
		if (!radio || !json.length) return;
		try {
			var value = JSON.parse(json.join('\n'));
			(value.results || []).forEach(function(n) {
				if (!n.ssid) return;
				networks.push({ radio: radio, band: band, ssid: n.ssid, bssid: n.bssid || '', channel: n.channel || '', signal: Number(n.signal || -999), encryption: n.encryption || {} });
			});
		} catch (e) { }
	}
	(text || '').split(/\n/).forEach(function(line) {
		if (line.indexOf('@@RADIO:') === 0) {
			flush();
			var parts = line.substring(8).split('|');
			radio = parts[0]; band = parts[1] || ''; json = [];
		} else if (radio) json.push(line);
	});
	flush();
	return networks.sort(function(a, b) { return b.signal - a.signal; });
}

function encryptionMode(enc) {
	if (!enc || !enc.enabled) return 'none';
	var text = JSON.stringify(enc).toLowerCase();
	if (text.indexOf('sae') >= 0 && (text.indexOf('psk') >= 0 || text.indexOf('wpa2') >= 0)) return 'sae-mixed';
	if (text.indexOf('sae') >= 0) return 'sae';
	return 'psk2';
}

function securityLabel(enc) {
	switch (encryptionMode(enc)) {
	case 'none': return _('Open');
	case 'sae': return _('WPA3 Personal');
	case 'sae-mixed': return _('WPA2/WPA3 Personal');
	default: return _('WPA2 Personal');
	}
}

function bandLabel(value) {
	if (value === '2g') return _('2.4 GHz');
	if (value === '5g') return _('5 GHz');
	if (value === '6g') return _('6 GHz');
	return value || '-';
}

function groupedNetworks(networks) {
	var groups = {};
	networks.forEach(function(n) {
		if (!groups[n.ssid]) groups[n.ssid] = { ssid: n.ssid, aps: [] };
		groups[n.ssid].aps.push(n);
	});
	return Object.keys(groups).map(function(ssid) {
		var group = groups[ssid];
		group.aps.sort(function(a, b) { return b.signal - a.signal; });
		group.best = group.aps[0];
		group.bands = [];
		group.aps.forEach(function(ap) { if (group.bands.indexOf(ap.band) < 0) group.bands.push(ap.band); });
		return group;
	}).sort(function(a, b) { return b.best.signal - a.best.signal; });
}

function passwordField(label) {
	var input = E('input', { 'class': 'cbi-input-password', 'type': 'password', 'autocomplete': 'new-password' });
	var toggle = E('button', { 'class': 'btn', 'type': 'button', 'click': function() {
		input.type = input.type === 'password' ? 'text' : 'password';
		toggle.textContent = input.type === 'password' ? _('Show') : _('Hide');
	} }, _('Show'));
	return { input: input, node: E('div', {}, [ E('label', {}, label), E('div', { 'style': 'display:flex;gap:.5rem' }, [ input, toggle ]) ]) };
}

return view.extend({
	load: function() {
		return L.resolveDefault(fs.exec('/usr/sbin/audiowrt-wifi-client', [ 'status' ]), { stdout: '' });
	},

	render: function(data) {
		var status = parseStatus(data.stdout), self = this;
		this.result = E('div', { 'class': 'cbi-section' }, [ E('em', {}, _('Press Scan to discover nearby Wi-Fi networks.')) ]);
		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Wi-Fi Client')),
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, _('Configure AudioWRT as a Wi-Fi client. Networks are grouped by SSID; expand a network only when you want to pin a specific access point.')),
				E('p', {}, [ E('strong', {}, _('Current network: ')), status.ssid || _('Not connected') ]),
				E('p', {}, [ E('strong', {}, _('Status: ')), status.network_up === '1' ? _('Connected') : _('Disconnected') ]),
				E('button', { 'class': 'btn cbi-button-action', 'click': function() { self.scan(); } }, _('Scan')), ' ',
				E('button', { 'class': 'btn', 'click': function() { self.manualDialog(); } }, _('Hidden / manual network'))
			]), this.result
		]);
	},

	scan: function() {
		var self = this;
		dom.content(this.result, E('p', { 'class': 'spinning' }, _('Scanning all radios…')));
		fs.exec('/usr/sbin/audiowrt-wifi-client', [ 'scan' ]).then(function(res) {
			if (res.code) throw new Error(res.stderr || _('Wi-Fi scan failed.'));
			var groups = groupedNetworks(parseScan(res.stdout));
			if (!groups.length) { dom.content(self.result, E('p', {}, _('No Wi-Fi networks were found.'))); return; }
			var nodes = groups.map(function(group) {
				var details = E('div', { 'style': 'display:none;margin:.25rem 0 1rem 1rem' }, group.aps.map(function(ap) {
					return E('div', { 'class': 'tr' }, [
						E('div', { 'class': 'td left' }, bandLabel(ap.band) + ' · ' + _('Channel %s').format(ap.channel || '-')),
						E('div', { 'class': 'td left' }, String(ap.signal) + ' dBm'),
						E('div', { 'class': 'td left' }, ap.bssid || '-'),
						E('div', { 'class': 'td right' }, E('button', { 'class': 'btn', 'click': function() { self.connectDialog(ap, true); } }, _('Select')))
					]);
				}));
				var bands = group.bands.map(bandLabel).join(' / ');
				var main = E('div', { 'class': 'tr' }, [
					E('div', { 'class': 'td left' }, [ E('strong', {}, group.ssid), E('div', {}, bands + ' · ' + _('Best: %s dBm').format(group.best.signal)) ]),
					E('div', { 'class': 'td left' }, _('%d access points').format(group.aps.length)),
					E('div', { 'class': 'td left' }, securityLabel(group.best.encryption)),
					E('div', { 'class': 'td right' }, [
						E('button', { 'class': 'btn cbi-button-action', 'click': function() { self.connectDialog(group.best, false); } }, _('Select')), ' ',
						E('button', { 'class': 'btn', 'click': function() { details.style.display = details.style.display === 'none' ? '' : 'none'; } }, _('▾'))
					])
				]);
				return E('div', {}, [ main, details ]);
			});
			dom.content(self.result, E('div', { 'class': 'table' }, nodes));
		}).catch(function(err) { dom.content(self.result, E('p', { 'class': 'alert-message error' }, err.message || String(err))); });
	},

	connectDialog: function(network, pinBssid) {
		var encryption = encryptionMode(network.encryption), password = passwordField(_('Wi-Fi password'));
		var info = bandLabel(network.band) + ' · ' + _('Channel %s').format(network.channel || '-');
		if (pinBssid && network.bssid) info += ' · ' + network.bssid;
		var self = this;
		ui.showModal(_('Connect to %s').format(network.ssid), [
			E('p', {}, info),
			encryption === 'none' ? E('p', {}, _('This is an open network.')) : password.node,
			E('div', { 'class': 'right' }, [ E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ',
				E('button', { 'class': 'btn cbi-button-action', 'click': function() {
					var key = encryption === 'none' ? '' : password.input.value;
					var args = [ 'connect', network.radio, network.ssid, encryption, key ];
					if (pinBssid && network.bssid) args.push(network.bssid);
					fs.exec('/usr/sbin/audiowrt-wifi-client', args).then(function(res) {
						if (res.code) throw new Error(res.stderr || _('Could not connect to Wi-Fi.'));
						ui.hideModal(); ui.addNotification(null, E('p', {}, _('Wi-Fi client configuration applied.')));
					}).catch(function(err) { ui.addNotification(null, E('p', {}, err.message || String(err)), 'error'); });
				} }, _('Connect'))
			])
		]);
	},

	manualDialog: function() {
		var self = this;
		fs.exec('/usr/sbin/audiowrt-wifi-client', [ 'radios' ]).then(function(res) {
			if (res.code) throw new Error(res.stderr || _('Could not enumerate Wi-Fi radios.'));
			var radios = (res.stdout || '').trim().split(/\n/).filter(Boolean).map(function(line) { var f = line.split('|'); return { name: f[0], band: f[1] || '' }; });
			if (!radios.length) throw new Error(_('No Wi-Fi radios are available.'));
			var radio = E('select', {}, radios.map(function(r) { return E('option', { 'value': r.name }, bandLabel(r.band)); }));
			var ssid = E('input', { 'type': 'text', 'autocomplete': 'off' });
			var encryption = E('select', {}, [ E('option', { 'value': 'sae-mixed' }, _('WPA2/WPA3 Personal')), E('option', { 'value': 'psk2' }, _('WPA2 Personal')), E('option', { 'value': 'sae' }, _('WPA3 Personal')), E('option', { 'value': 'none' }, _('Open network')) ]);
			var password = passwordField(_('Wi-Fi password'));
			function syncPassword() { password.node.style.display = encryption.value === 'none' ? 'none' : ''; }
			encryption.addEventListener('change', syncPassword); syncPassword();
			ui.showModal(_('Hidden / manual network'), [ E('label', {}, _('Band')), radio, E('label', {}, _('Network name (SSID)')), ssid, E('label', {}, _('Security')), encryption, password.node,
				E('div', { 'class': 'right' }, [ E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ', E('button', { 'class': 'btn cbi-button-action', 'click': function() {
					var key = encryption.value === 'none' ? '' : password.input.value;
					fs.exec('/usr/sbin/audiowrt-wifi-client', [ 'connect', radio.value, ssid.value, encryption.value, key ]).then(function(result) {
						if (result.code) throw new Error(result.stderr || _('Could not connect to Wi-Fi.'));
						ui.hideModal(); ui.addNotification(null, E('p', {}, _('Wi-Fi client configuration applied.')));
					}).catch(function(err) { ui.addNotification(null, E('p', {}, err.message || String(err)), 'error'); });
				} }, _('Connect')) ])
			]);
		}).catch(function(err) { ui.addNotification(null, E('p', {}, err.message || String(err)), 'error'); });
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
