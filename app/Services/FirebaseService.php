<?php

namespace App\Services;

use App\Models\WhitelabelApp;
use Kreait\Firebase\Factory;
use Google\Cloud\Firestore\FirestoreClient;

class FirebaseService
{
    /**
     * Get a Firestore connection for a specific app (optional).
     * If the app has its own service account JSON, we use it.
     * Otherwise, we fallback to the default workspace service account.
     */
    public function getFirestore(WhitelabelApp $app = null): FirestoreClient
    {
        $factory = new Factory();

        // 1. Determine the service account credentials file path
        $keyPath = null;
        if ($app && $app->firebase_credential_path && file_exists(storage_path('app/' . $app->firebase_credential_path))) {
            $keyPath = storage_path('app/' . $app->firebase_credential_path);
        } else {
            $defaultPath = storage_path('app/firebase/service-account.json');
            if (file_exists($defaultPath)) {
                $keyPath = $defaultPath;
            }
        }

        if ($keyPath) {
            $factory = $factory->withServiceAccount($keyPath);
        }

        // 2. Reflect to extract the ClientConfig from Kreait Factory and inject 'credentials' key
        $ref = new \ReflectionClass($factory);
        $m = $ref->getMethod('googleCloudClientConfig');
        $m->setAccessible(true);
        $config = $m->invoke($factory);

        // Map credentialsFetcher to credentials for FirestoreClient compatibility
        if (isset($config['credentialsFetcher'])) {
            $config['credentials'] = $config['credentialsFetcher'];
        }

        // Use REST transport instead of gRPC to prevent network hangs on Windows/local ISPs
        $config['transport'] = 'rest';

        // 3. Instantiate and return the Firestore Client directly
        return new FirestoreClient($config);
    }

    /**
     * Fetch the configuration map from Firestore for the app.
     * Checks configs/{package_name} first, and falls back to configs/urls -> spytrack if not found.
     */
    public function getAppConfig(WhitelabelApp $app): array
    {
        // If the app has custom credentials, fetch and cache individually
        if ($app->firebase_credential_path) {
            $cacheKey = 'app_config_custom_' . $app->package_name;
            return \Cache::remember($cacheKey, 86400, function() use ($app) {
                try {
                    $db = $this->getFirestore($app);
                    $docRef = $db->collection('configs')->document($app->package_name);
                    $snapshot = $docRef->snapshot();
                    if ($snapshot->exists()) {
                        $data = $snapshot->data();
                        if (!empty($data)) {
                            return $data;
                        }
                    }
                } catch (\Exception $e) {
                    \Log::error("Firebase Custom Fetch Error for {$app->name}: " . $e->getMessage());
                }
                return [];
            });
        }

        // For default apps, use the cached batch query
        try {
            $allConfigs = $this->getAllConfigs();

            // 1. Try package-specific config from the batch
            if (isset($allConfigs[$app->package_name])) {
                $data = $allConfigs[$app->package_name];
                if (!empty($data)) {
                    return $data;
                }
            }

            // 2. Fallback: Parse spytrack from configs/urls document (ONLY for Orbit GPS com.orbitgps.app)
            if ($app->package_name === 'com.orbitgps.app' && isset($allConfigs['urls']['spytrack'])) {
                $spy = $allConfigs['urls']['spytrack'];

                // Decode/normalize servers list
                $servers = [];
                if (isset($spy['url'])) {
                    if (is_array($spy['url'])) {
                        $servers = $spy['url'];
                    } elseif (is_string($spy['url'])) {
                        $decoded = json_decode($spy['url'], true);
                        if (is_array($decoded)) {
                            $servers = $decoded;
                        }
                    }
                }

                // Normalize server keys for view
                $formattedServers = [];
                foreach ($servers as $srv) {
                    $formattedServers[] = [
                        'name' => $srv['name'] ?? '',
                        'url' => $srv['url'] ?? '',
                        'type' => $srv['type'] ?? 'free',
                        'show_ads' => !empty($srv['showBannerAds']) || !empty($srv['show_ads']),
                    ];
                }

                return [
                    'app_name' => $spy['name'] ?? $app->name,
                    'version' => $spy['version'] ?? '1.0.0',
                    'tagline' => $spy['tagline'] ?? '',
                    'support' => [
                        'whatsapp' => $spy['whatsapp'] ?? '',
                        'phone' => $spy['phone'] ?? '',
                        'email' => $spy['email'] ?? '',
                        'address' => $spy['address'] ?? '',
                    ],
                    'servers' => $formattedServers,
                    'policies' => [
                        'terms' => $spy['terms'] ?? '',
                        'privacy' => $spy['privacy'] ?? '',
                    ],
                    'settings' => [
                        'show_ads' => (bool) ($spy['ads'] ?? false),
                        'ads_frequency' => (int) ($spy['adsfrequency'] ?? 30),
                        'enable_map_markers' => true,
                    ],
                ];
            }
        } catch (\Exception $e) {
            \Log::error("Firebase Fetch Error for {$app->name}: " . $e->getMessage());
        }

        return [];
    }

