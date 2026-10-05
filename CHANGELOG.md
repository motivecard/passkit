## [0.7.2]
- APNs: `PushNotificationService` keeps a per-process pool of persistent connections (`Apnotic::ConnectionPool`) instead of opening one per notification. New settings: `apns_pool_size` (default 5) and `push_error_handler` (called with socket errors). `reset_connection_pool!` closes them, e.g. after rotating the certificate.
- `PassesController#show` and `#create` delete the generated `.pkpass` and its build folder after responding; they used to stay in `tmp/passkit` forever. New `Passkit::Generator.cleanup(path)`.
- `RegistrationsController#show` returns `lastUpdated` with microseconds. Truncated to seconds, the latest pass was newer than its own tag and was listed again on every "what changed?" check: the device re-downloaded an unchanged pass and logged "lastUpdated tag remained the same". Second-precision tags already on devices keep working.

## [0.7.1]
- `additional_pass_data`: pass.json keys the gem doesn't model (an extra style dictionary such as `posterGeneric`, `relevantDates`, `featuredActions`), deep merged last. Empty by default, so existing passes are unchanged.

## [0.7.0]
- [#25](https://github.com/coorasse/passkit/pull/25): Change the label default color to black.

## [0.6.1]

- [#21](https://github.com/coorasse/passkit/pull/21): Support an ecryption key via `PASSKIT_URL_ENCRYPTION_KEY` environment variable.

## [0.6.0]

- [#20](https://github.com/coorasse/passkit/pull/20): Many new attributes added.

## [0.5.4]

- Fix last-modified header format. Return it in RFC 2616 format.

## [0.5.3]

- [#15](https://github.com/coorasse/passkit/pull/15): Send correct headers also on passes_controller


## [0.5.2]

- [#14](https://github.com/coorasse/passkit/pull/14): Send correct headers with previews so it auto-adds on iOS

## [0.5.1]

- [#13](https://github.com/coorasse/passkit/pull/13): Added sharingProhibited 
- [#13](https://github.com/coorasse/passkit/pull/13): Added maxDistance
- [#13](https://github.com/coorasse/passkit/pull/13): Allow custom files with add_other_files

## [0.5.0]

- Allow configuring labelColor
- Allow receiving the same push otken with different device identifiers
- Make the last_update more flexible

## [0.4.2]

- Fix the unregister endpoint.

## [0.4.1]

- Allow the registration of two passes on the same device.

## [0.4.0]

- Allow to use the dashboard also in production.
- Allow to protect the dashboard using different strategies. Basic auth is default.
- Breaking: now your Passkit dashboard is mounted under `/passkit/dashboard` instead of just `/passkit`. 

## [0.3.3]

- Fix previews page.

## [0.3.2]

## [0.3.1]

## [0.3.0]

## [0.2.0]

## [0.1.0]

- Initial release.
