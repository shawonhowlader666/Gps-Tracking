var SERVER_URL = [];
var BANNER_IMAGE = [];
Map<String, dynamic> fuelData = {};
var APP_VERSION = '';
var APP_NAME = "SP TRACK GPS";
var TERMS_AND_CONDITIONS = "https://cayon-1743949692657.staticrun.app";
var PRIVACY_POLICY = "https://bubble-1743950721625.staticrun.app";
var WHATS_APP = "";
var PHONE_NO = "";
var EMAIL = "";
int adsFrequency = 2;
bool SHOW_ADS = true;
bool ALWAYS_SHOW_BANNER_ADS = false;

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
