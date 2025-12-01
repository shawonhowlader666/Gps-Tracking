import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../config.dart';

class AdMobService {
  static final AdMobService _instance = AdMobService._internal();
  factory AdMobService() => _instance;
  AdMobService._internal();

  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  int _interstitialCounter = 0;
  int _rewardedCounter = 0;
  int _adFrequency = 1;

  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    _loadInterstitialAd();
    _loadRewardedAd();
    _setAdFrequency();
  }

  void _setAdFrequency() {
    _adFrequency = adsFrequency;
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: INTERSTITIAL_AD_ID,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          print("Interstitial ad loaded");
          _interstitialAd = ad;
        },
        onAdFailedToLoad: (error) {
          print("Interstitial ad load error: $error");
          _interstitialAd = null;
        },
      ),
    );
  }

  void _loadRewardedAd() {
    RewardedAd.load(
      adUnitId: REWARDED_AD_ID,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
        },
        onAdFailedToLoad: (error) {
          _rewardedAd = null;
        },
      ),
    );
  }

  void showInterstitialAd({bool ignoreFrequency = false}) {
    if (!SHOW_ADS) return;

    bool shouldShowAd = ignoreFrequency ||
        _adFrequency == 0 ||
        _interstitialCounter % (_adFrequency + 1) == 0;

    if (shouldShowAd && _interstitialAd != null) {
      _interstitialAd!.show();
      _loadInterstitialAd(); // Load next ad
    }

    _interstitialCounter++;
  }

  Future<bool> showRewardedAd({
    required Function(RewardItem) onRewarded,
    required Function() onFailed,
    bool ignoreFrequency = false,
  }) async {
    if (!SHOW_ADS) return false;

    bool shouldShowAd = ignoreFrequency ||
        _adFrequency == 0 ||
        _rewardedCounter % (_adFrequency + 1) == 0;

    if (shouldShowAd && _rewardedAd != null) {
      _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _loadRewardedAd();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _loadRewardedAd();
          onFailed();
        },
      );

      _rewardedAd!.show(
        onUserEarnedReward: (ad, reward) {
          onRewarded(reward);
        },
      );

      _rewardedCounter++;
      return true;
    }

    _rewardedCounter++;
    return false;
  }
}
