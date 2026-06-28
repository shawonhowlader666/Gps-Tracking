<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Create Admin - GPS Admin Portal</title>
    <!-- Favicon -->
    <link rel="shortcut icon" type="image/png" href="{{ asset('images/asthax.png') }}">
    <!-- FontAwesome Icons -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <!-- Main Style -->
    <link rel="stylesheet" href="{{ asset('css/admin.css') }}">
</head>
<body class="auth-page">
    <div class="auth-card">
        <div class="auth-header">
            <img src="{{ asset('images/asthax.png') }}" alt="AsthaX Logo" style="height: 70px; object-fit: contain; margin: 0 auto 20px; display: block; filter: drop-shadow(0 0 10px rgba(139, 92, 246, 0.2));">
            <h1 class="auth-title">Setup Admin Account</h1>
            <p class="auth-subtitle">Initialize the GPS Management Panel</p>
        </div>

        <form action="{{ route('register') }}" method="POST">
            @csrf
            <div class="form-group">
                <label for="name" class="form-label">Full Name</label>
                <input type="text" name="name" id="name" class="form-control" placeholder="Admin User" value="{{ old('name') }}" required autofocus>
                @error('name')
                    <span style="color: var(--danger); font-size: 12px; margin-top: 4px; display: block;">{{ $message }}</span>
                @enderror
            </div>

            <div class="form-group">
                <label for="email" class="form-label">Email Address</label>
                <input type="email" name="email" id="email" class="form-control" placeholder="admin@example.com" value="{{ old('email') }}" required>
                @error('email')
                    <span style="color: var(--danger); font-size: 12px; margin-top: 4px; display: block;">{{ $message }}</span>
                @enderror
            </div>

            <div class="form-group">
                <label for="password" class="form-label">Password</label>
                <input type="password" name="password" id="password" class="form-control" placeholder="••••••••" required>
                @error('password')
                    <span style="color: var(--danger); font-size: 12px; margin-top: 4px; display: block;">{{ $message }}</span>
                @enderror
            </div>

            <div class="form-group">
                <label for="password_confirmation" class="form-label">Confirm Password</label>
                <input type="password" name="password_confirmation" id="password_confirmation" class="form-control" placeholder="••••••••" required>
            </div>

            <button type="submit" class="btn btn-primary" style="margin-top: 10px;">
                <span>Register Admin</span>
                <i class="fa-solid fa-user-plus"></i>
            </button>
        </form>
    </div>
</body>
</html>
