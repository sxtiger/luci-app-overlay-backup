'use strict';
'require view';
'require form';
'require fs';
'require ui';
'require uci';
'require rpc';

var callBackup = rpc.declare({
	object: 'file',
	method: 'exec',
	params: ['command', 'params'],
	expect: { stdout: '' }
});

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('overlay_backup'),
			fs.exec('/usr/bin/overlay-backup.sh', ['mounted']),
			fs.exec('/usr/bin/overlay-backup.sh', ['filename'])
		]);
	},

	render: function(data) {
		var mountedData = {};
		var filename = 'backup.tar.gz';
		
		try {
			if (data[1] && data[1].stdout) {
				mountedData = JSON.parse(data[1].stdout);
			}
		} catch(e) {
			mountedData = { mounted: ['/tmp/upload'] };
		}
		
		try {
			if (data[2] && data[2].stdout) {
				filename = data[2].stdout.trim();
			}
		} catch(e) {}

		var m, s, o;

		m = new form.Map('overlay_backup', _('Overlay Backup'),
			_('Backup and restore the overlay filesystem.'));

		s = m.section(form.NamedSection, 'main', 'settings', _('Backup Settings'));

		o = s.option(form.ListValue, 'backup_path', _('Backup Path'));
		o.default = '/tmp/upload';
		if (mountedData.mounted) {
			mountedData.mounted.forEach(function(path) {
				o.value(path, path);
			});
		} else {
			o.value('/tmp/upload', '/tmp/upload');
		}

		o = s.option(form.DummyValue, '_filename', _('Backup Filename'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return '<code>' + filename + '</code>';
		};

		o = s.option(form.Button, '_backup', _('Create Backup'));
		o.inputstyle = 'apply';
		o.inputtitle = _('Create Backup Now');
		o.onclick = function() {
		    var pathSelect = document.querySelector('select[name="cbid.overlay_backup.main.backup_path"]');
		    var path = pathSelect ? pathSelect.value : (uci.get('overlay_backup', 'main', 'backup_path') || '/tmp/upload');
		    
		    ui.showModal(_('Creating Backup'), [
		        E('p', { class: 'spinning' }, _('Please wait while the backup is being created...'))
		    ]);

		    return fs.exec('/usr/bin/overlay-backup.sh', ['backup', path]).then(function(res) {
		        ui.hideModal();
		        var result = {};
		        try {
		            result = JSON.parse(res.stdout);
		        } catch(e) {
		            result = { success: false, message: 'Parse error: ' + (res.stdout || res.stderr || 'No output') };
		        }
		        
		        if (result.success) {
		            ui.addNotification(null, E('p', _('Backup created successfully: ') + result.filename), 'success');
		            window.location.reload();
		        } else {
		            ui.addNotification(null, E('p', _('Backup failed: ') + (result.message || 'Unknown error')), 'error');
		        }
		    }).catch(function(e) {
		        ui.hideModal();
		        ui.addNotification(null, E('p', _('Backup failed: ') + e.message), 'error');
		    });
		};
		
		o = s.option(form.Flag, 'auto_reboot', _('Auto Reboot After Restore'));
		o.default = '1';

		// Backup list section
		s = m.section(form.NamedSection, 'main', 'settings', _('Existing Backups'));
		
		o = s.option(form.DummyValue, '_backuplist', _('Backup Files'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return E('div', { id: 'backup-list' }, [
				E('p', { class: 'spinning' }, _('Loading backup list...'))
			]);
		};

		return m.render().then(function(node) {
			// Load backup list after render
			var backupPath = uci.get('overlay_backup', 'main', 'backup_path') || '/tmp/upload';
			fs.exec('/usr/bin/overlay-backup.sh', ['list', backupPath]).then(function(res) {
				var listDiv = document.getElementById('backup-list');
				if (!listDiv) return;
				
				var backups = [];
				try {
					var data = JSON.parse(res.stdout);
					backups = data.backups || [];
				} catch(e) {}

				if (backups.length === 0) {
					listDiv.innerHTML = '<p>' + _('No backup files found.') + '</p>';
					return;
				}

				var table = E('table', { class: 'table' }, [
					E('tr', { class: 'tr table-titles' }, [
						E('th', { class: 'th' }, _('Filename')),
						E('th', { class: 'th' }, _('Size')),
						E('th', { class: 'th' }, _('Date')),
						E('th', { class: 'th' }, _('Actions'))
					])
				]);

				backups.forEach(function(backup) {
					var row = E('tr', { class: 'tr' }, [
						E('td', { class: 'td' }, backup.filename),
						E('td', { class: 'td' }, backup.size),
						E('td', { class: 'td' }, backup.date),
						E('td', { class: 'td' }, [
							E('button', {
								class: 'btn cbi-button cbi-button-action',
								style: 'margin-right: 5px;',
								click: function() {
									window.location.href = '/cgi-bin/luci/admin/system/flashops/backup?backup=' + encodeURIComponent(backup.path);
								}
							}, _('Download')),
							E('button', {
								class: 'btn cbi-button cbi-button-negative',
								style: 'margin-right: 5px;',
								click: function() {
									if (confirm(_('Are you sure you want to delete this backup?'))) {
										fs.remove(backup.path).then(function() {
											window.location.reload();
										});
									}
								}
							}, _('Delete')),
							E('button', {
								class: 'btn cbi-button cbi-button-apply',
								click: function() {
									if (confirm(_('Warning: This will restore the backup and reboot the system. Continue?'))) {
										ui.showModal(_('Restoring'), [
											E('p', { class: 'spinning' }, _('Restoring backup, please wait...'))
										]);
										var autoReboot = uci.get('overlay_backup', 'main', 'auto_reboot') || '1';
										fs.exec('/usr/bin/overlay-restore.sh', ['restore', backup.path, autoReboot]).then(function(res) {
											var result = {};
											try {
												result = JSON.parse(res.stdout);
											} catch(e) {}
											
											if (result.success) {
												if (result.reboot) {
													ui.showModal(_('Rebooting'), [
														E('p', _('System is rebooting. Please wait and refresh the page.'))
													]);
												} else {
													ui.hideModal();
													ui.addNotification(null, E('p', _('Restore complete. Please reboot manually.')), 'success');
												}
											} else {
												ui.hideModal();
												ui.addNotification(null, E('p', _('Restore failed: ') + (result.message || 'Unknown error')), 'error');
											}
										}).catch(function(e) {
											ui.hideModal();
											ui.addNotification(null, E('p', _('Restore failed: ') + e.message), 'error');
										});
									}
								}
							}, _('Restore'))
						])
					]);
					table.appendChild(row);
				});

				listDiv.innerHTML = '';
				listDiv.appendChild(table);
			});

			return node;
		});
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
