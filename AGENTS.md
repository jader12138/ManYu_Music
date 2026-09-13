# Repository Workflow Rules

These instructions are mandatory for every coding task in this repository.

## Branch Policy

- Never develop features directly on `main`.
- Before making changes, fetch the latest `origin` and create a branch from `main` using the `codex/<short-feature-name>` naming pattern.
- Keep each feature or fix isolated on its own branch.
- Commit and push the feature branch to GitHub when a coherent milestone is complete.
- Do not merge into `main` until the user explicitly approves the merge.
- Do not create a release tag or publish a release until the user explicitly approves publication.

## Merge Reminder

- At the end of every work session, report the current branch and whether it is still unmerged.
- When a feature or fix is complete, explicitly remind the user that the branch is ready to merge and wait for approval.
- If the same `codex/*` branch remains unmerged for more than three days, prominently remind the user again.
- Never assume that silence means approval.

## Documentation Requirement

Every functional update must include documentation in the same branch:

- Update `CHANGELOG.md` with a concise description of the user-visible change.
- Update `README.md` or the relevant file under `docs/` when behavior, workflow, setup, or usage changes.
- Keep `VERSION` and the release tag consistent when preparing a release.
- Include the documentation changes in the same commit or pull request as the functional change.

## Verification Before Merge

Before asking for merge approval:

- Build the project successfully.
- Build or validate the macOS app bundle when app behavior changes.
- Verify the app signature when packaging changes.
- Report the branch name, commit hash, changed files, tests performed, and any remaining risks.
- Confirm that the feature branch is based on the latest `main`.

## Release Policy

After explicit approval only:

1. Merge the approved `codex/*` branch into `main`.
2. Update `VERSION` and `CHANGELOG.md`.
3. Build and verify the release.
4. Create an annotated version tag.
5. Push `main` and the tag to GitHub.
6. Verify the remote branch and tag with `git ls-remote`.
