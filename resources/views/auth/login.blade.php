<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Login - GPS Admin Portal</title>
    <!-- Favicon -->
    <link rel="shortcut icon" type="image/png" href="{{ asset('images/asthax.png') }}?v=1.0.1">
    <!-- FontAwesome Icons -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <!-- Main Style -->
    <link rel="stylesheet" href="{{ asset('css/admin.css') }}">
</head>
<body class="auth-page">
    <div class="auth-card">
        <div class="auth-header">
            <img src="{{ asset('images/asthax.png') }}?v=1.0.1" alt="AsthaX Logo" style="height: 70px; object-fit: contain; margin: 0 auto 20px; display: block; filter: drop-shadow(0 0 10px rgba(139, 92, 246, 0.2));">
            <h1 class="auth-title">Welcome Back</h1>
            <p class="auth-subtitle">GPS Apps Management Portal</p>
        </div>

        @if(session('success'))
            <div class="alert alert-success">
                <i class="fa-solid fa-circle-check"></i>
                <span>{{ session('success') }}</span>
            </div>
        @endif

        @if(session('error'))
            <div class="alert alert-danger">
                <i class="fa-solid fa-triangle-exclamation"></i>
                <span>{{ session('error') }}</span>
            </div>
        @endif

        <form action="{{ route('login') }}" method="POST">
            @csrf
            <div class="form-group">
                <label for="email" class="form-label">Email Address</label>
                <input type="email" name="email" id="email" class="form-control" placeholder="admin@example.com" value="{{ old('email') }}" required autofocus>
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

            <div class="form-group" style="display: flex; justify-content: space-between; align-items: center;">
                <label class="form-check">
                    <input type="checkbox" name="remember" class="form-check-input">
                    <span>Remember me</span>
                </label>
            </div>

            <button type="submit" class="btn btn-primary" style="margin-top: 10px;">
                <span>Sign In</span>
                <i class="fa-solid fa-arrow-right-to-bracket"></i>
            </button>
        </form>
    </div>
</body>
</html>
