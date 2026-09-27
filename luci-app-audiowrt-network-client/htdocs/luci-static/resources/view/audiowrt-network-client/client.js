'use strict';
'require view';
'require poll';
'require fs';
'require ui';
'require dom';
'require uci';


var NETWORK_CLIENT =
	'/usr/sbin/audiowrt-network-client';

var WIFI_CLIENT =
	'/usr/sbin/audiowrt-wifi-client';


function parseStatus(text) {
	var out = {};

	(text || '').trim().split(/\n/).forEach(function(line) {
		var p = line.indexOf('=');

		if (p > 0)
			out[line.substring(0, p)] =
				line.substring(p + 1);
	});

	return out;
}


function parseScan(text) {
	var networks = [];
	var radio = null;
	var band = '';
	var json = [];

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
		}
		catch (e) {
		}
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

	return networks.sort(function(a, b) {
		return b.signal - a.signal;
	});
}


function encryptionMode(enc) {
	if (!enc || !enc.enabled)
		return 'none';

	var text = JSON.stringify(enc).toLowerCase();

	if (
		text.indexOf('sae') >= 0 &&
		(
			text.indexOf('psk') >= 0 ||
			text.indexOf('wpa2') >= 0
		)
	)
		return 'sae-mixed';

	if (text.indexOf('sae') >= 0)
		return 'sae';

	return 'psk2';
}


function securityLabel(enc) {
	switch (encryptionMode(enc)) {
	case 'none':
		return _('Open');

	case 'sae':
		return _('WPA3 Personal');

	case 'sae-mixed':
		return _('WPA2/WPA3 Personal');

	default:
		return _('WPA2 Personal');
	}
}


function bandLabel(value) {
	if (value === '2g')
		return _('2.4 GHz');

	if (value === '5g')
		return _('5 GHz');

	if (value === '6g')
		return _('6 GHz');

	return value || '-';
}


function bandFromFrequency(value) {
	var mhz = Number(value || 0);

	if (mhz >= 5925)
		return _('6 GHz');

	if (mhz >= 4900)
		return _('5 GHz');

	if (mhz >= 2400)
		return _('2.4 GHz');

	return '-';
}


function scanBand(network, fallback) {
	var band = String(
		network && network.band != null
			? network.band
			: ''
	).toLowerCase();

	var mhz = Number(
		network && network.mhz || 0
	);

	if (
		band === '2' ||
		band === '2g' ||
		band === '2.4'
	)
		return '2g';

	if (
		band === '5' ||
		band === '5g'
	)
		return '5g';

	if (
		band === '6' ||
		band === '6g'
	)
		return '6g';

	if (mhz >= 5925)
		return '6g';

	if (mhz >= 4900)
		return '5g';

	if (mhz >= 2400)
		return '2g';

	return fallback || '';
}


function wifiGeneration(network) {
	if (network && network.eht_operation)
		return 7;

	if (network && network.he_operation)
		return 6;

	if (network && network.vht_operation)
		return 5;

	if (network && network.ht_operation)
		return 4;

	return null;
}


function wifiLabel(generation) {
	return generation
		? _('Wi-Fi %d').format(generation)
		: _('Legacy Wi-Fi');
}


function groupedNetworks(networks) {
	var groups = {};

	networks.forEach(function(n) {
		if (!groups[n.ssid]) {
			groups[n.ssid] = {
				ssid: n.ssid,
				aps: []
			};
		}

		groups[n.ssid].aps.push(n);
	});

	return Object.keys(groups).map(function(ssid) {
		var group = groups[ssid];

		group.aps.sort(function(a, b) {
			return b.signal - a.signal;
		});

		group.best = group.aps[0];
		group.bands = [];
		group.generations = [];

		group.aps.forEach(function(ap) {
			if (
				ap.band &&
				group.bands.indexOf(ap.band) < 0
			)
				group.bands.push(ap.band);

			if (
				ap.generation &&
				group.generations.indexOf(
					ap.generation
				) < 0
			)
				group.generations.push(
					ap.generation
				);
		});

		group.generations.sort(function(a, b) {
			return a - b;
		});

		return group;
	}).sort(function(a, b) {
		return b.best.signal - a.best.signal;
	});
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
		return '%.1f KiB'.format(
			n / 1024
		);

	if (n < 1024 * 1024 * 1024)
		return '%.1f MiB'.format(
			n / (1024 * 1024)
		);

	return '%.2f GiB'.format(
		n / (1024 * 1024 * 1024)
	);
}


