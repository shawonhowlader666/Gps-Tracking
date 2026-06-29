@extends('layouts.layout')

@section('title', 'Server Gateways - GPS Admin Portal')

@section('page_title')
    <i class="fa-solid fa-server" style="color: var(--accent); margin-right: 8px;"></i>Server Gateways Directory
@endsection

@section('content')
    <!-- Main Table Card -->
    <div class="card">
        <div class="card-header" style="border: none; margin-bottom: 24px; padding-bottom: 0;">
            <div>
                <h2 class="card-title">Registered Gateway Nodes</h2>
                <p style="color: var(--text-secondary); font-size: 13px; margin-top: 6px;">
                    Manage backend server endpoints. These gateways establish real-time tracking streams with your mobile clients.
                </p>
            </div>
            <!-- Trigger Add Modal Button -->
            <button type="button" class="btn btn-primary" id="open-add-modal" style="width: auto; padding: 10px 20px;">
                <i class="fa-solid fa-plus"></i> Add New Server
            </button>
        </div>

        @if(empty($servers))
            <div style="text-align: center; padding: 48px 0; color: var(--text-secondary);">
                <i class="fa-solid fa-network-wired" style="font-size: 48px; color: var(--text-muted); margin-bottom: 16px; display: block;"></i>
                <p style="font-weight: 500;">No server gateways configured in Firebase yet.</p>
                <p style="font-size: 13px; color: var(--text-muted); margin-top: 4px;">Click the "Add New Server" button above to add your first tracking endpoint.</p>
            </div>
        @else
            <div class="table-responsive">
                <table class="table">
                    <thead>
                        <tr>
                            <th style="width: 40px; text-align: center;"></th>
                            <th>Gateway Name</th>
                            <th>Server URL Address</th>
                            <th>Service Tier</th>
                            <th>Ads Settings</th>
                            <th>Status</th>
                            <th style="text-align: right;">Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach($servers as $index => $server)
                            @php
                                $isActive = !isset($server['active']) || ($server['active'] != '0' && $server['active'] !== false);
                            @endphp
                            <tr class="server-row" data-index="{{ $index }}" style="{{ !$isActive ? 'opacity: 0.55;' : '' }} transition: opacity 0.2s;">
                                <td style="text-align: center; color: var(--text-secondary); font-size: 12px;">
                                    <i class="fa-solid fa-chevron-right toggle-details-icon" style="transition: transform 0.2s ease;"></i>
                                </td>
                                <td style="font-weight: 700; font-size: 14.5px; color: var(--text-primary);">
                                    <div style="display: flex; align-items: center; gap: 10px;">
                                        <div style="width: 32px; height: 32px; border-radius: 5px; background-color: rgba(139,92,246,0.08); display: flex; align-items: center; justify-content: center; color: var(--accent); font-weight: 800; flex-shrink: 0;">
                                            <i class="fa-solid fa-server" style="font-size: 14px;"></i>
                                        </div>
                                        <span class="text-truncate-sm" title="{{ $server['name'] ?? 'Unnamed Node' }}">{{ $server['name'] ?? 'Unnamed Node' }}</span>
                                    </div>
                                </td>
                                <td>
                                    <code class="text-truncate-md" title="{{ $server['url'] }}" style="color: #a78bfa; font-size: 12.5px; font-family: monospace;">{{ $server['url'] }}</code>
                                </td>
                                <td>
                                    <span class="badge {{ ($server['type'] ?? 'free') == 'free' ? 'badge-primary' : (($server['type'] ?? 'free') == 'paid' ? 'badge-success' : 'badge-success') }}" style="text-transform: capitalize;">
                                        {{ $server['type'] ?? 'free' }}
                                    </span>
                                </td>
                                <td>
                                    @if(!empty($server['showBannerAds']))
                                        <span class="badge badge-success">Ads Active</span>
                                    @else
                                        <span class="badge badge-secondary" style="background-color: rgba(255,255,255,0.03); border: 1px solid var(--border-color); color: var(--text-muted);">No Ads</span>
                                    @endif
                                </td>
                                <td>
                                    <form action="{{ route('apps.toggle', $index) }}" method="POST" style="display: inline;" class="toggle-status-form">
                                        @csrf
                                        <button type="submit" style="background: none; border: none; cursor: pointer; padding: 0;" title="Click to Toggle Status">
                                            @if($isActive)
                                                <span class="badge badge-success">Active</span>
                                            @else
                                                <span class="badge badge-secondary" style="background-color: rgba(255,255,255,0.03); border: 1px solid var(--border-color); color: var(--text-muted);">Inactive</span>
                                            @endif
                                        </button>
                                    </form>
                                </td>
                                <td style="text-align: right;">
                                    <div style="display: inline-flex; gap: 8px; justify-content: flex-end; align-items: center;">
                                         <!-- Edit button populated with data attributes -->
                                         <button type="button" class="edit-server-btn" 
                                                 data-index="{{ $index }}"
                                                 data-name="{{ $server['name'] ?? '' }}"
                                                 data-url="{{ $server['url'] ?? '' }}"
                                                 data-type="{{ $server['type'] ?? 'free' }}"
                                                 data-ads="{{ !empty($server['showBannerAds']) ? '1' : '0' }}"
                                                 data-message="{{ $server['message'] ?? '' }}"
                                                 style="color: #60a5fa; background: rgba(96, 165, 250, 0.08); border: 1px solid rgba(96, 165, 250, 0.15); padding: 5px 8px; border-radius: 4px; display: inline-flex; align-items: center; justify-content: center; transition: all 0.2s; cursor: pointer;"
                                                 title="Edit Server">
                                             <i class="fa-solid fa-pen-to-square"></i>
                                         </button>
                                         <form action="{{ route('apps.destroy', $index) }}" method="POST" onsubmit="return confirm('Are you sure you want to delete this server node from Firebase?');" style="display: inline;">
                                             @csrf
                                             @method('DELETE')
                                             <button type="submit" 
                                                     style="color: var(--danger); background: rgba(239, 68, 68, 0.08); border: 1px solid rgba(239, 68, 68, 0.15); padding: 5px 8px; border-radius: 4px; display: inline-flex; align-items: center; justify-content: center; cursor: pointer; transition: all 0.2s;" 
                                                     title="Delete Server">
                                                 <i class="fa-solid fa-trash-can"></i>
                                             </button>
                                         </form>
                                     </div>
                                </td>
                             </tr>
                            
                             <!-- Expandable Drawer Details Row -->
                             <tr class="details-row" id="details-{{ $index }}" style="display: none; background-color: rgba(17, 21, 34, 0.45);">
                                 <td colspan="7" style="padding: 20px 24px; border-bottom: 1px solid var(--border-color);">
                                    <div style="display: grid; grid-template-columns: 1.5fr 2fr; gap: 24px; text-align: left;">
                                        
                                        <!-- Card Column 1: Config Info -->
                                        <div style="background-color: var(--bg-primary); padding: 16px; border: 1px solid var(--border-color); border-radius: 5px;">
                                            <h4 style="font-size: 12px; font-weight: 700; color: var(--accent); margin-bottom: 12px; display: flex; align-items: center; gap: 6px; text-transform: uppercase; letter-spacing: 0.05em; border-bottom: 1px solid var(--border-color); padding-bottom: 6px;">
                                                <i class="fa-solid fa-circle-info"></i> Node Properties
                                            </h4>
                                            <div style="display: flex; flex-direction: column; gap: 8px; font-size: 12.5px;">
                                                <div style="display: flex; justify-content: space-between; border-bottom: 1px solid rgba(255,255,255,0.03); padding-bottom: 6px;">
                                                    <span style="color: var(--text-secondary);">Firebase Index:</span>
                                                    <span style="font-weight: 700; color: var(--text-primary);">#{{ $index }}</span>
                                                </div>
                                                <div style="display: flex; justify-content: space-between; border-bottom: 1px solid rgba(255,255,255,0.03); padding-bottom: 6px;">
                                                    <span style="color: var(--text-secondary);">Service Tier:</span>
                                                    <span style="font-weight: 700; color: var(--text-primary); text-transform: uppercase;">{{ $server['type'] ?? 'free' }}</span>
                                                </div>
                                                <div style="display: flex; justify-content: space-between; border-bottom: 1px solid rgba(255,255,255,0.03); padding-bottom: 6px;">
                                                    <span style="color: var(--text-secondary);">Banner Ads:</span>
                                                    <span style="font-weight: 700; color: var(--text-primary);">{{ !empty($server['showBannerAds']) ? 'Enabled' : 'Disabled' }}</span>
                                                </div>
                                            </div>
                                        </div>

                                        <!-- Card Column 2: Status & Message -->
                                        <div style="background-color: var(--bg-primary); padding: 16px; border: 1px solid var(--border-color); border-radius: 5px;">
                                            <h4 style="font-size: 12px; font-weight: 700; color: var(--accent); margin-bottom: 12px; display: flex; align-items: center; gap: 6px; text-transform: uppercase; letter-spacing: 0.05em; border-bottom: 1px solid var(--border-color); padding-bottom: 6px;">
                                                <i class="fa-solid fa-message"></i> Status Message / Maintenance Alert
                                            </h4>
                                            <div style="font-size: 13px; line-height: 1.5; color: var(--text-primary);">
                                                @if(!empty($server['message']))
                                                    <div style="background-color: rgba(239, 68, 68, 0.05); border: 1px solid rgba(239, 68, 68, 0.15); padding: 10px; border-radius: 5px; color: #f87171;">
                                                        <i class="fa-solid fa-triangle-exclamation" style="margin-right: 4px;"></i> {{ $server['message'] }}
                                                    </div>
                                                @else
                                                    <span style="color: var(--text-muted); font-style: italic;">No maintenance message set. Server is online.</span>
                                                @endif
                                            </div>
                                        </div>

                                    </div>
                                </td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
        @endif
    </div>

    <!-- ADD SERVER MODAL POPUP -->
    <div class="modal-overlay" id="add-server-modal">
        <div class="modal-wrapper" style="max-width: 520px;">
            <div class="modal-header">
                <h3 class="modal-title">
                    <i class="fa-solid fa-server" style="color: var(--accent);"></i>Add Server Gateway Node
                </h3>
                <button type="button" class="modal-close" id="close-add-modal">
                    <i class="fa-solid fa-xmark"></i>
                </button>
            </div>
            
            <form action="{{ route('apps.store') }}" method="POST">
                @csrf
                
                <div class="form-group">
                    <label for="add-name" class="form-label">Gateway/Server Name</label>
                    <input type="text" name="name" id="add-name" class="form-control" placeholder="Enter Gateway Name" value="{{ old('name') }}">
                </div>

                <div class="form-group">
                    <label for="add-url" class="form-label">Server Connection URL</label>
                    <input type="url" name="url" id="add-url" class="form-control" placeholder="Enter Connection URL" value="{{ old('url') }}" required>
                </div>

                <div class="form-group">
                    <label for="add-type" class="form-label">Service Tier/Type</label>
                    <select name="type" id="add-type" class="form-control" style="background-color: var(--bg-primary); cursor: pointer;">
                        <option value="free" {{ old('type') == 'free' ? 'selected' : '' }}>Free Node</option>
                        <option value="paid" {{ old('type') == 'paid' ? 'selected' : '' }}>Paid Node</option>
                        <option value="pro" {{ old('type') == 'pro' ? 'selected' : '' }}>Pro Node</option>
                        <option value="premium" {{ old('type') == 'premium' ? 'selected' : '' }}>Premium Node</option>
                    </select>
                </div>

                <div class="form-group">
                    <label class="form-check">
                        <input type="checkbox" name="showBannerAds" id="add-ads" value="1" class="form-check-input" checked>
                        <span>Enable Mobile Ads on this Node</span>
                    </label>
                </div>

                <div class="form-group">
                    <label for="add-message" class="form-label">Maintenance/Custom Message (Optional)</label>
                    <input type="text" name="message" id="add-message" class="form-control" placeholder="Enter Maintenance/Custom Message" value="{{ old('message') }}">
                </div>

                <div style="display: flex; gap: 12px; margin-top: 24px;">
                    <button type="button" class="btn btn-secondary" id="cancel-add-modal" style="flex: 1;">
                        Cancel
                    </button>
                    <button type="submit" class="btn btn-primary" style="flex: 1;">
                        Add Node <i class="fa-solid fa-plus" style="margin-left: 4px;"></i>
                    </button>
                </div>
            </form>
        </div>
    </div>

    <!-- EDIT SERVER MODAL POPUP -->
    <div class="modal-overlay" id="edit-server-modal">
        <div class="modal-wrapper" style="max-width: 520px;">
            <div class="modal-header">
                <h3 class="modal-title">
                    <i class="fa-solid fa-sliders" style="color: var(--accent);"></i>Edit Server Gateway Node
                </h3>
                <button type="button" class="modal-close" id="close-edit-modal">
                    <i class="fa-solid fa-xmark"></i>
                </button>
            </div>
            
            <form action="" method="POST" id="edit-server-form">
                @csrf
                @method('PUT')
                
                <div class="form-group">
                    <label for="edit-name" class="form-label">Gateway/Server Name</label>
                    <input type="text" name="name" id="edit-name" class="form-control" placeholder="Enter Gateway Name" required>
                </div>

                <div class="form-group">
                    <label for="edit-url" class="form-label">Server Connection URL</label>
                    <input type="url" name="url" id="edit-url" class="form-control" placeholder="Enter Connection URL" required>
                </div>

                <div class="form-group">
                    <label for="edit-type" class="form-label">Service Tier/Type</label>
                    <select name="type" id="edit-type" class="form-control" style="background-color: var(--bg-primary); cursor: pointer;">
                        <option value="free">Free Node</option>
                        <option value="paid">Paid Node</option>
                        <option value="pro">Pro Node</option>
                        <option value="premium">Premium Node</option>
                    </select>
                </div>

                <div class="form-group">
                    <label class="form-check">
                        <input type="checkbox" name="showBannerAds" id="edit-ads" value="1" class="form-check-input">
                        <span>Enable Mobile Ads on this Node</span>
                    </label>
                </div>

                <div class="form-group">
                    <label for="edit-message" class="form-label">Maintenance/Custom Message (Optional)</label>
                    <input type="text" name="message" id="edit-message" class="form-control" placeholder="Enter Maintenance/Custom Message">
                </div>

                <div style="display: flex; gap: 12px; margin-top: 24px;">
                    <button type="button" class="btn btn-secondary" id="cancel-edit-modal" style="flex: 1;">
                        Cancel
                    </button>
                    <button type="submit" class="btn btn-primary" style="flex: 1;">
                        Save Changes <i class="fa-solid fa-cloud-arrow-up" style="margin-left: 4px;"></i>
                    </button>
                </div>
            </form>
        </div>
    </div>
