'use strict';

'require view';
'require fs';
'require ui';
'require poll';

function parseUsbCards(text) {
	var cards = [];

	(text || '').split(/\n/).forEach(function(line) {
		if (line.indexOf('USB-Audio') < 0)
			return;

		var m = line.match(/^\s*(\d+)\s+\[([^\]]+)\]:\s*(.+?)\s+-\s+(.+)$/);
		if (m) {
			cards.push({
				card: m[1],
				id: m[2].trim(),
				name: m[4].trim() || m[3].trim()
			});
		}
	});

	return cards;
}

function parseState(text) {
	var state = {};

	(text || '').split(/\n/).forEach(function(line) {
		var p = line.indexOf('=');
		if (p > 0)
			state[line.substring(0, p)] = line.substring(p + 1);
	});

	return state;
}

function parseBluetoothDevices(text) {
	return (text || '')
		.trim()
		.split(/\n/)
		.filter(Boolean)
		.map(function(line) {
			var f = line.split('|');

			return {
				mac: f[0],
				name: f[1] || f[0],
				paired: f[2] === '1',
				connected: f[3] === '1',
				selected: f[4] === '1',
				saved: f[5] === '1',
				preferred: f[6] === '1',
				present: f[7] === '1'
			};
		});
}

function parseBluetoothAdapters(text) {
	return (text || '')
		.trim()
		.split(/\n/)
		.filter(Boolean)
		.map(function(line) {
			var f = line.split('|');

			return {
				interface: f[0] || '',
				address: f[1] || '',
				alias: f[2] || '',
				name: f[3] || '',
				powered: f[4] === '1',
				discoverable: f[5] === '1',
				pairable: f[6] === '1',
				discovering: f[7] === '1'
			};
		})
		.sort(function(a, b) {
			var ai = /^hci(\d+)$/.exec(a.interface);
			var bi = /^hci(\d+)$/.exec(b.interface);

			if (ai && bi)
				return Number(ai[1]) - Number(bi[1]);

			return a.interface.localeCompare(b.interface);
		});
}

function iconDataUri(type) {
	var svg;

	if (type === 'bluetooth') {
		svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">' +
			'<path d="M30 6 L48 22 L36 32 L48 42 L30 58 L30 38 L18 50 L14 46 L28 32 L14 18 L18 14 L30 26 Z" ' +
			'fill="none" stroke="#1769aa" stroke-width="6" stroke-linejoin="round" stroke-linecap="round"/></svg>';
	} else {
		svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">' +
			'<path d="M8 26h13l12-10v32L21 38H8z" fill="#1769aa"/>' +
			'<path d="M40 24c5 4 5 12 0 16M47 17c10 8 10 22 0 30" fill="none" stroke="#1769aa" stroke-width="5" stroke-linecap="round"/></svg>';
	}

	return 'data:image/svg+xml;charset=UTF-8,' + encodeURIComponent(svg);
}

function outputIcon(type) {
	return E('span', {
		'class': 'center',
		'style': 'display:block;text-align:center'
	}, [
		E('img', {
			'src': iconDataUri(type),
			'alt': '',
			'width': type === 'bluetooth' ? '32' : '40',
			'height': type === 'bluetooth' ? '32' : '40'
		})
	]);
}

function outputIfaceBox(title, active, iconType, items) {
	return E('div', { 'class': 'ifacebox' }, [
		E('div', {
			'class': 'ifacebox-head center' + (active ? ' active' : '')
		}, E('strong', {}, title)),
		E('div', { 'class': 'ifacebox-body left' }, [
			outputIcon(iconType),
			L.itemlist(E('span'), items)
		])
	]);
}

function bluetoothTableHeader() {
	return E('tr', { 'class': 'tr table-titles' }, [
		E('th', { 'class': 'th' }, _('Name')),
		E('th', { 'class': 'th' }, _('Address')),
		E('th', { 'class': 'th' }, _('Status')),
		E('th', { 'class': 'th right' }, _('Actions'))
	]);
}

function actionButton(label, handler) {
	return E('button', {
		'class': 'btn cbi-button-action',
		'click': handler
	}, label);
}

function yesNo(value) {
	return value ? _('Yes') : _('No');
}

