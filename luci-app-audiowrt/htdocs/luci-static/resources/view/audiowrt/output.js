'use strict';

'require view';
'require fs';
'require ui';
'require poll';

function parseUsbCards(text) {
	var cards = [];
	(text || '').split(/\n/).forEach(function(line) {
		if (line.indexOf('USB-Audio') < 0) return;
		var m = line.match(/^\s*(\d+)\s+\[([^\]]+)\]:\s*(.+?)\s+-\s+(.+)$/);
		if (m) cards.push({ card: m[1], id: m[2].trim(), name: m[4].trim() || m[3].trim() });
	});
	return cards;
}

function parseState(text) {
	var state = {};
	(text || '').split(/\n/).forEach(function(line) {
		var p = line.indexOf('=');
		if (p > 0) state[line.substring(0, p)] = line.substring(p + 1);
	});
	return state;
}

function parseBluetoothDevices(text) {
	return (text || '').trim().split(/\n/).filter(Boolean).map(function(line) {
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

function actionButton(label, handler) {
	return E('button', {
		'class': 'btn cbi-button-action',
		'style': 'margin-left:.4rem',
		'click': handler
	}, label);
}

return view.extend({
	scanning: false,
	btSupported: false,

	load: function() {
		return Promise.all([
			L.resolveDefault(fs.stat('/usr/sbin/audiowrt-bluetooth'), null),
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

		if (dev.connected && !dev.selected)
			buttons.push(actionButton(_('Use'), function() {
				self.runBluetoothAction('use', dev, _('Switching audio output to ') + dev.name + '...');
			}));

		if (!dev.connected && dev.present && (dev.paired || dev.saved))
			buttons.push(actionButton(_('Connect'), function() {
				self.runBluetoothAction('connect', dev, _('Connecting to ') + dev.name + '...');
			}));

		if (dev.connected)
			buttons.push(actionButton(_('Disconnect'), function() {
				self.runBluetoothAction('disconnect', dev, _('Disconnecting ') + dev.name + '...');
			}));

		if (!dev.saved && (dev.paired || dev.connected))
			buttons.push(actionButton(_('Save'), function() {
				self.runBluetoothAction('save', dev, _('Saving ') + dev.name + _(' for future reboots...'));
			}));

		return E('div', { 'class': 'tr' }, [
			E('div', { 'class': 'td left' }, dev.name),
			E('div', { 'class': 'td left' }, dev.mac),
			E('div', { 'class': 'td left' }, this.deviceStatus(dev)),
			E('div', { 'class': 'td right' }, buttons.length ? buttons : '-')
		]);
	},

	renderNearbyRow: function(dev) {
		var self = this;
		return E('div', { 'class': 'tr' }, [
			E('div', { 'class': 'td left' }, dev.name),
			E('div', { 'class': 'td left' }, dev.mac),
			E('div', { 'class': 'td left' }, _('Discovered')),
			E('div', { 'class': 'td right' }, actionButton(_('Pair'), function() {
				self.runBluetoothAction('pair', dev, _('Pairing with ') + dev.name + '...');
			}))
		]);
	},

	renderBluetooth: function(devices) {
		var self = this;
		var mine = devices.filter(function(dev) { return dev.paired || dev.connected || dev.saved; });
		var nearby = devices.filter(function(dev) { return !dev.paired && !dev.connected && !dev.saved; });

		var scanButton = E('button', {
			'id': 'audiowrt-bt-scan',
			'class': 'btn cbi-button-action',
			'disabled': this.scanning ? 'disabled' : null,
			'click': function() { self.scanBluetooth(); }
		}, this.scanning ? _('Scanning...') : _('Scan for devices'));

		return E('div', {}, [
			E('h4', {}, _('My devices')),
			mine.length
				? E('div', { 'class': 'table' }, mine.map(function(dev) { return self.renderMyDeviceRow(dev); }))
				: E('p', {}, _('No paired, connected or saved Bluetooth devices yet.')),
			E('h4', { 'style': 'margin-top:1.5rem' }, _('Nearby devices')),
			E('p', {}, scanButton),
			nearby.length
				? E('div', { 'class': 'table' }, nearby.map(function(dev) { return self.renderNearbyRow(dev); }))
				: E('p', {}, this.scanning ? _('Waiting for nearby Bluetooth devices...') : _('No new Bluetooth devices discovered.'))
		]);
	},

	refreshBluetooth: function() {
		var self = this;
		if (!this.btSupported)
			return Promise.resolve();

		return L.resolveDefault(
			fs.exec('/usr/sbin/audiowrt-bluetooth', [ 'devices' ]),
			{ stdout: '' }
		).then(function(res) {
			var node = document.getElementById('audiowrt-bt-content');
			if (node)
				node.replaceChildren(self.renderBluetooth(parseBluetoothDevices(res.stdout || '')));
		});
	},

	scanBluetooth: function() {
		var self = this;
		if (this.scanning)
			return;
		this.scanning = true;
		this.refreshBluetooth();

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
		this.btSupported = !!data[0];
		var devices = this.btSupported ? parseBluetoothDevices(data[1].stdout || '') : [];
		var usbCards = parseUsbCards(data[2]);
		var audioState = parseState(data[3].stdout || '');
		var usbNode;

		if (!usbCards.length) {
			usbNode = E('p', {}, _('No USB audio device connected.'));
		} else if (usbCards.length === 1) {
			usbNode = E('p', {}, [
				E('strong', {}, '✓ ' + usbCards[0].name),
				' ',
				E('span', {}, audioState.output_type === 'usb' && audioState.ready === '1'
					? _('— Selected and ready')
					: _('— Ready'))
			]);
		} else {
			usbNode = E('div', {}, usbCards.map(function(card) {
				return E('p', {}, [
					E('strong', {}, '✓ ' + card.name),
					' ',
					E('span', {}, _('— USB Audio Class device'))
				]);
			}));
		}

		poll.add(function() {
			return self.refreshBluetooth();
		}, 2);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Audio Output')),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('USB Audio')),
				usbNode
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Bluetooth Audio')),
				this.btSupported
					? E('div', { 'id': 'audiowrt-bt-content' }, [ this.renderBluetooth(devices) ])
					: E('p', {}, _('Bluetooth audio support is not included in this firmware build.'))
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