function shortRate(value) {
	if (!value)
		return '-';

	var match = String(value).match(
		/^([0-9.]+\s+MBit\/s)/i
	);

	return match
		? match[1]
		: value;
}


function ipModeLabel(mode) {
	return mode === 'static'
		? _('Manual')
		: _('Automatic (DHCP)');
}


function signalPercent(dbm) {
	if (dbm == null || dbm === '')
		return -1;

	var signal = Number(dbm);

	if (!isFinite(signal))
		return -1;

	return Math.max(
		0,
		Math.min(
			100,
			2 * (signal + 100)
		)
	);
}


function signalIcon(dbm) {
	var q = signalPercent(dbm);

	if (q < 0)
		return L.resource(
			'icons/signal-none.svg'
		);

	if (q === 0)
		return L.resource(
			'icons/signal-000-000.svg'
		);

	if (q < 25)
		return L.resource(
			'icons/signal-000-025.svg'
		);

	if (q < 50)
		return L.resource(
			'icons/signal-025-050.svg'
		);

	if (q < 75)
		return L.resource(
			'icons/signal-050-075.svg'
		);

	return L.resource(
		'icons/signal-075-100.svg'
	);
}


function linkLabel(active) {
	return active
		? _('Active')
		: _('Inactive');
}


function ethernetStatus(status) {
	var link = status.ethernet_link === '1';
	var activeRoute = status.active_route === 'ethernet';
	var ip = status.ethernet_runtime_ip || '-';
	if (status.ethernet_runtime_prefix)
		ip += '/' + status.ethernet_runtime_prefix;

	var speed = '-';
	var n = Number(status.ethernet_speed || 0);
	if (n >= 1000)
		speed = (n / 1000) + ' Gbps';
	else if (n > 0)
		speed = n + ' Mbps';
	if (speed !== '-' && status.ethernet_duplex)
		speed += ' · ' + status.ethernet_duplex;

	return E('div', { 'class': 'ifacebox' }, [
		E('div', { 'class': 'ifacebox-head center ' + (link ? 'active' : '') },
			E('strong', {}, _('Ethernet'))),
		E('div', { 'class': 'ifacebox-body left' }, [
			E('img', {
				'src': L.resource(link ? 'icons/ethernet.svg' : 'icons/ethernet_disabled.svg'),
				'alt': '',
				'width': '40',
				'height': '40'
			}),
			L.itemlist(E('span'), [
				_('Route'), activeRoute ? _('Active uplink') : _('Inactive'),
				_('Link'), linkLabel(link),
				_('Address'), ip,
				_('IP configuration'), ipModeLabel(status.ethernet_ip_mode),
				_('Speed'), speed,
				_('Traffic'), '%s RX / %s TX'.format(
					formatBytes(status.ethernet_rx_bytes),
					formatBytes(status.ethernet_tx_bytes))
			])
		])
	]);
}


function wifiStatus(status, activeRoute) {
	var link = status.network_up === '1';
	var active = activeRoute === 'wifi';
	var ip = status.runtime_ip || '-';
	if (status.runtime_prefix)
		ip += '/' + status.runtime_prefix;

	var channel = status.channel || '-';
	var band = bandFromFrequency(status.frequency);
	if (status.channel && band !== '-')
		channel += ' · ' + band;

	var title = status.actual_ssid || status.ssid || _('Not configured');

	return E('div', { 'class': 'ifacebox' }, [
		E('div', { 'class': 'ifacebox-head center ' + (link ? 'active' : '') },
			E('strong', {}, _('Wi-Fi'))),
		E('div', { 'class': 'ifacebox-body left' }, [
			E('img', {
				'src': signalIcon(link ? status.signal : ''),
				'alt': '',
				'width': '40',
				'height': '40'
			}),
			L.itemlist(E('span'), [
				_('Network'), title,
				_('Route'), active ? _('Active uplink') : _('Inactive'),
				_('Link'), linkLabel(link),
				_('Signal'), status.signal ? '%s dBm'.format(status.signal) : '-',
				_('Channel'), channel,
				_('Address'), ip,
				_('RX / TX rate'), '%s / %s'.format(
					shortRate(status.rx_bitrate),
					shortRate(status.tx_bitrate)),
				_('Traffic'), '%s RX / %s TX'.format(
					formatBytes(status.rx_bytes),
					formatBytes(status.tx_bytes))
			])
		])
	]);
}


