@extends('layouts.layout')

@section('title', 'Configure ' . $app->name . ' - GPS Admin Portal')

@section('page_title')
    <i class="fa-solid fa-sliders" style="color: var(--accent); margin-right: 8px;"></i>Configuring: {{ $app->name }}
@endsection

@section('content')
    <div style="margin-bottom: 24px; display: flex; align-items: center; justify-content: space-between;">
        <a href="{{ route('apps.index') }}" class="btn btn-secondary" style="width: auto; padding: 10px 20px;">
            <i class="fa-solid fa-arrow-left"></i> Back to Directory
        </a>
        <div style="font-size: 13px; color: var(--text-secondary);">
            App Package: <code style="color: #a78bfa; font-weight: 700; font-family: monospace;">{{ $app->package_name }}</code>
        </div>
    </div>

    <form action="{{ route('apps.update', $app->id) }}" method="POST" enctype="multipart/form-data" id="config-update-form">
        @csrf
        @method('PUT')

        <!-- Main Responsive Two-Column Layout -->
        <div class="edit-grid-main" style="display: grid; grid-template-columns: 2fr 1fr; gap: 32px; align-items: start;">
            
            <!-- Left Column: Primary Configs & Servers -->
            <div style="display: flex; flex-direction: column; gap: 24px;">
                
                <!-- General Info Card -->
                <div class="card">
                    <h3 class="config-section-title">
                        <i class="fa-solid fa-gears" style="color: var(--accent);"></i>General App Settings
                    </h3>
                    
                    <div class="config-grid-2">
                        <div class="form-group">
                            <label for="app_name" class="form-label">App Display Name</label>
                            <input type="text" name="app_name" id="app_name" class="form-control" 
                                   value="{{ old('app_name', $remoteConfig['app_name'] ?? $app->name) }}" required>
                        </div>

                        <div class="form-group">
                            <label for="version" class="form-label">Application Version</label>
                            <input type="text" name="version" id="version" class="form-control" 
                                   value="{{ old('version', $remoteConfig['version'] ?? '1.0.0') }}" placeholder="Enter Version" required>
                        </div>
                    </div>

                    <div class="form-group" style="margin-bottom: 0;">
                        <label for="tagline" class="form-label">Tagline / Subtext</label>
                        <input type="text" name="tagline" id="tagline" class="form-control" 
                               value="{{ old('tagline', $remoteConfig['tagline'] ?? '') }}" placeholder="Enter Tagline / Subtext">
                    </div>
                </div>

                <!-- Server Infrastructure Gateways Card -->
                <div class="card">
                    <div class="card-header" style="border: none; margin-bottom: 16px; padding-bottom: 0;">
                        <div>
                            <h3 class="config-section-title" style="margin-bottom: 0; border: none; padding-bottom: 0;">
                                <i class="fa-solid fa-server" style="color: var(--accent);"></i>Server Nodes & Gateways
                            </h3>
                            <p style="color: var(--text-secondary); font-size: 12.5px; margin-top: 6px;">
                                Configure backend endpoints. The mobile app establishes tracking streams with these servers.
                            </p>
                        </div>
                        <!-- Add Server Node Modal Trigger Button -->
                        <button type="button" class="btn btn-primary" id="open-node-modal" style="width: auto; padding: 8px 16px; font-size: 12.5px;">
                            <i class="fa-solid fa-plus"></i> Add Server
                        </button>
                    </div>

                    <!-- Server Gateways Table -->
                    <div class="table-responsive">
                        <table class="table" id="server-nodes-table">
                            <thead>
                                <tr>
                                    <th>Gateway Name</th>
                                    <th>Server Address (URL)</th>
                                    <th>Service Tier</th>
                                    <th>Ads Settings</th>
                                    <th style="text-align: right;">Action</th>
                                </tr>
                            </thead>
                            <tbody id="server-nodes-tbody">
                                @php
                                    $servers = $remoteConfig['servers'] ?? [];
                                @endphp

                                @if(empty($servers))
                                    <!-- Empty Row Placeholder -->
                                    <tr class="placeholder-row">
                                        <td colspan="5" style="text-align: center; padding: 32px; color: var(--text-muted);">
                                            <i class="fa-solid fa-network-wired" style="font-size: 24px; margin-bottom: 8px; display: block;"></i>
                                            No server gateways configured yet. Click "Add Server" to define one.
                                        </td>
                                    </tr>
                                @else
                                    @foreach($servers as $index => $server)
                                        <tr class="server-node-row" data-index="{{ $index }}">
                                            <td style="font-weight: 700;">
                                                <span class="node-name-text text-truncate-sm" title="{{ $server['name'] ?: 'Unnamed Node' }}">{{ $server['name'] ?: 'Unnamed Node' }}</span>
                                                <input type="hidden" name="servers[{{ $index }}][name]" value="{{ $server['name'] }}">
                                            </td>
                                            <td>
                                                <code class="text-truncate-md" title="{{ $server['url'] }}" style="font-family: monospace; color: #a78bfa; font-size: 12.5px;">{{ $server['url'] }}</code>
                                                <input type="hidden" name="servers[{{ $index }}][url]" value="{{ $server['url'] }}">
                                            </td>
                                            <td>
                                                <span class="badge {{ ($server['type'] ?? 'free') == 'free' ? 'badge-primary' : 'badge-success' }}" style="text-transform: capitalize;">
                                                    {{ $server['type'] ?? 'free' }}
                                                </span>
                                                <input type="hidden" name="servers[{{ $index }}][type]" value="{{ $server['type'] ?? 'free' }}">
                                            </td>
                                            <td>
                                                @if(!empty($server['show_ads']))
                                                    <span class="badge badge-success">Ads Active</span>
                                                    <input type="hidden" name="servers[{{ $index }}][show_ads]" value="1">
                                                @else
                                                    <span class="badge badge-secondary" style="background-color: rgba(255,255,255,0.03); border: 1px solid var(--border-color); color: var(--text-muted);">No Ads</span>
                                                    <input type="hidden" name="servers[{{ $index }}][show_ads]" value="0">
                                                @endif
                                            </td>
                                            <td style="text-align: right;">
                                                <button type="button" class="remove-node-btn">
                                                    <i class="fa-solid fa-trash-can"></i>
                                                </button>
                                            </td>
                                        </tr>
                                    @endforeach
                                @endif
                            </tbody>
                        </table>
                    </div>
                </div>

                <!-- Support & Contact Details Card -->
                <div class="card">
                    <h3 class="config-section-title">
                        <i class="fa-solid fa-headset" style="color: var(--accent);"></i>Support & Customer Helpline
                    </h3>
                    
                    <div class="config-grid-2">
                        <div class="form-group">
                            <label for="whatsapp" class="form-label">WhatsApp Support No</label>
                            <input type="text" name="whatsapp" id="whatsapp" class="form-control" 
                                   value="{{ old('whatsapp', $remoteConfig['support']['whatsapp'] ?? '') }}" placeholder="Enter WhatsApp Support No">
                        </div>

                        <div class="form-group">
                            <label for="phone" class="form-label">Helpline Voice No</label>
                            <input type="text" name="phone" id="phone" class="form-control" 
                                   value="{{ old('phone', $remoteConfig['support']['phone'] ?? '') }}" placeholder="Enter Helpline Voice No">
                        </div>
                    </div>

                    <div class="config-grid-2">
                        <div class="form-group" style="margin-bottom: 0;">
                            <label for="email" class="form-label">Help Center Email</label>
                            <input type="email" name="email" id="email" class="form-control" 
                                   value="{{ old('email', $remoteConfig['support']['email'] ?? '') }}" placeholder="Enter Help Center Email">
                        </div>

                        <div class="form-group" style="margin-bottom: 0;">
                            <label for="address" class="form-label">Physical Office Address</label>
                            <input type="text" name="address" id="address" class="form-control" 
                                   value="{{ old('address', $remoteConfig['support']['address'] ?? '') }}" placeholder="Enter Physical Office Address">
                        </div>
                    </div>
                </div>
            </div>

            <!-- Right Column: Settings, Metadata & Sync Control -->
            <div style="display: flex; flex-direction: column; gap: 24px; position: sticky; top: 100px;">
                
                <!-- Sync controls -->
                <div class="card">
                    <h3 class="card-title" style="margin-bottom: 20px;">Actions & Publishing</h3>
                    
                    <button type="submit" class="btn btn-primary" style="margin-bottom: 12px; font-size: 13.5px; padding: 12px 20px;">
                        <i class="fa-solid fa-cloud-arrow-up"></i>
                        <span>Sync with Firestore</span>
                    </button>
                    
                    <div style="font-size: 12px; color: var(--text-secondary); line-height: 1.5; background-color: rgba(255,255,255,0.01); border: 1px solid var(--border-color); padding: 12px; border-radius: 5px;">
                        <i class="fa-solid fa-circle-info" style="color: var(--accent); margin-right: 4px;"></i>
                        Synchronizes configurations directly to your Firestore database. Update values instantly on all active mobile clients.
                    </div>
                </div>

                <!-- Client App Info -->
                <div class="card">
                    <h3 class="card-title" style="margin-bottom: 16px;">Client Credentials</h3>
                    
                    <div class="form-group">
                        <label for="name" class="form-label">Client / Brand Name</label>
                        <input type="text" name="name" id="name" class="form-control" value="{{ $app->name }}" required>
                    </div>

                    <div class="form-group">
                        <label for="ios_bundle_id" class="form-label">iOS Bundle ID</label>
                        <input type="text" name="ios_bundle_id" id="ios_bundle_id" class="form-control" value="{{ $app->ios_bundle_id }}">
                    </div>

                    <div class="form-group" style="margin-bottom: 16px;">
                        <label for="firebase_credential" class="form-label">Update Credentials JSON</label>
                        <input type="file" name="firebase_credential" id="firebase_credential" class="form-control" style="padding: 8px 12px;">
                        <small style="color: var(--text-secondary); font-size: 11px; margin-top: 4px; display: block;">
                            Upload only to replace the existing JSON credentials file.
                        </small>
                    </div>

                    <div style="font-size: 12px; color: var(--text-secondary); display: flex; flex-direction: column; gap: 6px; border-top: 1px solid var(--border-color); padding-top: 12px;">
                        <div>Package: <code style="color: #a78bfa; font-family: monospace;">{{ $app->package_name }}</code></div>
                        <div>Status: 
                            @if($app->firebase_credential_path)
                                <span class="badge badge-success" style="padding: 2px 8px; font-size: 10px;">Custom JSON Active</span>
                            @else
                                <span class="badge badge-primary" style="padding: 2px 8px; font-size: 10px;">Shared Config</span>
                            @endif
                        </div>
                    </div>
                </div>

                <!-- Toggles & Flags Card -->
                <div class="card">
                    <h3 class="card-title" style="margin-bottom: 16px;">Features & Advertising</h3>
                    
                    <div class="form-group">
                        <label class="form-check">
                            <input type="checkbox" name="show_ads" value="1" class="form-check-input" {{ !empty($remoteConfig['settings']['show_ads']) ? 'checked' : '' }}>
                            <span>Enable AdMob Banners</span>
                        </label>
                    </div>

                    <div class="form-group">
                        <label for="ads_frequency" class="form-label">Banner Frequency (Seconds)</label>
                        <input type="number" name="ads_frequency" id="ads_frequency" class="form-control" 
                               value="{{ old('ads_frequency', $remoteConfig['settings']['ads_frequency'] ?? 30) }}" min="0">
                    </div>

                    <div class="form-group">
                        <label class="form-check">
                            <input type="checkbox" name="enable_map_markers" value="1" class="form-check-input" {{ !empty($remoteConfig['settings']['enable_map_markers']) ? 'checked' : '' }}>
                            <span>Show Map Markers</span>
                        </label>
                    </div>

                    <div class="form-group" style="margin-bottom: 0;">
                        <label for="terms_url" class="form-label">Terms and Conditions URL</label>
                        <input type="url" name="terms_url" id="terms_url" class="form-control" 
                               value="{{ old('terms_url', $remoteConfig['policies']['terms'] ?? '') }}" placeholder="https://domain.com/terms">
                    </div>

                    <div class="form-group" style="margin-bottom: 0; margin-top: 14px;">
                        <label for="privacy_url" class="form-label">Privacy Policy URL</label>
                        <input type="url" name="privacy_url" id="privacy_url" class="form-control" 
                               value="{{ old('privacy_url', $remoteConfig['policies']['privacy'] ?? '') }}" placeholder="https://domain.com/privacy">
                    </div>
                </div>
            </div>
        </div>
    </form>

    <!-- Add Server Node Modal Popup -->
    <div class="modal-overlay" id="node-modal">
        <div class="modal-wrapper">
            <div class="modal-header">
                <h3 class="modal-title">
                    <i class="fa-solid fa-server" style="color: var(--accent);"></i>Add Server Gateway Node
                </h3>
                <button type="button" class="modal-close" id="close-node-modal">
                    <i class="fa-solid fa-xmark"></i>
                </button>
            </div>
            
            <div class="form-group">
                <label for="modal-node-name" class="form-label">Gateway/Server Name</label>
                <input type="text" id="modal-node-name" class="form-control" placeholder="Enter Gateway Name">
            </div>

            <div class="form-group">
                <label for="modal-node-url" class="form-label">Server Connection URL</label>
                <input type="url" id="modal-node-url" class="form-control" placeholder="Enter Connection URL">
            </div>

            <div class="form-group">
                <label for="modal-node-type" class="form-label">Service Tier/Type</label>
                <select id="modal-node-type" class="form-control" style="background-color: var(--bg-primary); cursor: pointer;">
                    <option value="free">Free Node</option>
                    <option value="pro">Pro Node</option>
                    <option value="premium">Premium Node</option>
                </select>
            </div>

            <div class="form-group" style="margin-bottom: 24px;">
                <label class="form-check">
                    <input type="checkbox" id="modal-node-ads" value="1" class="form-check-input" checked>
                    <span>Enable Ads on this Node</span>
                </label>
            </div>

            <div style="display: flex; gap: 12px; margin-top: 16px;">
                <button type="button" class="btn btn-secondary" id="cancel-node-modal" style="flex: 1;">
                    Cancel
                </button>
                <button type="button" class="btn btn-primary" id="save-node-btn" style="flex: 1;">
                    Add Node <i class="fa-solid fa-plus" style="margin-left: 4px;"></i>
                </button>
            </div>
        </div>
    </div>
