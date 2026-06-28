<?php

namespace App\Http\Controllers;

use App\Models\WhitelabelApp;
use App\Services\FirebaseService;

class DashboardController extends Controller
{
    protected $firebaseService;

    public function __construct(FirebaseService $firebaseService)
    {
        $this->firebaseService = $firebaseService;
    }

    public function index()
    {
        $servers = $this->firebaseService->getSpytrackServers();
        $totalServers = count($servers);
        $totalApps = WhitelabelApp::count();

        return view('dashboard', compact('totalServers', 'servers', 'totalApps'));
    }
}
