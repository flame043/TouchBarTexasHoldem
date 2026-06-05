# TouchBar Texas Holdem

A local-only virtual-chip Texas Holdem practice game for MacBook Pro Touch Bar.

- No real money
- No online play
- No accounts
- No payments
- Virtual chips only

## Controls

- Left / Right: select action
- Up / Down: change raise amount
- Enter: confirm selected action
- Esc: fold, or quit on game over
- R: new hand / restart game
- Q: quit

## Build with GitHub Actions

1. Upload this repository to GitHub.
2. Open the repository page.
3. Go to **Actions**.
4. Select **Build macOS App**.
5. Click **Run workflow**.
6. Download the artifact named `TouchBarTexasHoldem-macOS-x86_64`.
7. Unzip it and open the app on your Mac.

If macOS blocks the app, right-click the app and choose **Open**. This build uses ad-hoc signing, not Apple Developer ID notarization.
