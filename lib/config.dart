var SERVER_URL = [];
var BANNER_IMAGE = [];
Map<String, dynamic> fuelData = {};
var APP_VERSION = '';
var APP_NAME = "ONFLEET GPS";
var TERMS_AND_CONDITIONS = "https://cayon-1743949692657.staticrun.app";
var PRIVACY_POLICY = "https://bubble-1743950721625.staticrun.app";
var WHATS_APP = "";
var PHONE_NO = "";
var EMAIL = "";
int adsFrequency = 2;
bool SHOW_ADS = true;
bool ALWAYS_SHOW_BANNER_ADS = false;

// AdMob Test IDs
const String ADMOB_APP_ID = 'ca-app-pub-3231110074331419~8479601102';
const String BANNER_AD_ID = 'ca-app-pub-3231110074331419/1828015542';
const String INTERSTITIAL_AD_ID = 'ca-app-pub-3231110074331419/1648972019';
const String REWARDED_AD_ID = 'ca-app-pub-3231110074331419/1333277240';

// System controls from Firestore
bool globalMaintenanceEnabled = false;
String globalMaintenanceMessage = "";
bool forceUpdateEnabled = false;
String forceUpdateVersion = "";
String forceUpdateUrl = "";
String forceUpdateMessage = "";

// Payment Numbers overrides
String bkashNumber = "";
String nagadNumber = "";
String rocketNumber = "";
