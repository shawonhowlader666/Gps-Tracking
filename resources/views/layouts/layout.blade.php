<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>@yield('title', 'GPS Admin Portal')</title>
    <!-- Favicon -->
    <link rel="shortcut icon" type="image/png" href="{{ asset('images/asthax.png') }}?v=1.0.3">
    <!-- FontAwesome Icons -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <!-- Main Style -->
    <link rel="stylesheet" href="{{ asset('css/admin.css') }}?v=1.0.9">
    @yield('styles')
</head>
<body>
    <div class="app-container">
        <!-- Sidebar -->
        <aside class="sidebar">
            <div class="sidebar-brand">
                <img src="{{ asset('images/asthax.png') }}?v=1.0.3" alt="AsthaX Logo" style="height: 18px; object-fit: contain; border-radius: 5px; filter: drop-shadow(0 0 5px rgba(139, 92, 246, 0.3));">
            </div>
            <ul class="sidebar-menu">
                <li>
                    <a href="{{ route('dashboard') }}" class="sidebar-link {{ request()->routeIs('dashboard') ? 'active' : '' }}">
                        <i class="fa-solid fa-chart-pie"></i>
                        <span>Dashboard</span>
                    </a>
                </li>
                <li>
                    <a href="{{ route('whitelabel-apps.index') }}" class="sidebar-link {{ request()->routeIs('whitelabel-apps.*') ? 'active' : '' }}">
                        <i class="fa-solid fa-mobile-screen-button"></i>
                        <span>Apps Manage</span>
                    </a>
                </li>
                <li>
                    <a href="{{ route('apps.index') }}" class="sidebar-link {{ request()->routeIs('apps.*') ? 'active' : '' }}">
                        <i class="fa-solid fa-server"></i>
                        <span>Server Gateways</span>
                    </a>
                </li>
                <li>
                    <a href="{{ route('maintenance.index') }}" class="sidebar-link {{ request()->routeIs('maintenance.*') ? 'active' : '' }}">
                        <i class="fa-solid fa-screwdriver-wrench"></i>
                        <span>Maintenance Mode</span>
                    </a>
                </li>
            </ul>
            <div class="sidebar-footer">
                <span>v1.0.0</span>
                @auth
                <form action="{{ route('logout') }}" method="POST" style="display: inline;">
                    @csrf
                    <button type="submit" class="logout-btn">
                        <i class="fa-solid fa-right-from-bracket"></i>
                        <span>Logout</span>
                    </button>
                </form>
                @endauth
            </div>
        </aside>

        <!-- Main Content -->
        <div class="main-wrapper">
            <!-- Top Navbar -->
            <header class="top-navbar">
                <button class="mobile-toggle-btn" id="sidebar-toggle-btn">
                    <i class="fa-solid fa-bars"></i>
                </button>
                <div class="page-title">
                    @yield('page_title', 'Dashboard')
                </div>
                <div class="user-profile">
                    <span class="user-name">{{ Auth::user()->name ?? 'Admin' }}</span>
                    <div class="user-avatar">
                        {{ strtoupper(substr(Auth::user()->name ?? 'A', 0, 1)) }}
                    </div>
                </div>
            </header>

            <!-- Content Body -->
            <main class="content-body">
                @if(session('success'))
                    <div class="modal-overlay active" id="success-celebration-modal" style="z-index: 10000;">
                        <div class="modal-wrapper" style="max-width: 400px; text-align: center; padding: 32px 24px; border-color: var(--success); border-radius: 5px;">
                            <div style="width: 64px; height: 64px; border-radius: 50%; background-color: var(--success-bg); color: var(--success); display: inline-flex; align-items: center; justify-content: center; font-size: 32px; margin-bottom: 20px; animation: pulse 2s infinite;">
                                <i class="fa-solid fa-circle-check"></i>
                            </div>
                            <h3 style="font-size: 18px; font-weight: 800; margin-bottom: 12px; color: var(--text-primary); letter-spacing: -0.02em;">Operation Successful!</h3>
                            <p style="color: var(--text-secondary); font-size: 13.5px; line-height: 1.5; margin-bottom: 24px;">
                                {{ session('success') }}
                            </p>
                            <button type="button" class="btn btn-primary" onclick="closeSuccessModal()" style="width: 100%; font-size: 13.5px; padding: 12px; border-radius: 5px; cursor: pointer;">
                                Done <i class="fa-solid fa-check" style="margin-left: 4px;"></i>
                            </button>
                        </div>
                    </div>

                    <!-- Balloons container -->
                    <div class="balloon-container" id="balloon-container"></div>

                    <script>
                        function spawnBalloons() {
                            const container = document.getElementById('balloon-container');
                            if (!container) return;
                            
                            const colors = ['#8b5cf6', '#a78bfa', '#10b981', '#34d399', '#ef4444', '#f87171', '#f59e0b', '#fbbf24', '#3b82f6', '#60a5fa'];
                            
                            for (let i = 0; i < 22; i++) {
                                const balloon = document.createElement('div');
                                balloon.className = 'balloon';
                                
                                const randomColor = colors[Math.floor(Math.random() * colors.length)];
                                const randomLeft = Math.random() * 95;
                                const randomDelay = Math.random() * 2.8;
                                const randomSize = 32 + Math.random() * 18;
                                const randomDuration = 3.2 + Math.random() * 1.8;
                                
                                balloon.style.backgroundColor = randomColor;
                                balloon.style.left = randomLeft + 'vw';
                                balloon.style.width = randomSize + 'px';
                                balloon.style.height = (randomSize * 1.2) + 'px';
                                balloon.style.animationDelay = randomDelay + 's';
                                balloon.style.animationDuration = randomDuration + 's';
                                
                                container.appendChild(balloon);
                            }
                        }

                        function closeSuccessModal() {
                            const modal = document.getElementById('success-celebration-modal');
                            if (modal) {
                                modal.classList.remove('active');
                            }
                            const container = document.getElementById('balloon-container');
                            if (container) {
                                container.remove();
                            }
                        }

                        document.addEventListener('DOMContentLoaded', function() {
                            spawnBalloons();
                            // Automatically remove balloons after 6 seconds
                            setTimeout(closeSuccessModal, 7000);
                        });
                    </script>
                @endif

                @if(session('error'))
                    <div class="alert alert-danger">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        <span>{{ session('error') }}</span>
                    </div>
                @endif

                @yield('content')
            </main>
        </div>
    </div>

    <script>
    document.addEventListener('DOMContentLoaded', function() {
        const toggleBtn = document.getElementById('sidebar-toggle-btn');
        const sidebar = document.querySelector('.sidebar');
        
        if (toggleBtn && sidebar) {
            toggleBtn.addEventListener('click', function(e) {
                e.stopPropagation();
                sidebar.classList.toggle('active');
            });
            
            document.addEventListener('click', function(e) {
                if (window.innerWidth <= 768) {
                    if (!sidebar.contains(e.target) && e.target !== toggleBtn) {
                        sidebar.classList.remove('active');
                    }
                }
            });
        }
    });
    </script>
    @yield('scripts')
</body>
</html>
