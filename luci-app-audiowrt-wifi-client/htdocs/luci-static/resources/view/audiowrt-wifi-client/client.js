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
	var networks = [], radio = null, json = [];
	function flush() {
		if (!radio || !json.length) return;
		try {
			var value = JSON.parse(json.join('\n'));
			(value.results || []).forEach(function(n) {
				networks.push({
					radio: radio,
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
			radio = line.substring(8);
			json = [];
		} else if (radio) {
			json.push(line);
		}
	});
	flush();
	return networks;
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
				E('button', { 'class': 'btn cbi-button-action', 'click': function() { self.scan(); } }, _('Scan'))
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
					E('div', { 'class': 'td left' }, n.radio),
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
		var encryption = recommendedEncryption(network.encryption), password = E('input', {
			'class': 'cbi-input-password', 'type': 'password', 'autocomplete': 'new-password'
		});
		var toggle = E('button', { 'class': 'btn', 'type': 'button', 'click': function() {
			password.type = password.type === 'password' ? 'text' : 'password';
			toggle.textContent = password.type === 'password' ? _('Show') : _('Hide');
		}}, _('Show'));
		ui.showModal(_('Connect to %s').format(network.ssid || _('hidden network')), [
			E('p', {}, _('Radio: %s').format(network.radio)),
			encryption === 'none' ? E('p', {}, _('This is an open network.')) : E('div', {}, [
				E('label', {}, _('Wi-Fi password')),
				E('div', { 'style': 'display:flex;gap:.5rem' }, [ password, toggle ])
			]),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ',
				E('button', { 'class': 'btn cbi-button-action', 'click': function() {
					var key = encryption === 'none' ? '' : password.value;
					fs.exec('/usr/sbin/audiowrt-wifi-client', [ 'connect', network.radio, network.ssid, encryption, key ]).then(function(res) {
						if (res.code) throw new Error(res.stderr || _('Could not connect to Wi-Fi.'));
						ui.hideModal();
						ui.addNotification(null, E('p', {}, _('Wi-Fi client configuration applied.')));
					}).catch(function(err) { ui.addNotification(null, E('p', {}, err.message || String(err)), 'error'); });
				} }, _('Connect'))
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