function cbiRow(
	label,
	field,
	description
) {
	return E('div', {
		'class': 'cbi-value'
	}, [
		E('label', {
			'class': 'cbi-value-title'
		}, label),

		E('div', {
			'class': 'cbi-value-field'
		}, [
			field,

			description
				? E('div', {
					'class':
						'cbi-value-description'
				}, description)
				: ''
		])
	]);
}


function validIPv4(value) {
	var parts =
		String(value || '').split('.');

	if (parts.length !== 4)
		return false;

	for (
		var i = 0;
		i < parts.length;
		i++
	) {
		if (
			!(/^\d+$/.test(parts[i])) ||
			Number(parts[i]) < 0 ||
			Number(parts[i]) > 255
		)
			return false;
	}

	return true;
}


function validNetmask(value) {
	var masks = [
		'0.0.0.0',
		'128.0.0.0',
		'192.0.0.0',
		'224.0.0.0',
		'240.0.0.0',
		'248.0.0.0',
		'252.0.0.0',
		'254.0.0.0',
		'255.0.0.0',

		'255.128.0.0',
		'255.192.0.0',
		'255.224.0.0',
		'255.240.0.0',
		'255.248.0.0',
		'255.252.0.0',
		'255.254.0.0',
		'255.255.0.0',

		'255.255.128.0',
		'255.255.192.0',
		'255.255.224.0',
		'255.255.240.0',
		'255.255.248.0',
		'255.255.252.0',
		'255.255.254.0',
		'255.255.255.0',

		'255.255.255.128',
		'255.255.255.192',
		'255.255.255.224',
		'255.255.255.240',
		'255.255.255.248',
		'255.255.255.252',
		'255.255.255.254',
		'255.255.255.255'
	];

	return masks.indexOf(
		String(value || '')
	) >= 0;
}


function sameValue(a, b) {
	if (
		Array.isArray(a) ||
		Array.isArray(b)
	) {
		var aa =
			Array.isArray(a)
				? a
				: (
					a == null ||
					a === ''
						? []
						: [ String(a) ]
				);

		var bb =
			Array.isArray(b)
				? b
				: (
					b == null ||
					b === ''
						? []
						: [ String(b) ]
				);

		return (
			aa.length === bb.length &&
			aa.every(function(v, i) {
				return String(v) ===
					String(bb[i]);
			})
		);
	}

	return String(
		a == null ? '' : a
	) === String(
		b == null ? '' : b
	);
}


function setUciValue(
	config,
	section,
	option,
	value
) {
	var current =
		uci.get(
			config,
			section,
			option
		);

	var empty =
		value == null ||
		value === '' ||
		(
			Array.isArray(value) &&
			value.length === 0
		);

	if (empty) {
		if (
			current != null &&
			current !== ''
		) {
			uci.unset(
				config,
				section,
				option
			);
		}

		return;
	}

	if (!sameValue(current, value)) {
		uci.set(
			config,
			section,
			option,
			value
		);
	}
}


function ensureSection(
	config,
	type,
	name
) {
	if (!uci.get(config, name))
		uci.add(
			config,
			type,
			name
		);

	return name;
}


function passwordField() {
	var input = E('input', {
		'class': 'cbi-input-password',
		'type': 'password',
		'autocomplete': 'new-password'
	});

	var toggle = E('button', {
		'class': 'btn',
		'type': 'button',

		'click': function() {
			input.type =
				input.type === 'password'
					? 'text'
					: 'password';

			toggle.textContent =
				input.type === 'password'
					? _('Show')
					: _('Hide');
		}
	}, _('Show'));

	return {
		input: input,

		node: E('span', {}, [ input, ' ', toggle ])
	};
}


