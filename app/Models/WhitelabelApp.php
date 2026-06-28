<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class WhitelabelApp extends Model
{
    protected $fillable = [
        'name',
        'package_name',
        'ios_bundle_id',
        'firebase_credential_path',
    ];
}