function usbTabLabel(card, index, total) {
	if (total === 1)
		return card.name || _('USB Audio');

	var name = card.name || '';
	if (name.length > 26)
		name = name.substring(0, 23) + '...';

	return name || _('USB Audio %d').format(index + 1);
}

function adapterDisplayName(adapter) {
	return adapter.alias || adapter.name || adapter.interface || _('Bluetooth');
}

function bluetoothTabLabel(adapter, adapters) {
	var label = adapterDisplayName(adapter);
	var duplicates = adapters.filter(function(item) {
		return adapterDisplayName(item) === label;
	}).length;

	return duplicates > 1
		? '%s · %s'.format(label, adapter.interface)
		: label;
}

return view.extend({
	scanning: false,
	btPackageAvailable: false,
	btAdapters: [],
	btKernelDetected: false,
	activeTab: null,

	load: function() {
		return Promise.all([
			L.resolveDefault(fs.stat('/usr/sbin/audiowrt-bluetooth'), null),
			L.resolveDefault(fs.exec('/usr/sbin/audiowrt-bluetooth', [ 'kernel-adapters' ]), { stdout: '' }),
			L.resolveDefault(fs.exec('/usr/sbin/audiowrt-bluetooth', [ 'adapters' ]), { stdout: '' }),
			L.resolveDefault(fs.exec('/usr/sbin/audiowrt-bluetooth', [ 'devices' ]), { stdout: '' }),
			L.resolveDefault(fs.read('/proc/asound/cards'), ''),
			L.resolveDefault(fs.exec('/usr/sbin/audiowrt-audio', [ 'status' ]), { stdout: '' })
		]);
	},

	deviceStatus: function(dev) {
		var status;

		if (dev.saved && !dev.present)
			status = _('Saved · Waiting');
		else if (dev.connected && dev.selected)
			status = _('Connected · In use');
		else if (dev.connected)
			status = _('Connected');
		else if (dev.paired)
			status = _('Paired');
		else
			status = _('Discovered');

		if (dev.saved && dev.present)
			status += ' · ' + _('✓ Saved');

		return status;
	},

	runBluetoothAction: function(action, dev, message) {
		var self = this;

		ui.showModal(_('Bluetooth audio'), [
			E('p', { 'class': 'spinning' }, message)
		]);

		return fs.exec('/usr/sbin/audiowrt-bluetooth', [ action, dev.mac ]).then(function(res) {
			ui.hideModal();

			if (res.code)
				throw new Error(res.stderr || _('Bluetooth operation failed.'));

			return self.refreshBluetooth();
		}).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, err.message || String(err)), 'error');
		});
	},

	renderMyDeviceRow: function(dev) {
		var self = this;
		var buttons = [];

		if (dev.connected && !dev.selected) {
			buttons.push(actionButton(_('Use'), function() {
				self.runBluetoothAction('use', dev, _('Switching audio output to ') + dev.name + '...');
			}));
		}

		if (!dev.connected && dev.present && (dev.paired || dev.saved)) {
			buttons.push(actionButton(_('Connect'), function() {
				self.runBluetoothAction('connect', dev, _('Connecting to ') + dev.name + '...');
			}));
		}

		if (dev.connected) {
			buttons.push(actionButton(_('Disconnect'), function() {
				self.runBluetoothAction('disconnect', dev, _('Disconnecting ') + dev.name + '...');
			}));
		}

		if (!dev.saved && (dev.paired || dev.connected)) {
			buttons.push(actionButton(_('Save'), function() {
				self.runBluetoothAction('save', dev, _('Saving ') + dev.name + _(' for future reboots...'));
			}));
		}

		return E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td' }, dev.name),
			E('td', { 'class': 'td' }, dev.mac),
			E('td', { 'class': 'td' }, this.deviceStatus(dev)),
			E('td', { 'class': 'td right' }, buttons.length ? buttons : '-')
		]);
	},

	renderNearbyRow: function(dev) {
		var self = this;

		return E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td' }, dev.name),
			E('td', { 'class': 'td' }, dev.mac),
			E('td', { 'class': 'td' }, _('Discovered')),
			E('td', { 'class': 'td right' }, actionButton(_('Pair'), function() {
				self.runBluetoothAction('pair', dev, _('Pairing with ') + dev.name + '...');
			}))
		]);
	},

	renderAdapterInfo: function(adapter) {
		return outputIfaceBox(
			adapterDisplayName(adapter),
			adapter.powered,
			'bluetooth',
			[
				_('Type'), _('Bluetooth adapter'),
				_('Address'), adapter.address,
				_('Interface'), adapter.interface,
				_('Powered'), yesNo(adapter.powered),
				_('Pairable'), yesNo(adapter.pairable),
				_('Discoverable'), yesNo(adapter.discoverable),
				_('Discovering'), yesNo(adapter.discovering)
			]
		);
	},

	renderBluetoothDevices: function(adapter, devices) {
		var self = this;
		var mine = devices.filter(function(dev) {
			return dev.paired || dev.connected || dev.saved;
		});
		var nearby = devices.filter(function(dev) {
			return !dev.paired && !dev.connected && !dev.saved;
		});

		var scanButton = E('button', {
			'class': 'btn cbi-button-action',
			'disabled': this.scanning ? 'disabled' : null,
			'click': function() {
				self.scanBluetooth(adapter);
			}
		}, this.scanning ? _('Scanning...') : _('Scan for devices'));

		var mineRows = [ bluetoothTableHeader() ];
		if (mine.length) {
			mine.forEach(function(dev) {
				mineRows.push(self.renderMyDeviceRow(dev));
			});
		} else {
			mineRows.push(E('tr', { 'class': 'tr placeholder' }, [
				E('td', { 'class': 'td', 'colspan': '4' },
					E('em', {}, _('No paired, connected or saved Bluetooth devices yet.')))
			]));
		}

		var nearbyRows = [ bluetoothTableHeader() ];
		if (nearby.length) {
			nearby.forEach(function(dev) {
				nearbyRows.push(self.renderNearbyRow(dev));
			});
		} else {
			nearbyRows.push(E('tr', { 'class': 'tr placeholder' }, [
				E('td', { 'class': 'td', 'colspan': '4' },
					E('em', {}, this.scanning
						? _('Waiting for nearby Bluetooth devices...')
						: _('No new Bluetooth devices discovered.')))
			]));
		}

		return E('div', {}, [
			this.renderAdapterInfo(adapter),

			E('div', { 'class': 'cbi-section cbi-tblsection' }, [
				E('h3', {}, _('My devices')),
				E('table', { 'class': 'table cbi-section-table' }, mineRows)
			]),

			E('div', { 'class': 'cbi-section cbi-tblsection' }, [
				E('h3', {}, _('Nearby devices')),
				E('p', {}, scanButton),
				E('table', { 'class': 'table cbi-section-table' }, nearbyRows)
			])
		]);
	},

	renderBluetoothEmpty: function() {
		if (!this.btPackageAvailable) {
			return E('p', {}, _(
				'Bluetooth audio support is not included in this firmware build.'
			));
		}

		if (this.btKernelDetected) {
			return E('p', {}, _(
				'Bluetooth adapter detected, but it could not be initialized. Check system logs for details.'
			));
		}

		return E('p', {}, _('No Bluetooth adapter detected.'));
	},

	renderUsbContent: function(card, audioState) {
		var selected =
			audioState.output_type === 'usb' &&
			audioState.ready === '1' &&
			String(audioState.card || '') === String(card.card);

		return outputIfaceBox(
			card.name || _('USB Audio'),
			true,
			'speaker',
			[
				_('Type'), _('USB audio device'),
				_('Device'), card.name || _('USB Audio'),
				_('ALSA card'), String(card.card),
				_('Interface'), _('USB'),
				_('Status'), selected ? _('Selected and ready') : _('Ready')
			]
		);
	},

	renderUsbEmpty: function() {
		return E('p', {}, _('No USB audio device detected.'));
	},

	setTab: function(tabId) {
		this.activeTab = tabId;

		document.querySelectorAll('#audiowrt-output-tabs > li').forEach(function(tab) {
			tab.className = tab.getAttribute('data-tab') === tabId
				? 'cbi-tab'
				: 'cbi-tab-disabled';
		});

		document.querySelectorAll('.audiowrt-output-pane').forEach(function(pane) {
			pane.style.display = pane.getAttribute('data-tab') === tabId ? '' : 'none';
		});
	},

	tabNode: function(id, label, active) {
		var self = this;

		return E('li', {
			'class': active ? 'cbi-tab' : 'cbi-tab-disabled',
			'data-tab': id
		}, [
			E('a', {
				'href': '#',
				'click': function(ev) {
					ev.preventDefault();
					self.setTab(id);
				}
			}, label)
		]);
	},

	paneNode: function(id, content, active) {
		return E('div', {
			'class': 'audiowrt-output-pane',
			'data-tab': id,
			'style': active ? '' : 'display:none'
		}, [ content ]);
	},

	refreshBluetooth: function() {
		var self = this;

		if (!this.btPackageAvailable)
			return Promise.resolve();

		return Promise.all([
			L.resolveDefault(
				fs.exec('/usr/sbin/audiowrt-bluetooth', [ 'adapters' ]),
				{ stdout: '' }
			),
			L.resolveDefault(
				fs.exec('/usr/sbin/audiowrt-bluetooth', [ 'devices' ]),
				{ stdout: '' }
			)
		]).then(function(data) {
			self.btAdapters = parseBluetoothAdapters(data[0].stdout || '');
			var devices = parseBluetoothDevices(data[1].stdout || '');

			self.btAdapters.forEach(function(adapter) {
				var node = document.getElementById(
					'audiowrt-bt-' + adapter.interface
				);

				if (node) {
					node.replaceChildren(
						self.renderBluetoothDevices(adapter, devices)
					);
				}
			});
		});
	},

	scanBluetooth: function(adapter) {
		var self = this;

		if (this.scanning)
			return;

		this.scanning = true;
		this.refreshBluetooth();

		/*
		 * Adapter enumeration is now explicit. Device discovery/actions still use
		 * the existing backend behavior, which selects the first BlueZ adapter.
		 * The adapter object is kept here for the future adapter-aware commands.
		 */
		fs.exec('/usr/sbin/audiowrt-bluetooth', [ 'scan', '8' ]).then(function(res) {
			if (res.code)
				throw new Error(res.stderr || _('Bluetooth scan failed.'));
		}).catch(function(err) {
			ui.addNotification(null, E('p', {}, err.message || String(err)), 'error');
		}).finally(function() {
			self.scanning = false;
			self.refreshBluetooth();
		});
	},

	render: function(data) {
		var self = this;

		this.btPackageAvailable = !!data[0];
		this.btKernelDetected = this.btPackageAvailable && !!(data[1].stdout || '').trim();
		this.btAdapters = this.btPackageAvailable
			? parseBluetoothAdapters(data[2].stdout || '')
			: [];

		var devices = this.btPackageAvailable
			? parseBluetoothDevices(data[3].stdout || '')
			: [];

		var usbCards = parseUsbCards(data[4]);
		var audioState = parseState(data[5].stdout || '');

		var tabs = [];
		var panes = [];
		var firstTab = null;

		function addTab(id, label, content) {
			var active = firstTab === null;

			if (active)
				firstTab = id;

			tabs.push(self.tabNode(id, label, active));
			panes.push(self.paneNode(id, content, active));
		}

		if (!usbCards.length) {
			addTab(
				'usb-empty',
				_('USB Audio'),
				this.renderUsbEmpty()
			);
		} else {
			usbCards.forEach(function(card, index) {
				addTab(
					'usb-' + card.card,
					usbTabLabel(card, index, usbCards.length),
					self.renderUsbContent(card, audioState)
				);
			});
		}

		if (!this.btAdapters.length) {
			addTab(
				'bluetooth-empty',
				_('Bluetooth'),
				this.renderBluetoothEmpty()
			);
		} else {
			this.btAdapters.forEach(function(adapter) {
				addTab(
					'bluetooth-' + adapter.interface,
					bluetoothTabLabel(adapter, self.btAdapters),
					E('div', {
						'id': 'audiowrt-bt-' + adapter.interface
					}, [
						self.renderBluetoothDevices(adapter, devices)
					])
				);
			});
		}

		this.activeTab = firstTab;

		poll.add(function() {
			return self.refreshBluetooth();
		}, 2);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Audio Output')),
			E('ul', {
				'id': 'audiowrt-output-tabs',
				'class': 'cbi-tabmenu'
			}, tabs),
			E('div', {}, panes)
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