@endsection

@section('scripts')
<script>
document.addEventListener('DOMContentLoaded', function() {
    const modal = document.getElementById('node-modal');
    const openBtn = document.getElementById('open-node-modal');
    const closeBtn = document.getElementById('close-node-modal');
    const cancelBtn = document.getElementById('cancel-node-modal');
    const saveBtn = document.getElementById('save-node-btn');
    const tbody = document.getElementById('server-nodes-tbody');

    // Open Modal
    if (openBtn) {
        openBtn.addEventListener('click', function() {
            // Reset modal input fields
            document.getElementById('modal-node-name').value = '';
            document.getElementById('modal-node-url').value = '';
            document.getElementById('modal-node-type').value = 'free';
            document.getElementById('modal-node-ads').checked = true;

            modal.classList.add('active');
            document.body.style.overflow = 'hidden';
        });
    }

    // Close Modal
    function closeModal() {
        modal.classList.remove('active');
        document.body.style.overflow = '';
    }

    if (closeBtn) closeBtn.addEventListener('click', closeModal);
    if (cancelBtn) cancelBtn.addEventListener('click', closeModal);

    // Close on backdrop click
    modal.addEventListener('click', function(e) {
        if (e.target === modal) {
            closeModal();
        }
    });

    // Save Node (Insert into table dynamically)
    if (saveBtn) {
        saveBtn.addEventListener('click', function() {
            const name = document.getElementById('modal-node-name').value.trim();
            const url = document.getElementById('modal-node-url').value.trim();
            const type = document.getElementById('modal-node-type').value;
            const ads = document.getElementById('modal-node-ads').checked;

            if (!url) {
                alert('Please enter a valid connection URL!');
                return;
            }

            // Remove placeholder row if present
            const placeholder = tbody.querySelector('.placeholder-row');
            if (placeholder) {
                placeholder.remove();
            }

            // Calculate next index
            const rows = tbody.querySelectorAll('.server-node-row');
            let nextIndex = 0;
            if (rows.length > 0) {
                rows.forEach(row => {
                    const idx = parseInt(row.getAttribute('data-index') || 0);
                    if (idx >= nextIndex) nextIndex = idx + 1;
                });
            }

            // Create new row
            const tr = document.createElement('tr');
            tr.className = 'server-node-row';
            tr.setAttribute('data-index', nextIndex);

            // Format Ads status badges
            const adsBadge = ads 
                ? '<span class="badge badge-success">Ads Active</span>' 
                : '<span class="badge badge-secondary" style="background-color: rgba(255,255,255,0.03); border: 1px solid var(--border-color); color: var(--text-muted);">No Ads</span>';

            const typeBadge = type === 'free' 
                ? '<span class="badge badge-primary">Free</span>' 
                : (type === 'pro' ? '<span class="badge badge-success">Pro</span>' : '<span class="badge badge-success">Premium</span>');

            tr.innerHTML = `
                <td style="font-weight: 700;">
                    <span class="node-name-text text-truncate-sm" title="${name || 'Unnamed Node'}">${name || 'Unnamed Node'}</span>
                    <input type="hidden" name="servers[${nextIndex}][name]" value="${name}">
                </td>
                <td>
                    <code class="text-truncate-md" title="${url}" style="font-family: monospace; color: #a78bfa; font-size: 12.5px;">${url}</code>
                    <input type="hidden" name="servers[${nextIndex}][url]" value="${url}">
                </td>
                <td>
                    ${typeBadge}
                    <input type="hidden" name="servers[${nextIndex}][type]" value="${type}">
                </td>
                <td>
                    ${adsBadge}
                    <input type="hidden" name="servers[${nextIndex}][show_ads]" value="${ads ? '1' : '0'}">
                </td>
                <td style="text-align: right;">
                    <button type="button" class="remove-node-btn">
                        <i class="fa-solid fa-trash-can"></i>
                    </button>
                </td>
            `;

            tbody.appendChild(tr);
            attachRemoveHandler(tr.querySelector('.remove-node-btn'));
            closeModal();
        });
    }

    // Attach Remove Event Handler
    function attachRemoveHandler(btn) {
        btn.addEventListener('click', function() {
            const row = btn.closest('.server-node-row');
            row.remove();

            // Re-add placeholder row if empty
            if (tbody.querySelectorAll('.server-node-row').length === 0) {
                tbody.innerHTML = `
                    <tr class="placeholder-row">
                        <td colspan="5" style="text-align: center; padding: 32px; color: var(--text-muted);">
                            <i class="fa-solid fa-network-wired" style="font-size: 24px; margin-bottom: 8px; display: block;"></i>
                            No server gateways configured yet. Click "Add Server" to define one.
                        </td>
                    </tr>
                `;
            }
        });
    }

    // Attach remove handlers to existing nodes on page load
    tbody.querySelectorAll('.remove-node-btn').forEach(btn => {
        attachRemoveHandler(btn);
    });
});
</script>
@endsection
