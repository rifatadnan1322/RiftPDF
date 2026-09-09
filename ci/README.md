# Continuous integration

`release.yml` builds the macOS app and the Windows `.exe` on their own native
runners and attaches both to a GitHub release when a `v*` tag is pushed.

It is parked here rather than in `.github/workflows/` because pushing a
workflow file needs the `workflow` OAuth scope, which the token used to create
this repository does not carry. GitHub rejects the push outright:

```
refusing to allow an OAuth App to create or update workflow
.github/workflows/release.yml without `workflow` scope
```

## Activating it

```bash
gh auth refresh -s workflow          # opens a browser to grant the scope
mkdir -p .github/workflows
git mv ci/release.yml .github/workflows/release.yml
git commit -m "Enable release CI"
git push
git tag v1.0.1 && git push --tags    # builds and publishes both packages
```

Until then the macOS package is built locally by `build.sh`, and the Windows
package has to be built on a Windows machine with `python qt/build_windows.py`.
