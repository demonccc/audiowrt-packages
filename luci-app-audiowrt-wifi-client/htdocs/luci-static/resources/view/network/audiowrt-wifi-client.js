'use strict';
'require view';
'require fs';
'require ui';
'require dom';

function parseStatus(text) {
	var result = {};
	(text || '').split(/\n/).forEach(function(line) {
		var pos = line.indexOf('=');
		if (pos > 0)
			result[line.substring(0, pos)] = line.substring(pos + 1);
	});
	return result;
}

function encryptionFor(entry) {
	var enc = entry.encryption || {};
	if (enc.enabled === false || enc.enabled === 0)
		return 'none';
	var auth = Array.isArray(enc.authentication) ? enc.authentication.map(String) : [];
	var hasSae = auth.some(function(v) { return v.toLowerCase().indexOf('sae') >= 0; });
	var hasPsk = auth.some(function(v) { return v.toLowerCase().indexOf('psk') >= 0; });
	if (hasSae && hasPsk)
		return 'sae-mixed';
	if (hasSae)
		return 'sae';
	return 'psk2';
}

return view.extend({
	load: function() {
		return L.resolveDefault(fs.exec('/usr/sbin/audiowrt-wifi-client', [ 'status' ]), { stdout: '' });
	},

	render: function(statusResult) {
		var status = parseStatus(statusResult.stdout),
		    select = E('select', { 'class': 'cbi-input-select', 'style': 'width:100%' }, [
			E('option', { 'value': '' }, _('Scan to select a Wi-Fi network'))
		]),
		    key = E('input', { 'type': 'password', 'class': 'cbi-input-text', 'placeholder': _('Wi-Fi password'), 'style': 'width:100%' }),
		    show = E('button', { 'class': 'btn cbi-button', 'type': 'button' }, _('Show')),
		    scan = E('button', { 'class': 'btn cbi-button-action', 'type': 'button' }, _('Scan networks')),
		    connect = E('button', { 'class': 'btn cbi-button-apply', 'type': 'button' }, _('Connect'));

		show.addEventListener('click', function() {
			var visible = key.type === 'text';
			key.type = visible ? 'password' : 'text';
			show.textContent = visible ? _('Show') : _('Hide');
		});

		scan.addEventListener('click', function() {
			scan.disabled = true;
			fs.exec('/usr/sbin/audiowrt-wifi-client', [ 'scan' ]).then(function(res) {
				var data = JSON.parse(res.stdout || '{"radios":[]}'), options = [];
				(data.radios || []).forEach(function(radio) {
					var band = radio.band === '5g' ? '5 GHz' : (radio.band === '2g' ? '2.4 GHz' : radio.band || radio.device);
					((radio.scan || {}).results || []).forEach(function(entry) {
						if (!entry.ssid)
							return;
						options.push({
							value: JSON.stringify({ radio: radio.device, ssid: entry.ssid, encryption: encryptionFor(entry) }),
							label: '%s — %s — %s dBm'.format(entry.ssid, band, entry.signal != null ? entry.signal : '?')
						});
					});
				});
				options.sort(function(a, b) { return a.label.localeCompare(b.label); });
				dom.content(select, [ E('option', { 'value': '' }, options.length ? _('Select a Wi-Fi network') : _('No Wi-Fi networks found')) ].concat(options.map(function(o) {
					return E('option', { 'value': o.value }, o.label);
				})));
			}).catch(function(err) {
				ui.addNotification(null, E('p', {}, err.message || String(err)), 'error');
			}).finally(function() { scan.disabled = false; });
		});

		connect.addEventListener('click', function() {
			if (!select.value) {
				ui.addNotification(null, E('p', {}, _('Select a Wi-Fi network first.')), 'error');
				return;
			}
			var selected = JSON.parse(select.value), password = key.value || '';
			if (selected.encryption !== 'none' && password.length < 8) {
				ui.addNotification(null, E('p', {}, _('Wi-Fi password must contain at least 8 characters.')), 'error');
				return;
			}
			connect.disabled = true;
			fs.exec('/usr/sbin/audiowrt-wifi-client', [ 'connect', selected.radio, selected.ssid, selected.encryption, password ]).then(function(res) {
				if (res.code)
					throw new Error(res.stderr || _('Could not connect to the selected Wi-Fi network.'));
				ui.addNotification(null, E('p', {}, _('Wi-Fi client connected.')));
				window.setTimeout(function() { window.location.reload(); }, 1500);
			}).catch(function(err) {
				ui.addNotification(null, E('p', {}, err.message || String(err)), 'error');
			}).finally(function() { connect.disabled = false; });
		});

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Wi-Fi Client')),
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, _('This optional AudioWRT component configures OpenWrt as a Wi-Fi client. Installing it alone does not change networking.')),
				E('table', { 'class': 'table' }, [
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left', 'width': '33%' }, _('Status')), E('td', { 'class': 'td left' }, status.connected === '1' ? _('Connected') : _('Not connected')) ]),
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('SSID')), E('td', { 'class': 'td left' }, status.ssid || '-') ]),
					E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Radio')), E('td', { 'class': 'td left' }, status.radio || '-') ])
				]),
				E('div', { 'style': 'margin-top:1em' }, scan),
				E('label', { 'style': 'display:block;margin-top:1em' }, [ E('strong', {}, _('Network')), select ]),
				E('label', { 'style': 'display:block;margin-top:1em' }, [ E('strong', {}, _('Password')), E('div', { 'style': 'display:flex;gap:.5em' }, [ key, show ]) ]),
				E('div', { 'style': 'margin-top:1em' }, connect)
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
