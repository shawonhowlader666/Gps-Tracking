@extends('layouts.layout')

@section('title', 'Global Maintenance Controls - GPS Admin Portal')

@section('page_title')
    <i class="fa-solid fa-screwdriver-wrench" style="color: var(--accent); margin-right: 8px;"></i>Global Maintenance Controls
@endsection

@section('styles')
<style>
.maintenance-container {
    max-width: 100%;
    animation: fadeIn 0.3s ease-out;
}
.app-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(380px, 1fr));
    gap: 20px;
    margin-top: 16px;
}
.app-card {
    background-color: var(--bg-secondary);
    border: 1px solid var(--border-color);
    border-radius: 6px;
    padding: 20px;
    box-shadow: var(--card-shadow);
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    transition: transform 0.2s ease, border-color 0.2s ease;
}
.app-card:hover {
    border-color: var(--accent);
}
.app-card-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    border-bottom: 1px solid var(--border-color);
    padding-bottom: 12px;
    margin-bottom: 16px;
}
.app-title {
    font-size: 16px;
    font-weight: 800;
    color: var(--text-primary);
    margin: 0;
}
.package-name {
    font-family: monospace;
    font-size: 11px;
    color: var(--text-secondary);
    background-color: var(--bg-primary);
    padding: 2px 6px;
    border-radius: 4px;
    border: 1px solid var(--border-color);
    display: inline-block;
    margin-top: 4px;
}
.status-badge {
    padding: 4px 10px;
    font-size: 11px;
    font-weight: 700;
    border-radius: 20px;
    text-transform: uppercase;
}
.status-live {
    background-color: rgba(34, 197, 94, 0.1);
    color: #22c55e;
    border: 1px solid rgba(34, 197, 94, 0.2);
}
.status-maintenance {
    background-color: rgba(239, 68, 68, 0.1);
    color: #ef4444;
    border: 1px solid rgba(239, 68, 68, 0.2);
}
.toggle-switch-container {
    display: flex;
    align-items: center;
    justify-content: space-between;
    background-color: var(--bg-primary);
    border: 1px solid var(--border-color);
    padding: 10px 14px;
    border-radius: 6px;
    margin-bottom: 16px;
}
.toggle-label {
    font-size: 13.5px;
    font-weight: 700;
    color: var(--text-primary);
}
.form-group-custom {
    margin-bottom: 16px;
}
.form-label-custom {
    font-size: 12.5px;
    font-weight: 600;
    color: var(--text-secondary);
    margin-bottom: 6px;
    display: block;
}
.form-control-custom {
    background-color: var(--bg-primary);
    border: 1px solid var(--border-color);
    color: var(--text-primary);
    padding: 10px 12px;
    border-radius: 6px;
    font-size: 13px;
    width: 100%;
    transition: border-color 0.2s;
}
.form-control-custom:focus {
    outline: none;
    border-color: var(--accent);
}
</style>
@endsection

@section('content')
<div class="maintenance-container">
    <div style="margin-bottom: 24px;">
        <p style="color: var(--text-secondary); font-size: 14px; margin: 0; line-height: 1.5;">
            Toggle Maintenance Mode and update alert messages in real-time for all of your Whitelabel Applications.
            When enabled, users will see the maintenance screen immediately upon launching the app.
        </p>
    </div>

    <div class="app-grid">
        @foreach($appsData as $data)
            <div class="app-card">
                <form action="{{ route('maintenance.update', $data['app']->id) }}" method="POST">
                    @csrf
                    @method('PUT')
                    
                    <div class="app-card-header">
                        <div>
                            <h4 class="app-title">{{ $data['app']->name }}</h4>
                            <span class="package-name">{{ $data['app']->package_name }}</span>
                        </div>
                        <div>
                            @if($data['maintenance_enabled'])
                                <span class="status-badge status-maintenance">
                                    <i class="fa-solid fa-triangle-exclamation" style="margin-right: 4px;"></i> Maintenance
                                </span>
                            @else
                                <span class="status-badge status-live">
                                    <i class="fa-solid fa-circle-check" style="margin-right: 4px;"></i> Live
                                </span>
                            @endif
                        </div>
                    </div>

                    @if(isset($data['error']))
                        <div style="background-color: rgba(239,68,68,0.1); border: 1px solid rgba(239,68,68,0.2); padding: 12px; border-radius: 6px; margin-bottom: 16px;">
                            <small style="color: #ef4444; font-weight: 600; display: block; margin-bottom: 4px;">
                                <i class="fa-solid fa-circle-exclamation"></i> Firebase Fetch Error
                            </small>
                            <small style="color: var(--text-secondary); font-family: monospace; font-size: 11px;">{{ $data['error'] }}</small>
                        </div>
                    @endif

                    <div class="toggle-switch-container">
                        <span class="toggle-label">Maintenance Mode</span>
                        <label class="form-check" style="margin: 0; display: flex; align-items: center; cursor: pointer;">
                            <input type="checkbox" name="maintenance_mode" value="1" class="form-check-input" 
                                   {{ $data['maintenance_enabled'] ? 'checked' : '' }} style="width: 38px; height: 20px; cursor: pointer;">
                        </label>
                    </div>

                    <div class="form-group-custom">
                        <label class="form-label-custom">Maintenance Notice Message</label>
                        <textarea name="maintenance_message" class="form-control-custom" rows="3" required
                                  placeholder="Enter the message to display on the maintenance screen...">{{ $data['maintenance_message'] ?: 'The app is currently undergoing scheduled maintenance. Please try again later.' }}</textarea>
                    </div>

                    <button type="submit" class="btn btn-primary" style="width: 100%; padding: 12px; font-size: 13px; font-weight: 700; border-radius: 6px;">
                        <i class="fa-solid fa-cloud-arrow-up" style="margin-right: 6px;"></i> Update & Sync
                    </button>
                </form>
            </div>
        @endforeach
    </div>
</div>
@endsection