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
		const audioReady = uci.get('audiowrt', 'main', 'audio_ready') === '1';
		const audioDevice = uci.get('audiowrt', 'main', 'audio_device') || '-';
		const audioCard = uci.get('audiowrt', 'main', 'audio_card') || '-';
		const wifiSsid = uci.get('audiowrt', 'main', 'wifi_ssid') || '-';
		const lastError = uci.get('audiowrt', 'main', 'last_error') || '';

		const rows = [
			[ _('Device name'), deviceName ],
			[ _('Wi-Fi'), provisioning ? _('Setup required') : wifiSsid ],
			[ _('USB audio'), audioReady ? _('Ready') : _('Not detected') ],
			[ _('ALSA device'), audioDevice ],
			[ _('ALSA card'), audioCard ]
		];

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('AudioWRT')),
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'class': 'table' }, rows.map(function(row) {
					return E('div', { 'class': 'tr' }, [
						E('div', { 'class': 'td left', 'width': '35%' }, row[0]),
						E('div', { 'class': 'td left' }, row[1])
					]);
				})),
				lastError ? E('p', { 'class': 'alert-message warning' }, lastError) : '',
				provisioning
					? E('p', {}, [
						_('Wi-Fi provisioning is active. Open '),
						E('a', { 'href': '/audiowrt.html' }, _('AudioWRT Setup')),
						_(' to configure the network.')
					])
					: E('p', {}, _('To re-enter provisioning mode, hold the WPS button for at least five seconds.')),
				E('p', {}, audioReady
					? _('Audio services use the selected USB DAC through the AudioWRT ALSA default device.')
					: _('Connect a USB DAC or USB audio interface. AudioWRT will select it automatically.'))
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
