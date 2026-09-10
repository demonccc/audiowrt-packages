'use strict';

'require view';
'require fs';
'require ui';
'require uci';

function parseUsbCards(text) {
	var cards = [];
	(text || '').split(/\n/).forEach(function(line) {
		if (line.indexOf('USB-Audio') < 0) return;
		var m = line.match(/^\s*(\d+)\s+\[([^\]]+)\]:\s*(.+?)\s+-\s+(.+)$/);
		if (m) cards.push({ card: m[1], id: m[2].trim(), name: m[4].trim() || m[3].trim() });
	});
	return cards;
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('audiowrt-audio'),
			L.resolveDefault(fs.stat('/usr/sbin/audiowrt-bluetooth'), null),
			L.resolveDefault(fs.exec('/usr/sbin/audiowrt-bluetooth', [ 'devices' ]), { stdout: '' }),
			L.resolveDefault(fs.read('/proc/asound/cards'), '')
		]);
	},

	render: function(data) {
		var self = this;
		var btSupported = !!data[1];
		var outputType = uci.get('audiowrt-audio', 'main', 'output_type') || 'auto';
		var selected = uci.get('audiowrt-audio', 'main', 'bluetooth_device') || '';
		var usbCards = parseUsbCards(data[3]);
		var devices = btSupported ? (data[2].stdout || '').trim().split(/\n/).filter(Boolean).map(function(line) {
			var f = line.split('|');
			return { mac: f[0], name: f[1] || f[0], paired: f[2] === '1', connected: f[3] === '1', selected: f[4] === '1' };
		}) : [];

		var usbNode;
		if (!usbCards.length) {
			usbNode = E('p', {}, _('No USB audio device connected.'));
		} else if (usbCards.length === 1) {
			usbNode = E('p', {}, [ E('strong', {}, '✓ ' + usbCards[0].name), ' ', E('span', {}, outputType === 'usb' ? _('— Selected and ready') : _('— Ready')) ]);
		} else {
			usbNode = E('div', {}, usbCards.map(function(card) {
				return E('p', {}, [ E('strong', {}, '✓ ' + card.name), ' ', E('span', {}, _('— USB Audio Class device')) ]);
			}));
		}

		var deviceRows = devices.length ? devices.map(function(dev) {
			return E('div', { 'class': 'tr' }, [
				E('div', { 'class': 'td left' }, dev.name),
				E('div', { 'class': 'td left' }, dev.mac),
				E('div', { 'class': 'td left' }, dev.connected ? _('Connected') : (dev.paired ? _('Paired') : _('Discovered'))),
				E('div', { 'class': 'td right' }, E('button', {
					'class': 'btn cbi-button-action',
					'click': function() { self.useBluetooth(dev); }
				}, dev.selected ? _('Reconnect') : (dev.paired ? _('Use') : _('Pair & use'))))
			]);
		}) : [];

		var bluetoothNode;
		if (!btSupported) {
			bluetoothNode = E('p', {}, _('Bluetooth audio support is not included in this firmware build.'));
		} else {
			bluetoothNode = E('div', {}, [
				E('button', { 'class': 'btn cbi-button-action', 'click': function() { self.scanBluetooth(); } }, _('Scan for devices')),
				deviceRows.length ? E('div', { 'class': 'table', 'style': 'margin-top:1rem' }, deviceRows) : E('p', {}, _('No Bluetooth audio devices are known yet.')),
				selected ? E('p', {}, [ E('strong', {}, _('Selected Bluetooth device: ')), selected ]) : ''
			]);
		}

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Audio Output')),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('USB Audio')),
				usbNode
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Bluetooth Audio')),
				bluetoothNode
			])
		]);
	},

	scanBluetooth: function() {
		var self = this;
		ui.showModal(_('Scanning for Bluetooth devices'), [ E('p', { 'class': 'spinning' }, _('Scanning for 8 seconds...')) ]);
		fs.exec('/usr/sbin/audiowrt-bluetooth', [ 'scan', '8' ]).then(function(res) {
			ui.hideModal();
			if (res.code) throw new Error(res.stderr || _('Bluetooth scan failed.'));
			window.location.reload();
		}).catch(function(err) { ui.hideModal(); ui.addNotification(null, E('p', {}, err.message || String(err)), 'error'); });
	},

	useBluetooth: function(dev) {
		var action = dev.paired ? 'select' : 'pair';
		ui.showModal(_('Configuring Bluetooth audio'), [ E('p', { 'class': 'spinning' }, _('Connecting to ') + dev.name + '...') ]);
		fs.exec('/usr/sbin/audiowrt-bluetooth', [ action, dev.mac ]).then(function(res) {
			ui.hideModal();
			if (res.code) throw new Error(res.stderr || _('Bluetooth connection failed.'));
			window.location.reload();
		}).catch(function(err) { ui.hideModal(); ui.addNotification(null, E('p', {}, err.message || String(err)), 'error'); });
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
