@extends('layouts.layout')

@section('title', 'Configure ' . $app->name . ' - GPS Admin Portal')

@section('page_title')
    <i class="fa-solid fa-sliders" style="color: var(--accent); margin-right: 8px;"></i>Configuring: {{ $app->name }}
@endsection

@section('styles')
<style>
/* Full Width Layout Wrapper */
.config-wrapper {
    max-width: 100%;
    animation: fadeIn 0.3s ease-out;
}
.content-body {
    padding: 16px 20px !important;
}

/* Header Action Bar */
.config-header-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: 16px;
    background-color: var(--bg-secondary);
    border: 1px solid var(--border-color);
    padding: 10px 18px;
    border-radius: 6px;
    margin-bottom: 16px;
    box-shadow: var(--card-shadow);
}

/* Modern Tab Navigation */
.config-tabs-container {
    display: flex;
    border-bottom: 1px solid var(--border-color);
    margin-bottom: 16px;
    gap: 8px;
    overflow-x: auto;
    scrollbar-width: none;
}
.config-tabs-container::-webkit-scrollbar {
    display: none;
}
.config-tab-btn {
    background: none;
    border: none;
    color: var(--text-secondary);
    padding: 8px 14px;
    font-size: 13.5px;
    font-weight: 600;
    cursor: pointer;
    border-bottom: 2px solid transparent;
    transition: all 0.2s ease;
    display: flex;
    align-items: center;
    gap: 8px;
    white-space: nowrap;
}
.config-tab-btn:hover {
    color: var(--text-primary);
    background-color: rgba(255, 255, 255, 0.02);
}
.config-tab-btn.active {
    color: var(--accent);
    border-bottom-color: var(--accent);
}

/* Tab Contents */
.config-tab-content {
    display: none;
}
.config-tab-content.active {
    display: block;
}

/* Clean Card Layout */
.config-card {
    background-color: var(--bg-secondary);
    border: 1px solid var(--border-color);
    border-radius: 6px;
    padding: 18px;
    box-shadow: var(--card-shadow);
    margin-bottom: 16px;
}
.config-card-title {
    font-size: 15px;
    font-weight: 700;
    color: var(--text-primary);
    margin-bottom: 14px;
    padding-bottom: 8px;
    border-bottom: 1px solid var(--border-color);
    display: flex;
    align-items: center;
    gap: 8px;
}

/* Spacing and Utilities */
.form-row-2 {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 20px;
}
@media (max-width: 600px) {
    .form-row-2 {
        grid-template-columns: 1fr;
        gap: 16px;
    }
}
.section-divider {
    border-top: 1px solid var(--border-color);
    margin: 20px 0;
}
.edit-node-btn {
    background: none;
    border: none;
    color: #3b82f6;
    cursor: pointer;
    font-size: 14px;
    transition: color 0.2s;
}
.edit-node-btn:hover {
    color: #2563eb;
}
.toggle-status-btn {
    background: none;
    border: none;
    cursor: pointer;
    padding: 0;
}
</style>
@endsection