function makeIpFields(
	status,
	prefix
) {
	status = status || {};
	prefix = prefix || '';

	var dns = (
		status[prefix + 'dns'] || ''
	).trim().split(/\s+/).filter(Boolean);

	var mode = E('select', {
		'class': 'cbi-input-select'
	}, [
		E('option', {
			'value': 'dhcp'
		}, _('Automatic (DHCP)')),

		E('option', {
			'value': 'static'
		}, _('Manual'))
	]);

	var ipaddr = E('input', {
		'class': 'cbi-input-text',
		'type': 'text',
		'placeholder': '192.168.1.50',
		'value':
			status[prefix + 'ipaddr'] || ''
	});

	var netmask = E('input', {
		'class': 'cbi-input-text',
		'type': 'text',
		'placeholder': '255.255.255.0',
		'value':
			status[prefix + 'netmask'] || ''
	});

	var gateway = E('input', {
		'class': 'cbi-input-text',
		'type': 'text',
		'placeholder': '192.168.1.1',
		'value':
			status[prefix + 'gateway'] || ''
	});

	var dns1 = E('input', {
		'class': 'cbi-input-text',
		'type': 'text',
		'placeholder': '192.168.1.1',
		'value': dns[0] || ''
	});

	var dns2 = E('input', {
		'class': 'cbi-input-text',
		'type': 'text',
		'placeholder': '1.1.1.1',
		'value': dns[1] || ''
	});

	var manual = E('div', {}, [
		cbiRow(
			_('IPv4 address'),
			ipaddr
		),

		cbiRow(
			_('IPv4 netmask'),
			netmask
		),

		cbiRow(
			_('IPv4 gateway'),
			gateway
		),

		cbiRow(
			_('Primary DNS'),
			dns1
		),

		cbiRow(
			_('Secondary DNS'),
			dns2
		)
	]);

	function sync() {
		manual.style.display =
			mode.value === 'static'
				? ''
				: 'none';
	}

	mode.value =
		status[prefix + 'ip_mode'] ===
			'static'
				? 'static'
				: 'dhcp';

	mode.addEventListener(
		'change',
		sync
	);

	sync();

	return {
		mode: mode,
		ipaddr: ipaddr,
		netmask: netmask,
		gateway: gateway,
		dns1: dns1,
		dns2: dns2,

		node: E('div', {}, [
			cbiRow(
				_('IP configuration'),
				mode
			),

			manual
		])
	};
}


function validateIpFields(
	fields,
	label
) {
	if (fields.mode.value !== 'static')
		return;

	var ipaddr =
		fields.ipaddr.value.trim();

	var netmask =
		fields.netmask.value.trim();

	var gateway =
		fields.gateway.value.trim();

	var dns1 =
		fields.dns1.value.trim();

	var dns2 =
		fields.dns2.value.trim();

	if (!validIPv4(ipaddr))
		throw new Error(
			_('Invalid %s IPv4 address.').format(
				label
			)
		);

	if (!validNetmask(netmask))
		throw new Error(
			_('Invalid %s IPv4 netmask.').format(
				label
			)
		);

	if (!validIPv4(gateway))
		throw new Error(
			_('Invalid %s IPv4 gateway.').format(
				label
			)
		);

	if (
		dns1 &&
		!validIPv4(dns1)
	)
		throw new Error(
			_('Invalid primary DNS server.')
		);

	if (
		dns2 &&
		!validIPv4(dns2)
	)
		throw new Error(
			_('Invalid secondary DNS server.')
		);
}


function stageIpFields(
	section,
	fields
) {
	var mode =
		fields.mode.value;

	setUciValue(
		'network',
		section,
		'proto',
		mode
	);

	if (mode === 'dhcp') {
		setUciValue(
			'network',
			section,
			'ipaddr',
			null
		);

		setUciValue(
			'network',
			section,
			'netmask',
			null
		);

		setUciValue(
			'network',
			section,
			'gateway',
			null
		);

		setUciValue(
			'network',
			section,
			'dns',
			null
		);

		return;
	}

	var dns = [];

	if (fields.dns1.value.trim())
		dns.push(
			fields.dns1.value.trim()
		);

	if (fields.dns2.value.trim())
		dns.push(
			fields.dns2.value.trim()
		);

	setUciValue(
		'network',
		section,
		'ipaddr',
		fields.ipaddr.value.trim()
	);

	setUciValue(
		'network',
		section,
		'netmask',
		fields.netmask.value.trim()
	);

	setUciValue(
		'network',
		section,
		'gateway',
		fields.gateway.value.trim()
	);

	setUciValue(
		'network',
		section,
		'dns',
		dns
	);
}


