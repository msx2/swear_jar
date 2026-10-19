# SwearJar

Fast profanity detector for Polish (`:pl`) and English (`:en`) text. It handles Polish inflection and common obfuscation (missing diacritics, leetspeak, repeated letters, spaced or masked letters) and returns every match with its exact range in the original text.

SwearJar only detects. Your application decides what to do with the matches (censor them, reject a name, count offences). It works as a plain Ruby library and integrates with Rails when Rails is present. Requires Ruby 3.0+. No runtime dependencies.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'swear_jar'
```

And then execute:

```sh
bundle install
```

Or install it yourself as:

```sh
gem install swear_jar
```

## Usage

```ruby
require 'swear_jar'

detector = SwearJar::Detector.new

detector.profane?('ty k u r r w o!') # => true (stops at the first match)
detector.profane?('skurcz łydki')    # => false

detector.matches('Ty k u r r w o! Co za wkurwiony dzień.')
# => [#<struct SwearJar::Match text="k u r r w o", range=3...14, stem="kurw", locale=:pl,
#      severity=:strong, categories=[:vulgar]>,
#     #<struct SwearJar::Match text="wkurwiony", range=22...31, stem="kurw", locale=:pl,
#      severity=:strong, categories=[:vulgar]>]

# Module-level shortcuts use a shared detector built with the defaults (see Configuration)
SwearJar.profane?('What the fuck') # => true
SwearJar.matches('What the fuck')
```

`nil` and `''` give `[]` and `false`. A Symbol or any other object is converted with `to_s`. The input string is never modified.

Detection takes time linear in the length of the input, but a long input still costs more: cap the length before you call the detector (see [Long input](#long-input)).

A `Detector` is frozen after `new` and safe to share between threads. All word-list loading and pattern compilation happens in `new` (about 10 ms with both bundled lists), so build a detector once and reuse it. To change the word list, build a new detector and swap the reference.

### Detector options

```ruby
SwearJar::Detector.new(
  locales: %i[pl en],
  mode: :words,
  min_severity: :mild,
  categories: nil,
  extra_paths: ['config/swear_jar/*.yml'],
  extra_words: [{ stem: 'smoczydup', locale: :pl, severity: :strong, categories: [:insult] }],
  allow: %w[dupleks]
)
```

| option | default | meaning |
|---|---|---|
| `locales` | `%i[pl en]` | bundled word lists to load |
| `mode` | `:words` | `:words` or `:embedded`, see [Modes](#modes) |
| `min_severity` | `:mild` | `:mild`, `:strong` or `:severe`; `:strong` keeps `strong` and `severe` entries |
| `categories` | `nil` (all) | keep entries that have at least one of these: `:vulgar`, `:sexual`, `:insult`, `:slur`, `:religious` |
| `extra_paths` | `[]` | glob patterns of extra word-list YAML files |
| `extra_words` | `[]` | extra entries as hashes; each needs a `locale:` |
| `allow` | `[]` | extra allowlisted words |

An unknown locale, mode, severity or category raises `ArgumentError`, and so does an empty `locales` or `categories` list (it would find nothing). A malformed word list raises `SwearJar::InvalidWordListError` with the file and entry in the message. An `extra_paths` entry without wildcards (`*`, `?`, `[`, `{`) must name an existing file, otherwise it raises `InvalidWordListError`; a glob may match nothing. `allow` takes an Array or a single String.

### `SwearJar::Match`

A frozen `Struct`:

| field | example | meaning |
|---|---|---|
| `text` | `"k u r r w o"` | the matched fragment of the string |
| `range` | `3...14` | character (not byte) range, so `string[match.range] == match.text` |
| `stem` | `"kurw"` | canonical stem from the word list |
| `locale` | `:pl` | |
| `severity` | `:strong` | `:mild`, `:strong` or `:severe` |
| `categories` | `[:vulgar]` | |

Matches are sorted by position and never overlap. A match covers the whole word that contains the stem (`wkurwiony`, not `kurw`), including combining marks after its last letter, but without punctuation around it (`kurwa!!!` gives `kurwa`). One word gives at most one match: the highest severity wins, then the longest stem. `text` is always a plain `String`, also when the input is a subclass such as Rails' `ActiveSupport::SafeBuffer`.

Every profane word is a separate match, so `kurwa kurwa kurwa` gives 3 matches. To count offences per message (for example, mute after 3 offences in 10 minutes), count messages with at least one match (`profane?`), not matches, or one long message counts as many offences.

`range` indexes the string after UTF-8 coercion. For valid UTF-8 input (the normal case) that is the input itself. If your string has invalid bytes or another encoding, coerce it yourself first, the same way the detector does, and use the ranges on the coerced string:

```ruby
text = text.encode('UTF-8', invalid: :replace, undef: :replace, replace: '') unless text.encoding == Encoding::UTF_8
text = text.scrub('')
```

### Censoring

`censor` returns a copy of the text with every match replaced. By default each match becomes one `*` per character; `with:` gives a fixed replacement, and a block gets each `SwearJar::Match` and returns its replacement:

```ruby
text = 'Ty k u r r w o! Co za wkurwiony dzień.'
detector.censor(text)                     # => "Ty ***********! Co za ********* dzień."
detector.censor(text, with: '[bleep]')    # => "Ty [bleep]! Co za [bleep] dzień."
detector.censor('dupa i kurwa') { |match| match.severity == :mild ? match.text : '[bleep]' }
# => "dupa i [bleep]"
SwearJar.censor(text, with: '[bleep]')    # the global detector
```

The input is never modified, `nil` returns `nil`, and a clean text comes back as an unchanged copy. Passing both `with:` and a block raises `ArgumentError`. The result is plain text, not HTML.

To censor at display time in a Rails view with markup (`<em>`), split the raw text at the match ranges and let `safe_join` escape each piece, with markup only between them:

```ruby
# app/helpers/chat_helper.rb
def censored(text)
  pieces = []
  pos = 0
  SwearJar.matches(text).each do |match|
    pieces << text[pos...match.range.begin] << tag.em('[bleep]')
    pos = match.range.end
  end
  safe_join(pieces << text[pos..])
end
```

Do not insert tags into the raw string and call `html_safe` on the result: the rest of the user's text would then be rendered unescaped (an XSS hole).

### Modes

- `:words` (default, intended for chat): a stem matches only at the start of a word, optionally after a Polish prefix (`wkurwiony`, `spierdolić`, `zajebać`). English entries take no prefixes.
- `:embedded` (intended for character names and logins): a stem also matches inside a word (`xxchujxx`, `KurwiMistrz`). Entries marked `embeddable: false` still need a word boundary.

```ruby
SwearJar::Detector.new.profane?('xxchujxx')                   # => false
SwearJar::Detector.new(mode: :embedded).profane?('xxchujxx')  # => true
```

### What is detected

Every message goes through a normalizer before matching:

- case and Unicode compatibility forms: `KURWA`, fullwidth `ｋｕｒｗａ`
- Polish diacritics, written or not, and other combining marks: `gówno` and `gowno`
- leetspeak: `a` = `4 @`, `o` = `0`, `i` = `1 ! |`, `e` = `3`, `s` = `$ 5`, `t` = `7`, `l` = `1 |`, `b` = `8`, `g` = `9`
- repeated letters: `kuuuurwa`
- separators inside a word: `kur.wa`, `kur-wa`
- spaced letters: `k u r w a`, `k.u.r.w.a`, `k-u-r-w-a` (three or more single characters, one repeated separator), also right after a one-letter word that the run takes in: `a k u r w a` reports `k u r w a`. In `:words` mode, an exact entry (`ass`) is split off only after a one-letter word (`a`, `i`, `o`, `u`, `w`, `z`), so `i a s s` is reported and `p a s s` is not
- masked letters: `k*rwa`, `k#rwa`, `k%rwa`, `k_rwa` (`_` only between letters), and several masks for a doubled letter: `a**hole`, `pu**y`. Masks count as letters only between two letters: at the edge of a word they are markers, so `**kurwa**`, `*kurwa*`, `~~chuj~~` and `#kurwa` report just the word, and `censor` keeps the markers (`censor('**kurwa** mac', with: 'X')` → `'**X** mac'`)
- invisible characters inside a word, which are ignored: zero-width space, zero-width (non-)joiner, word joiner, soft hyphen, byte order mark and other format characters. They render as nothing, so `ku\u200Brwa` is one word; in `:words` mode the letter after them is also tried as a word start, so `you\u200Bidiot` reports `idiot`

## Rails

With Rails loaded, SwearJar adds `config.swear_jar` and an ActiveModel validator.

### Configuration

Set options in `config/application.rb`:

```ruby
config.swear_jar.locales = %i[pl en]
config.swear_jar.min_severity = :mild
config.swear_jar.extra_paths = [Rails.root.join('config/swear_jar/*.yml').to_s]
```

Or in an initializer (this also works without Rails):

```ruby
# config/initializers/swear_jar.rb
SwearJar.configure do |config|
  config.locales = %i[pl en]
  config.mode = :words
  config.allow = %w[dupleks]
end
```

Use one of the two. `config.swear_jar` is applied after the initializers run, and each `configure` call starts from the defaults, so the later one replaces the earlier one. The Railtie then builds `SwearJar.detector` during boot, so a server that preloads the app (Puma `preload_app!`) shares one detector between its workers. `configure` accepts the same options as `Detector.new`. It builds a new detector first, so invalid options raise and leave the current one in place, and then swaps it in under a mutex. `SwearJar.detector`, `SwearJar.profane?`, `SwearJar.matches` and `SwearJar.censor` use that detector. Without configuration it uses the defaults. An unknown `config.swear_jar` key raises `ArgumentError` at boot.

### Validator

```ruby
class Character < ApplicationRecord
  validates :name, swear_jar: { mode: :embedded }
  validates :bio, swear_jar: true
  validates :motto, swear_jar: { min_severity: :strong, message: :inappropriate }
end
```

`swear_jar: true` uses `SwearJar.detector`. Any detector option (`mode`, `locales`, `min_severity`, `categories`, `extra_paths`, `extra_words`, `allow`) gives the validator its own detector, built once per option set and cached. Standard validator options (`message`, `if`, `unless`, `on`, `allow_nil`, `allow_blank`, `strict`) work as usual. Blank values are skipped.

The error type is `:profane` (`record.errors.added?(:name, :profane)`), with the message key `errors.messages.profane` and translations for `en` ("contains inappropriate language") and `pl` ("zawiera niedozwolone słowa"). Override it in your own locale files. A custom `message:` (a String, a Symbol translation key or a Proc) replaces only the text; the error type stays `:profane`.

Rails runs every validator of an attribute, even after an earlier one has failed, so a `length:` validation does not keep a huge value away from the detector. Skip the check for values that are too long anyway:

```ruby
validates :name, length: { maximum: 30 }, swear_jar: { if: -> { name.to_s.length <= 30 } }
```

## Word lists

The bundled lists are in `locales/pl/words.yml` and `locales/en/words.yml`. Extra files use the same format plus a top-level `locale:`:

```yaml
locale: pl
prefixes: [bez]                # Polish only, optional
words:
  - stem: kurw
    variants: [kurew, kurest]  # other spellings that report the same stem
    severity: strong
    categories: [vulgar]
  - stem: ass
    severity: mild
    categories: [vulgar]
    embeddable: false          # never inside a word, even in :embedded mode
    exact: true                # whole word only: no prefixes, no suffixes
allow:
  - duplikat                   # an innocent word that contains a stem
```

| key | required | default | meaning |
|---|---|---|---|
| `stem` | yes | | canonical stem, written normally (with diacritics, no leetspeak or digits) |
| `variants` | no | `[]` | other spellings that report the same `stem` |
| `severity` | yes | | `mild`, `strong` or `severe` |
| `categories` | yes | | one or more of `vulgar`, `sexual`, `insult`, `slur`, `religious` |
| `embeddable` | no | `true` | may match inside a word in `:embedded` mode |
| `exact` | no | `false` | must be the whole word |

Stems go through the same normalizer as the input. A stem matches with any ending, so `kurw` covers `kurwa`, `kurwy` and `kurwiszon`. An allow word cancels a match when it is found in the same word and covers the stem (`duplikat` covers `dup`).

To extend the lists, point `extra_paths` at your own files, or pass `extra_words` and `allow`:

```ruby
SwearJar::Detector.new(
  extra_paths: ['config/swear_jar/*.yml'],
  extra_words: [{ stem: 'smoczydup', locale: :pl, severity: :strong, categories: [:insult] }],
  allow: %w[dupleks]
)
```

Extra files and words for a locale that is not in `locales` are ignored.

## Known limitations

- A mask (`*`, `#`, `%`, `_`) stands for one letter of the stem, or for up to as many letters as a run of the same letter has (`a*hole` and `a**hole` for `asshole`), and only for an interior one: the stem's first and last letters must be written. With the stem `kurw`, `k*rwa` and `k**wa` match, but `*urwa` (the `*` is read as a marker before `urwa`) and `k***a` do not.
- When spaced letters follow a one-letter word (`a k u r w a`), only the first character is split off again: after two one-letter words (`i a k u r w a`) the stem is missed in `:words` mode. `:embedded` mode does not split it off at all, so an exact or non-embeddable entry after a swallowed letter (`i a s s`) is missed there; non-exact stems (`a k u r w a`) are found anyway.
- A word glued to a profane one by an invisible character is reported together with it when the scanner sees the profane part first (`kurwa\u200Bmać` is one match). A Polish prefix before the invisible character counts as part of the word: `za\u200Bchuj` reports `za\u200Bchuj`.
- Spaced letters need at least three single characters (`k u r w a`, but not `ku r wa`). This keeps Polish one-letter words (`i`, `w`, `z`, `a`) apart.
- `1` and `|` stand for both `i` and `l`. When a stem has an `i` right before an `l`, the first run takes the shared character: `d1ldo` matches, `di1do` does not.
- Allow words are single words. A phrase such as `bastard sword` cannot be allowlisted.
- `:words` mode does not find a stem in the middle of a compound (`horseshit`, `clusterfuck`). Only listed compounds such as `bullshit`, `jackass` and `motherfuck` are caught.

False positives found while writing the lists. They cannot be fixed in the data without missing real profanity:

- `pedał` (bicycle pedal) is reported, because it is the same word as the slur. `pedałować` (to pedal) is allowed. English `pedal` and `pedals` are reported too.
- English `dupe` and `duped` (Polish `dupę` without diacritics is `dupe`), and `Dupont`.
- `pierdoła` (`pierdol`), `Matołek` (`matoł`), `palant` (a bat game, same word as the insult), `Jebel` (`jeb`), `Sukkot` (`suk`), Czech `sucet` (`suce`) and the surname `Ciotti` (`ciot`).
- `cocky`, the name `Dick`, `Cumming`, `tit` (the bird), French `douche`, British `fag` (cigarette), `cholera` (the disease), `summa cum laude`, `pussy willow`, and `the damned`.
- `:embedded` only: `bipedal` and `Ospedale` (`pedał`), and Japanese names such as `Yoshitsune` and `Yoshitaka` (`shit`). `Matsushita` is allowlisted.

False negatives:

- `pedałów` and `spedałowany`, because the allow word `pedałow` (for `pedałować`) covers them.
- Forms of the slur `ciota` that are spelled like forms of `ciotka` (`ciotek`, `ciotce`), which are allowed.

## Performance

A clean message costs one regexp scan over its normalized form. Entry identification, allowlist checks and the original-text index map run only around hits.

`bundle exec rake bench` on an arm64 Mac, Ruby 3.4.9, default detector (both locales), average per `matches` call unless noted:

| message (~175 characters) | `:words` | `:embedded` |
|---|---|---|
| clean Polish | 30 µs | 60 µs |
| clean English | 22 µs | 51 µs |
| clean, with emoji | 33 µs | 54 µs |
| 3 profanities (`matches`) | 111 µs | 128 µs |
| 3 profanities (`profane?`) | 65 µs | 71 µs |

`Detector.new` with both lists takes about 10 ms, so build one detector at boot and reuse it. Characters outside the Latin blocks (emoji, symbols) are folded once per block of 256 code points and cached for the life of the process, up to 64 blocks. A message with characters beyond that is still handled correctly, just more slowly.

### Long input

The time grows linearly with the length of the input and the number of hits, also for adversarial input (long runs of one letter or symbol, thousands of profanities, one huge glued word). On the machine above, text without matches takes at most about 60 ms per 50 000 characters (one glued word in `:embedded` mode is the slowest case), and each profanity found adds 5 to 10 µs (`'kurwa ' * 8_333` takes about 50 ms). Still, a chat message or a name has no reason to be long, so cap the length before detection (reject or truncate first). In Rails, a `length:` validation alone is not enough, see [Validator](#validator).

## Development

```sh
bundle install
bundle exec rspec
bundle exec rubocop
bundle exec rake # both
bundle exec rake bench
```

The public API is `SwearJar` (`configure`, `detector`, `profane?`, `matches`, `censor`), `SwearJar::Detector`, `SwearJar::Match`, `SwearJar::Configuration`, the error classes and `SwearJarValidator`. Classes marked `@api private` (`Entry`, `WordList`, `Normalizer`, `FoldTable`, `PatternBuilder`, `Matcher`, `Skeleton`, `Slicer`) may change in any release.

The spec suite includes a table-driven corpus (`spec/fixtures/pl.yml`, `spec/fixtures/en.yml`) with profane and clean cases. When you change a word list, add cases there.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/msx2/swear_jar. When submitting changes, please make sure specs and RuboCop pass and document user-facing changes in [CHANGELOG.md](CHANGELOG.md).

## License

MIT, see [LICENSE.txt](LICENSE.txt).
