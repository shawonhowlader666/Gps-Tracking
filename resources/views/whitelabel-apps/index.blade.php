@extends('layouts.layout')

@section('title', 'Apps Manage - GPS Admin Portal')

@section('page_title')
    <i class="fa-solid fa-mobile-screen-button" style="color: var(--accent); margin-right: 8px;"></i>Apps Manage
@endsection

@section('content')
    <!-- Main Table Card -->
    <div class="card">
        <div class="card-header" style="border: none; margin-bottom: 24px; padding-bottom: 0;">
            <div>
                <h2 class="card-title">Registered Applications</h2>
                <p style="color: var(--text-secondary); font-size: 13px; margin-top: 6px;">
                    Register and manage your GPS mobile client applications. Configure tracking gateways, helplines, policies, and ad settings.
                </p>
            </div>
            <!-- Add Modal Trigger Button -->
            <button type="button" class="btn btn-primary" id="open-add-app-modal" style="width: auto; padding: 10px 20px;">
                <i class="fa-solid fa-plus"></i> Register New App
            </button>
        </div>

        @if($apps->isEmpty())
            <div style="text-align: center; padding: 48px 0; color: var(--text-secondary);">
                <i class="fa-solid fa-mobile-screen-button" style="font-size: 48px; color: var(--text-muted); margin-bottom: 16px; display: block;"></i>
                <p style="font-weight: 500;">No applications registered yet.</p>
                <p style="font-size: 13px; color: var(--text-muted); margin-top: 4px;">Click the "Register New App" button above to add your first mobile app.</p>
            </div>
        @else
            <div class="table-responsive">
                <table class="table">
                    <thead>
                        <tr>
                            <th>App Brand Name</th>
                            <th>Package Name / App ID</th>
                            <th>iOS Bundle ID</th>
                            <th>Credentials JSON</th>
                            <th style="text-align: right;">Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach($apps as $app)
                            <tr>
                                <td style="font-weight: 700; font-size: 14.5px; color: var(--text-primary);">
                                    <div style="display: flex; align-items: center; gap: 10px;">
                                        <div style="width: 32px; height: 32px; border-radius: 5px; background-color: rgba(139,92,246,0.08); display: flex; align-items: center; justify-content: center; color: var(--accent); font-weight: 800; flex-shrink: 0;">
                                            <i class="fa-solid fa-mobile-screen-button" style="font-size: 14px;"></i>
                                        </div>
                                        <span class="text-truncate-sm" title="{{ $app->name }}">{{ $app->name }}</span>
                                    </div>
                                </td>
                                <td>
                                    <code style="color: #a78bfa; font-size: 12.5px; font-family: monospace;">{{ $app->package_name }}</code>
                                </td>
                                <td>
                                    <span style="font-size: 13px; color: var(--text-secondary);">{{ $app->ios_bundle_id ?: '—' }}</span>
                                </td>
                                <td>
                                    @if($app->firebase_credential_path)
                                        <span class="badge badge-success" title="{{ $app->firebase_credential_path }}">Custom Loaded</span>
                                    @else
                                        <span class="badge badge-secondary" style="background-color: rgba(255,255,255,0.03); border: 1px solid var(--border-color); color: var(--text-muted);">Shared Workspace</span>
                                    @endif
                                </td>
                                <td style="text-align: right;">
                                    <div style="display: inline-flex; gap: 8px; justify-content: flex-end; align-items: center;">
                                        <!-- Edit Action Button -->
                                        <a href="{{ route('whitelabel-apps.edit', $app->id) }}" 
                                           style="color: #60a5fa; background: rgba(96, 165, 250, 0.08); border: 1px solid rgba(96, 165, 250, 0.15); padding: 5px 8px; border-radius: 4px; display: inline-flex; align-items: center; justify-content: center; text-decoration: none; transition: all 0.2s;" 
                                           title="Edit Application">
                                            <i class="fa-solid fa-pen-to-square"></i>
                                        </a>
                                        
                                        <!-- Delete Action Button -->
                                        <form action="{{ route('whitelabel-apps.destroy', $app->id) }}" method="POST" onsubmit="return confirm('Are you sure you want to delete this app registration from the local registry?');" style="display: inline;">
                                            @csrf
                                            @method('DELETE')
                                            <button type="submit" 
                                                    style="color: var(--danger); background: rgba(239, 68, 68, 0.08); border: 1px solid rgba(239, 68, 68, 0.15); padding: 5px 8px; border-radius: 4px; display: inline-flex; align-items: center; justify-content: center; cursor: pointer; transition: all 0.2s;" 
                                                    title="Delete Application">
                                                <i class="fa-solid fa-trash-can"></i>
                                            </button>
                                        </form>
                                    </div>
                                </td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
        @endif
    </div>

    <!-- REGISTER NEW APP MODAL -->
    <div class="modal-overlay" id="add-app-modal">
        <div class="modal-wrapper" style="max-width: 520px;">
            <div class="modal-header">
                <h3 class="modal-title">
                    <i class="fa-solid fa-mobile-screen-button" style="color: var(--accent);"></i>Register New App
                </h3>
                <button type="button" class="modal-close" id="close-add-modal">
                    <i class="fa-solid fa-xmark"></i>
                </button>
            </div>
            
            <form action="{{ route('whitelabel-apps.store') }}" method="POST" enctype="multipart/form-data">
                @csrf
                
                <div class="form-group">
                    <label for="add-name" class="form-label">Brand / Application Name</label>
                    <input type="text" name="name" id="add-name" class="form-control" placeholder="Enter Brand Name" required>
                </div>

                <div class="form-group">
                    <label for="add-package-name" class="form-label">Android Package Name (Application ID)</label>
                    <input type="text" name="package_name" id="add-package-name" class="form-control" placeholder="Enter Package Name" required>
                </div>

                <div class="form-group">
                    <label for="add-ios-bundle-id" class="form-label">iOS Bundle ID (Optional)</label>
                    <input type="text" name="ios_bundle_id" id="add-ios-bundle-id" class="form-control" placeholder="Enter iOS Bundle ID">
                </div>

                <div class="form-group">
                    <label for="add-firebase-credential" class="form-label">Firebase Credentials JSON File (Optional)</label>
                    <input type="file" name="firebase_credential" id="add-firebase-credential" class="form-control" style="padding: 8px 12px;">
                    <small style="color: var(--text-secondary); font-size: 11px; margin-top: 4px; display: block;">
                        Upload the Google Services service account key file to target a custom Firebase project.
                    </small>
                </div>

                <div style="display: flex; gap: 12px; margin-top: 24px;">
                    <button type="button" class="btn btn-secondary" id="cancel-add-modal" style="flex: 1;">
                        Cancel
                    </button>
                    <button type="submit" class="btn btn-primary" style="flex: 1;">
                        Register App <i class="fa-solid fa-plus" style="margin-left: 4px;"></i>
                    </button>
                </div>
            </form>
        </div>
    </div>
@endsection

@section('scripts')
<script>
document.addEventListener('DOMContentLoaded', function() {
    const addModal = document.getElementById('add-app-modal');
    const openAddBtn = document.getElementById('open-add-app-modal');
    const closeAddBtn = document.getElementById('close-add-modal');
    const cancelAddBtn = document.getElementById('cancel-add-modal');

    function openModal() {
        addModal.classList.add('active');
        document.body.style.overflow = 'hidden';
    }

    function closeModal() {
        addModal.classList.remove('active');
        document.body.style.overflow = '';
    }

    if (openAddBtn) openAddBtn.addEventListener('click', openModal);
    if (closeAddBtn) closeAddBtn.addEventListener('click', closeModal);
    if (cancelAddBtn) cancelAddBtn.addEventListener('click', closeModal);

    // Close on Backdrop Click
    if (addModal) {
        addModal.addEventListener('click', function(e) {
            if (e.target === addModal) {
                closeModal();
            }
        });
    }
});
</script>
@endsection
