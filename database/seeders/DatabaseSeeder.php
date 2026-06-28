<?php

namespace Database\Seeders;

use App\Models\User;
use App\Models\WhitelabelApp;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    /**
     * Seed the application's database.
     */
    public function run(): void
    {
        // Create Admin User
        User::updateOrCreate(
            ['email' => 'admin@asthax.com'],
            [
                'name' => 'AsthaX Admin',
                'password' => Hash::make('admin1234'),
            ]
        );

        // Create Whitelabel App: Orbit GPS
        WhitelabelApp::updateOrCreate(
            ['package_name' => 'com.orbitgps.app'],
            [
                'name' => 'Orbit GPS',
                'ios_bundle_id' => 'com.orbitgps.app',
            ]
        );

        // Create Whitelabel App: Onfleet GPS
        WhitelabelApp::updateOrCreate(
            ['package_name' => 'com.onfleetgps.app'],
            [
                'name' => 'Onfleet GPS',
                'ios_bundle_id' => 'com.onfleetgps.app',
            ]
        );
    }
}
