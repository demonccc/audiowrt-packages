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
				networks.push({
					radio: radio,
					band: band,
					ssid: n.ssid || '',
					bssid: n.bssid || '',
					channel: n.channel || '',
					signal: n.signal || '',
					encryption: n.encryption || {}
				});
			});
		} catch (e) { }
	}
	(text || '').split(/\n/).forEach(function(line) {
		if (line.indexOf('@@RADIO:') === 0) {
			flush();
			var parts = line.substring(8).split('|');
			radio = parts[0];
			band = parts[1] || '';
			json = [];
		} else if (radio) {
			json.push(line);
		}
	});
	flush();
	return networks.sort(function(a, b) { return Number(b.signal || -999) - Number(a.signal || -999); });
}

function securityLabel(enc) {
	if (!enc || !enc.enabled) return _('Open');
	var auth = enc.wpa || enc.authentication || enc.description;
	return Array.isArray(auth) ? auth.join('/') : (auth || _('Secured'));
}

function recommendedEncryption(enc) {
	if (!enc || !enc.enabled) return 'none';
	var text = JSON.stringify(enc).toLowerCase();
	if (text.indexOf('sae') >= 0 && text.indexOf('psk') >= 0) return 'sae-mixed';
	if (text.indexOf('sae') >= 0) return 'sae';
	return 'psk2';
}

function bandLabel(value) {
	if (value === '2g') return _('2.4 GHz');
	if (value === '5g') return _('5 GHz');
	if (value === '6g') return _('6 GHz');
	return value || '-';
}

function passwordField(label) {
	var input = E('input', {
		'class': 'cbi-input-password',
		'type': 'password',
		'autocomplete': 'new-password'
	});
	var toggle = E('button', {
		'class': 'btn',
		'type': 'button',
		'click': function() {
			input.type = input.type === 'password' ? 'text' : 'password';
			toggle.textContent = input.type === 'password' ? _('Show') : _('Hide');
		}
	}, _('Show'));
	return {
		input: input,
		node: E('div', {}, [
			E('label', {}, label),
			E('div', { 'style': 'display:flex;gap:.5rem' }, [ input, toggle ])
		])
	};
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
				E('p', {}, _('Configure this OpenWrt device as a Wi-Fi client. No wireless settings are changed until Connect is pressed.')),
				E('p', {}, [ E('strong', {}, _('Current network: ')), status.ssid || _('Not connected') ]),
				E('p', {}, [ E('strong', {}, _('Status: ')), status.network_up === '1' ? _('Connected') : _('Disconnected') ]),
				E('button', { 'class': 'btn cbi-button-action', 'click': function() { self.scan(); } }, _('Scan')),
				' ',
				E('button', { 'class': 'btn', 'click': function() { self.manualDialog(); } }, _('Hidden / manual network'))
			]),
			this.result
		]);
	},

	scan: function() {
		var self = this;
		dom.content(this.result, E('p', { 'class': 'spinning' }, _('Scanning all radios…')));
		fs.exec('/usr/sbin/audiowrt-wifi-client', [ 'scan' ]).then(function(res) {
			if (res.code) throw new Error(res.stderr || _('Wi-Fi scan failed.'));
			var networks = parseScan(res.stdout);
			if (!networks.length) {
				dom.content(self.result, E('p', {}, _('No Wi-Fi networks were found.')));
				return;
			}
			var rows = networks.map(function(n) {
				return E('div', { 'class': 'tr' }, [
					E('div', { 'class': 'td left' }, n.ssid || _('Hidden network')),
					E('div', { 'class': 'td left' }, bandLabel(n.band)),
					E('div', { 'class': 'td left' }, String(n.signal) + ' dBm'),
					E('div', { 'class': 'td left' }, securityLabel(n.encryption)),
					E('div', { 'class': 'td right' }, E('button', {
						'class': 'btn cbi-button-action',
						'click': function() { self.connectDialog(n); }
					}, _('Select')))
				]);
			});
			dom.content(self.result, E('div', { 'class': 'table' }, rows));
		}).catch(function(err) {
			dom.content(self.result, E('p', { 'class': 'alert-message error' }, err.message || String(err)));
		});
	},

	connectDialog: function(network) {
		var encryption = recommendedEncryption(network.encryption), password = passwordField(_('Wi-Fi password'));
		ui.showModal(_('Connect to %s').format(network.ssid || _('hidden network')), [
			E('p', {}, _('Radio: %s (%s)').format(network.radio, bandLabel(network.band))),
			encryption === 'none' ? E('p', {}, _('This is an open network.')) : password.node,
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ',
				E('button', { 'class': 'btn cbi-button-action', 'click': function() {
					var key = encryption === 'none' ? '' : password.input.value;
					fs.exec('/usr/sbin/audiowrt-wifi-client', [ 'connect', network.radio, network.ssid, encryption, key ]).then(function(res) {
						if (res.code) throw new Error(res.stderr || _('Could not connect to Wi-Fi.'));
						ui.hideModal();
						ui.addNotification(null, E('p', {}, _('Wi-Fi client configuration applied.')));
					}).catch(function(err) { ui.addNotification(null, E('p', {}, err.message || String(err)), 'error'); });
				} }, _('Connect'))
			])
		]);
	},

	manualDialog: function() {
		fs.exec('/usr/sbin/audiowrt-wifi-client', [ 'radios' ]).then(function(res) {
			if (res.code) throw new Error(res.stderr || _('Could not enumerate Wi-Fi radios.'));
			var radios = (res.stdout || '').trim().split(/\n/).filter(Boolean).map(function(line) {
				var f = line.split('|');
				return { name: f[0], band: f[1] || '' };
			});
			if (!radios.length) throw new Error(_('No Wi-Fi radios are available.'));
			var radio = E('select', {}, radios.map(function(r) { return E('option', { 'value': r.name }, r.name + ' (' + bandLabel(r.band) + ')'); }));
			var ssid = E('input', { 'type': 'text', 'autocomplete': 'off' });
			var encryption = E('select', {}, [
				E('option', { 'value': 'sae-mixed' }, _('WPA2/WPA3 Personal')),
				E('option', { 'value': 'psk2' }, _('WPA2 Personal')),
				E('option', { 'value': 'sae' }, _('WPA3 Personal')),
				E('option', { 'value': 'none' }, _('Open network'))
			]);
			var password = passwordField(_('Wi-Fi password'));
			function syncPassword() { password.node.style.display = encryption.value === 'none' ? 'none' : ''; }
			encryption.addEventListener('change', syncPassword); syncPassword();
			ui.showModal(_('Hidden / manual network'), [
				E('label', {}, _('Radio')), radio,
				E('label', {}, _('Network name (SSID)')), ssid,
				E('label', {}, _('Security')), encryption,
				password.node,
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ',
					E('button', { 'class': 'btn cbi-button-action', 'click': function() {
						var key = encryption.value === 'none' ? '' : password.input.value;
						fs.exec('/usr/sbin/audiowrt-wifi-client', [ 'connect', radio.value, ssid.value, encryption.value, key ]).then(function(result) {
							if (result.code) throw new Error(result.stderr || _('Could not connect to Wi-Fi.'));
							ui.hideModal();
							ui.addNotification(null, E('p', {}, _('Wi-Fi client configuration applied.')));
						}).catch(function(err) { ui.addNotification(null, E('p', {}, err.message || String(err)), 'error'); });
					} }, _('Connect'))
				])
			]);
		}).catch(function(err) {
			ui.addNotification(null, E('p', {}, err.message || String(err)), 'error');
		});
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
