# homebrew-tap

Local Homebrew tap for apps not published in official Homebrew repositories.

## Repository name

Publish this directory as GitHub repository named `homebrew-tap` under your account, for example:

- `https://github.com/dyakovlev/homebrew-tap`

## Add tap

```bash
brew tap dyakovlev/local https://github.com/dyakovlev/homebrew-tap
```

For local testing before pushing:

```bash
brew tap dyakovlev/local /Users/dyakovlev/homebrew-tap
```

## Install

```bash
brew install --cask dynamicnotch
```

## Upgrade flow

Once the tap repo is pushed to GitHub and GitHub Actions are enabled:

1. The workflow checks upstream `jackson-storm/DynamicNotch` releases every 6 hours.
2. When a new release appears, the tap updates `Casks/dynamicnotch.rb` and pushes a commit.
3. On your Mac, normal Homebrew update flow works:

```bash
brew update
brew upgrade --cask dynamicnotch
```

If you use `brew-cask-upgrade`:

```bash
brew cu -a -f
```

## Manual bump

```bash
/Users/dyakovlev/homebrew-tap/bin/update-dynamicnotch
```

## Notes

- `sha256 :no_check` is used because the asset URL changes per release and this is a fast-moving third-party cask.
- `livecheck` is configured in the cask, so Homebrew can detect the latest GitHub release version.
