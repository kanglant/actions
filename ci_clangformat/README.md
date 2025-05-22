# CI Clang-format

This composite action helps maintain consistent C/C++ code style by running
`clang-format` on modified files in your pull requests. It checks for
formatting violations and will cause the workflow to fail if any issues are
found, ensuring code quality before merging.

The action uses your .clang-format style file if present in the repository
root; otherwise, it will use the .clang-format.default under this folder.

This action offers the following configuration through its inputs:
* `clang_format_version`: Choose the exact clang-format version to use,
 with `20.1.5` as the default to align with recent stable releases.
* `branch_name`: Specify the name of your repository branch (`main` by
 default) for comparing changes within the pull requests.

## Resolving Formatting Failures
If a workflow run fails due to formatting violations, you're expected to
fix the issues locally. Simply run `clang-format` on the problematic
files, e.g., using
`pipx run clang-format==20.1.5 --style=file --Werror -i <files>`,
and then commit the formatted code to your pull request.

## Pipx Requirement
This action leverages `pipx` to reliably install and run specific
`clang-format` versions, ensuring consistent behavior across different
environments. `pipx` is generally pre-installed on GitHub Actions hosted
runners (you can verify available tools on the runner images [doc](https://github.com/actions/runner-images?tab=readme-ov-file#available-images)).
If `pipx` does not exist, you'll need to include a step to install it
in your workflow's running environment.
