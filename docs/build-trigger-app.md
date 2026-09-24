# KindlyOps build-trigger App

A public source repository requests a release using a GitHub-hosted workflow. An organization-owned
GitHub App authenticates the cross-repository dispatch. The private build repository validates the
source SHA on a hosted runner before any source code runs on the self-hosted signing Mac.

## Registration

The KindlyOps App is [KindlyOps Build Trigger](https://github.com/apps/kindlyops-build-trigger).
Its App ID is `5060909` and its Client ID is `Iv23liRAIl0BmIWjxpim`; these identifiers are public.
Organization owners can manage it in
[App settings](https://github.com/organizations/kindlyops/settings/apps/kindlyops-build-trigger).
Reuse this registration for builders in the same trust boundary. For a separate registration:

Create **KindlyOps Build Trigger** in KindlyOps → Settings → Developer settings → GitHub Apps.
Use `https://github.com/kindlyops` as its homepage, disable webhooks, leave OAuth callbacks and
user authorization off, and allow installation **only on this account**.

Grant only **Repository permissions → Actions: read and write**. GitHub adds mandatory Metadata
read access. No Contents, Workflows, organization, or account permissions are needed. Actions write
can manage runs and artifacts as well as dispatch jobs; GitHub has no dispatch-only permission.
Install the App on **selected repositories**, initially `kindlyops/artprep-build` only.

Generate a private key in the App's settings. Save it in a password manager or other secure secret
store. Do not commit it or paste it into a chat, issue, or workflow file. A client secret is not
needed. The official token action signs a JWT with the App private key, requests an installation
token restricted to the named builder, and revokes the token when the dispatch job finishes.

## Configure the public source repository

Create a GitHub Actions environment named **build-trigger**, restricted to deployment from the
`main` branch only. Store the complete PEM as its environment secret
**KINDLYOPS_BUILD_APP_PRIVATE_KEY**. Set the repository variable **KINDLYOPS_BUILD_APP_CLIENT_ID**
to the App's Client ID. This keeps the key out of workflows running on other branches. The release
workflow uses that environment and never checks out or executes source code.

With the GitHub CLI signed in, store the downloaded PEM without printing its contents:

```bash
gh secret set KINDLYOPS_BUILD_APP_PRIVATE_KEY \
  --repo kindlyops/artprep \
  --env build-trigger \
  < "/path/to/downloaded-private-key.pem"
```

Replace the placeholder path with the downloaded file's path. Verify that the secret exists with
`gh secret list --repo kindlyops/artprep --env build-trigger`; GitHub does not return its contents.

The workflow requests only Actions write for `artprep-build` and dispatches the builder's
`release.yml` on `main` with `source_sha` set to the public event SHA. The App need not be installed
on the public source repository. No webhook server or polling service is needed.

## Reuse for another KindlyOps project

1. Create a private build repository, with protected `main` and reviewed release controls.
2. Install this App on that selected private builder.
3. Configure the public source's protected `build-trigger` environment, PEM secret, and Client ID.
4. Copy the public dispatch workflow, changing the source repository guard and target builder.
5. Adapt the private workflow to a fixed source repository. Keep the full-SHA and main-ancestry
   validation before the self-hosted job, exact source checkout, and main-only event guards.
6. Add only that private workflow at `refs/heads/main` to the runner group's workflow allowlist.

Anyone with the App private key can mint tokens for all repositories on which the App is installed.
Per-job token scoping limits the normal job token, not a stolen private key. Share this App only
among source maintainers who belong to the same trust boundary. Use separate Apps for projects
that need isolation. Protect source `main` because merged source executes on the signing runner.

## Verify and rotate

After configuring the App and merging both workflows, run **Request macOS release** on public
`main`. Verify a corresponding private run, successful hosted validation, and Mac assignment.
An invalid or unmerged SHA must fail in the hosted validation job without allocating the Mac.
A successful dispatch does not mean the build or Apple notarization succeeded; inspect the
private run and the public release separately.

For rotation, generate a new key, replace the selected environment secrets, verify dispatches,
then revoke the old key. Removing an installation stops that builder from accepting App tokens.

References: [GitHub App authentication in Actions](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/making-authenticated-api-requests-with-a-github-app-in-a-github-actions-workflow),
[official token action](https://github.com/actions/create-github-app-token), and
[runner group access controls](https://docs.github.com/en/enterprise-cloud@latest/actions/how-tos/manage-runners/self-hosted-runners/manage-access).
