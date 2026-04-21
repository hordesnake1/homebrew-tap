# homebrew-tap

Local Homebrew tap for apps not published in official Homebrew repositories.

## Add tap locally

```bash
brew tap dyakovlev/local /Users/dyakovlev/homebrew-tap
```

## Install

```bash
brew install --cask dynamicnotch
```

## Update when upstream releases a new version

```bash
/Users/dyakovlev/homebrew-tap/bin/update-dynamicnotch
cd /Users/dyakovlev/homebrew-tap
git add Casks/dynamicnotch.rb
git commit -m "chore(dynamicnotch): bump to <version>"
git push
brew update
brew upgrade --cask dynamicnotch
```

If this tap is pushed to GitHub as `dyakovlev/homebrew-tap`, Homebrew update flows work normally after each tap update.
