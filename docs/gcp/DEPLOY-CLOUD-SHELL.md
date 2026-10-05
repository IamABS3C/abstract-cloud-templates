# The Open in Cloud Shell button

## What it actually is

GCP has no "Deploy to Google Cloud" button in the sense Azure has one. Azure's button
posts an ARM template to the portal and renders a parameter form. **Google's equivalent is
Open in Cloud Shell**, and it works differently — it is not a form, it is a terminal.

For this job it is the better mechanism, because a log sink is a sequence of dependent
steps with decisions in between, not a set of parameters.

## What happens when a customer clicks it

1. **Cloud Shell opens in their browser**, already authenticated as whoever is signed in
   to the Google Cloud console. No `gcloud auth login`, no key, no local install.
2. **This repository is cloned** into their Cloud Shell home directory.
3. **The working directory is set** to the deployment they picked, from
   `cloudshell_workspace`.
4. **The tutorial opens in a side panel**, from `cloudshell_tutorial`, next to a live
   terminal. Code blocks in the tutorial have a copy-to-terminal button.
5. Nothing runs. **The customer is in control of every command.**

Cloud Shell provides a Debian VM with `gcloud`, `terraform`, Python and an editor
preinstalled, and 5 GB of persistent home directory.

## The URL, and the one parameter that is easy to get wrong

```
https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/IamABS3C/abstract-cloud-templates&cloudshell_git_branch=main&cloudshell_workspace=templates/gcp/gcp-source-audit-logs-organization&cloudshell_tutorial=TUTORIAL.md
```

> **`cloudshell_tutorial` is resolved RELATIVE TO `cloudshell_workspace`, not to the
> repository root.** Google's docs: *"If the working_dir param is provided, the path to
> this file is treated as relative to working_dir."*
>
> Writing `cloudshell_tutorial=templates/gcp/gcp-source-audit-logs-organization/TUTORIAL.md` alongside
> `cloudshell_workspace=templates/gcp/gcp-source-audit-logs-organization` resolves to
> `templates/gcp/gcp-source-audit-logs-organization/templates/gcp/gcp-source-audit-logs-organization/TUTORIAL.md`, and the tutorial
> silently fails to load while the terminal still opens. **This repo shipped that bug.**
> Checking the raw GitHub URL does not catch it — that path exists; it is just not the
> path Cloud Shell uses.

| Parameter | Purpose |
|---|---|
| `cloudshell_git_repo` | Repository to clone. **Must be public** — Cloud Shell clones anonymously |
| `cloudshell_workspace` | Directory to open the terminal in |
| `cloudshell_tutorial` | Tutorial file, **relative to the workspace** |
| `cloudshell_git_branch` | Branch. **Always set `main`**: Cloud Shell defaults to `master`, which this repository does not have, and without it the button opens an empty shell with nothing cloned |
| `ephemeral` | Discard the VM at session end |
| `show` | `ide`, `terminal`, or `ide%2Cterminal` |

## The session is temporary

Google opens a repository it does not own in a **temporary** Cloud Shell environment: it
has none of your credentials, and its home directory is deleted when the session ends.
So every tutorial starts by signing in (`gcloud auth login`, then
`gcloud auth application-default login` for Terraform), and every Terraform template needs
its `backend.tf` in place before `apply`, or the state disappears with the session.

## Adding a button for a new deployment

1. Create `templates/gcp/gcp-source-audit-logs-organization/` with `main.tf`, `variables.tf`, `outputs.tf`.
2. Add `TUTORIAL.md` **in that same directory**.
3. Add a row to the README table:

```markdown
[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/IamABS3C/abstract-cloud-templates&cloudshell_git_branch=main&cloudshell_workspace=templates/gcp/gcp-source-audit-logs-organization&cloudshell_tutorial=TUTORIAL.md)
```

**Verify the resolved path, not the repo path:**

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/templates/gcp/gcp-source-audit-logs-organization/TUTORIAL.md
```

## Tutorial markup

Cloud Shell tutorials are Markdown plus a few tags:

| Tag | Effect |
|---|---|
| `<walkthrough-tutorial-duration duration="15"/>` | Shows an estimated time |
| `<walkthrough-project-setup/>` | Renders a project picker |
| `<walkthrough-project-id/>` | Substitutes the chosen project ID |
| `<walkthrough-info-message>…</walkthrough-info-message>` | Highlighted callout |
| `<walkthrough-conclusion-trophy/>` | End-of-tutorial marker |

`##` headings become steps with Next/Back navigation, so heading structure *is* the step
structure — renumbering headings renumbers the walkthrough.

## When NOT to use the button

- **The customer has an IaC practice.** Give them the repo and let their pipeline run it,
  so state and plan live in their CI rather than in someone's Cloud Shell.
- **Deployment must be auditable and repeatable.** Use Infrastructure Manager — see
  [DEPLOY-INFRA-MANAGER.md](DEPLOY-INFRA-MANAGER.md).
- **The repo is private.** The button cannot clone it.
