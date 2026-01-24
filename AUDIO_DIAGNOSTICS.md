# Audio Playback Diagnostics Guide

## What Changed

Enhanced `NativeAudioPlayer.swift` with comprehensive diagnostic logging to identify why audio doesn't play or background.

## Key Diagnostic Outputs to Watch For

When you rebuild and test, **watch the Xcode console** for these logs:

### 1. **During setQueue()** - URL Loading
```
🎧 [NativeAudioPlayer] setQueue() called with N urls
   ↳ queue URL: https://supabase-url...
📊 [NativeAudioPlayer] KVO observers added to item 0
✅ [NativeAudioPlayer] Queue created with 1 AVPlayerItem(s)
```

**What you're looking for:**
- If URLs are logged correctly ✅
- If KVO observers attached successfully ✅

### 2. **During play()** - Player State Transitions
```
▶️ [NativeAudioPlayer] play() called from JS
🔊 [NativeAudioPlayer] Setting audio session to .playback (most background-compatible)
✅ [NativeAudioPlayer] Audio session configured for pure playback

📊 [NativeAudioPlayer] Player state BEFORE play():
   ↳ volume: 1.0
   ↳ rate: 0.0
   ↳ timeControlStatus: 0 (0=paused, 1=waitingToPlayAtSpecifiedRate, 2=playing)
   ↳ currentItem status: 0 (0=unknown, 1=ready, 2=failed)
```

**Critical check:**
- `currentItem status: 0` = item not loaded yet (normal, will become 1)
- `currentItem status: 1` = item ready ✅
- `currentItem status: 2` = item FAILED TO LOAD ❌ (this is likely your issue)

After `player.play()` is called:
```
✅ [NativeAudioPlayer] player.play() called
📊 [NativeAudioPlayer] Player state AFTER play():
   ↳ rate: 1.0
   ↳ timeControlStatus: 1 (0=paused, 1=waitingToPlayAtSpecifiedRate, 2=playing)
   ✅ Player is WAITING (likely buffering audio from URL)
```

**Critical check:**
- `timeControlStatus: 2` = PLAYING ✅
- `timeControlStatus: 1` = WAITING/BUFFERING ✅ (normal during load)
- `timeControlStatus: 0` = PAUSED ❌ (playback didn't start)
- `rate: 0.0` = NOT PLAYING ❌

### 3. **Item Status Changes** - URL Loading Success/Failure
These appear AFTER play() as the player loads the audio:

**Success case:**
```
✅ [NativeAudioPlayer] Item status changed to: READY TO PLAY
   ↳ URL loaded from: 52.7.174.102 (or similar IP)
```

**Failure case:**
```
❌ [NativeAudioPlayer] Item status changed to: FAILED
   ↳ Error: The operation couldn't be completed. (NSURLErrorDomain error -1200.)
   ↳ Error code: -1200
   ↳ Error domain: NSURLErrorDomain
```

## Common Error Codes & Meanings

| Code | Meaning | Common Cause |
|------|---------|-------------|
| -1200 | SSL/Certificate error | Supabase URL has SSL issue on iOS |
| -1001 | Timeout | Network too slow or URL unreachable |
| -1004 | Cannot connect to host | DNS or network issue |
| -1022 | HTTPS not allowed | App Transport Security blocking request |

## Diagnostic Workflow

### Step 1: Test Question Playback
1. Start study session
2. Look at console for `🎧 [NativeAudioPlayer] setQueue()` log
3. Note the URL being loaded
4. Look for `✅ Item status changed to: READY TO PLAY` or `❌ FAILED`

### Step 2: If Status is READY TO PLAY
1. Audio URL loaded successfully ✅
2. Look for `timeControlStatus: 2` (playing) or `timeControlStatus: 1` (waiting/buffering)
3. **Do you hear audio?** 
   - YES → Issue is background continuation
   - NO → Issue is something else (volume muted? speaker not working?)

### Step 3: If Status is FAILED with SSL Error
1. Supabase URL has SSL certificate issue on iOS
2. Try testing with a different audio source (e.g., Apple's example MP3)
3. May need to add App Transport Security exception

### Step 4: If Item Never Changes to READY or FAILED
1. URL might be malformed
2. Network request might be hanging
3. Check if rate is set to 1.0 after play()

## Testing URL Directly

If you see SSL errors, test the Supabase URL directly:
```bash
curl -v "https://YOUR_SUPABASE_URL/storage/v1/object/public/..."
```

If curl works but iOS fails → ATS (App Transport Security) issue

## Expected Log Sequence (Success Case)

```
🎧 [NativeAudioPlayer] setQueue() called with 1 urls
   ↳ queue URL: https://...
📊 [NativeAudioPlayer] KVO observers added to item 0
✅ [NativeAudioPlayer] Queue created with 1 AVPlayerItem(s)

[User taps play]

▶️ [NativeAudioPlayer] play() called from JS
🔊 [NativeAudioPlayer] Setting audio session to .playback
✅ [NativeAudioPlayer] Audio session configured for pure playback
📊 [NativeAudioPlayer] Player state BEFORE play():
   ↳ timeControlStatus: 0 (paused, not loaded yet)
   ↳ currentItem status: 0 (unknown, loading)
✅ [NativeAudioPlayer] player.play() called
📊 [NativeAudioPlayer] Player state AFTER play():
   ↳ rate: 1.0
   ↳ timeControlStatus: 1 (waiting/buffering)

[A moment later, URL loads]

✅ [NativeAudioPlayer] Item status changed to: READY TO PLAY
   ↳ URL loaded from: 52.7.174.102

[Audio plays]
```

## Expected Log Sequence (Failure Case - SSL Error)

```
🎧 [NativeAudioPlayer] setQueue() called with 1 urls
✅ [NativeAudioPlayer] Queue created with 1 AVPlayerItem(s)

[User taps play]

▶️ [NativeAudioPlayer] play() called from JS
✅ [NativeAudioPlayer] Audio session configured for pure playback
📊 [NativeAudioPlayer] Player state AFTER play():
   ↳ rate: 1.0
   ↳ timeControlStatus: 1 (trying to load)

[A moment later, URL fails to load]

❌ [NativeAudioPlayer] Item status changed to: FAILED
   ↳ Error: The operation couldn't be completed. (NSURLErrorDomain error -1200.)
   ↳ Error domain: NSURLErrorDomain

[No audio plays]
```

## Next Steps Based on Findings

**If logs show READY TO PLAY but no audio heard:**
- Check if device volume is up
- Check if silent switch is off
- Issue is likely background continuation (needs testing with app backgrounded)

**If logs show FAILED with SSL error:**
- Add ATS exception in Info.plist
- Or use alternative audio host (CloudFront, S3 with proper certs)

**If logs show rate: 0.0 or timeControlStatus: 0:**
- Audio session setup might be interfering
- May need to debug audio session category/mode

**If no logs appear at all:**
- Plugin might not be loading
- Check that app.html is calling `NativeAudioPlayer.setQueue()` correctly
