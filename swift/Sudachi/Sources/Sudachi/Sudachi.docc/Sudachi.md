# ``Sudachi``

On-device Japanese morphological analysis with the Sudachi analyzer.

## Overview

Sudachi splits Japanese text into morphemes and annotates each one with its
reading, dictionary form, normalized form and part of speech. This package
compiles [sudachi.rs](https://github.com/WorksApplications/sudachi.rs) into a
prebuilt framework and exposes it to Swift, so tokenization runs on the device
with no server round-trip.

The package does not include a dictionary. Sudachi needs a
[SudachiDict](https://github.com/WorksApplications/SudachiDict) system
dictionary (`system_*.dic`) at runtime, with the `char.def` and `unk.def`
resource files next to it. The
[README](https://github.com/iasnezhkov/sudachi-swift#the-dictionary) covers
fetching one, the three editions, and shipping it with an app.

```swift
import Sudachi

let dictionary = try SudachiDictionary(
    systemDictionary: URL(fileURLWithPath: "/path/to/system_core.dic"))
let tokenizer = try SudachiTokenizer(dictionary: dictionary, mode: .c)

for morpheme in try tokenizer.tokenize(text: "毎日勉強しても上手にならない。") {
    let furigana = katakanaToHiragana(s: morpheme.readingForm)
    print(morpheme.surface, furigana, morpheme.partOfSpeech)
}
```

Load a dictionary once and share it: it is memory-mapped and immutable, so
opening it is cheap and every tokenizer created over it reuses the same pages.
A tokenizer serializes its calls with an internal lock, so one instance is safe
to share across tasks. For parallel work, create one tokenizer per worker over
the same dictionary.

Morpheme offsets count Unicode scalars, not bytes or `Character`s. Map them
back into the source string with ``Morpheme/range(in:)``.

## Topics

### Loading a dictionary

- ``SudachiDictionary``

### Tokenizing text

- ``SudachiTokenizer``
- ``SplitMode``

### Results

- ``Morpheme``
- ``MorphemeLite``
- ``katakanaToHiragana(s:)``

### Errors

- ``SudachiError``

### Protocols

The protocols the generated classes conform to, for substituting fakes in tests.

- ``SudachiDictionaryProtocol``
- ``SudachiTokenizerProtocol``

### Binding runtime

Part of the generated bindings: it checks that the Swift bindings and the
compiled library agree on the UniFFI contract and API checksum. Every call into
the library already runs it, so there is no need to call it yourself.

- ``uniffiEnsureSudachiSwiftInitialized()``
