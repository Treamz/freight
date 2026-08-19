# Releasing

Both packages are released the same way, independently: `freight` and
`freight_cli` carry their own versions and their own tags.

## The first publish of a package is manual

pub.dev authenticates the Publish workflow by its GitHub OIDC token rather than
a stored secret, and that has to be enabled per package under Admin on pub.dev —
which is only possible once the package exists. So the first version of each
package goes out by hand, and everything after it is automated.

## Steps

1. **Run the Release workflow** from the Actions tab, choosing the package and
   `patch`, `minor` or `major`. It names the version, renames `## Unreleased` in
   that package's CHANGELOG, bumps its pubspec, and pushes a
   `release/<package>-vX.Y.Z` branch.

   A pre-release version becomes the release it was heading for: `0.1.0-dev`
   releases as `0.1.0` rather than skipping to `0.1.1`.

2. **Open the pull request** from the link in the run summary, and let CI
   finish. The workflow does not open it on purpose: a pull request opened with
   a workflow's own token cannot start another workflow, so the release commit
   would otherwise be the only commit in the repository that nothing had
   checked.

3. **Merge it.**

4. **Tag the merge commit and push the tag**, as `<package>-vX.Y.Z`. The Publish
   workflow checks that the tag, the pubspec and the CHANGELOG all agree, then
   publishes.

   For a package's first version, publish by hand instead:
   `cd packages/<package> && flutter pub publish`. Then enable automated
   publishing on pub.dev so the workflow can take over.

Abandoning a prepared release costs nothing: delete the branch. `main` still
says `## Unreleased`, because the rename only ever happened on the branch.

## Never name a version in an ordinary pull request

`version:` in a pubspec is touched only by a release, and CHANGELOG entries go
under `## Unreleased`.

A branch that picks its own number is picking one it cannot know is still free
when it lands: release something else from `main` meanwhile and the number is
spent, while every check keeps passing, because the pubspec and the CHANGELOG
only ever agree with each other. Only pub.dev knows.

If a version turns out to be taken, do not move the published section. Give the
new work the next number and leave what was published byte-identical.

Publishing is irreversible and each version is spent for good. Approval to
publish one version is not approval to publish the next.
