# Changelog

## 0.1.0 - Unreleased

- Require Ruby 3.0+, no runtime dependencies
- Add `SwearJar::Detector` with `profane?` and `matches`, and the frozen `SwearJar::Match` value object (`text`, character `range`, `stem`, `locale`, `severity`, `categories`)
- Add Polish (`:pl`) and English (`:en`) word lists with severities (`mild`, `strong`, `severe`), categories (`vulgar`, `sexual`, `insult`, `slur`, `religious`), variants, Polish prefixes and allowlists
- Add detector options: `locales`, `mode` (`:words`, `:embedded`), `min_severity`, `categories`, `extra_paths`, `extra_words` and `allow`
- Detect obfuscation: case, missing diacritics, fullwidth and other compatibility characters, leetspeak, repeated letters, separators inside a word, spaced letters and masked letters
- Treat masks at the edge of a word as markers, not masked letters: `**kurwa**`, `*kurwa*`, `#kurwa` report just the word, and `censor` keeps the markers
- Add `Detector#censor` (one `*` per character by default, a `with:` string or a block per match)
- Add `SwearJar.configure`, `SwearJar.detector`, `SwearJar.profane?`, `SwearJar.matches` and `SwearJar.censor`
- Add a Railtie with `config.swear_jar`, and `SwearJarValidator` (`validates :name, swear_jar: true`) with `en` and `pl` messages under `errors.messages.profane`
- Detect invisible characters inside a word (zero-width space and joiners, soft hyphen, byte order mark and other format characters), several masks for a doubled letter (`a**hole`), spaced letters right after a one-letter word (`a k u r w a`; exact entries only after `a i o u w z`, so `p a s s` stays clean), and in `:words` mode words separated only by an invisible character (`you\u200Bidiot`)
- Extend a match over combining marks after its last letter; `Match#text` is always a plain `String`, also for an `ActiveSupport::SafeBuffer` input
- Run in linear time on adversarial input: many hits, long runs of letters or leet symbols, one long glued word, non-ASCII text
- `SwearJarValidator` keeps the `:profane` error type with a custom `message:`
- Raise `ArgumentError` for empty `locales` or `categories`, and `InvalidWordListError` for an `extra_paths` entry without wildcards that names no file, for an entry with a non-string key, and for a stem, variant or allow word with a digit or without letters, naming the file and entry; accept a single String for `allow`
- The Railtie builds `SwearJar.detector` at boot, so preloading app servers share it
- Compact `inspect` for `Detector` and the internal classes, which are marked `@api private`
- Add `rake bench` (a clean ~200-character message averages under 50 µs in `:words` mode)
- Add RuboCop configuration and GitHub Actions CI workflow
