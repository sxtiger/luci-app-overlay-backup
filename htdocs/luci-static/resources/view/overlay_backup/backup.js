'use strict';
'require view';
'require form';
'require fs';
'require ui';
'require uci';
'require rpc';

var callFileRead = rpc.declare({
	object: 'file',
	method: 'read',
	params: ['path'],
	expect: { data: '' }
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
			_('Backup and restore the overlay filesystem. This backs up all changes made to the system including installed packages, configurations, and modified files.'));

		s = m.section(form.NamedSection, 'main', 'settings', _('Backup Settings'));

		o = s.option(form.ListValue, 'backup_path', _('Backup Path'),
			_('Select the storage location for backup files. External storage devices will be detected automatically.'));
		o.default = '/tmp/upload';
		if (mountedData.mounted) {
			mountedData.mounted.forEach(function(path) {
				o.value(path, path);
			});
		} else {
			o.value('/tmp/upload', '/tmp/upload');
		}

		o = s.option(form.DummyValue, '_filename', _('Backup Filename'),
			_('The backup file will be named based on system version and current time.'));
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
				E('p', { class: 'spinning' }, _('Please wait while the backup is being created. This may take a few minutes depending on the size of your overlay...'))
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
					ui.addNotification(null, E('p', _('Backup created successfully: ') + result.filename + ' (' + result.size + ')'), 'success');
					window.location.reload();
				} else {
					ui.addNotification(null, E('p', _('Backup failed: ') + (result.message || 'Unknown error')), 'error');
				}
			}).catch(function(e) {
				ui.hideModal();
				ui.addNotification(null, E('p', _('Backup failed: ') + e.message), 'error');
			});
		};
		
		o = s.option(form.Flag, 'auto_reboot', _('Auto Reboot After Restore'),
			_('Automatically reboot the system after a successful restore. Recommended for changes to take effect.'));
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

		// Upload section
		s = m.section(form.NamedSection, 'main', 'settings', _('Upload Backup'));
		
		o = s.option(form.DummyValue, '_upload', _('Upload Backup File'),
			_('Upload a backup file to restore from.'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return E('div', {}, [
				E('input', {
					type: 'file',
					id: 'backup-upload-file',
					accept: '.tar.gz,.tgz',
					style: 'margin-right: 10px;'
				}),
				E('button', {
					class: 'btn cbi-button cbi-button-action',
					click: function() {
						var fileInput = document.getElementById('backup-upload-file');
						if (!fileInput.files || fileInput.files.length === 0) {
							ui.addNotification(null, E('p', _('Please select a backup file to upload.')), 'warning');
							return;
						}
						
						var file = fileInput.files[0];
						var uploadPath = uci.get('overlay_backup', 'main', 'backup_path') || '/tmp/upload';
						
						ui.showModal(_('Uploading'), [
							E('p', { class: 'spinning' }, _('Uploading backup file...'))
						]);
						
						var formData = new FormData();
						formData.append('sessionid', rpc.getSessionID());
						formData.append('filename', uploadPath + '/' + file.name);
						formData.append('filedata', file);
						
						fetch('/cgi-bin/cgi-upload', {
							method: 'POST',
							body: formData
						}).then(function(response) {
							ui.hideModal();
							if (response.ok) {
								ui.addNotification(null, E('p', _('Backup file uploaded successfully.')), 'success');
								window.location.reload();
							} else {
								ui.addNotification(null, E('p', _('Upload failed. Please try again.')), 'error');
							}
						}).catch(function(e) {
							ui.hideModal();
							ui.addNotification(null, E('p', _('Upload failed: ') + e.message), 'error');
						});
					}
				}, _('Upload'))
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
									// Use LuCI's download mechanism
									var downloadUrl = '/cgi-bin/luci/admin/system/overlay_backup/download?path=' + encodeURIComponent(backup.path);
									
									// Create a hidden iframe to trigger download
									var iframe = document.createElement('iframe');
									iframe.style.display = 'none';
									iframe.src = downloadUrl;
									document.body.appendChild(iframe);
									
									// Fallback: direct link
									setTimeout(function() {
										if (iframe.parentNode) {
											iframe.parentNode.removeChild(iframe);
										}
										// Alternative download method
										var a = document.createElement('a');
										a.href = downloadUrl;
										a.download = backup.filename;
										document.body.appendChild(a);
										a.click();
										document.body.removeChild(a);
									}, 1000);
								}
							}, _('Download')),
							E('button', {
								class: 'btn cbi-button cbi-button-negative',
								style: 'margin-right: 5px;',
								click: function() {
									if (confirm(_('Are you sure you want to delete this backup?'))) {
										ui.showModal(_('Deleting'), [
											E('p', { class: 'spinning' }, _('Deleting backup file...'))
										]);
										fs.remove(backup.path).then(function() {
											ui.hideModal();
											window.location.reload();
										}).catch(function(e) {
											ui.hideModal();
											ui.addNotification(null, E('p', _('Delete failed: ') + e.message), 'error');
										});
									}
								}
							}, _('Delete')),
							E('button', {
								class: 'btn cbi-button cbi-button-apply',
								click: function() {
									ui.showModal(_('Confirm Restore'), [
										E('p', {}, _('Warning: This will restore the backup and overwrite current overlay contents.')),
										E('p', {}, _('The system will reboot after restoration if auto-reboot is enabled.')),
										E('p', { style: 'font-weight: bold;' }, _('Are you sure you want to continue?')),
										E('div', { class: 'right' }, [
											E('button', {
												class: 'btn',
												click: function() {
													ui.hideModal();
												}
											}, _('Cancel')),
											E('button', {
												class: 'btn cbi-button-negative',
												style: 'margin-left: 10px;',
												click: function() {
													ui.showModal(_('Restoring'), [
														E('p', { class: 'spinning' }, _('Restoring backup, please wait. Do not close this page or power off the device...'))
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
																	E('p', _('Restore complete. System is rebooting...')),
																	E('p', _('Please wait and refresh the page after the system comes back online.'))
																]);
																// Keep checking if system is back
																var checkReboot = function() {
																	fetch('/cgi-bin/luci/', { method: 'HEAD' }).then(function() {
																		window.location.reload();
																	}).catch(function() {
																		setTimeout(checkReboot, 5000);
																	});
																};
																setTimeout(checkReboot, 30000);
															} else {
																ui.hideModal();
																ui.addNotification(null, E('p', _('Restore complete. Please reboot manually for changes to take effect.')), 'success');
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
											}, _('Restore'))
										])
									]);
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
