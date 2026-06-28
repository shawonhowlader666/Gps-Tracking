@extends('layouts.layout')

@section('title', 'Dashboard - GPS Admin Portal')

@section('page_title')
    <i class="fa-solid fa-chart-pie" style="color: var(--accent); margin-right: 8px;"></i>Dashboard Overview
@endsection

@section('content')
    <!-- Welcome Panel -->
    <div class="card" style="background: linear-gradient(135deg, rgba(139, 92, 246, 0.07) 0%, rgba(17, 21, 34, 0.2) 100%); border-color: rgba(139, 92, 246, 0.2); padding: 14px 18px !important; margin-bottom: 16px !important;">
        <h2 style="font-size: 15px; font-weight: 800; margin-bottom: 6px;">Welcome back to AsthaX Portal</h2>
        <p style="color: var(--text-secondary); font-size: 11.5px; line-height: 1.5; max-width: 600px;">
            Manage configurations, support details, and tracking server gateways for all your registered GPS mobile applications from a single centralized console.
        </p>
    </div>

    <!-- Statistics Grid -->
    <div class="stat-grid">
        <!-- Registered Applications Card -->
        <div class="stat-card card-glow-purple" style="background: linear-gradient(135deg, rgba(139, 92, 246, 0.12) 0%, rgba(139, 92, 246, 0.03) 100%) !important; border: 1px solid rgba(139, 92, 246, 0.2) !important;">
            <div class="stat-info">
                <h3>Registered Applications</h3>
                <p>{{ $totalApps }}</p>
            </div>
            <div class="stat-icon" style="background-color: rgba(139, 92, 246, 0.15); color: var(--accent);">
                <i class="fa-solid fa-mobile-screen-button"></i>
            </div>
        </div>

        <!-- Active Server Gateways Card -->
        <div class="stat-card card-glow-blue" style="background: linear-gradient(135deg, rgba(59, 130, 246, 0.12) 0%, rgba(59, 130, 246, 0.03) 100%) !important; border: 1px solid rgba(59, 130, 246, 0.2) !important;">
            <div class="stat-info">
                <h3>Active Server Gateways</h3>
                <p>{{ $totalServers }}</p>
            </div>
            <div class="stat-icon" style="background-color: rgba(59, 130, 246, 0.15); color: #3b82f6;">
                <i class="fa-solid fa-server"></i>
            </div>
        </div>
        
        <!-- Premium Gateways Card -->
        <div class="stat-card card-glow-gold" style="background: linear-gradient(135deg, rgba(245, 158, 11, 0.12) 0%, rgba(245, 158, 11, 0.03) 100%) !important; border: 1px solid rgba(245, 158, 11, 0.2) !important;">
            <div class="stat-info">
                <h3>Premium Gateways</h3>
                <p>{{ collect($servers)->where('type', 'paid')->count() }}</p>
            </div>
            <div class="stat-icon" style="background-color: rgba(245, 158, 11, 0.15); color: var(--warning);">
                <i class="fa-solid fa-crown"></i>
            </div>
        </div>

        <!-- Ad-Supported Gateways Card -->
        <div class="stat-card card-glow-green" style="background: linear-gradient(135deg, rgba(16, 185, 129, 0.12) 0%, rgba(16, 185, 129, 0.03) 100%) !important; border: 1px solid rgba(16, 185, 129, 0.2) !important;">
            <div class="stat-info">
                <h3>Ad-Supported Nodes</h3>
                <p>{{ collect($servers)->filter(function($srv) { return !empty($srv['showBannerAds']) || !empty($srv['show_ads']); })->count() }}</p>
            </div>
            <div class="stat-icon" style="background-color: rgba(16, 185, 129, 0.15); color: #10b981;">
                <i class="fa-solid fa-rectangle-ad"></i>
            </div>
        </div>
    </div>

    <!-- Recently Sync Table -->
    <div class="card">
        <div class="card-header">
            <h2 class="card-title">
                <i class="fa-solid fa-clock-rotate-left" style="margin-right: 8px; color: var(--accent);"></i>Active Server Gateways
            </h2>
            <a href="{{ route('apps.index') }}" class="btn btn-secondary" style="width: auto; padding: 6px 16px; font-size: 12.5px;">
                Manage Servers
            </a>
        </div>

        @if(empty($servers))
            <div style="text-align: center; padding: 40px 0; color: var(--text-secondary);">
                <i class="fa-solid fa-folder-open" style="font-size: 44px; color: var(--text-muted); margin-bottom: 16px; display: block;"></i>
                <p>No servers configured yet. Click <a href="{{ route('apps.index') }}" style="color: var(--accent); font-weight: 600;">here</a> to add one.</p>
            </div>
        @else
            <div class="table-responsive">
                <table class="table">
                    <thead>
                        <tr>
                            <th>Gateway Name</th>
                            <th>Server URL Address</th>
                            <th>Service Tier</th>
                            <th>Ads Settings</th>
                            <th>Message / Status</th>
                            <th style="text-align: right;">Action</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach($servers as $index => $server)
                            <tr>
                                <td style="font-weight: 700; font-size: 14.5px; color: var(--text-primary);">
                                    <span class="text-truncate-sm" title="{{ $server['name'] ?? 'Unnamed Node' }}">{{ $server['name'] ?? 'Unnamed Node' }}</span>
                                </td>
                                <td>
                                    <code class="text-truncate-md" title="{{ $server['url'] }}" style="color: #a78bfa; font-size: 12.5px; font-family: monospace; display: block;">{{ $server['url'] }}</code>
                                </td>
                                <td>
                                    <span class="badge {{ ($server['type'] ?? 'free') == 'free' ? 'badge-primary' : 'badge-success' }}" style="text-transform: capitalize;">
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
                                <td style="font-size: 13px; color: var(--text-secondary);">
                                    <span class="text-truncate-sm" title="{{ $server['message'] ?? '—' }}">{{ $server['message'] ?? '—' }}</span>
                                </td>
                                <td style="text-align: right;">
                                    <a href="{{ route('apps.index') }}" 
                                       style="color: #60a5fa; background: rgba(96, 165, 250, 0.08); border: 1px solid rgba(96, 165, 250, 0.15); padding: 5px 8px; border-radius: 4px; display: inline-flex; align-items: center; justify-content: center; text-decoration: none; transition: all 0.2s;" 
                                       title="Configure Gateways">
                                        <i class="fa-solid fa-pen-to-square"></i>
                                    </a>
                                </td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
        @endif
    </div>