    /**
     * Save/Sync configurations to Firestore configs/{package_name}.
     * Also updates legacy configs/urls -> spytrack to ensure backward compatibility for old app builds.
     */
    public function syncAppConfig(WhitelabelApp $app, array $data): bool
    {
        try {
            $db = $this->getFirestore($app);
            
            // 1. Save to new package-specific document
            $docRef = $db->collection('configs')->document($app->package_name);
            $docRef->set($data);

            // 2. Save/Update legacy configs/urls -> spytrack key for backward compatibility
            if ($app->package_name === 'com.orbitgps.app' || $app->package_name === 'com.onfleetgps.app') {
                $oldDocRef = $db->collection('configs')->document('urls');
                
                // Preserve existing legacy banners, fuelData and servers list so they are not deleted
                $oldBanners = [];
                $oldFuelData = (object) [];
                $legacyServers = [];
                $oldSnapshot = $oldDocRef->snapshot();
                if ($oldSnapshot->exists()) {
                    $oldDocData = $oldSnapshot->data();
                    if (isset($oldDocData['spytrack'])) {
                        $oldBanners = $oldDocData['spytrack']['banners'] ?? [];
                        $oldFuelData = $oldDocData['spytrack']['fuelData'] ?? (object) [];
                        $legacyServers = $oldDocData['spytrack']['url'] ?? [];
                    }
                }

                // Format servers list for the legacy app schema
                if (isset($data['servers'])) {
                    $oldServers = [];
                    foreach ($data['servers'] as $srv) {
                        $oldServers[] = [
                            'name' => $srv['name'] ?? '',
                            'url' => $srv['url'] ?? '',
                            'type' => $srv['type'] ?? 'free',
                            'showBannerAds' => !empty($srv['show_ads']),
                            'message' => '',
                        ];
                    }
                } else {
                    $oldServers = $legacyServers;
                }

                $spytrackData = [
                    'name' => $data['app_name'] ?? $app->name,
                    'url' => $oldServers,
                    'ads' => (bool) ($data['settings']['show_ads'] ?? false),
                    'whatsapp' => $data['support']['whatsapp'] ?? '',
                    'phone' => $data['support']['phone'] ?? '',
                    'email' => $data['support']['email'] ?? '',
                    'adsfrequency' => (int) ($data['settings']['ads_frequency'] ?? 30),
                    'version' => $data['version'] ?? '1.0.0',
                    'banners' => $oldBanners,
                    'fuelData' => $oldFuelData,
                ];

                // Merge-set to preserve other legacy project-level keys
                $oldDocRef->set([
                    'spytrack' => $spytrackData
                ], ['merge' => true]);
            }

            // Clear cache after sync changes
            \Cache::forget('firestore_all_configs');
            \Cache::forget('firestore_apps_sync');
            \Cache::forget('firestore_spytrack_servers');
            \Cache::forget('app_config_custom_' . $app->package_name);

            return true;
        } catch (\Exception $e) {
            \Log::error("Firebase Sync Error for {$app->name}: " . $e->getMessage());
            throw $e;
        }
    }

    /**
     * Retrieve all config documents from the 'configs' collection.
     */
    public function getAllConfigs(): array
    {
        return \Cache::remember('firestore_all_configs', 86400, function() {
            try {
                $db = $this->getFirestore();
                $documents = $db->collection('configs')->documents();
                $configs = [];
                foreach ($documents as $document) {
                    if ($document->exists()) {
                        $configs[$document->id()] = $document->data();
                    }
                }
                return $configs;
            } catch (\Exception $e) {
                \Log::error("Firebase getAllConfigs Error: " . $e->getMessage());
                return [];
            }
        });
    }

