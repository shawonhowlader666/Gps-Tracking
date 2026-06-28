<?php

namespace App\Http\Controllers;

use App\Models\WhitelabelApp;
use App\Services\FirebaseService;
use Illuminate\Http\Request;

class AppConfigController extends Controller
{
    protected $firebaseService;

    public function __construct(FirebaseService $firebaseService)
    {
        $this->firebaseService = $firebaseService;
    }

    public function index()
    {
        $servers = $this->firebaseService->getSpytrackServers();
        return view('apps.index', compact('servers'));
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'name' => ['nullable', 'string', 'max:255'],
            'url' => ['required', 'url', 'max:255'],
            'type' => ['required', 'string', 'in:free,pro,paid,premium'],
            'showBannerAds' => ['nullable'],
            'message' => ['nullable', 'string', 'max:255'],
        ]);

        $servers = $this->firebaseService->getSpytrackServers();

        $newServer = [
            'name' => $data['name'] ?: 'Unnamed Node',
            'url' => $data['url'],
            'type' => $data['type'],
            'showBannerAds' => $request->has('showBannerAds') ? (bool)$request->boolean('showBannerAds') : true,
            'message' => $data['message'] ?: '',
        ];

        // Append to the end of the array (bottom in Firebase)
        $servers[] = $newServer;

        try {
            $this->firebaseService->saveSpytrackServers($servers);
            return redirect()->route('apps.index')->with('success', 'New server gateway successfully added at the bottom of the list in Firebase!');
        } catch (\Exception $e) {
            return redirect()->route('apps.index')->with('error', 'Failed to save server to Firebase: ' . $e->getMessage());
        }
    }

    public function update(Request $request, $index)
    {
        $data = $request->validate([
            'name' => ['nullable', 'string', 'max:255'],
            'url' => ['required', 'url', 'max:255'],
            'type' => ['required', 'string', 'in:free,pro,paid,premium'],
            'showBannerAds' => ['nullable'],
            'message' => ['nullable', 'string', 'max:255'],
        ]);

        $servers = $this->firebaseService->getSpytrackServers();

        if (!isset($servers[$index])) {
            return redirect()->route('apps.index')->with('error', 'Server node index not found in Firebase.');
        }

        $servers[$index] = [
            'name' => $data['name'] ?: 'Unnamed Node',
            'url' => $data['url'],
            'type' => $data['type'],
            'showBannerAds' => $request->has('showBannerAds') ? (bool)$request->boolean('showBannerAds') : true,
            'message' => $data['message'] ?: '',
        ];

        try {
            $this->firebaseService->saveSpytrackServers($servers);
            return redirect()->route('apps.index')->with('success', 'Server gateway node successfully updated and synced with Firebase!');
        } catch (\Exception $e) {
            return redirect()->route('apps.index')->with('error', 'Failed to update server in Firebase: ' . $e->getMessage());
        }
    }

    public function destroy($index)
    {
        $servers = $this->firebaseService->getSpytrackServers();

        if (isset($servers[$index])) {
            unset($servers[$index]);
            // Re-index array values to ensure it remains a valid list
            $servers = array_values($servers);
        }

        try {
            $this->firebaseService->saveSpytrackServers($servers);
            return redirect()->route('apps.index')->with('success', 'Server gateway node successfully deleted from Firebase.');
        } catch (\Exception $e) {
            return redirect()->route('apps.index')->with('error', 'Failed to delete server in Firebase: ' . $e->getMessage());
        }
    }
}