@endsection

@section('scripts')
<script>
document.addEventListener('DOMContentLoaded', function() {
    // Add Modal Elements
    const addModal = document.getElementById('add-server-modal');
    const openAddBtn = document.getElementById('open-add-modal');
    const closeAddBtn = document.getElementById('close-add-modal');
    const cancelAddBtn = document.getElementById('cancel-add-modal');

    // Edit Modal Elements
    const editModal = document.getElementById('edit-server-modal');
    const closeEditBtn = document.getElementById('close-edit-modal');
    const cancelEditBtn = document.getElementById('cancel-edit-modal');
    const editForm = document.getElementById('edit-server-form');

    // Helper functions to open/close
    function openModal(modalEl) {
        modalEl.classList.add('active');
        document.body.style.overflow = 'hidden';
    }

    function closeModal(modalEl) {
        modalEl.classList.remove('active');
        document.body.style.overflow = '';
    }

    // Add Modal Handlers
    if (openAddBtn) openAddBtn.addEventListener('click', () => openModal(addModal));
    if (closeAddBtn) closeAddBtn.addEventListener('click', () => closeModal(addModal));
    if (cancelAddBtn) cancelAddBtn.addEventListener('click', () => closeModal(addModal));

    // Edit Modal Handlers
    if (closeEditBtn) closeEditBtn.addEventListener('click', () => closeModal(editModal));
    if (cancelEditBtn) cancelEditBtn.addEventListener('click', () => closeModal(editModal));

    // Close on Backdrop Click
    [addModal, editModal].forEach(modal => {
        if (modal) {
            modal.addEventListener('click', function(e) {
                if (e.target === modal) {
                    closeModal(modal);
                }
            });
        }
    });

    // Populate and Open Edit Modal
    document.querySelectorAll('.edit-server-btn').forEach(btn => {
        btn.addEventListener('click', function(e) {
            e.stopPropagation(); // Prevent row expand trigger
            const index = this.getAttribute('data-index');
            const name = this.getAttribute('data-name');
            const url = this.getAttribute('data-url');
            const type = this.getAttribute('data-type');
            const ads = this.getAttribute('data-ads') === '1';
            const message = this.getAttribute('data-message');

            // Set Form action dynamically to /apps/{index}
            editForm.action = `/apps/${index}`;

            // Populate fields
            document.getElementById('edit-name').value = name;
            document.getElementById('edit-url').value = url;
            document.getElementById('edit-type').value = type;
            document.getElementById('edit-ads').checked = ads;
            document.getElementById('edit-message').value = message;

            openModal(editModal);
        });
    });

    // Toggle Details Row
    document.querySelectorAll('.server-row').forEach(row => {
        row.addEventListener('click', function(e) {
            if (e.target.closest('.btn') || e.target.closest('form')) {
                return;
            }
            const index = this.getAttribute('data-index');
            const detailsRow = document.getElementById(`details-${index}`);
            const icon = this.querySelector('.toggle-details-icon');
            
            if (detailsRow.style.display === 'none') {
                detailsRow.style.display = 'table-row';
                if (icon) icon.style.transform = 'rotate(90deg)';
                this.style.backgroundColor = 'rgba(255, 255, 255, 0.02)';
            } else {
                detailsRow.style.display = 'none';
                if (icon) icon.style.transform = 'rotate(0deg)';
                this.style.backgroundColor = '';
            }
        });
    });
});
</script>
@endsection
