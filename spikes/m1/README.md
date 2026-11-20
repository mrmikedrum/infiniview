# Milestone 1 spike (throwaway)

Proves the mechanisms in the spec's milestone 1. Results: [docs/research/milestone-1-spikes-2026-11.md](../../docs/research/milestone-1-spikes-2026-11.md).

- `./build.sh` builds `InfiniviewSpike.app` (two preview extensions), `QLProbe.app` and `learn`, then installs the app to `~/Applications`.
- `build/learn "<helper.app>" ext...` rewrites the Learned Type helper and re-registers it.
- `build/QLProbe.app/Contents/MacOS/QLProbe file...` previews files in a `QLPreviewView`. With no arguments, it reads paths from stdin.
- `./uninstall.sh` removes it all. Run this before installing Infiniview itself: the spike also claims `public.data`.
