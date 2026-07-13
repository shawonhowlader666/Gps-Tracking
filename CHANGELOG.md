# Changelog

## [1.0.0+7] - 2026-07-13

### Added
- Integrated dynamic billing packages fetched from the server.
- Integrated Tracksolid Pro API support.
- Added full support for Bengali translations throughout the app.

### Changed & Improved
- **Direct WhatsApp Chat:** Optimized WhatsApp payment button to directly open WhatsApp chat with pre-filled message, bypassing the OS Share Sheet selection popup.
- **Dynamic Discount calculation:** Fixed the discount percentage displaying bug (previously showed raw discount amount like 50% instead of correct calculation 17%).
- **Faster Startup:** Optimized splash screen timing (reduced minimum wait time from 2s to 800ms) for a faster, snappy startup.
- **Dismissible Popups:** Improved billing expiration check and payment dialogs to be easily dismissible.

### Fixed
- Fixed playback screen ticker crashes.
- Fixed engine lock/unlock status sync issues with instant UI updates.
- Fixed device identifier (email/username) corruption issues by adding sanitization logic.
- Solved Android APK build output folder path resolution issue.
- Fixed map marker sizing and duplicate Km unit bugs.

---

## Play Store Release Notes / What's New (Copy-Paste)

### English (en-US)
- Directly chat on WhatsApp for manual payment confirmation (no more share sheet popups).
- Fixed package discount percentage displaying correctly.
- Improved app startup speed and splash screen load times.
- Added support for new GPS tracking devices.
- Fixed engine lock/unlock status syncing and other minor bugs.

### Bengali (bn-BD)
- ম্যানুয়াল পেমেন্ট কনফার্মেশনের জন্য এখন সরাসরি হোয়াটসঅ্যাপ চ্যাট ওপেন হবে (কোনো শেয়ার শিট পপআপ আসবে না)।
- প্যাকেজ ডিসকাউন্ট পার্সেন্টেজ সঠিকভাবে দেখার সুবিধা যুক্ত করা হয়েছে।
- অ্যাপ ওপেনিং স্পিড ও স্প্ল্যাশ স্ক্রিনের লোডিং টাইম কমানো হয়েছে।
- নতুন জিপিএস ট্র্যাকিং ডিভাইসের সাপোর্ট ও ইঞ্জিন লক/আনলক স্ট্যাটাসের বাগ ফিক্স করা হয়েছে।