@endsection

@section('styles')
<style>
/* Pulsating Glow Animations */
@keyframes purpleGlow {
    0% {
        box-shadow: 0 0 5px rgba(139, 92, 246, 0.1), inset 0 0 5px rgba(139, 92, 246, 0.03);
        border-color: rgba(139, 92, 246, 0.15);
    }
    50% {
        box-shadow: 0 0 15px rgba(139, 92, 246, 0.35), inset 0 0 10px rgba(139, 92, 246, 0.08);
        border-color: rgba(139, 92, 246, 0.4);
    }
    100% {
        box-shadow: 0 0 5px rgba(139, 92, 246, 0.1), inset 0 0 5px rgba(139, 92, 246, 0.03);
        border-color: rgba(139, 92, 246, 0.15);
    }
}

@keyframes blueGlow {
    0% {
        box-shadow: 0 0 5px rgba(59, 130, 246, 0.1), inset 0 0 5px rgba(59, 130, 246, 0.03);
        border-color: rgba(59, 130, 246, 0.15);
    }
    50% {
        box-shadow: 0 0 15px rgba(59, 130, 246, 0.35), inset 0 0 10px rgba(59, 130, 246, 0.08);
        border-color: rgba(59, 130, 246, 0.4);
    }
    100% {
        box-shadow: 0 0 5px rgba(59, 130, 246, 0.1), inset 0 0 5px rgba(59, 130, 246, 0.03);
        border-color: rgba(59, 130, 246, 0.15);
    }
}

@keyframes goldGlow {
    0% {
        box-shadow: 0 0 5px rgba(245, 158, 11, 0.1), inset 0 0 5px rgba(245, 158, 11, 0.03);
        border-color: rgba(245, 158, 11, 0.15);
    }
    50% {
        box-shadow: 0 0 15px rgba(245, 158, 11, 0.35), inset 0 0 10px rgba(245, 158, 11, 0.08);
        border-color: rgba(245, 158, 11, 0.4);
    }
    100% {
        box-shadow: 0 0 5px rgba(245, 158, 11, 0.1), inset 0 0 5px rgba(245, 158, 11, 0.03);
        border-color: rgba(245, 158, 11, 0.15);
    }
}

@keyframes greenGlow {
    0% {
        box-shadow: 0 0 5px rgba(16, 185, 129, 0.1), inset 0 0 5px rgba(16, 185, 129, 0.03);
        border-color: rgba(16, 185, 129, 0.15);
    }
    50% {
        box-shadow: 0 0 15px rgba(16, 185, 129, 0.35), inset 0 0 10px rgba(16, 185, 129, 0.08);
        border-color: rgba(16, 185, 129, 0.4);
    }
    100% {
        box-shadow: 0 0 5px rgba(16, 185, 129, 0.1), inset 0 0 5px rgba(16, 185, 129, 0.03);
        border-color: rgba(16, 185, 129, 0.15);
    }
}

.card-glow-purple {
    animation: purpleGlow 4s infinite ease-in-out !important;
}

.card-glow-blue {
    animation: blueGlow 4s infinite ease-in-out !important;
}

.card-glow-gold {
    animation: goldGlow 4s infinite ease-in-out !important;
}

.card-glow-green {
    animation: greenGlow 4s infinite ease-in-out !important;
}
</style>
@endsection
