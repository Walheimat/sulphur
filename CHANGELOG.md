# Changelog

## [0.8.0](https://github.com/Walheimat/bydi/compare/v0.7.0...v0.8.0) (2024-08-30)


### Features

* **calling-macros:** use keyword argument for clear ([a4a3a3d](https://github.com/Walheimat/bydi/commit/a4a3a3dd7338b8f9f82bfca8b086b5cc703ff7aa))
* **mock:** allow sharing history between bydi forms ([4409d4a](https://github.com/Walheimat/bydi/commit/4409d4a1281dfe5da32d5bf67eeb81e662a768ed))
* **volatile:** allow sharing volatility ([e69c82d](https://github.com/Walheimat/bydi/commit/e69c82dbd35caf1f8dc073796b3dac3045a5b824))

## [0.7.0](https://github.com/Walheimat/bydi/compare/v0.6.5...v0.7.0) (2024-03-01)


### Features

* **mock:** add keyword :var ([fe2d75c](https://github.com/Walheimat/bydi/commit/fe2d75cd6b190a21b75685cc54c836e690f35eb8))

## [0.6.5](https://github.com/Walheimat/bydi/compare/v0.6.4...v0.6.5) (2024-01-27)


### Features

* **ci:** release job ([5f30a1d](https://github.com/Walheimat/bydi/commit/5f30a1dcf699e4be172df4dab513463741f491b3))

## [0.6.4]

### Added

- Keyword `:fail` can be used to have a function fail. By default it
  uses `signal` passing `'(error "Lisp error")` but what is used can
  be set using `:with` and what is passed using `:args`.

### Changed

- `bydi-when` now uses keywords. This is a breaking change.

## [0.6.3]

### Fixed

- `bydi-mock--volatile` no longer returns the resut of `memq` which
  can mess up tests. Instead it returns `t` or `nil`.g

## [0.6.2]

### Added

- Macro `bydi-when` that allows selectively returning mock values for
  function that are spied upon with `:spy`.

## [0.6.1]

### Added

- Volatile functions (using `:sometimes` or `:othertimes`) now can be
  individually toggled using `bydi-toggle-volatile`.

### Changed

- `bydi-toggle-sometimes` now only clears mocks for functions using
  `:sometimes` or `:othertimes`.

## [v0.6.0]

### Changed

- Submodules `bydi-ci` and `bydi-report` were removed since they now
  are part of `dinghy` as `dinghy-rope`.

## [v0.5.5]

### Added

- Function `bydi-report-setup-ert` that accepts key
  `:increase-print-depth` to do just that.

### Fixed

- `bydi-ci` now requires `bydi` and `bydi` requires `ert`.
- The explainer for `bydi-match-expansion` now shows actual value as
  actual and expected as expected.

## [v0.5.4]

### Added

- Command `bydi-report-find-test-helper` to find the test helper
  `ert-runner` uses.
- Explainers for `bydi-was{-not}-called` and `bydi-was{-not}-called`
  should be more useful now.

## Fixed

- The package name in the Makefile.
- The execution of `bydi` is now wrapped by special form
  `unwind-protect` to avoid a faulty test from breaking other tests.

## [v0.5.3]

### Fixed

- Explainer for `bydi-matches-expansion` includes the expanded form.

## [v0.5.2]

### Added

- Macros `bydi-was-called{-with}` now accept an optional
  {second,third} argument to clear the mocks for that very function.
- Macros `bydi-was-set{-to}` now accept optional {second,third}
  argument to clear the assignments to that very variable.

## [v0.5.1]

### Added

- Shorthand `:othertimes` that will return `nil` when `:sometimes`
  would return `t`.
- `bydi-was-set-to{-nth}` now also works for `let` bindings. These two
  as well as `bydi-was{-not}-set` have explainers.

## [v0.5.0]

### Added

- Variables can now be watched using `:watch` and inspected using
  aliases `bydi-was-set`, `bydi-was-set-to` etc.
- `bydi-was-called-with` now supports matching with elided arguments.
- Warnings about risky mocks can be silenced by using `:risky-mock`
  instead of `:mock`.
- Macros now use `ert--explain-equal-rec` on failure to provide more
  information.

### Changed

- `bydi-clear-mocks` now uses `clrhash` instead of creating a new hash
  table.

### Fixed

- Passing a single argument to `bydi-was-called-{nth-}with` should now
  work reliably.

## [v0.3.0]

### Added

- Macro `bydi-was-called-last-with` as a convenience function to get
  the last result.

### Changed

- Macro `bydi-match-expansion` now has its own `ert-explainer` to show
  the mismatch between actual and expected expansion.
- Switched to using `dinghy`.
- Calling `bydi-toggle-sometimes` now automatically calls
  `bydi-clear-mocks` unless it is called with `t` to prevent that.
- Reporting (`undercover` and `ert-runner`) were factored out into new
  package `bydi-report`.
- `bydi-calculate-coverage` has been deprecated. Printing the report
  and the average is now done automatically for text coverage.
- `bydi-path-setup` was made obsolete by `bydi-ci-setup-paths`.

## [v0.2.0]

### Added

- Self-referential test suite.
- Command `bydi-calculate-coverage` to that using the text report file.
- Macro `bydi-with-mock` is now also aliased by just `bydi`.
- `bydi` now accepts `plist`s of a certain shape. You can use `(:mock
  fun :return value)` or `(:mock fun :with other-fun)`.
- `bydi` now accepts shorthand `(:always fun)` and `(:ignore fun)` to
  mock a function with `ignore` or `always` respectively.
- `bydi` now accepts shorthand `(:sometimes fun)` that will have a
  function return `t` by default or `nil` if `(bydi-toggle-sometimes)`
  was called.
- `bydi-was-{not}-called-{n-times, with}` now have an explainer
  function.
- `bydi` now accepts `(:spy fun)` that allows spying on a function
  without replacing it so it can be used in conjunction with
  `bydi-was-{not}-called-{n-times, with}`.
- `bydi` will now issue warnings if a function belonging to
  `bydi--never-mock` is being mocked.

### Changed

- Source code was refactored to group functions (sometimes renaming them).

## [v0.1.0]

Initial version as an extraction of my config package.
