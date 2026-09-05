'use strict';

'require view';
'require fs';
'require ui';

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(fs.exec('/usr/sbin/audiowrt-extensions', [ 'list' ]), { stdout: '' }),
			L.resolveDefault(fs.exec('/usr/sbin/audiowrt-storage', [ 'status' ]), { stdout: '' })
		]);
	},

	render: function(data) {
		var self = this;
		var external = /(^|\n)active=1(\n|$)/.test(data[1].stdout || '');
		var extensions = (data[0].stdout || '').trim().split(/\n/).filter(Boolean).map(function(line) {
			var f = line.split('|');
			return { id: f[0], package: f[1], state: f[2], title: f[3], description: f.slice(4).join('|') };
		});

		var cards = extensions.map(function(ext) {
			var installed = ext.state === 'installed';
			return E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, ext.title),
				E('p', {}, ext.description),
				E('p', {}, [ E('strong', {}, _('Status: ')), installed ? _('Installed') : _('Available') ]),
				E('button', {
					'class': installed ? 'btn cbi-button-negative' : 'btn cbi-button-action',
					'click': function() { self.changeExtension(ext.id, installed ? 'remove' : 'install'); }
				}, installed ? _('Remove') : _('Install'))
			]);
		});

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('AudioWRT Extensions')),
			E('p', {}, external
				? _('Extensions are currently installed on AudioWRT external USB storage.')
				: _('Extensions are currently installed on internal flash. If space is insufficient, enable USB extension storage first.')),
			E('p', {}, _('AudioWRT installs the underlying packages from the OpenWrt repositories and then applies AudioWRT-specific audio configuration.')),
			E('div', {}, cards)
		]);
	},

	changeExtension: function(id, action) {
		var label = action === 'install' ? _('Installing extension') : _('Removing extension');
		ui.showModal(label, [ E('p', { 'class': 'spinning' }, _('Please wait...')) ]);
		fs.exec('/usr/sbin/audiowrt-extensions', [ action, id ]).then(function(res) {
			ui.hideModal();
			if (res.code)
				throw new Error(res.stderr || _('Extension operation failed.'));
			window.location.reload();
		}).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, err.message || String(err)), 'error');
		});
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
