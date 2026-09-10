'use strict';

'require view';
'require fs';
'require ui';

return view.extend({
	load: function() {
		return L.resolveDefault(fs.exec('/usr/sbin/audiowrt-extensions', [ 'list' ]), { stdout: '' });
	},

	render: function(data) {
		var self = this;
		var extensions = (data.stdout || '').trim().split(/\n/).filter(Boolean).map(function(line) {
			var f = line.split('|');
			return { id: f[0], package: f[1], state: f[2], title: f[3], description: f.slice(4).join('|') };
		});

		function statusLabel(state) {
			if (state === 'installed') return _('Installed');
			if (state === 'installable') return _('Available in configured repositories');
			return _('Not available in configured repositories');
		}

		var cards = extensions.map(function(ext) {
			var installed = ext.state === 'installed';
			var installable = ext.state === 'installable';
			var actions = [];
			if (installed) {
				actions.push(E('button', {
					'class': 'btn cbi-button-negative',
					'click': function() { self.changeExtension(ext.id, 'remove'); }
				}, _('Remove')));
			} else if (installable) {
				actions.push(E('button', {
					'class': 'btn cbi-button-action',
					'click': function() { self.changeExtension(ext.id, 'install'); }
				}, _('Install')));
			}
			return E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, ext.title),
				E('p', {}, ext.description),
				E('p', {}, [ E('strong', {}, _('Status: ')), statusLabel(ext.state) ]),
				actions.length ? E('div', {}, actions) : E('p', { 'class': 'text-muted' }, _('Configure an AudioWRT package repository to install this service later.'))
			]);
		});

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('AudioWRT Extensions')),
			E('p', {}, _('Extensions are optional audio services. Availability is based on the package repositories currently configured on this device.')),
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
