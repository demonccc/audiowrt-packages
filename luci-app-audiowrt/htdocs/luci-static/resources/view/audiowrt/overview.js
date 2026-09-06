'use strict';

'require view';
'require uci';

return view.extend({
	load: function() {
		return Promise.all([ uci.load('audiowrt-audio'), uci.load('system') ]);
	},

	render: function() {
		var configuredName = uci.get('audiowrt-audio', 'main', 'device_name') || '';
		var hostname = uci.get('system', '@system[0]', 'hostname') || 'OpenWrt';
		var outputType = uci.get('audiowrt-audio', 'main', 'output_type') || 'auto';
		var ready = uci.get('audiowrt-audio', 'main', 'ready') === '1';
		var device = uci.get('audiowrt-audio', 'main', 'device') || '-';
		var btName = uci.get('audiowrt-audio', 'main', 'bluetooth_name') || '';
		var error = uci.get('audiowrt-audio', 'main', 'last_error') || '';

		var rows = [
			[ _('Audio name'), configuredName || hostname ],
			[ _('Output type'), outputType ],
			[ _('Output status'), ready ? _('Ready') : _('Not ready') ],
			[ _('ALSA device'), device ],
			[ _('Bluetooth device'), btName || '-' ]
		];

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('AudioWRT Audio')),
			E('p', {}, _('AudioWRT adds audio outputs and music services without changing this OpenWrt device\'s router or network configuration.')),
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'class': 'table' }, rows.map(function(row) {
					return E('div', { 'class': 'tr' }, [
						E('div', { 'class': 'td left', 'width': '35%' }, row[0]),
						E('div', { 'class': 'td left' }, row[1])
					]);
				})),
				error ? E('p', { 'class': 'alert-message warning' }, error) : ''
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