@section('content')
<div class="config-wrapper">
    
    <!-- Action Header Bar -->
    <div class="config-header-bar">
        <div style="display: flex; align-items: center; gap: 16px; flex-wrap: wrap;">
            <a href="{{ route('whitelabel-apps.index') }}" class="btn btn-secondary" style="width: auto; padding: 10px 18px;">
                <i class="fa-solid fa-arrow-left"></i> Back
            </a>
            <div style="font-size: 13.5px; color: var(--text-secondary);">
                Package: <code style="color: #a78bfa; font-weight: 700; font-family: monospace; background-color: var(--bg-primary); padding: 4px 8px; border-radius: 4px; border: 1px solid var(--border-color);">{{ $app->package_name }}</code>
            </div>
        </div>
        
        <button type="submit" form="config-update-form" class="btn btn-primary" style="width: auto; padding: 10px 24px; font-size: 13.5px;">
            <i class="fa-solid fa-cloud-arrow-up"></i>
            <span>Sync with Firestore</span>
        </button>
    </div>

    <!-- Navigation Tabs -->
    <div class="config-tabs-container">
        <button type="button" class="config-tab-btn active" data-tab="general-tab">
            <i class="fa-solid fa-gears"></i> General & Credentials
        </button>
        <button type="button" class="config-tab-btn" data-tab="servers-tab">
            <i class="fa-solid fa-server"></i> Server Gateways
        </button>
        <button type="button" class="config-tab-btn" data-tab="support-tab">
            <i class="fa-solid fa-headset"></i> Support & Payments
        </button>
        <button type="button" class="config-tab-btn" data-tab="features-tab">
            <i class="fa-solid fa-toggle-on"></i> Features & Systems
        </button>
    </div>

    <!-- Main Configuration Form -->
    <form action="{{ route('whitelabel-apps.update', $app->id) }}" method="POST" enctype="multipart/form-data" id="config-update-form">
        @csrf
        @method('PUT')

        <!-- TAB 1: General & Credentials -->
        <div class="config-tab-content active" id="general-tab">
            <div class="config-card">
                <h3 class="config-card-title">
                    <i class="fa-solid fa-gears" style="color: var(--accent);"></i>General App Settings
                </h3>
                
                <div class="form-row-2">
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

                <div class="section-divider"></div>

                <h3 class="config-card-title" style="border: none; margin-bottom: 16px; padding-bottom: 0;">
                    <i class="fa-solid fa-shield-halved" style="color: var(--accent);"></i>Client Credentials
                </h3>
                
                <div class="form-row-2">
                    <div class="form-group">
                        <label for="name" class="form-label">Client / Brand Name</label>
                        <input type="text" name="name" id="name" class="form-control" value="{{ $app->name }}" required>
                    </div>

                    <div class="form-group">
                        <label for="ios_bundle_id" class="form-label">iOS Bundle ID</label>
                        <input type="text" name="ios_bundle_id" id="ios_bundle_id" class="form-control" value="{{ $app->ios_bundle_id }}">
                    </div>
                </div>

                <div class="form-group" style="margin-bottom: 20px;">
                    <label for="firebase_credential" class="form-label">Update Credentials JSON</label>
                    <input type="file" name="firebase_credential" id="firebase_credential" class="form-control" style="padding: 8px 12px;">
                    <small style="color: var(--text-secondary); font-size: 11px; margin-top: 4px; display: block;">
                        Upload Google Services service account JSON key file to replace configuration credentials.
                    </small>
                </div>

                <div style="font-size: 12.5px; color: var(--text-secondary); display: flex; align-items: center; justify-content: space-between; border-top: 1px solid var(--border-color); padding-top: 16px;">
                    <div>Package Name: <code style="color: #a78bfa; font-family: monospace;">{{ $app->package_name }}</code></div>
                    <div>Status: 
                        @if($app->firebase_credential_path)
                            <span class="badge badge-success" style="padding: 2px 8px; font-size: 10px;">Custom JSON Active</span>
                        @else
                            <span class="badge badge-primary" style="padding: 2px 8px; font-size: 10px;">Shared Workspace Config</span>
                        @endif
                    </div>
                </div>
            </div>
        </div>

        <!-- TAB 2: Server Gateways -->
        <div class="config-tab-content" id="servers-tab">
            <div class="config-card">
                <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 20px; border-bottom: 1px solid var(--border-color); padding-bottom: 12px; flex-wrap: wrap; gap: 12px;">
                    <div>
                        <h3 style="font-size: 15px; font-weight: 700; color: var(--text-primary); display: flex; align-items: center; gap: 8px; margin: 0;">
                            <i class="fa-solid fa-server" style="color: var(--accent);"></i>Server Gateways List
                        </h3>
                    </div>
                    <!-- Add Server Button (single line flex) -->
                    <button type="button" class="btn btn-primary" id="open-node-modal" style="width: auto; padding: 8px 16px; font-size: 12.5px; white-space: nowrap; flex-shrink: 0;">
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
                                <th>Status</th>
                                <th style="text-align: right;">Action</th>
                            </tr>
                        </thead>
                        <tbody id="server-nodes-tbody">
                            @php
                                $servers = $remoteConfig['all_servers'] ?? $remoteConfig['servers'] ?? [];
                            @endphp
 
                            @if(empty($servers))
                                <tr class="placeholder-row">
                                    <td colspan="6" style="text-align: center; padding: 32px; color: var(--text-muted);">
                                        <i class="fa-solid fa-network-wired" style="font-size: 24px; margin-bottom: 8px; display: block;"></i>
                                        No server gateways configured yet. Click "Add Server" to define one.
                                    </td>
                                </tr>
                            @else
                                @foreach($servers as $index => $server)
                                    @php
                                        $isActive = !isset($server['active']) || ($server['active'] != '0' && $server['active'] !== false);
                                    @endphp
                                    <tr class="server-node-row" data-index="{{ $index }}" style="{{ !$isActive ? 'opacity: 0.55;' : '' }} transition: opacity 0.2s;">
                                        <td style="font-weight: 700;">
                                            <span class="node-name-text text-truncate-sm" title="{{ $server['name'] ?: 'Unnamed Node' }}">{{ $server['name'] ?: 'Unnamed Node' }}</span>
                                            <input type="hidden" name="servers[{{ $index }}][name]" value="{{ $server['name'] }}" class="node-name-input">
                                        </td>
                                        <td>
                                            <code class="text-truncate-md" title="{{ $server['url'] }}" style="font-family: monospace; color: #a78bfa; font-size: 12.5px;">{{ $server['url'] }}</code>
                                            <input type="hidden" name="servers[{{ $index }}][url]" value="{{ $server['url'] }}" class="node-url-input">
                                        </td>
                                        <td>
                                            <span class="badge {{ ($server['type'] ?? 'free') == 'free' ? 'badge-primary' : 'badge-success' }}" style="text-transform: capitalize;">
                                                {{ $server['type'] ?? 'free' }}
                                            </span>
                                            <input type="hidden" name="servers[{{ $index }}][type]" value="{{ $server['type'] ?? 'free' }}" class="node-type-input">
                                        </td>
                                        <td>
                                            @if(!empty($server['show_ads']))
                                                <span class="badge badge-success ads-badge-indicator">Ads Active</span>
                                                <input type="hidden" name="servers[{{ $index }}][show_ads]" value="1" class="node-ads-input">
                                            @else
                                                <span class="badge badge-secondary ads-badge-indicator" style="background-color: rgba(255,255,255,0.03); border: 1px solid var(--border-color); color: var(--text-muted);">No Ads</span>
                                                <input type="hidden" name="servers[{{ $index }}][show_ads]" value="0" class="node-ads-input">
                                            @endif
                                        </td>
                                        <td>
                                            <button type="button" class="toggle-status-btn">
                                                @if($isActive)
                                                    <span class="badge badge-success status-badge-indicator">Active</span>
                                                @else
                                                    <span class="badge badge-secondary status-badge-indicator" style="background-color: rgba(255,255,255,0.03); border: 1px solid var(--border-color); color: var(--text-muted);">Inactive</span>
                                                @endif
                                            </button>
                                            <input type="hidden" name="servers[{{ $index }}][active]" value="{{ $isActive ? '1' : '0' }}" class="node-active-input">
                                        </td>
                                        <td style="text-align: right;">
                                            <button type="button" class="edit-node-btn" style="margin-right: 8px;">
                                                <i class="fa-solid fa-pen-to-square"></i>
                                            </button>
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
        </div>

        <!-- TAB 3: Support & Payments -->
        <div class="config-tab-content" id="support-tab">
            <div class="config-card">
                <h3 class="config-card-title">
                    <i class="fa-solid fa-headset" style="color: var(--accent);"></i>Support Helpline
                </h3>
                
                <div class="form-row-2">
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

                <div class="form-row-2">
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

                <div class="section-divider"></div>

                <h3 class="config-card-title" style="border: none; margin-bottom: 8px; padding-bottom: 0;">
                    <i class="fa-solid fa-wallet" style="color: var(--accent);"></i>Custom Payment Numbers
                </h3>
                <p style="color: var(--text-secondary); font-size: 12.5px; margin-bottom: 20px;">
                    Provide override numbers for bKash, Nagad, and Rocket payments. Falls back to Helpline Voice No if left empty.
                </p>

                <div class="form-row-3" style="display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 20px;">
                    <div class="form-group" style="margin-bottom: 0;">
                        <label for="payment_bkash" class="form-label">bKash Number</label>
                        <input type="text" name="payment_bkash" id="payment_bkash" class="form-control" 
                               value="{{ old('payment_bkash', $remoteConfig['payment']['bkash'] ?? '') }}" placeholder="Enter bKash Number">
                    </div>

                    <div class="form-group" style="margin-bottom: 0;">
                        <label for="payment_nagad" class="form-label">Nagad Number</label>
                        <input type="text" name="payment_nagad" id="payment_nagad" class="form-control" 
                               value="{{ old('payment_nagad', $remoteConfig['payment']['nagad'] ?? '') }}" placeholder="Enter Nagad Number">
                    </div>

                    <div class="form-group" style="margin-bottom: 0;">
                        <label for="payment_rocket" class="form-label">Rocket Number</label>
                        <input type="text" name="payment_rocket" id="payment_rocket" class="form-control" 
                               value="{{ old('payment_rocket', $remoteConfig['payment']['rocket'] ?? '') }}" placeholder="Enter Rocket Number">
                    </div>
                </div>
            </div>
        </div>

        <!-- TAB 4: Features & Systems -->
        <div class="config-tab-content" id="features-tab">
            <div class="config-card">
                <h3 class="config-card-title">
                    <i class="fa-solid fa-sliders" style="color: var(--accent);"></i>System Controls
                </h3>
                
                <div class="form-row-2">
                    <div class="form-group">
                        <label class="form-check" style="margin-bottom: 12px;">
                            <input type="checkbox" name="maintenance_mode" value="1" class="form-check-input" {{ !empty($remoteConfig['maintenance']['enabled']) ? 'checked' : '' }}>
                            <span style="font-weight: 700; color: var(--text-primary);">Enable Global Maintenance Mode</span>
                        </label>
                        <label for="maintenance_message" class="form-label" style="margin-top: 14px;">Maintenance Notice Alert</label>
                        <input type="text" name="maintenance_message" id="maintenance_message" class="form-control" 
                               value="{{ old('maintenance_message', $remoteConfig['maintenance']['message'] ?? 'The app is currently undergoing scheduled maintenance. Please try again later.') }}">
                    </div>

                    <div class="form-group">
                        <label class="form-check" style="margin-bottom: 12px;">
                            <input type="checkbox" name="force_update" value="1" class="form-check-input" {{ !empty($remoteConfig['force_update']['enabled']) ? 'checked' : '' }}>
                            <span style="font-weight: 700; color: var(--text-primary);">Enable Forced App Update</span>
                        </label>
                        <div style="display: grid; grid-template-columns: 1fr 2fr; gap: 10px; margin-top: 14px;">
                            <div>
                                <label for="force_update_version" class="form-label">Version</label>
                                <input type="text" name="force_update_version" id="force_update_version" class="form-control" 
                                       value="{{ old('force_update_version', $remoteConfig['force_update']['version'] ?? '1.0.0') }}" placeholder="2.0.0">
                            </div>
                            <div>
                                <label for="force_update_url" class="form-label">Store Link (URL)</label>
                                <input type="url" name="force_update_url" id="force_update_url" class="form-control" 
                                       value="{{ old('force_update_url', $remoteConfig['force_update']['url'] ?? '') }}" placeholder="https://play.google.com/store/apps/details?...">
                            </div>
                        </div>
                    </div>
                </div>
                
                <div class="form-group" style="margin-bottom: 0; margin-top: 10px;">
                    <label for="force_update_message" class="form-label">Forced Update Alert Message</label>
                    <input type="text" name="force_update_message" id="force_update_message" class="form-control" 
                           value="{{ old('force_update_message', $remoteConfig['force_update']['message'] ?? 'A new version of the app is available. Please update to continue.') }}">
                </div>

                <div class="section-divider"></div>

                <h3 class="config-card-title" style="border: none; margin-bottom: 16px; padding-bottom: 0;">
                    <i class="fa-solid fa-rectangle-ad" style="color: var(--accent);"></i>Features & Advertising
                </h3>
                
                <div class="form-row-2">
                    <div class="form-group" style="margin-bottom: 0;">
                        <label class="form-check" style="margin-bottom: 16px;">
                            <input type="checkbox" name="show_ads" value="1" class="form-check-input" {{ !empty($remoteConfig['settings']['show_ads']) ? 'checked' : '' }}>
                            <span>Enable AdMob Banner Advertisements</span>
                        </label>
                        
                        <label for="ads_frequency" class="form-label">Ad Banner Frequency (Seconds)</label>
                        <input type="number" name="ads_frequency" id="ads_frequency" class="form-control" 
                               value="{{ old('ads_frequency', $remoteConfig['settings']['ads_frequency'] ?? 30) }}" min="0">
                    </div>

                    <div class="form-group" style="margin-bottom: 0;">
                        <label class="form-check" style="margin-bottom: 16px;">
                            <input type="checkbox" name="enable_map_markers" value="1" class="form-check-input" {{ !empty($remoteConfig['settings']['enable_map_markers']) ? 'checked' : '' }}>
                            <span>Enable Map Custom Markers Layout</span>
                        </label>
                        
                        <div style="margin-top: 12px;">
                            <label for="terms_url" class="form-label">Terms & Conditions URL</label>
                            <input type="url" name="terms_url" id="terms_url" class="form-control" 
                                   value="{{ old('terms_url', $remoteConfig['policies']['terms'] ?? '') }}" placeholder="https://domain.com/terms">
                        </div>
                    </div>
                </div>

                <div class="form-row-2" style="margin-top: 20px;">
                    <div class="form-group" style="margin-bottom: 0; grid-column: 2;">
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
@section('scripts')
<script>
document.addEventListener('DOMContentLoaded', function() {
    // ─── TAB NAVIGATION LOGIC ───────────────────────────────────────────────
    const tabs = document.querySelectorAll('.config-tab-btn');
    const contents = document.querySelectorAll('.config-tab-content');

    tabs.forEach(tab => {
        tab.addEventListener('click', function() {
            tabs.forEach(t => t.classList.remove('active'));
            contents.forEach(c => c.classList.remove('active'));

            this.classList.add('active');

            const targetTab = this.getAttribute('data-tab');
            const targetContent = document.getElementById(targetTab);
            if (targetContent) {
                targetContent.classList.add('active');
            }
        });
    });

    // ─── ADD/EDIT/REMOVE SERVER NODE LOGIC ───────────────────────────────────
    const modal = document.getElementById('node-modal');
    const openBtn = document.getElementById('open-node-modal');
    const closeBtn = document.getElementById('close-node-modal');
    const cancelBtn = document.getElementById('cancel-node-modal');
    const saveBtn = document.getElementById('save-node-btn');
    const tbody = document.getElementById('server-nodes-tbody');

    const modalTitle = modal.querySelector('.modal-title');
    const modalSubmitBtn = document.getElementById('save-node-btn');

    // Open Modal for Adding
    if (openBtn) {
        openBtn.addEventListener('click', function(e) {
            e.preventDefault();
            modal.removeAttribute('data-edit-index');
            modalTitle.innerHTML = '<i class="fa-solid fa-server" style="color: var(--accent);"></i>Add Server Gateway Node';
            modalSubmitBtn.innerHTML = 'Add Node <i class="fa-solid fa-plus" style="margin-left: 4px;"></i>';

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

    modal.addEventListener('click', function(e) {
        if (e.target === modal) {
            closeModal();
        }
    });

    // Toggle Status Handler
    function attachStatusToggleHandler(btn) {
        btn.addEventListener('click', function(e) {
            e.preventDefault();
            const row = btn.closest('.server-node-row');
            const activeInput = row.querySelector('.node-active-input');
            const indicator = btn.querySelector('.status-badge-indicator');
            
            const isCurrentlyActive = activeInput.value === '1';
            const newActiveState = !isCurrentlyActive;
            
            activeInput.value = newActiveState ? '1' : '0';
            
            if (newActiveState) {
                indicator.className = 'badge badge-success status-badge-indicator';
                indicator.textContent = 'Active';
                indicator.style.backgroundColor = '';
                indicator.style.border = '';
                indicator.style.color = '';
                row.style.opacity = '1';
            } else {
                indicator.className = 'badge badge-secondary status-badge-indicator';
                indicator.textContent = 'Inactive';
                indicator.style.backgroundColor = 'rgba(255,255,255,0.03)';
                indicator.style.border = '1px solid var(--border-color)';
                indicator.style.color = 'var(--text-muted)';
                row.style.opacity = '0.55';
            }
        });
    }

    // Edit Handler
    function attachEditHandler(btn) {
        btn.addEventListener('click', function(e) {
            e.preventDefault();
            const row = btn.closest('.server-node-row');
            const index = row.getAttribute('data-index');

            const name = row.querySelector('.node-name-input').value;
            const url = row.querySelector('.node-url-input').value;
            const type = row.querySelector('.node-type-input').value;
            const ads = row.querySelector('.node-ads-input').value === '1';

            modal.setAttribute('data-edit-index', index);
            modalTitle.innerHTML = '<i class="fa-solid fa-server" style="color: var(--accent);"></i>Edit Server Gateway Node';
            modalSubmitBtn.innerHTML = 'Update Node <i class="fa-solid fa-check" style="margin-left: 4px;"></i>';

            document.getElementById('modal-node-name').value = name;
            document.getElementById('modal-node-url').value = url;
            document.getElementById('modal-node-type').value = type;
            document.getElementById('modal-node-ads').checked = ads;

            modal.classList.add('active');
            document.body.style.overflow = 'hidden';
        });
    }

    // Remove Handler
    function attachRemoveHandler(btn) {
        btn.addEventListener('click', function(e) {
            e.preventDefault();
            const row = btn.closest('.server-node-row');
            row.remove();

            if (tbody.querySelectorAll('.server-node-row').length === 0) {
                tbody.innerHTML = `
                    <tr class="placeholder-row">
                        <td colspan="6" style="text-align: center; padding: 32px; color: var(--text-muted);">
                            <i class="fa-solid fa-network-wired" style="font-size: 24px; margin-bottom: 8px; display: block;"></i>
                            No server gateways configured yet. Click "Add Server" to define one.
                        </td>
                    </tr>
                `;
            }
        });
    }

    // Save Node (Insert or Update row)
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

            const editIndex = modal.getAttribute('data-edit-index');

            if (editIndex !== null) {
                // UPDATE EXISTING ROW
                const row = tbody.querySelector(`.server-node-row[data-index="${editIndex}"]`);
                if (row) {
                    row.querySelector('.node-name-text').textContent = name || 'Unnamed Node';
                    row.querySelector('.node-name-text').title = name || 'Unnamed Node';
                    row.querySelector('.node-name-input').value = name;

                    row.querySelector('code').textContent = url;
                    row.querySelector('code').title = url;
                    row.querySelector('.node-url-input').value = url;

                    const typeBadge = row.querySelector('.node-type-input').previousElementSibling;
                    typeBadge.className = `badge ${type === 'free' ? 'badge-primary' : 'badge-success'}`;
                    typeBadge.textContent = type.charAt(0).toUpperCase() + type.slice(1);
                    row.querySelector('.node-type-input').value = type;

                    const adsBadge = row.querySelector('.node-ads-input').previousElementSibling;
                    if (ads) {
                        adsBadge.className = 'badge badge-success ads-badge-indicator';
                        adsBadge.textContent = 'Ads Active';
                        adsBadge.style.backgroundColor = '';
                        adsBadge.style.border = '';
                        adsBadge.style.color = '';
                    } else {
                        adsBadge.className = 'badge badge-secondary ads-badge-indicator';
                        adsBadge.textContent = 'No Ads';
                        adsBadge.style.backgroundColor = 'rgba(255,255,255,0.03)';
                        adsBadge.style.border = '1px solid var(--border-color)';
                        adsBadge.style.color = 'var(--text-muted)';
                    }
                    row.querySelector('.node-ads-input').value = ads ? '1' : '0';
                }
            } else {
                // ADD NEW ROW
                const placeholder = tbody.querySelector('.placeholder-row');
                if (placeholder) {
                    placeholder.remove();
                }

                const rows = tbody.querySelectorAll('.server-node-row');
                let nextIndex = 0;
                if (rows.length > 0) {
                    rows.forEach(row => {
                        const idx = parseInt(row.getAttribute('data-index') || 0);
                        if (idx >= nextIndex) nextIndex = idx + 1;
                    });
                }

                const tr = document.createElement('tr');
                tr.className = 'server-node-row';
                tr.setAttribute('data-index', nextIndex);
                tr.style.transition = 'opacity 0.2s';

                const adsBadge = ads 
                    ? '<span class="badge badge-success ads-badge-indicator">Ads Active</span>' 
                    : '<span class="badge badge-secondary ads-badge-indicator" style="background-color: rgba(255,255,255,0.03); border: 1px solid var(--border-color); color: var(--text-muted);">No Ads</span>';

                const typeBadge = type === 'free' 
                    ? '<span class="badge badge-primary">Free</span>' 
                    : (type === 'pro' ? '<span class="badge badge-success">Pro</span>' : '<span class="badge badge-success">Premium</span>');

                tr.innerHTML = `
                    <td style="font-weight: 700;">
                        <span class="node-name-text text-truncate-sm" title="${name || 'Unnamed Node'}">${name || 'Unnamed Node'}</span>
                        <input type="hidden" name="servers[${nextIndex}][name]" value="${name}" class="node-name-input">
                    </td>
                    <td>
                        <code class="text-truncate-md" title="${url}" style="font-family: monospace; color: #a78bfa; font-size: 12.5px;">${url}</code>
                        <input type="hidden" name="servers[${nextIndex}][url]" value="${url}" class="node-url-input">
                    </td>
                    <td>
                        ${typeBadge}
                        <input type="hidden" name="servers[${nextIndex}][type]" value="${type}" class="node-type-input">
                    </td>
                    <td>
                        ${adsBadge}
                        <input type="hidden" name="servers[${nextIndex}][show_ads]" value="${ads ? '1' : '0'}" class="node-ads-input">
                    </td>
                    <td>
                        <button type="button" class="toggle-status-btn">
                            <span class="badge badge-success status-badge-indicator">Active</span>
                        </button>
                        <input type="hidden" name="servers[${nextIndex}][active]" value="1" class="node-active-input">
                    </td>
                    <td style="text-align: right;">
                        <button type="button" class="edit-node-btn" style="margin-right: 8px;">
                            <i class="fa-solid fa-pen-to-square"></i>
                        </button>
                        <button type="button" class="remove-node-btn">
                            <i class="fa-solid fa-trash-can"></i>
                        </button>
                    </td>
                `;

                tbody.appendChild(tr);
                attachStatusToggleHandler(tr.querySelector('.toggle-status-btn'));
                attachEditHandler(tr.querySelector('.edit-node-btn'));
                attachRemoveHandler(tr.querySelector('.remove-node-btn'));
            }

            closeModal();
        });
    }

    // Attach event listeners to initial rows
    tbody.querySelectorAll('.toggle-status-btn').forEach(btn => {
        attachStatusToggleHandler(btn);
    });
    tbody.querySelectorAll('.edit-node-btn').forEach(btn => {
        attachEditHandler(btn);
    });
    tbody.querySelectorAll('.remove-node-btn').forEach(btn => {
        attachRemoveHandler(btn);
    });
});
</script>
@endsection
