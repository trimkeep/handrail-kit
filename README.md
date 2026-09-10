# Handrail

![CI](https://github.com/trimkeep/handrail-kit/actions/workflows/ci.yml/badge.svg)
![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Fail-closed tests](https://img.shields.io/badge/fail--closed-tested%20in%20CI-informational)

## What it is

Handrail is a small, dependency-free pack of six guardrail hooks for AI
coding-agent CLIs: shell scripts that inspect a tool call before it runs and
deny, ask-first, or step aside, so a destructive `rm -rf`, a force-push to
`main`, a stray read of `.env`, or a piped `curl | bash` doesn't happen just
because an agent proposed it. Handrail works with Claude Code hooks. Each
rule script is self-contained bash + jq, reads the tool call's JSON off
stdin, and only ever tightens what the agent is allowed to do — it never
grants permission on its own.

The six hooks in this repo are free (MIT). A paid early-access pack, Handrail v0.9, adds the full rule set for $19 one-time; what it contains, the refund terms and the checkout are under [Paid pack](#paid-pack).

## Docs

Docs and landing: https://trimkeep.github.io/handrail-kit/

## What it blocks / asks

- **destructive-shell** — blocks `rm -rf` / `rm -fr` in any flag order
  (bare, chained, inside a subshell, or `sudo`-prefixed), `mkfs`, `dd`
  writing to a block device, `shred`, redirecting into `/dev/sd*`, `chmod -R
  777 /`, and the classic fork bomb.
- **git-force-push** — blocks `git push --force` / `-f` /
  `--force-with-lease` / `--mirror` / `--delete` or a `+refspec` push,
  `git reset --hard`, `git clean -f`, `git branch -D` on `main`/`master`, and
  `git checkout -- .`; asks before any plain push straight to
  `main`/`master`.
- **secret-paths** — blocks reading or writing `.env` / `.env.*`, `*.pem`,
  `*.key`, `id_rsa*` / `id_ed25519*`, anything under a `secrets/` directory,
  `~/.aws/credentials`, or `~/.ssh/*`, whether the reference comes from a
  shell command or an edit's file path; also blocks writing content shaped
  like a live credential (an Anthropic-style API key, a Stripe live key, an
  AWS access key, a GitHub token, an xAI key, or a PEM private-key block).
- **prod-guard** — asks before a command that sets a production environment
  variable (`NODE_ENV=production`, `RAILS_ENV=production`, `ENV=prod`, ...),
  runs `kubectl apply` / `terraform apply`, passes `--prod` / `--production`,
  or runs a migration against a URL that looks like production; blocks
  `terraform destroy` and `kubectl delete namespace` outright.
- **publish-guard** — asks before `npm publish`, `pip`/`twine upload`,
  `cargo publish`, `gem push`, `docker push`, `gh release create`,
  `wrangler deploy`, `vercel --prod`, or `firebase deploy`; blocks
  `npm publish --access public` unless `HANDRAIL_ALLOW_PUBLISH=1` is set.
- **remote-exec** — blocks piping a remote download straight into an
  interpreter (`curl | bash`, `wget | sh`, `bash <(curl ...)`,
  `python -c "$(curl ...)"`, `eval "$(curl ...)"`) and `npx`/`pnpm dlx` of a
  bare URL; asks before `npx <pkg>` (or `pnpm dlx <pkg>`) when the package
  isn't pinned to an explicit version.

## Install as a Claude Code plugin

Handrail is also packaged as a Claude Code plugin, so the hooks can be enabled without
copying files into a project. In Claude Code:

```
/plugin marketplace add trimkeep/claude-plugins
/plugin install handrail@trimkeep
```

The plugin registers the same six hooks (`hooks/hooks.json`) against `${CLAUDE_PLUGIN_ROOT}`;
nothing is written into your repository. Disable or uninstall it from `/plugin` at any time.
Prefer copies you can read and edit in-repo? Use the script install below instead.

## Install in 2 minutes

No `curl | bash` here — Handrail blocks exactly that pattern, so it ships
the same way it expects everyone else to install things:

```sh
git clone <this-repo-url> handrail-kit
cd handrail-kit
./install.sh /path/to/your/project
```

`install.sh` copies the six hook scripts into
`<your-project>/.claude/hooks/handrail/`, `chmod +x`s them, and merges the
hooks block into `<your-project>/.claude/settings.json` — creating the file
if it doesn't exist, and otherwise backing the existing one up to
`.claude/settings.json.bak-<timestamp>` before editing it in place. Running
it again is a no-op if nothing changed. To remove Handrail, run
`./uninstall.sh /path/to/your/project` from this directory — it deletes the
copied hooks and restores the backed-up `settings.json` (or, if there was
never a prior file to back up, strips just Handrail's own entries back out).

Prefer to wire it up by hand? `settings.example.json` in this repo is the
exact hooks block `install.sh` writes — copy the pieces you want into your
own `.claude/settings.json`.

## Fail-closed and only-tightens

Every hook is written so that anything it doesn't understand is treated as
dangerous, not safe: missing `jq`, empty stdin, stdin that isn't valid JSON,
or a tool call with no `tool_input` all make the hook deny (exit 2) rather
than pass the call through. And every hook only ever *removes* permission —
it denies outright, or asks the human to confirm; none of the six scripts
ever emits a decision that grants permission on its own. `test/hooks.test.js`
asserts both properties directly, per hook, against the fixtures in
`test/fixtures/`: every dangerous fixture is denied or asked, every benign
fixture is allowed, all four fail-closed conditions produce a denial, and a
full sweep of every shipped fixture confirms no hook ever prints an "allow"
decision. Run `npm test` to see it for yourself.

## Paid pack

The pack in this repo is free and always will be. A paid early-access pack (v0.9) adds the full rule set — protected-path guard, per-role write scopes, secret detection in edits, a wider dangerous-command matrix — with v1.0 shipping to every buyer within 14 days of purchase and 12 months of updates.

Handrail v0.9 — early-access price: $19 one-time. Early access is limited to the first 20 buyers; when it closes, this page will say so — no live counter, no countdown. Handrail v0.9 comes with a voluntary 14-day, no-questions refund, processed through Polar in addition to — not in place of — any statutory withdrawal right shown at checkout; refunds deactivate your licence key.

Buy early access ($19): https://buy.polar.sh/polar_cl_FVHg2M2c1DNYFiXqJN3IBELAHNwQ4XQDkkDwg25nonO — checkout runs on Polar, the merchant of record. Docs: https://trimkeep.com/handrail-kit/

Handrail is a defence-in-depth layer — it reduces risk but does not eliminate it, is not a security audit or certification, and does not replace backups, code review, or your own judgment.

Everything runs locally: secret detection, command checks and every decision happen on your machine; no scan result, prompt content, command, file path or file content is transmitted to us or anyone else.

Handrail works with Claude Code and other agent CLIs in plain text only; it is not affiliated with, endorsed by, or a product of Anthropic.

## Supported versions

See [`SUPPORTED_VERSIONS.md`](./SUPPORTED_VERSIONS.md).

## Licence

MIT — see [`LICENSE`](./LICENSE). Provenance of every shipped file is listed
in [`PROVENANCE.md`](./PROVENANCE.md).
