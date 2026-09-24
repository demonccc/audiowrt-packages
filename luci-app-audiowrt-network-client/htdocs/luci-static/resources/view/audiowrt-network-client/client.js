'use strict';
'require view';
'require poll';
'require fs';
'require ui';
'require dom';

function parseStatus(text) {
	var out = {};
	(text || '').trim().split(/\n/).forEach(function(line) {
		var p = line.indexOf('=');
		if (p > 0)
			out[line.substring(0, p)] = line.substring(p + 1);
	});
	return out;
}

function parseScan(text) {
	var networks = [], radio = null, band = '', json = [];

	function flush() {
		if (!radio || !json.length)
			return;

		try {
			var value = JSON.parse(json.join('\n'));
			(value.results || []).forEach(function(n) {
				if (!n.ssid)
					return;
				networks.push({
					radio: radio,
					band: scanBand(n, band),
					generation: wifiGeneration(n),
					ssid: n.ssid,
					bssid: n.bssid || '',
					channel: n.channel || '',
					signal: Number(n.signal || -999),
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
		}
		else if (radio) {
			json.push(line);
		}
	});

	flush();
	return networks.sort(function(a, b) { return b.signal - a.signal; });
}

function encryptionMode(enc) {
	if (!enc || !enc.enabled)
		return 'none';

	var text = JSON.stringify(enc).toLowerCase();
	if (text.indexOf('sae') >= 0 && (text.indexOf('psk') >= 0 || text.indexOf('wpa2') >= 0))
		return 'sae-mixed';
	if (text.indexOf('sae') >= 0)
		return 'sae';

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

function bandFromFrequency(value) {
	var mhz = Number(value || 0);
	if (mhz >= 5925) return _('6 GHz');
	if (mhz >= 4900) return _('5 GHz');
	if (mhz >= 2400) return _('2.4 GHz');
	return '-';
}

function scanBand(network, fallback) {
	var band = String(network && network.band != null ? network.band : '').toLowerCase();
	var mhz = Number(network && network.mhz || 0);

	if (band === '2' || band === '2g' || band === '2.4') return '2g';
	if (band === '5' || band === '5g') return '5g';
	if (band === '6' || band === '6g') return '6g';
	if (mhz >= 5925) return '6g';
	if (mhz >= 4900) return '5g';
	if (mhz >= 2400) return '2g';

	return fallback || '';
}

function wifiGeneration(network) {
	if (network && network.eht_operation) return 7;
	if (network && network.he_operation) return 6;
	if (network && network.vht_operation) return 5;
	if (network && network.ht_operation) return 4;
	return null;
}

function wifiLabel(generation) {
	return generation ? _('Wi-Fi %d').format(generation) : _('Legacy Wi-Fi');
}

function groupedNetworks(networks) {
	var groups = {};

	networks.forEach(function(n) {
		if (!groups[n.ssid])
			groups[n.ssid] = { ssid: n.ssid, aps: [] };
		groups[n.ssid].aps.push(n);
	});

	return Object.keys(groups).map(function(ssid) {
		var group = groups[ssid];
		group.aps.sort(function(a, b) { return b.signal - a.signal; });
		group.best = group.aps[0];
		group.bands = [];
		group.generations = [];

		group.aps.forEach(function(ap) {
			if (ap.band && group.bands.indexOf(ap.band) < 0)
				group.bands.push(ap.band);
			if (ap.generation && group.generations.indexOf(ap.generation) < 0)
				group.generations.push(ap.generation);
		});

		group.generations.sort(function(a, b) { return a - b; });
		return group;
	}).sort(function(a, b) { return b.best.signal - a.best.signal; });
}

function formatBytes(value) {
	if (value == null || value === '')
		return '-';

	var n = Number(value);
	if (!isFinite(n) || n < 0)
		return '-';
	if (n < 1024)
		return '%d B'.format(n);
	if (n < 1024 * 1024)
		return '%.1f KiB'.format(n / 1024);
	if (n < 1024 * 1024 * 1024)
		return '%.1f MiB'.format(n / (1024 * 1024));
	return '%.2f GiB'.format(n / (1024 * 1024 * 1024));
}

function ipModeLabel(mode) {
	return mode === 'static' ? _('Manual') : _('Automatic (DHCP)');
}

function routeLabel(value) {
	if (value === 'ethernet') return _('Ethernet');
	if (value === 'wifi') return _('Wi-Fi');
	return value || '-';
}

function statusBadge(connected) {
	return E('span', {
		'style': [
			'display:inline-flex',
			'align-items:center',
			'gap:.35rem',
			'padding:.18rem .55rem',
			'border-radius:999px',
			'font-size:.85em',
			'font-weight:600',
			connected ? 'background:rgba(40,167,69,.12)' : 'background:rgba(108,117,125,.12)',
			connected ? 'color:#218838' : 'color:#6c757d'
		].join(';')
	}, [
		E('span', { 'style': 'font-size:.8em' }, connected ? '●' : '○'),
		connected ? _('Connected') : _('Disconnected')
	]);
}

function metric(label, value, node) {
	return E('div', {
		'style': 'min-width:0;padding:.2rem 0'
	}, [
		E('div', {
			'style': 'font-size:.78rem;opacity:.68;margin-bottom:.15rem'
		}, label),
		E('div', {
			'style': 'font-size:1rem;font-weight:600;overflow-wrap:anywhere'
		}, node || value || '-')
	]);
}

function metricGrid(items) {
	return E('div', {
		'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(145px,1fr));gap:.65rem 1.35rem'
	}, items);
}

function group(title, items) {
	return E('div', { 'style': 'margin-top:1rem' }, [
		E('div', {
			'style': 'font-size:.82rem;font-weight:700;opacity:.72;margin-bottom:.45rem'
		}, title),
		metricGrid(items)
	]);
}

function sectionHeader(icon, title, subtitle, connected) {
	return E('div', {
		'style': 'display:flex;align-items:center;justify-content:space-between;gap:1rem;flex-wrap:wrap;margin-bottom:.5rem'
	}, [
		E('div', { 'style': 'display:flex;align-items:center;gap:.7rem;min-width:0' }, [
			E('img', {
				'src': icon,
				'style': 'width:32px;height:32px;flex:none'
			}),
			E('div', { 'style': 'min-width:0' }, [
				E('div', { 'style': 'font-size:1.2rem;font-weight:700' }, title),
				subtitle ? E('div', { 'style': 'opacity:.75;overflow-wrap:anywhere' }, subtitle) : ''
			])
		]),
		statusBadge(connected)
	]);
}

function signalPercent(dbm) {
	if (dbm == null || dbm === '')
		return -1;

	var signal = Number(dbm);
	if (!isFinite(signal))
		return -1;
	return Math.max(0, Math.min(100, 2 * (signal + 100)));
}

function signalIcon(dbm) {
	var q = signalPercent(dbm);

	if (q < 0) return L.resource('icons/signal-none.svg');
	if (q === 0) return L.resource('icons/signal-000-000.svg');
	if (q < 25) return L.resource('icons/signal-000-025.svg');
	if (q < 50) return L.resource('icons/signal-025-050.svg');
	if (q < 75) return L.resource('icons/signal-050-075.svg');
	return L.resource('icons/signal-075-100.svg');
}

function signalNode(dbm) {
	if (dbm == null || dbm === '')
		return E('span', {}, '-');

	return E('span', { 'style': 'display:inline-flex;align-items:center;gap:.35rem' }, [
		E('img', {
			'src': signalIcon(dbm),
			'style': 'width:24px;height:24px'
		}),
		E('span', {}, '%s dBm'.format(dbm))
	]);
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

function ipConfigFields(status, prefix) {
	status = status || {};
	prefix = prefix || '';

	var dns = (status[prefix + 'dns'] || '').trim().split(/\s+/).filter(Boolean);
	var mode = E('select', {}, [
		E('option', { 'value': 'dhcp' }, _('Automatic (DHCP)')),
		E('option', { 'value': 'static' }, _('Manual'))
	]);
	var ipaddr = E('input', {
		'type': 'text',
		'placeholder': '192.168.1.50',
		'value': status[prefix + 'ipaddr'] || ''
	});
	var netmask = E('input', {
		'type': 'text',
		'placeholder': '255.255.255.0',
		'value': status[prefix + 'netmask'] || ''
	});
	var gateway = E('input', {
		'type': 'text',
		'placeholder': '192.168.1.1',
		'value': status[prefix + 'gateway'] || ''
	});
	var dns1 = E('input', {
		'type': 'text',
		'placeholder': '192.168.1.1',
		'value': dns[0] || ''
	});
	var dns2 = E('input', {
		'type': 'text',
		'placeholder': '1.1.1.1',
		'value': dns[1] || ''
	});
	var manual = E('div', {
		'style': 'margin-top:.5rem;display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:.5rem 1rem'
	}, [
		E('div', {}, [ E('label', {}, _('IP address')), ipaddr ]),
		E('div', {}, [ E('label', {}, _('Netmask')), netmask ]),
		E('div', {}, [ E('label', {}, _('Gateway')), gateway ]),
		E('div', {}, [ E('label', {}, _('Primary DNS (optional)')), dns1 ]),
		E('div', {}, [ E('label', {}, _('Secondary DNS (optional)')), dns2 ])
	]);

	function sync() {
		manual.style.display = mode.value === 'static' ? 'grid' : 'none';
	}

	mode.value = status[prefix + 'ip_mode'] === 'static' ? 'static' : 'dhcp';
	mode.addEventListener('change', sync);
	sync();

	return {
		mode: mode,
		ipaddr: ipaddr,
		netmask: netmask,
		gateway: gateway,
		dns1: dns1,
		dns2: dns2,
		node: E('div', {}, [
			E('label', {}, _('IP configuration')),
			mode,
			manual
		])
	};
}

function ethernetStatus(status) {
	var connected = status.ethernet_up === '1' && status.ethernet_link === '1';
	var icon = L.resource(connected ? 'icons/ethernet.svg' : 'icons/ethernet_disabled.svg');
	var speed = status.ethernet_speed ? status.ethernet_speed + ' Mbps' : '-';
	if (status.ethernet_duplex)
		speed += ' · ' + status.ethernet_duplex;

	var ip = status.ethernet_runtime_ip || '-';
	if (status.ethernet_runtime_prefix)
		ip += '/' + status.ethernet_runtime_prefix;

	return E('div', { 'class': 'cbi-section', 'style': 'padding-bottom:.5rem' }, [
		sectionHeader(icon, _('Ethernet'), status.ethernet_physical_device || status.ethernet_device || '', connected),
		group(_('Connection'), [
			metric(_('Link'), connected ? _('Up') : _('Down')),
			metric(_('IP configuration'), ipModeLabel(status.ethernet_ip_mode)),
			metric(_('Speed'), speed),
			metric(_('Active route'), routeLabel(status.active_route))
		]),
		group(_('Address'), [
			metric(_('IP address'), ip),
			metric(_('Gateway'), status.ethernet_runtime_gateway || '-'),
			metric(_('DNS'), status.ethernet_runtime_dns || '-')
		]),
		group(_('Traffic'), [
			metric(_('RX'), formatBytes(status.ethernet_rx_bytes)),
			metric(_('TX'), formatBytes(status.ethernet_tx_bytes))
		])
	]);
}

function wifiStatus(status, activeRoute) {
	var connected = status.network_up === '1';
	var title = status.actual_ssid || status.ssid || _('Not configured');
	var ip = status.runtime_ip || '-';

	if (status.runtime_prefix)
		ip += '/' + status.runtime_prefix;

	return E('div', { 'class': 'cbi-section', 'style': 'padding-bottom:.5rem' }, [
		sectionHeader(signalIcon(connected ? status.signal : ''), _('Wi-Fi'), title, connected),
		group(_('Connection'), [
			metric(_('Signal'), '', signalNode(status.signal)),
			metric(_('Channel'), status.channel || '-'),
			metric(_('Band'), bandFromFrequency(status.frequency)),
			metric(_('Frequency'), status.frequency ? status.frequency + ' MHz' : '-'),
			metric(_('RX bitrate'), status.rx_bitrate || '-'),
			metric(_('TX bitrate'), status.tx_bitrate || '-'),
			metric(_('BSSID'), status.actual_bssid || status.bssid || '-'),
			metric(_('Active route'), routeLabel(activeRoute))
		]),
		group(_('Address'), [
			metric(_('IP address'), ip),
			metric(_('Gateway'), status.runtime_gateway || '-'),
			metric(_('DNS'), status.runtime_dns || '-')
		]),
		group(_('Traffic'), [
			metric(_('RX'), formatBytes(status.rx_bytes)),
			metric(_('TX'), formatBytes(status.tx_bytes))
		])
	]);
}

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(fs.exec('/usr/sbin/audiowrt-network-client', [ 'status' ]), { stdout: '' }),
			L.resolveDefault(fs.exec('/usr/sbin/audiowrt-wifi-client', [ 'status' ]), { stdout: '' })
		]);
	},

	render: function(data) {
		var self = this;
		this.networkStatus = parseStatus(data[0].stdout);
		this.wifiStatus = parseStatus(data[1].stdout);

		this.ethernetNode = E('div');
		this.wifiNode = E('div');
		this.refreshStatus();

		this.saveWifiButton = E('button', {
			'class': 'btn cbi-button-positive',
			'disabled': this.wifiStatus.network_up !== '1' || this.wifiStatus.pending !== '1',
			'click': function() {
				fs.exec('/usr/sbin/audiowrt-wifi-client', [ 'commit-client' ]).then(function(r) {
					if (r.code)
						throw new Error(r.stderr);
					ui.addNotification(null, E('p', {}, _('Wi-Fi settings saved.')));
				}).catch(function(e) {
					ui.addNotification(null, E('p', {}, e.message), 'error');
				});
			}
		}, _('Save Wi-Fi'));

		this.scanResult = E('div', { 'class': 'cbi-section' }, [
			E('em', {}, _('Press Scan to discover nearby Wi-Fi networks.'))
		]);

		var ethernetFields = ipConfigFields(this.networkStatus, 'ethernet_');
		var ethernetConfig = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Ethernet configuration')),
			E('p', {}, _('Configure the LAN client address. Changing this may move the web interface to a new IP address.')),
			ethernetFields.node,
			E('div', { 'style': 'margin-top:.75rem' }, [
				E('button', {
					'class': 'btn cbi-button-positive',
					'click': function() {
						var args = [
							'configure-ethernet',
							ethernetFields.mode.value,
							ethernetFields.ipaddr.value,
							ethernetFields.netmask.value,
							ethernetFields.gateway.value,
							ethernetFields.dns1.value,
							ethernetFields.dns2.value
						];

						fs.exec('/usr/sbin/audiowrt-network-client', args).then(function(r) {
							if (r.code)
								throw new Error(r.stderr || _('Could not configure Ethernet.'));
							ui.addNotification(null, E('p', {}, _('Ethernet configuration saved. The device address may change.')));
						}).catch(function(e) {
							ui.addNotification(null, E('p', {}, e.message || String(e)), 'error');
						});
					}
				}, _('Save Ethernet'))
			])
		]);

		var wifiConfig = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Wi-Fi configuration')),
			E('div', {}, [
				E('button', {
					'class': 'btn cbi-button-action',
					'click': function() { self.scan(); }
				}, _('Scan')),
				' ',
				E('button', {
					'class': 'btn',
					'click': function() { self.manualDialog(); }
				}, _('Hidden / manual network')),
				' ',
				this.saveWifiButton
			]),
			E('p', {}, _('Connect tests the network in memory. Press Save Wi-Fi after a successful connection to keep it across reboots.'))
		]);

		poll.add(function() {
			return Promise.all([
				fs.exec('/usr/sbin/audiowrt-network-client', [ 'status' ]),
				fs.exec('/usr/sbin/audiowrt-wifi-client', [ 'status' ])
			]).then(function(results) {
				self.networkStatus = parseStatus(results[0].stdout);
				self.wifiStatus = parseStatus(results[1].stdout);
				self.saveWifiButton.disabled = self.wifiStatus.network_up !== '1' || self.wifiStatus.pending !== '1';
				self.refreshStatus();
			});
		}, 3);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Network Client')),
			E('p', {}, _('View and configure how AudioWRT connects to the network. Ethernet and Wi-Fi status are shown together for quick diagnostics.')),
			this.ethernetNode,
			this.wifiNode,
			ethernetConfig,
			wifiConfig,
			this.scanResult
		]);
	},

	refreshStatus: function() {
		dom.content(this.ethernetNode, ethernetStatus(this.networkStatus || {}));
		dom.content(this.wifiNode, wifiStatus(this.wifiStatus || {}, (this.networkStatus || {}).active_route));
	},

	scan: function() {
		var self = this;
		dom.content(this.scanResult, E('p', { 'class': 'spinning' }, _('Scanning all radios…')));

		fs.exec('/usr/sbin/audiowrt-wifi-client', [ 'scan' ]).then(function(res) {
			if (res.code)
				throw new Error(res.stderr || _('Wi-Fi scan failed.'));

			var groups = groupedNetworks(parseScan(res.stdout));
			if (!groups.length) {
				dom.content(self.scanResult, E('p', {}, _('No Wi-Fi networks were found.')));
				return;
			}

			var nodes = groups.map(function(groupData) {
				var details = E('div', {
					'style': 'display:none;margin:.25rem 0 1rem 1rem'
				}, groupData.aps.map(function(ap) {
					return E('div', { 'class': 'tr' }, [
						E('div', { 'class': 'td left' }, wifiLabel(ap.generation) + ' · ' + bandLabel(ap.band) + ' · ' + _('Channel %s').format(ap.channel || '-')),
						E('div', { 'class': 'td left' }, String(ap.signal) + ' dBm'),
						E('div', { 'class': 'td left' }, ap.bssid || '-'),
						E('div', { 'class': 'td right' }, E('button', {
							'class': 'btn',
							'click': function() { self.connectDialog(ap, true); }
						}, _('Select')))
					]);
				}));

				var bands = groupData.bands.map(bandLabel).join(' / ');
				var standards = groupData.generations.length ? groupData.generations.map(wifiLabel).join(' / ') : _('Legacy Wi-Fi');

				var main = E('div', { 'class': 'tr' }, [
					E('div', { 'class': 'td left' }, [
						E('strong', {}, groupData.ssid),
						E('div', {}, standards + ' · ' + bands + ' · ' + _('Best: %s dBm').format(groupData.best.signal))
					]),
					E('div', { 'class': 'td left' }, _('%d access points').format(groupData.aps.length)),
					E('div', { 'class': 'td left' }, securityLabel(groupData.best.encryption)),
					E('div', { 'class': 'td right' }, [
						E('button', {
							'class': 'btn cbi-button-action',
							'click': function() { self.connectDialog(groupData.best, false); }
						}, _('Select')),
						' ',
						E('button', {
							'class': 'btn',
							'click': function() {
								details.style.display = details.style.display === 'none' ? '' : 'none';
							}
						}, _('▾'))
					])
				]);

				return E('div', {}, [ main, details ]);
			});

			dom.content(self.scanResult, E('div', { 'class': 'table' }, nodes));
		}).catch(function(err) {
			dom.content(self.scanResult, E('p', { 'class': 'alert-message error' }, err.message || String(err)));
		});
	},

	connectDialog: function(network, pinBssid) {
		var encryption = encryptionMode(network.encryption);
		var password = passwordField(_('Wi-Fi password'));
		var ip = ipConfigFields(this.wifiStatus);
		var info = wifiLabel(network.generation) + ' · ' + bandLabel(network.band) + ' · ' + _('Channel %s').format(network.channel || '-');

		if (pinBssid && network.bssid)
			info += ' · ' + network.bssid;

		ui.showModal(_('Connect to %s').format(network.ssid), [
			E('p', {}, info),
			encryption === 'none' ? E('p', {}, _('This is an open network.')) : password.node,
			ip.node,
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')),
				' ',
				E('button', {
					'class': 'btn cbi-button-action',
					'click': function() {
						var key = encryption === 'none' ? '' : password.input.value;
						var args = [
							'connect',
							network.radio,
							network.ssid,
							encryption,
							key,
							pinBssid && network.bssid ? network.bssid : '',
							ip.mode.value,
							ip.ipaddr.value,
							ip.netmask.value,
							ip.gateway.value,
							ip.dns1.value,
							ip.dns2.value
						];

						fs.exec('/usr/sbin/audiowrt-wifi-client', args).then(function(res) {
							if (res.code)
								throw new Error(res.stderr || _('Could not connect to Wi-Fi.'));
							ui.hideModal();
							ui.addNotification(null, E('p', {}, _('Wi-Fi client configuration applied.')));
						}).catch(function(err) {
							ui.addNotification(null, E('p', {}, err.message || String(err)), 'error');
						});
					}
				}, _('Connect'))
			])
		]);
	},

	manualDialog: function() {
		var self = this;

		fs.exec('/usr/sbin/audiowrt-wifi-client', [ 'radios' ]).then(function(res) {
			if (res.code)
				throw new Error(res.stderr || _('Could not enumerate Wi-Fi radios.'));

			var radios = (res.stdout || '').trim().split(/\n/).filter(Boolean).map(function(line) {
				var f = line.split('|');
				return { name: f[0], band: f[1] || '' };
			});

			if (!radios.length)
				throw new Error(_('No Wi-Fi radios are available.'));

			var radio = E('select', {}, radios.map(function(r) {
				return E('option', { 'value': r.name }, bandLabel(r.band));
			}));
			var ssid = E('input', { 'type': 'text', 'autocomplete': 'off' });
			var encryption = E('select', {}, [
				E('option', { 'value': 'sae-mixed' }, _('WPA2/WPA3 Personal')),
				E('option', { 'value': 'psk2' }, _('WPA2 Personal')),
				E('option', { 'value': 'sae' }, _('WPA3 Personal')),
				E('option', { 'value': 'none' }, _('Open network'))
			]);
			var password = passwordField(_('Wi-Fi password'));
			var ip = ipConfigFields(self.wifiStatus);

			function syncPassword() {
				password.node.style.display = encryption.value === 'none' ? 'none' : '';
			}

			encryption.addEventListener('change', syncPassword);
			syncPassword();

			ui.showModal(_('Hidden / manual network'), [
				E('label', {}, _('Band')), radio,
				E('label', {}, _('Network name (SSID)')), ssid,
				E('label', {}, _('Security')), encryption,
				password.node,
				ip.node,
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')),
					' ',
					E('button', {
						'class': 'btn cbi-button-action',
						'click': function() {
							var key = encryption.value === 'none' ? '' : password.input.value;

							fs.exec('/usr/sbin/audiowrt-wifi-client', [
								'connect',
								radio.value,
								ssid.value,
								encryption.value,
								key,
								'',
								ip.mode.value,
								ip.ipaddr.value,
								ip.netmask.value,
								ip.gateway.value,
								ip.dns1.value,
								ip.dns2.value
							]).then(function(result) {
								if (result.code)
									throw new Error(result.stderr || _('Could not connect to Wi-Fi.'));
								ui.hideModal();
								ui.addNotification(null, E('p', {}, _('Wi-Fi client configuration applied.')));
							}).catch(function(err) {
								ui.addNotification(null, E('p', {}, err.message || String(err)), 'error');
							});
						}
					}, _('Connect'))
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