function scanHeader() {
	return E('tr', { 'class': 'tr table-titles' }, [
		E('th', { 'class': 'th' }, _('Network')),
		E('th', { 'class': 'th' }, _('Access points')),
		E('th', { 'class': 'th' }, _('Security')),
		E('th', { 'class': 'th right' }, _('Action'))
	]);
}


return view.extend({
	load: function() {
		return Promise.all([
			uci.load('network'),
			uci.load('wireless'),

			L.resolveDefault(
				fs.exec(
					NETWORK_CLIENT,
					[ 'status' ]
				),
				{ stdout: '' }
			),

			L.resolveDefault(
				fs.exec(
					WIFI_CLIENT,
					[ 'status' ]
				),
				{ stdout: '' }
			)
		]);
	},


	render: function(data) {
		var self = this;

		this.networkStatus =
			parseStatus(
				data[2].stdout
			);

		this.wifiStatus =
			parseStatus(
				data[3].stdout
			);

		this.pendingWifi = null;

		this.statusNode = E('div', { 'class': 'network-status-table' });

		this.refreshStatus();

		this.ethernetFields =
			makeIpFields(
				this.networkStatus,
				'ethernet_'
			);

		this.wifiIpFields =
			makeIpFields(
				this.wifiStatus,
				''
			);

		this.wifiCandidateNode = E('div', { 'class': 'cbi-value-description' }, '');

		var ethernetConfig =
			E('div', {
				'class': 'cbi-section'
			}, [
				E('h3', {},
					_('Ethernet configuration')
				),

				E('div', {
					'class':
						'cbi-section-descr'
				}, _(
					'Configure the Ethernet client address.'
				)),

				E('div', {
					'class':
						'cbi-section-node'
				}, [
					this.ethernetFields.node
				])
			]);

		this.scanResult = E('div', { 'class': 'cbi-section' }, [
			E('em', {}, _(
				'Press Scan to discover nearby Wi-Fi networks.'
			))
		]);

		var wifiConfig =
			E('div', {
				'class': 'cbi-section'
			}, [
				E('h3', {},
					_('Wi-Fi configuration')
				),

				E('div', {
					'class':
						'cbi-section-descr'
				}, _(
					'Configure the Wi-Fi client address and select the wireless network.'
				)),

				E('div', {
					'class':
						'cbi-section-node'
				}, [
					this.wifiIpFields.node,

					cbiRow(
						_('Network'),
						E('div', {}, [
							E('button', {
								'class':
									'btn cbi-button-action',

								'click':
									function() {
										self.scan();
									}
							}, _('Scan')),

							' ',

							E('button', {
								'class': 'btn',

								'click':
									function() {
										self.manualDialog();
									}
							}, _(
								'Hidden / manual network'
							))
						]),

						_(
							'Connect performs a temporary in-memory test before the configuration is saved.'
						)
					),

					this.wifiCandidateNode,

					this.scanResult
				])
			]);

		poll.add(function() {
			return Promise.all([
				fs.exec(
					NETWORK_CLIENT,
					[ 'status' ]
				),

				fs.exec(
					WIFI_CLIENT,
					[ 'status' ]
				)
			]).then(function(results) {
				self.networkStatus =
					parseStatus(
						results[0].stdout
					);

				self.wifiStatus =
					parseStatus(
						results[1].stdout
					);

				self.refreshStatus();
			});
		}, 3);

		return E('div', {
			'class': 'cbi-map'
		}, [
			E('h2', {},
				_('Network Client')
			),

			E('div', {
				'class': 'cbi-map-descr'
			}, _(
				'View and configure how AudioWRT connects to the network.'
			)),

			this.statusNode,

			ethernetConfig,
			wifiConfig
		]);
	},


	refreshStatus: function() {
		dom.content(
			this.statusNode,
			E([], [
				ethernetStatus(
					this.networkStatus || {}
				),

				wifiStatus(
					this.wifiStatus || {},
					(
						this.networkStatus || {}
					).active_route
				)
			])
		);
	},


	stageEthernet: function() {
		validateIpFields(
			this.ethernetFields,
			_('Ethernet')
		);

		stageIpFields(
			'lan',
			this.ethernetFields
		);
	},


	stageWifiIp: function() {
		ensureSection(
			'network',
			'interface',
			'audiowrt_wifi'
		);

		validateIpFields(
			this.wifiIpFields,
			_('Wi-Fi')
		);

		stageIpFields(
			'audiowrt_wifi',
			this.wifiIpFields
		);
	},


	stageWifiNetwork: function() {
		var c =
			this.pendingWifi;

		if (!c)
			return;

		ensureSection(
			'wireless',
			'wifi-iface',
			'audiowrt_client'
		);

		setUciValue(
			'wireless',
			c.radio,
			'disabled',
			'0'
		);

		setUciValue(
			'wireless',
			'audiowrt_client',
			'device',
			c.radio
		);

		setUciValue(
			'wireless',
			'audiowrt_client',
			'mode',
			'sta'
		);

		setUciValue(
			'wireless',
			'audiowrt_client',
			'network',
			'audiowrt_wifi'
		);

		setUciValue(
			'wireless',
			'audiowrt_client',
			'ssid',
			c.ssid
		);

		setUciValue(
			'wireless',
			'audiowrt_client',
			'encryption',
			c.encryption
		);

		setUciValue(
			'wireless',
			'audiowrt_client',
			'disabled',
			'0'
		);

		setUciValue(
			'wireless',
			'audiowrt_client',
			'bssid',
			c.bssid || null
		);

		setUciValue(
			'wireless',
			'audiowrt_client',
			'key',
			c.encryption === 'none'
				? null
				: c.key
		);
	},


	handleSave: function() {
		var self = this;

		try {
			this.stageEthernet();
			this.stageWifiIp();
			this.stageWifiNetwork();
		}
		catch (e) {
			ui.addNotification(
				null,
				E('p', {},
					e.message || String(e)
				),
				'error'
			);

			return Promise.reject(e);
		}

		return uci.save()
			.then(
				L.bind(
					ui.changes.init,
					ui.changes
				)
			)
			.then(
				L.bind(
					ui.changes.displayChanges,
					ui.changes
				)
			)
			.then(function() {
				if (self.pendingWifi) {
					dom.content(
						self.wifiCandidateNode,
						E('div', {
							'class':
								'alert-message notice'
						}, _(
							'Tested Wi-Fi configuration saved as pending changes.'
						))
					);
				}
			});
	},


	handleSaveApply: function(
		ev,
		mode
	) {
		return this.handleSave(ev)
			.then(function() {
				return ui.changes.apply(
					mode == '0'
				);
			});
	},


	handleReset: function() {
		var self = this;

		return Promise.resolve(
			ui.changes.revert()
		).then(function() {
			if (
				self.pendingWifi ||
				self.wifiStatus.pending === '1'
			) {
				return L.resolveDefault(
					fs.exec(
						WIFI_CLIENT,
						[ 'rollback-client' ]
					),
					null
				);
			}
		}).then(function() {
			window.location.reload();
		});
	},


	buildWifiTestCandidate: function(
		network,
		encryption,
		key,
		bssid
	) {
		validateIpFields(
			this.wifiIpFields,
			_('Wi-Fi')
		);

		return {
			radio:
				network.radio,

			ssid:
				network.ssid,

			encryption:
				encryption,

			key:
				key,

			bssid:
				bssid || '',

			ipMode:
				this.wifiIpFields
					.mode
					.value,

			ipaddr:
				this.wifiIpFields
					.ipaddr
					.value
					.trim(),

			netmask:
				this.wifiIpFields
					.netmask
					.value
					.trim(),

			gateway:
				this.wifiIpFields
					.gateway
					.value
					.trim(),

			dns1:
				this.wifiIpFields
					.dns1
					.value
					.trim(),

			dns2:
				this.wifiIpFields
					.dns2
					.value
					.trim()
		};
	},


	testWifiCandidate: function(
		candidate
	) {
		var self = this;

		var args = [
			'connect',
			candidate.radio,
			candidate.ssid,
			candidate.encryption,
			candidate.key,
			candidate.bssid,
			candidate.ipMode,
			candidate.ipaddr,
			candidate.netmask,
			candidate.gateway,
			candidate.dns1,
			candidate.dns2
		];

		return fs.exec(
			WIFI_CLIENT,
			args
		).then(function(res) {
			if (res.code) {
				throw new Error(
					res.stderr ||
					_(
						'Could not connect to Wi-Fi.'
					)
				);
			}

			self.pendingWifi =
				candidate;

			dom.content(
				self.wifiCandidateNode,
				E('div', {
					'class':
						'alert-message notice'
				}, _(
					'Wi-Fi connection test started. When it succeeds, use Save or Save & Apply to keep it.'
				))
			);

			ui.addNotification(
				null,
				E('p', {}, _(
					'Wi-Fi client configuration applied temporarily for testing.'
				))
			);
		});
	},


	scan: function() {
		var self = this;

		dom.content(this.scanResult,
			E('p', { 'class': 'spinning' }, _('Scanning all radios…')));

		fs.exec(WIFI_CLIENT, [ 'scan' ]).then(function(res) {
			if (res.code)
				throw new Error(res.stderr || _('Wi-Fi scan failed.'));

			var groups = groupedNetworks(parseScan(res.stdout));
			if (!groups.length) {
				dom.content(self.scanResult,
					E('p', {}, _('No Wi-Fi networks were found.')));
				return;
			}

			var rows = [ scanHeader() ];

			groups.forEach(function(groupData) {
				var bands = groupData.bands.map(bandLabel).join(' / ');
				var standards = groupData.generations.length
					? groupData.generations.map(wifiLabel).join(' / ')
					: _('Legacy Wi-Fi');

				var details = E('tr', {
					'class': 'tr',
					'style': 'display:none'
				}, [
					E('td', { 'class': 'td', 'colspan': '4' }, [
						E('table', { 'class': 'table cbi-section-table' }, [
							E('tr', { 'class': 'tr table-titles' }, [
								E('th', { 'class': 'th' }, _('BSSID')),
								E('th', { 'class': 'th' }, _('Mode')),
								E('th', { 'class': 'th' }, _('Signal')),
								E('th', { 'class': 'th right' }, _('Action'))
							])
						].concat(groupData.aps.map(function(ap) {
							return E('tr', { 'class': 'tr' }, [
								E('td', { 'class': 'td' }, ap.bssid || '-'),
								E('td', { 'class': 'td' },
									'%s · %s · %s'.format(
										wifiLabel(ap.generation),
										bandLabel(ap.band),
										_('Channel %s').format(ap.channel || '-'))),
								E('td', { 'class': 'td' }, '%s dBm'.format(ap.signal)),
								E('td', { 'class': 'td right' },
									E('button', {
										'class': 'btn',
										'click': function() { self.connectDialog(ap, true); }
									}, _('Select')))
							]);
						}))
					])
				]);

				rows.push(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td' }, [
						E('strong', {}, groupData.ssid),
						E('div', { 'class': 'cbi-value-description' },
							'%s · %s · %s'.format(
								standards,
								bands,
								_('Best: %s dBm').format(groupData.best.signal)))
					]),
					E('td', { 'class': 'td' }, _('%d').format(groupData.aps.length)),
					E('td', { 'class': 'td' }, securityLabel(groupData.best.encryption)),
					E('td', { 'class': 'td right' }, [
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
						}, _('Details'))
					])
				]));
				rows.push(details);
			});

			dom.content(self.scanResult,
				E('div', { 'class': 'cbi-section cbi-tblsection' }, [
					E('table', { 'class': 'table cbi-section-table' }, rows)
				]));
		}).catch(function(err) {
			dom.content(self.scanResult,
				E('p', { 'class': 'alert-message error' }, err.message || String(err)));
		});
	},

	connectDialog: function(
		network,
		pinBssid
	) {
		var self = this;

		var encryption =
			encryptionMode(
				network.encryption
			);

		var password =
			passwordField();

		var info =
			wifiLabel(
				network.generation
			) +
			' · ' +
			bandLabel(
				network.band
			) +
			' · ' +
			_('Channel %s').format(
				network.channel || '-'
			);

		if (
			pinBssid &&
			network.bssid
		) {
			info +=
				' · ' +
				network.bssid;
		}

		ui.showModal(
			_('Connect to %s').format(
				network.ssid
			),
			[
				E('p', {}, info),

				encryption === 'none'
					? E('p', {}, _(
						'This is an open network.'
					))
					: cbiRow(
						_('Wi-Fi password'),
						password.node
					),

				E('div', {
					'class': 'right'
				}, [
					E('button', {
						'class': 'btn',
						'click':
							ui.hideModal
					}, _('Cancel')),

					' ',

					E('button', {
						'class':
							'btn cbi-button-action',

						'click':
							function() {
								try {
									var candidate =
										self.buildWifiTestCandidate(
											network,
											encryption,
											encryption ===
												'none'
												? ''
												: password
													.input
													.value,
											pinBssid &&
											network.bssid
												? network.bssid
												: ''
										);

									self.testWifiCandidate(
										candidate
									).then(
										function() {
											ui.hideModal();
										}
									).catch(
										function(err) {
											ui.addNotification(
												null,
												E(
													'p',
													{},
													err.message ||
														String(err)
												),
												'error'
											);
										}
									);
								}
								catch (err) {
									ui.addNotification(
										null,
										E(
											'p',
											{},
											err.message ||
												String(err)
										),
										'error'
									);
								}
							}
					}, _('Connect'))
				])
			]
		);
	},


	manualDialog: function() {
		var self = this;

		fs.exec(
			WIFI_CLIENT,
			[ 'radios' ]
		).then(function(res) {
			if (res.code) {
				throw new Error(
					res.stderr ||
					_(
						'Could not enumerate Wi-Fi radios.'
					)
				);
			}

			var radios =
				(res.stdout || '')
					.trim()
					.split(/\n/)
					.filter(Boolean)
					.map(function(line) {
						var f =
							line.split('|');

						return {
							name: f[0],
							band:
								f[1] || ''
						};
					});

			if (!radios.length) {
				throw new Error(
					_(
						'No Wi-Fi radios are available.'
					)
				);
			}

			var radio =
				E('select', {
					'class':
						'cbi-input-select'
				},
				radios.map(
					function(r) {
						return E(
							'option',
							{
								'value':
									r.name
							},
							bandLabel(
								r.band
							)
						);
					}
				));

			var ssid =
				E('input', {
					'class':
						'cbi-input-text',
					'type': 'text',
					'autocomplete':
						'off'
				});

			var encryption =
				E('select', {
					'class':
						'cbi-input-select'
				}, [
					E('option', {
						'value':
							'sae-mixed'
					}, _(
						'WPA2/WPA3 Personal'
					)),

					E('option', {
						'value':
							'psk2'
					}, _(
						'WPA2 Personal'
					)),

					E('option', {
						'value':
							'sae'
					}, _(
						'WPA3 Personal'
					)),

					E('option', {
						'value':
							'none'
					}, _(
						'Open network'
					))
				]);

			var password =
				passwordField();

			var passwordRow =
				cbiRow(
					_('Wi-Fi password'),
					password.node
				);

			function syncPassword() {
				passwordRow.style.display =
					encryption.value ===
						'none'
						? 'none'
						: '';
			}

			encryption.addEventListener(
				'change',
				syncPassword
			);

			syncPassword();

			ui.showModal(
				_(
					'Hidden / manual network'
				),
				[
					cbiRow(
						_('Band'),
						radio
					),

					cbiRow(
						_(
							'Network name (SSID)'
						),
						ssid
					),

					cbiRow(
						_('Security'),
						encryption
					),

					passwordRow,

					E('div', {
						'class': 'right'
					}, [
						E('button', {
							'class': 'btn',
							'click':
								ui.hideModal
						}, _('Cancel')),

						' ',

						E('button', {
							'class':
								'btn cbi-button-action',

							'click':
								function() {
									var network = {
										radio:
											radio.value,

										ssid:
											ssid.value,

										band: '',

										generation:
											null,

										channel: ''
									};

									try {
										var candidate =
											self.buildWifiTestCandidate(
												network,
												encryption.value,
												encryption.value ===
													'none'
													? ''
													: password
														.input
														.value,
												''
											);

										self.testWifiCandidate(
											candidate
										).then(
											function() {
												ui.hideModal();
											}
										).catch(
											function(err) {
												ui.addNotification(
													null,
													E(
														'p',
														{},
														err.message ||
															String(err)
													),
													'error'
												);
											}
										);
									}
									catch (err) {
										ui.addNotification(
											null,
											E(
												'p',
												{},
												err.message ||
													String(err)
											),
											'error'
										);
									}
								}
						}, _('Connect'))
					])
				]
			);
		}).catch(function(err) {
			ui.addNotification(
				null,
				E(
					'p',
					{},
					err.message ||
						String(err)
				),
				'error'
			);
		});
	}
});