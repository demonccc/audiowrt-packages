'use strict';

'require view';
'require fs';
'require ui';

function parseStatus(text) {
	var result = {};
	(text || '').trim().split(/\n/).forEach(function(line) {
		var pos = line.indexOf('=');
		if (pos > 0)
			result[line.substring(0, pos)] = line.substring(pos + 1);
	});
	return result;
}

function formatKiB(value) {
	var kib = parseInt(value || '0', 10);
	if (!kib)
		return '-';
	if (kib >= 1048576)
		return (kib / 1048576).toFixed(1) + ' GiB';
	return (kib / 1024).toFixed(1) + ' MiB';
}

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(fs.exec('/usr/sbin/audiowrt-storage', [ 'status' ]), { stdout: '' }),
			L.resolveDefault(fs.exec('/usr/sbin/audiowrt-storage', [ 'devices' ]), { stdout: '' })
		]);
	},

	render: function(data) {
		var status = parseStatus(data[0].stdout);
		var devices = (data[1].stdout || '').trim().split(/\n/).filter(Boolean).map(function(line) {
			var fields = line.split('|');
			return { device: fields[0], fstype: fields[1] || '-', label: fields[2] || '-', mounted: fields[4] === '1' };
		});
		var self = this;

		var deviceRows = devices.length ? devices.map(function(item) {
			var button = E('button', {
				'class': 'btn cbi-button-action',
				'disabled': item.mounted ? 'disabled' : null,
				'click': function() { self.enableStorage(item.device); }
			}, _('Use for extensions'));
			return E('div', { 'class': 'tr' }, [
				E('div', { 'class': 'td left' }, item.device),
				E('div', { 'class': 'td left' }, item.fstype),
				E('div', { 'class': 'td left' }, item.label),
				E('div', { 'class': 'td left' }, item.mounted ? _('Mounted') : button)
			]);
		}) : [ E('p', {}, _('No unused USB storage partitions were detected.')) ];

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('AudioWRT Storage')),
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, _('The internal flash always contains the AudioWRT core. Optional external storage expands the writable overlay so larger extensions can be installed without changing the firmware image.')),
				E('div', { 'class': 'table' }, [
					E('div', { 'class': 'tr' }, [ E('div', { 'class': 'td left', 'width': '35%' }, _('Active package storage')), E('div', { 'class': 'td left' }, status.active === '1' ? _('External USB storage') : _('Internal flash')) ]),
					E('div', { 'class': 'tr' }, [ E('div', { 'class': 'td left' }, _('Root free space')), E('div', { 'class': 'td left' }, formatKiB(status.root_free_kb)) ]),
					E('div', { 'class': 'tr' }, [ E('div', { 'class': 'td left' }, _('Configured device')), E('div', { 'class': 'td left' }, status.device || '-') ])
				]),
				status.active === '1' ? E('button', { 'class': 'btn cbi-button-negative', 'click': function() { self.disableStorage(); } }, _('Return to internal storage')) : ''
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Available partitions')),
				E('p', { 'class': 'alert-message warning' }, _('Enabling extension storage formats the selected partition as ext4 and permanently deletes all data on it.')),
				E('div', { 'class': 'table' }, deviceRows)
			])
		]);
	},

	enableStorage: function(device) {
		if (!window.confirm(_('All data on %s will be erased. Continue?').format(device)))
			return;
		ui.showModal(_('Preparing extension storage'), [ E('p', { 'class': 'spinning' }, _('Formatting and copying the current AudioWRT overlay...')) ]);
		fs.exec('/usr/sbin/audiowrt-storage', [ 'enable', device, '--yes' ]).then(function(res) {
			ui.hideModal();
			if (res.code)
				throw new Error(res.stderr || _('Storage preparation failed.'));
			ui.addNotification(null, E('p', {}, _('Storage is prepared. Reboot AudioWRT to activate it.')));
		}).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, err.message || String(err)), 'error');
		});
	},

	disableStorage: function() {
		if (!window.confirm(_('Return package storage to the internal flash after the next reboot?')))
			return;
		fs.exec('/usr/sbin/audiowrt-storage', [ 'disable', '--yes' ]).then(function(res) {
			if (res.code)
				throw new Error(res.stderr || _('Could not disable extension storage.'));
			ui.addNotification(null, E('p', {}, _('External storage is disabled. Reboot to use the internal core overlay.')));
		}).catch(function(err) {
			ui.addNotification(null, E('p', {}, err.message || String(err)), 'error');
		});
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
