<?php

namespace App\Http\Controllers;

use App\Models\WhitelabelApp;
use App\Services\FirebaseService;
use Illuminate\Http\Request;

class WhitelabelAppController extends Controller
{
    protected $firebaseService;

    public function __construct(FirebaseService $firebaseService)
    {
        $this->firebaseService = $firebaseService;
    }

    /**
     * Display a listing of the resource.
     */
    public function index()
    {
        try {
            // Only synchronize local registry with Firestore once every 5 seconds to avoid slow database/network overhead
            \Cache::remember('firestore_db_sync_lock', 5, function() {
                $this->firebaseService->syncLocalDatabase();
                return true;
            });
        } catch (\Exception $e) {
            \Log::error("Failed to sync local database with Firestore: " . $e->getMessage());
        }

        $apps = WhitelabelApp::all();
        return view('whitelabel-apps.index', compact('apps'));
    }

    /**
     * Store a newly created resource in storage.
     */
    public function store(Request $request)
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'package_name' => ['required', 'string', 'max:255', 'unique:whitelabel_apps,package_name'],
            'ios_bundle_id' => ['nullable', 'string', 'max:255'],
            'firebase_credential' => ['nullable', 'file', 'mimetypes:application/json,text/plain'],
        ]);

        $app = new WhitelabelApp();
        $app->name = $data['name'];
        $app->package_name = $data['package_name'];
        $app->ios_bundle_id = $data['ios_bundle_id'];

        if ($request->hasFile('firebase_credential')) {
            $path = $request->file('firebase_credential')->store('firebase');
            $app->firebase_credential_path = $path;
        }

        $app->save();

        \Cache::forget('firestore_db_sync_lock');

        return redirect()->route('whitelabel-apps.index')->with('success', 'Whitelabel App registered successfully!');
    }

    /**
     * Show the form for editing the specified resource.
     */
    public function edit($id)
    {
        $app = WhitelabelApp::findOrFail($id);
        $remoteConfig = $this->firebaseService->getAppConfig($app);

        return view('whitelabel-apps.edit', compact('app', 'remoteConfig'));
    }

    /**
     * Update the specified resource in storage.
     */
    public function update(Request $request, $id)
    {
        $app = WhitelabelApp::findOrFail($id);

        $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'ios_bundle_id' => ['nullable', 'string', 'max:255'],
            'firebase_credential' => ['nullable', 'file', 'mimetypes:application/json,text/plain'],
            'app_name' => ['required', 'string', 'max:255'],
            'version' => ['required', 'string', 'max:255'],
            'tagline' => ['nullable', 'string', 'max:255'],
            'whatsapp' => ['nullable', 'string', 'max:255'],
            'phone' => ['nullable', 'string', 'max:255'],
            'email' => ['nullable', 'email', 'max:255'],
            'address' => ['nullable', 'string', 'max:255'],
            'show_ads' => ['nullable'],
            'ads_frequency' => ['required', 'integer', 'min:0'],
            'enable_map_markers' => ['nullable'],
            'terms_url' => ['nullable', 'url', 'max:255'],
            'privacy_url' => ['nullable', 'url', 'max:255'],
            'servers' => ['nullable', 'array'],
            'payment_bkash' => ['nullable', 'string', 'max:255'],
            'payment_nagad' => ['nullable', 'string', 'max:255'],
            'payment_rocket' => ['nullable', 'string', 'max:255'],
            'maintenance_mode' => ['nullable'],
            'maintenance_message' => ['nullable', 'string', 'max:500'],
            'force_update' => ['nullable'],
            'force_update_version' => ['nullable', 'string', 'max:255'],
            'force_update_url' => ['nullable', 'url', 'max:500'],
            'force_update_message' => ['nullable', 'string', 'max:500'],
        ]);

        // Update local WhitelabelApp attributes
        $app->name = $request->input('name');
        $app->ios_bundle_id = $request->input('ios_bundle_id');

        if ($request->hasFile('firebase_credential')) {
            $path = $request->file('firebase_credential')->store('firebase');
            $app->firebase_credential_path = $path;
        }

        $app->save();

        // Format Firestore config data
        $servers = [];
        foreach ($request->input('servers', []) as $srv) {
            if (empty($srv['url'])) continue;
            $servers[] = [
                'name' => $srv['name'] ?: 'Unnamed Node',
                'url' => $srv['url'],
                'type' => $srv['type'] ?? 'free',
                'show_ads' => !empty($srv['show_ads']),
            ];
        }

        $configData = [
            'app_name' => $request->input('app_name'),
            'version' => $request->input('version'),
            'tagline' => $request->input('tagline') ?: '',
            'support' => [
                'whatsapp' => $request->input('whatsapp') ?: '',
                'phone' => $request->input('phone') ?: '',
                'email' => $request->input('email') ?: '',
                'address' => $request->input('address') ?: '',
            ],
            'servers' => $servers,
            'policies' => [
                'terms' => $request->input('terms_url') ?: '',
                'privacy' => $request->input('privacy_url') ?: '',
            ],
            'settings' => [
                'show_ads' => $request->has('show_ads'),
                'ads_frequency' => (int) $request->input('ads_frequency', 30),
                'enable_map_markers' => $request->has('enable_map_markers'),
            ],
            'payment' => [
                'bkash' => $request->input('payment_bkash') ?: '',
                'nagad' => $request->input('payment_nagad') ?: '',
                'rocket' => $request->input('payment_rocket') ?: '',
            ],
            'maintenance' => [
                'enabled' => $request->has('maintenance_mode'),
                'message' => $request->input('maintenance_message') ?: '',
            ],
            'force_update' => [
                'enabled' => $request->has('force_update'),
                'version' => $request->input('force_update_version') ?: '',
                'url' => $request->input('force_update_url') ?: '',
                'message' => $request->input('force_update_message') ?: '',
            ],
        ];

        try {
            $this->firebaseService->syncAppConfig($app, $configData);
            \Cache::forget('firestore_db_sync_lock');
            return redirect()->route('whitelabel-apps.index')->with('success', 'App configurations successfully synced to Firestore!');
        } catch (\Exception $e) {
            return back()->withInput()->with('error', 'Failed to sync config with Firebase: ' . $e->getMessage());
        }
    }

    /**
     * Remove the specified resource from storage.
     */
    public function destroy($id)
    {
        $app = WhitelabelApp::findOrFail($id);
        $app->delete();

        \Cache::forget('firestore_db_sync_lock');

        return redirect()->route('whitelabel-apps.index')->with('success', 'Whitelabel App deleted successfully.');
    }

    /**
     * Show centralized maintenance dashboard for all apps.
     */
    public function maintenanceList()
    {
        $apps = WhitelabelApp::all();
        $appsData = [];

        // Clear the cached all-configs list ONCE before the loop so we fetch a fresh batch from Firestore
        \Cache::forget('firestore_all_configs');

        foreach ($apps as $app) {
            try {
                // Clear individual config cache if this app has its own service account/credential
                if ($app->firebase_credential_path) {
                    \Cache::forget('app_config_custom_' . $app->package_name);
                }
                
                $remoteConfig = $this->firebaseService->getAppConfig($app);
                $appsData[] = [
                    'app' => $app,
                    'maintenance_enabled' => !empty($remoteConfig['maintenance']['enabled']),
                    'maintenance_message' => $remoteConfig['maintenance']['message'] ?? '',
                ];
            } catch (\Exception $e) {
                $appsData[] = [
                    'app' => $app,
                    'maintenance_enabled' => false,
                    'maintenance_message' => '',
                    'error' => $e->getMessage()
                ];
            }
        }

        return view('whitelabel-apps.maintenance', compact('appsData'));
    }

    /**
     * Update maintenance status for a specific app from the centralized dashboard.
     */
    public function maintenanceUpdate(Request $request, $id)
    {
        $app = WhitelabelApp::findOrFail($id);

        $request->validate([
            'maintenance_mode' => ['nullable'],
            'maintenance_message' => ['nullable', 'string', 'max:500'],
        ]);

        try {
            // 1. Fetch current remote config
            \Cache::forget('app_config_custom_' . $app->package_name);
            \Cache::forget('firestore_all_configs');
            $currentConfig = $this->firebaseService->getAppConfig($app);

            // 2. Overwrite maintenance node
            $currentConfig['maintenance'] = [
                'enabled' => $request->has('maintenance_mode'),
                'message' => $request->input('maintenance_message') ?: '',
            ];

            // 3. Sync to Firestore
            $this->firebaseService->syncAppConfig($app, $currentConfig);
            \Cache::forget('firestore_db_sync_lock');

            return redirect()->route('maintenance.index')->with('success', "Maintenance mode for {$app->name} successfully updated!");
        } catch (\Exception $e) {
            return back()->with('error', 'Failed to update maintenance settings: ' . $e->getMessage());
        }
    }
}
