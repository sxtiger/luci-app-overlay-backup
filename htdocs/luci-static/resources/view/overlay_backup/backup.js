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

// Global variable to store current backup path
var currentBackupPath = '/tmp/upload';

// Helper function to find and get backup path from select element
function getSelectedBackupPath() {
	// Method 1: Try to find select by common LuCI naming patterns
	var selectors = [
		'select[name="cbid.overlay_backup.main.backup_path"]',
		'select[id*="overlay_backup"][id*="backup_path"]',
		'select[data-name="backup_path"]',
		'[data-widget="select"][id*="backup_path"] select',
		'.cbi-value[data-name="backup_path"] select',
		'.cbi-value-field select[id*="backup_path"]'
	];
	
	for (var i = 0; i < selectors.length; i++) {
		var el = document.querySelector(selectors[i]);
		if (el && el.value && el.value.startsWith('/')) {
			console.log('Found backup path via selector:', selectors[i], '=', el.value);
			return el.value;
		}
	}
	
	// Method 2: Find all selects and look for one with mount paths
	var allSelects = document.querySelectorAll('select');
	for (var j = 0; j < allSelects.length; j++) {
		var sel = allSelects[j];
		if (sel.options && sel.options.length > 0) {
			// Check if any option looks like a path
			for (var k = 0; k < sel.options.length; k++) {
				var optVal = sel.options[k].value;
				if (optVal && (optVal.startsWith('/mnt/') || optVal === '/tmp/upload')) {
					console.log('Found backup path via option scan:', sel.value);
					return sel.value;
				}
			}
		}
	}
	
	// Method 3: Return the global variable (updated by change listener)
	console.log('Using stored backup path:', currentBackupPath);
	return currentBackupPath;
}

// Function to load and display backup list
function loadBackupList(path) {
	var listDiv = document.getElementById('backup-list');
	if (!listDiv) return;
	
	listDiv.innerHTML = '<p class="spinning">' + _('Loading backup list...') + '</p>';
	
	fs.exec('/usr/bin/overlay-backup.sh', ['list', path]).then(function(res) {
		var backups = [];
		try {
			var data = JSON.parse(res.stdout);
			backups = data.backups || [];
		} catch(e) {
			console.error('Failed to parse backup list:', e);
		}

		if (backups.length === 0) {
			listDiv.innerHTML = '<p>' + _('No backup files found in ') + path + '</p>';
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
							var downloadUrl = '/cgi-bin/luci/admin/system/overlay_backup/download?path=' + encodeURIComponent(backup.path);
							var iframe = document.createElement('iframe');
							iframe.style.display = 'none';
							iframe.src = downloadUrl;
							document.body.appendChild(iframe);
							
							setTimeout(function() {
								if (iframe.parentNode) {
									iframe.parentNode.removeChild(iframe);
								}
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
									loadBackupList(getSelectedBackupPath());
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
		listDiv.appendChild(E('p', {}, _('Current path: ') + path));
		listDiv.appendChild(table);
	}).catch(function(e) {
		listDiv.innerHTML = '<p class="error">' + _('Failed to load backup list: ') + e.message + '</p>';
	});
}

// Setup path change listener
function setupPathChangeListener() {
	// Find all selects that might be the backup path selector
	var allSelects = document.querySelectorAll('select');
	allSelects.forEach(function(sel) {
		// Check if this select has path-like options
		var hasPathOptions = false;
		for (var i = 0; i < sel.options.length; i++) {
			var val = sel.options[i].value;
			if (val && (val.startsWith('/mnt/') || val === '/tmp/upload')) {
				hasPathOptions = true;
				break;
			}
		}
		
		if (hasPathOptions) {
			console.log('Found backup path select, adding change listener');
			sel.addEventListener('change', function(e) {
				currentBackupPath = e.target.value;
				console.log('Backup path changed to:', currentBackupPath);
				// Reload backup list with new path
				loadBackupList(currentBackupPath);
			});
			// Initialize currentBackupPath
			currentBackupPath = sel.value;
		}
	});
}

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
		
		// Initialize currentBackupPath from UCI
		currentBackupPath = uci.get('overlay_backup', 'main', 'backup_path') || '/tmp/upload';

		var m, s, o;

		m = new form.Map('overlay_backup', _('Overlay Backup'),
			_('Backup and restore the overlay filesystem. This backs up all changes made to the system including installed packages, configurations, and modified files.'));

		s = m.section(form.NamedSection, 'main', 'settings', _('Backup Settings'));

		o = s.option(form.ListValue, 'backup_path', _('Backup Path'),
			_('Select the storage location for backup files. External storage devices will be detected automatically.'));
		o.default = '/tmp/upload';
		o.rmempty = false;
		if (mountedData.mounted) {
			mountedData.mounted.forEach(function(path) {
				o.value(path, path);
			});
		} else {
			o.value('/tmp/upload', '/tmp/upload');
		}
		// Add onchange handler directly to the option
		o.onchange = function(ev, section_id, value) {
			currentBackupPath = value;
			console.log('Path changed via onchange:', value);
			loadBackupList(value);
		};

		o = s.option(form.DummyValue, '_filename', _('Backup Filename'),
			_('The backup file will be named based on system version and current time.'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return '<code>' + filename + '</code>';
		};

		o = s.option(form.Button, '_backup', _('Create Backup'));
		o.inputstyle = 'apply';
		o.inputtitle = _('Create Backup Now');
		o.onclick = function(ev) {
			// Get the selected backup path
			var path = getSelectedBackupPath();
			
			console.log('Creating backup to path:', path);
			
			ui.showModal(_('Creating Backup'), [
				E('p', { class: 'spinning' }, _('Please wait while the backup is being created. This may take a few minutes depending on the size of your overlay...')),
				E('p', {}, _('Backup location: ') + E('strong', {}, path))
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
					// Reload backup list
					loadBackupList(path);
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
						var uploadPath = getSelectedBackupPath();
						
						ui.showModal(_('Uploading'), [
							E('p', { class: 'spinning' }, _('Uploading backup file...')),
							E('p', {}, _('Upload location: ') + uploadPath)
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
								loadBackupList(uploadPath);
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
			// Setup path change listener after DOM is ready
			setTimeout(function() {
				setupPathChangeListener();
				// Load initial backup list
				loadBackupList(currentBackupPath);
			}, 100);

			return node;
		});
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
