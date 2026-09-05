'use strict';

'require view';
'require uci';

return view.extend({
	load: function() {
		return uci.load('audiowrt');
	},

	render: function() {
		const deviceName = uci.get('audiowrt', 'main', 'device_name') || 'AudioWRT';
		const provisioning = uci.get('audiowrt', 'main', 'provisioning') === '1';

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('AudioWRT')),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Device')),
				E('p', {}, [ _('Name: '), E('strong', {}, deviceName) ]),
				E('p', {}, [ _('Provisioning: '), E('strong', {}, provisioning ? _('Enabled') : _('Disabled')) ])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Audio services')),
				E('p', {}, _('Audio service controls will appear here as AudioWRT packages are enabled.'))
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
