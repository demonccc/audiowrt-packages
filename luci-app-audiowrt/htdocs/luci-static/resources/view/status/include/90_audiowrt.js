'use strict';
'require baseclass';
'require fs';

function parse(text) {
	var values = {};
	(text || '').split(/\n/).forEach(function(line) {
		var pos = line.indexOf('=');
		if (pos > 0)
			values[line.substring(0, pos)] = line.substring(pos + 1);
	});
	return values;
}

return baseclass.extend({
	title: _('AudioWRT'),

	load: function() {
		return L.resolveDefault(fs.exec('/usr/sbin/audiowrt-audio', [ 'status' ]), { stdout: '' });
	},

	render: function(result) {
		var status = parse(result.stdout),
		    fields = [
			_('Audio name'), status.device_name || '-',
			_('Output type'), status.output_type || 'auto',
			_('Output status'), status.ready === '1' ? _('Ready') : _('Not ready'),
			_('ALSA device'), status.device || '-',
			_('Bluetooth device'), status.bluetooth_name || status.bluetooth_device || '-',
			_('Last error'), status.last_error || '-'
		],
		    table = E('table', { 'class': 'table' });

		for (var i = 0; i < fields.length; i += 2) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, fields[i]),
				E('td', { 'class': 'td left' }, fields[i + 1])
			]));
		}
		return table;
	}
});