    /**
     * Fetch raw servers list from configs/urls -> spytrack -> url array.
     */
    public function getSpytrackServers(): array
    {
        return \Cache::remember('firestore_spytrack_servers', 86400, function() {
            try {
                $db = $this->getFirestore();
                $docRef = $db->collection('configs')->document('urls');
                $snapshot = $docRef->snapshot();
                if ($snapshot->exists()) {
                    $data = $snapshot->data();
                    if (isset($data['spytrack']['url']) && is_array($data['spytrack']['url'])) {
                        return $data['spytrack']['url'];
                    }
                }
            } catch (\Exception $e) {
                \Log::error("Firebase getSpytrackServers Error: " . $e->getMessage());
            }
            return [];
        });
    }

    /**
     * Save the updated servers array back to configs/urls -> spytrack -> url.
     */
    public function saveSpytrackServers(array $servers): bool
    {
        try {
            $db = $this->getFirestore();
            $docRef = $db->collection('configs')->document('urls');
            
            // Format legacy and merge-save to keep other spytrack config properties
            $oldBanners = [];
            $oldFuelData = (object) [];
            $oldAds = true;
            $oldAdsFreq = 30;
            $oldWhatsApp = "";
            $oldPhone = "";
            $oldEmail = "";
            $oldVersion = "1.0.0";
            
            $oldSnapshot = $docRef->snapshot();
            if ($oldSnapshot->exists()) {
                $oldDocData = $oldSnapshot->data();
                if (isset($oldDocData['spytrack'])) {
                    $spy = $oldDocData['spytrack'];
                    $oldBanners = $spy['banners'] ?? [];
                    $oldFuelData = $spy['fuelData'] ?? (object) [];
                    $oldAds = isset($spy['ads']) ? (bool)$spy['ads'] : true;
                    $oldAdsFreq = isset($spy['adsfrequency']) ? (int)$spy['adsfrequency'] : 30;
                    $oldWhatsApp = $spy['whatsapp'] ?? "";
                    $oldPhone = $spy['phone'] ?? "";
                    $oldEmail = $spy['email'] ?? "";
                    $oldVersion = $spy['version'] ?? "1.0.0";
                }
            }

            $spytrackData = [
                'url' => $servers,
                'ads' => $oldAds,
                'adsfrequency' => $oldAdsFreq,
                'whatsapp' => $oldWhatsApp,
                'phone' => $oldPhone,
                'email' => $oldEmail,
                'version' => $oldVersion,
                'banners' => $oldBanners,
                'fuelData' => $oldFuelData,
            ];

            $docRef->set([
                'spytrack' => $spytrackData
            ], ['merge' => true]);

            // Clear cache
            \Cache::forget('firestore_spytrack_servers');
            \Cache::forget('firestore_all_configs');
            \Cache::forget('firestore_apps_sync');
            return true;
        } catch (\Exception $e) {
            \Log::error("Firebase saveSpytrackServers Error: " . $e->getMessage());
            throw $e;
        }
    }

    /**
     * Synchronize Firestore configs collection with local SQLite registry.
     */
    public function syncLocalDatabase(): void
    {
        $remoteConfigs = $this->getAllConfigs();
        if (empty($remoteConfigs)) {
            return;
        }

        // Fetch all local apps indexed by package name in a single query
        $localApps = WhitelabelApp::all()->keyBy('package_name');

        foreach ($remoteConfigs as $packageName => $docData) {
            if ($packageName === 'urls') {
                continue;
            }

            if (strpos($packageName, '.') !== false) {
                $appName = $docData['app_name'] ?? $packageName;
                $iosBundleId = $docData['policies']['ios_bundle_id'] ?? null;
                if (!$iosBundleId && isset($docData['ios_bundle_id'])) {
                    $iosBundleId = $docData['ios_bundle_id'];
                }

                $app = $localApps->get($packageName);
                if (!$app) {
                    WhitelabelApp::create([
                        'package_name' => $packageName,
                        'name' => $appName,
                        'ios_bundle_id' => $iosBundleId,
                    ]);
                } else {
                    $hasChanges = false;
                    if ($app->name !== $appName) {
                        $app->name = $appName;
                        $hasChanges = true;
                    }
                    if ($iosBundleId && $app->ios_bundle_id !== $iosBundleId) {
                        $app->ios_bundle_id = $iosBundleId;
                        $hasChanges = true;
                    }
                    if ($hasChanges) {
                        $app->save();
                    }
                }
            }
        }
    }
}
