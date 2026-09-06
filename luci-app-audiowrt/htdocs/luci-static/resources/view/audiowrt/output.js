'use strict';

'require view';
'require fs';
'require ui';
'require uci';

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('audiowrt-audio'),
			L.resolveDefault(fs.stat('/usr/sbin/audiowrt-bluetooth'), null),
			L.resolveDefault(fs.exec('/usr/sbin/audiowrt-bluetooth', [ 'devices' ]), { stdout: '' })
		]);
	},

	render: function(data) {
		var self = this;
		var btInstalled = !!data[1];
		var outputType = uci.get('audiowrt-audio', 'main', 'output_type') || 'auto';
		var selected = uci.get('audiowrt-audio', 'main', 'bluetooth_device') || '';
		var devices = btInstalled ? (data[2].stdout || '').trim().split(/\n/).filter(Boolean).map(function(line) {
			var f = line.split('|');
			return { mac: f[0], name: f[1] || f[0], paired: f[2] === '1', connected: f[3] === '1', selected: f[4] === '1' };
		}) : [];

		var deviceRows = devices.length ? devices.map(function(dev) {
			return E('div', { 'class': 'tr' }, [
				E('div', { 'class': 'td left' }, dev.name),
				E('div', { 'class': 'td left' }, dev.mac),
				E('div', { 'class': 'td left' }, dev.connected ? _('Connected') : (dev.paired ? _('Paired') : _('Discovered'))),
				E('div', { 'class': 'td left' }, E('button', {
					'class': 'btn cbi-button-action',
					'click': function() { self.useBluetooth(dev); }
				}, dev.selected ? _('Reconnect') : (dev.paired ? _('Use') : _('Pair & use'))))
			]);
		}) : [ E('p', {}, btInstalled ? _('No Bluetooth audio devices are known yet.') : _('Install the Bluetooth Audio extension to scan and pair speakers.')) ];

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Audio Output')),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('USB Audio')),
				E('p', {}, outputType === 'usb' ? _('USB is the selected output.') : _('Select the first detected USB Audio Class playback device.')),
				E('button', { 'class': 'btn cbi-button-action', 'click': function() { self.useUsb(); } }, _('Use USB audio'))
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Bluetooth Audio')),
				btInstalled ? E('button', { 'class': 'btn cbi-button-action', 'click': function() { self.scanBluetooth(); } }, _('Scan')) : '',
				E('div', { 'class': 'table' }, deviceRows),
				selected ? E('p', {}, _('Selected Bluetooth device: ') + selected) : ''
			])
		]);
	},

	useUsb: function() {
		fs.exec('/usr/sbin/audiowrt-audio', [ 'output', 'usb' ]).then(function(res) {
			if (res.code) throw new Error(res.stderr || _('Could not select USB audio.'));
			window.location.reload();
		}).catch(function(err) { ui.addNotification(null, E('p', {}, err.message || String(err)), 'error'); });
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
