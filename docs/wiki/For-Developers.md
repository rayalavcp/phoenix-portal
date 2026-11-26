# For developers

Phoenix Portal is a Flutter app (`app/`) with native Android code (Kotlin), a remote admin in
plain JavaScript (`app/remote-ui`), Phoenix Control (`control/`) and provisioning scripts.

Everything a developer, or an AI coding agent such as Cursor or Claude Code, needs is in
[HANDOFF.md](https://github.com/rayalavcp/phoenix-portal/blob/main/HANDOFF.md):

- where every feature lives in the code;
- the toolchain (Flutter 3.44.6, Java 21, Android SDK 36, Node 22);
- **the signing key** set-up (`app/android/key.properties`, never committed): a build signed
  with another key cannot update the Portals;
- building, testing and **releasing** (`install/make_releases.py`, `install/publish_release.sh`
  and the Phoenix release workflow);
- the project's rules (nothing sent to the original project, keep the licence and credits, the
  calm look, ask before changing a device);
- open decisions and known flaky tests.

Cursor loads `.cursor/rules/phoenix-portal.mdc`; other agents start at `AGENTS.md`.

Work happens on `main`. Builds ship as GitHub Releases; APKs are never committed.
